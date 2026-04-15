//
//  LibraryStore.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import CloudKit
import Combine
import Foundation
import UIKit

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published private(set) var locations: [LibraryLocation] = []
    @Published private(set) var availableRepositories: [LibraryRepositoryReference] = []
    @Published var searchText = ""
    @Published var selectedLocationID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isCreatingRepository = false
    @Published private(set) var isImportingLegacyData = false
    @Published private(set) var syncStatus: LibrarySyncStatus
    @Published private(set) var currentRepository: LibraryRepositoryReference?
    @Published var alertMessage: String?
    @Published private(set) var importProgress: RepositoryImportProgress?
    @Published private(set) var latestExportURL: URL?

    private let configuration: LibraryAppConfiguration
    private let cacheStore: LibraryCacheStore
    private let sessionStore: RepositorySessionStore
    private let remoteService: any LibraryRemoteSyncing

    private var sessionState: LibrarySessionState
    private var hasLoaded = false
    private var isLoadInFlight = false
    private var coverCache: [String: Data] = [:]

    init(configuration: LibraryAppConfiguration) {
        self.configuration = configuration
        cacheStore = configuration.cacheStore
        sessionStore = configuration.sessionStore
        remoteService = configuration.remoteService
        sessionState = configuration.sessionStore.load()
        currentRepository = sessionState.currentRepository
        syncStatus = .idle
    }

    var visibleBooks: [Book] {
        LibraryFilter.filteredBooks(
            from: books,
            query: searchText,
            selectedLocationID: selectedLocationID,
            locationsByID: locationsByID
        )
    }

    var hasRepository: Bool {
        currentRepository != nil
    }

    var hasOwnedRepository: Bool {
        availableRepositories.contains(where: \.isOwner)
    }

    var canSearch: Bool {
        hasLoaded && hasRepository
    }

    var canManageLocations: Bool {
        hasRepository
    }

    var canManageSharing: Bool {
        currentRepository?.isOwner == true && remoteService is CloudKitLibraryService
    }

    var repositoryTitle: String {
        currentRepository?.name ?? "还没有仓库"
    }

    var repositorySubtitle: String {
        currentRepository?.subtitle ?? "当前设备还没有可访问的家庭书库。"
    }

    var repositoryRoleTitle: String {
        currentRepository?.role.title ?? "未连接"
    }

    var repositoryScopeTitle: String {
        currentRepository?.databaseScope.title ?? "未连接"
    }

    var shareStatusTitle: String {
        currentRepository?.shareStatus.title ?? "未共享"
    }

    var visibleLocationFilters: [LibraryLocationFilter] {
        [LibraryLocationFilter.all] + visibleLocations.map(LibraryLocationFilter.init(location:))
    }

    var defaultLocationID: String {
        if let selectedLocationID, locationsByID[selectedLocationID] != nil {
            return selectedLocationID
        }

        return visibleLocations.first?.id ?? locations.first?.id ?? LibraryLocation.defaultLocations()[0].id
    }

    func loadBooksIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        await loadBooks(force: true)
    }

    func loadBooks(force: Bool = false) async {
        guard !isLoadInFlight else {
            return
        }

        isLoadInFlight = true
        isLoading = books.isEmpty
        defer {
            isLoadInFlight = false
            isLoading = false
        }

        do {
            guard let repository = try await resolveCurrentRepository(forceRefresh: force) else {
                books = []
                locations = []
                coverCache = [:]
                syncStatus = .idle
                hasLoaded = true
                return
            }

            let didRestoreCache = await restoreCachedContentIfAvailable(repositoryID: repository.id)
            if didRestoreCache {
                hasLoaded = true
                isLoading = false
            }

            try await refreshFromCloud(repository: repository)
            hasLoaded = true
        } catch {
            let message = Self.userFacingMessage(for: error)
            alertMessage = message
            syncStatus = .failed(message)
        }
    }

    @discardableResult
    func createOwnedRepository() async -> Bool {
        guard !isCreatingRepository else {
            return false
        }

        isCreatingRepository = true
        defer { isCreatingRepository = false }

        do {
            let repository = try await remoteService.createOwnedRepository(
                preferredName: configuration.preferredOwnedRepositoryName
            )
            sessionState.currentRepository = repository
            persistSessionState()
            try await refreshAvailableRepositories(selecting: repository)
            try await refreshFromCloud(repository: repository)
            return true
        } catch {
            let message = Self.userFacingMessage(for: error)
            alertMessage = message
            syncStatus = .failed(message)
            return false
        }
    }

    func switchRepository(to repository: LibraryRepositoryReference) async {
        sessionState.currentRepository = repository
        persistSessionState()
        await loadBooks(force: true)
    }

    @discardableResult
    func saveLocations(_ draftLocations: [LibraryLocation]) async -> Bool {
        guard let repository = currentRepository else {
            alertMessage = "当前还没有可写入的仓库。"
            return false
        }

        do {
            let savedLocations = try await remoteService.saveLocations(draftLocations, in: repository)
            locations = savedLocations
            validateSelectedLocation()
            try await replaceCache(
                books: books,
                locations: savedLocations,
                coverDataByAssetID: [:],
                repositoryID: repository.id,
                synchronizedAt: Date()
            )
            return true
        } catch {
            let message = Self.userFacingMessage(for: error)
            alertMessage = message
            syncStatus = .failed(message)
            return false
        }
    }

    @discardableResult
    func saveBook(draft: BookDraft, editing existingBook: Book?) async -> Bool {
        let normalizedDraft = draft.normalized

        guard normalizedDraft.canSave else {
            alertMessage = "书名和地点不能为空。"
            return false
        }

        guard let repository = currentRepository else {
            alertMessage = "请先创建或切换到一个仓库。"
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let now = Date()
            let preservedCoverAssetID = normalizedDraft.keepsExistingCoverReference ? existingBook?.coverAssetID : nil
            let book = Book(
                id: existingBook?.id ?? UUID().uuidString,
                title: normalizedDraft.title,
                author: normalizedDraft.author,
                publisher: normalizedDraft.publisher,
                year: normalizedDraft.year,
                locationID: normalizedDraft.locationID,
                customFields: normalizedDraft.customFields,
                coverAssetID: preservedCoverAssetID,
                createdAt: existingBook?.createdAt ?? now,
                updatedAt: now
            )

            syncStatus = .syncing
            let snapshot = try await remoteService.upsertBook(book, coverData: normalizedDraft.coverData, in: repository)
            try await writeSnapshotToCache(snapshot, repositoryID: repository.id, synchronizedAt: now)
            syncStatus = .upToDate(now)
            try await reloadFromCache(repositoryID: repository.id)
            return true
        } catch {
            let message = Self.userFacingMessage(for: error)
            alertMessage = message
            syncStatus = .failed(message)
            return false
        }
    }

    @discardableResult
    func deleteBook(_ book: Book) async -> Bool {
        guard let repository = currentRepository else {
            alertMessage = "当前还没有可写入的仓库。"
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let deletedAt = Date()
            syncStatus = .syncing
            try await remoteService.deleteBook(id: book.id, deletedAt: deletedAt, in: repository)
            syncStatus = .upToDate(deletedAt)

            let cacheStore = self.cacheStore
            try await Task.detached(priority: .utility) {
                try cacheStore.removeBook(id: book.id, repositoryID: repository.id)
            }.value

            try await reloadFromCache(repositoryID: repository.id)
            return true
        } catch {
            let message = Self.userFacingMessage(for: error)
            alertMessage = message
            syncStatus = .failed(message)
            return false
        }
    }

    func coverData(for assetID: String?) async -> Data? {
        guard let assetID, let repositoryID = currentRepository?.id else {
            return nil
        }

        if let cached = coverCache[assetID] {
            return cached
        }

        do {
            let cacheStore = self.cacheStore
            let data = try await Task.detached(priority: .utility) {
                try cacheStore.coverData(for: assetID, repositoryID: repositoryID)
            }.value

            if let data {
                coverCache[assetID] = data
            }

            return data
        } catch {
            return nil
        }
    }

    func coverDataSynchronously(for assetID: String?) -> Data? {
        guard let assetID, let repositoryID = currentRepository?.id else {
            return nil
        }

        if let cached = coverCache[assetID] {
            return cached
        }

        guard let data = try? cacheStore.coverData(for: assetID, repositoryID: repositoryID) else {
            return nil
        }

        coverCache[assetID] = data
        return data
    }

    @discardableResult
    func importLegacyJSON(from fileURL: URL) async -> Bool {
        guard !isImportingLegacyData else {
            return false
        }

        isImportingLegacyData = true
        importProgress = RepositoryImportProgress(phase: .counting, totalCount: 0, importedCount: 0)
        defer {
            isImportingLegacyData = false
        }

        do {
            let repository = try await ensureOwnedRepositoryForImport()
            let bundle = try await loadImportBundle(from: fileURL)
            let normalizedLocations = normalizeImportedLocations(bundle.locations)
            let totalCount = bundle.books.count

            guard totalCount > 0 else {
                importProgress = nil
                alertMessage = "选中的 JSON 没有可导入的书籍。"
                return false
            }

            importProgress = RepositoryImportProgress(phase: .importing, totalCount: totalCount, importedCount: 0)
            _ = try await remoteService.saveLocations(normalizedLocations, in: repository)

            syncStatus = .syncing
            for (index, imported) in bundle.books.sorted(by: { $0.book.updatedAt < $1.book.updatedAt }).enumerated() {
                _ = try await remoteService.upsertBook(imported.book, coverData: imported.coverData, in: repository)
                importProgress = RepositoryImportProgress(
                    phase: .importing,
                    totalCount: totalCount,
                    importedCount: index + 1
                )
            }

            importProgress = RepositoryImportProgress(phase: .completed, totalCount: totalCount, importedCount: totalCount)
            sessionStore.markLegacyMigrationCompleted(for: repository.id)
            try await refreshFromCloud(repository: repository)
            alertMessage = "已完成导入，共 \(totalCount) 本。"
            return true
        } catch {
            importProgress = nil
            let message = Self.userFacingMessage(for: error)
            alertMessage = message
            syncStatus = .failed(message)
            return false
        }
    }

    @discardableResult
    func clearCurrentRepository() async -> Bool {
        guard let repository = currentRepository else {
            alertMessage = "当前还没有仓库。"
            return false
        }

        do {
            let resetLocations = LibraryLocation.defaultLocations()
            try await remoteService.clearRepository(repository, resetLocations: resetLocations)
            try await refreshFromCloud(repository: repository)
            alertMessage = "当前仓库已经清空。"
            return true
        } catch {
            let message = Self.userFacingMessage(for: error)
            alertMessage = message
            syncStatus = .failed(message)
            return false
        }
    }

    @discardableResult
    func exportCurrentRepository() async -> URL? {
        guard let repository = currentRepository else {
            alertMessage = "当前还没有仓库。"
            return nil
        }

        do {
            let package = try await remoteService.exportRepository(repository)
            let data = try LibraryJSONCodec.makeEncoder().encode(package)
            let exportDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("homeLibrary-exports", isDirectory: true)
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

            let sanitizedName = repository.name.replacingOccurrences(of: "/", with: "-").trimmed.nilIfEmpty ?? "homeLibrary"
            let url = exportDirectory.appendingPathComponent("\(sanitizedName)-\(Int(Date().timeIntervalSince1970)).zip")
            try LibraryZipArchiveWriter.writeSingleFileArchive(filename: "LibraryImport.json", fileData: data, to: url)
            latestExportURL = url
            return url
        } catch {
            let message = Self.userFacingMessage(for: error)
            alertMessage = message
            syncStatus = .failed(message)
            return nil
        }
    }

    func consumeLatestExportURL() -> URL? {
        defer { latestExportURL = nil }
        return latestExportURL
    }

    func dismissImportProgress() {
        importProgress = nil
    }

    func removeRepository(_ repository: LibraryRepositoryReference) async {
        do {
            try await remoteService.deleteRepository(repository)
            if currentRepository?.id == repository.id && currentRepository?.databaseScope == repository.databaseScope {
                sessionState.currentRepository = nil
                persistSessionState()
            }
            await loadBooks(force: true)
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
        }
    }

    func makeSharingControllerForCurrentRepository() async throws -> UICloudSharingController {
        guard let repository = currentRepository,
              let service = remoteService as? CloudKitLibraryService else {
            throw LibraryRemoteServiceError.permissionDenied
        }

        return try await service.makeSharingController(for: repository)
    }

    func acceptShareMetadata(_ metadata: CKShare.Metadata) async {
        guard let service = remoteService as? CloudKitLibraryService else {
            return
        }

        do {
            let existingIDs = Set(availableRepositories.map { "\($0.databaseScope.rawValue):\($0.id)" })
            try await service.acceptShare(metadata: metadata)
            let repositories = try await remoteService.listRepositories()
            availableRepositories = repositories
            if let newRepository = repositories.first(where: { !existingIDs.contains("\($0.databaseScope.rawValue):\($0.id)") }) {
                sessionState.currentRepository = newRepository
                persistSessionState()
            }
            await loadBooks(force: true)
        } catch {
            let message = Self.userFacingMessage(for: error)
            alertMessage = message
            syncStatus = .failed(message)
        }
    }

    nonisolated static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription?.trimmed.nilIfEmpty {
            return description
        }

        if let localizedDescription = error.localizedDescription.trimmed.nilIfEmpty {
            return localizedDescription
        }

        return "发生了未预期的错误。"
    }

    private var locationsByID: [String: LibraryLocation] {
        Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
    }

    private var visibleLocations: [LibraryLocation] {
        locations
            .filter(\.isVisible)
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func resolveCurrentRepository(forceRefresh: Bool) async throws -> LibraryRepositoryReference? {
        if forceRefresh || availableRepositories.isEmpty {
            try await refreshAvailableRepositories(selecting: sessionState.currentRepository)
        }

        if let currentRepository = sessionState.currentRepository,
           let refreshedRepository = availableRepositories.first(where: { $0.id == currentRepository.id && $0.databaseScope == currentRepository.databaseScope }) {
            sessionState.currentRepository = refreshedRepository
            persistSessionState()
            return refreshedRepository
        }

        if let ownerRepository = availableRepositories.first(where: \.isOwner) {
            sessionState.currentRepository = ownerRepository
            persistSessionState()
            return ownerRepository
        }

        if let sharedRepository = availableRepositories.first {
            sessionState.currentRepository = sharedRepository
            persistSessionState()
            return sharedRepository
        }

        sessionState.currentRepository = nil
        persistSessionState()
        return nil
    }

    private func refreshAvailableRepositories(selecting preferredRepository: LibraryRepositoryReference?) async throws {
        let repositories = try await remoteService.listRepositories()
        availableRepositories = repositories

        if let preferredRepository,
           let resolvedRepository = repositories.first(where: { $0.id == preferredRepository.id && $0.databaseScope == preferredRepository.databaseScope }) {
            sessionState.currentRepository = resolvedRepository
        } else if sessionState.currentRepository == nil {
            sessionState.currentRepository = repositories.first(where: \.isOwner) ?? repositories.first
        }
    }

    private func refreshFromCloud(repository: LibraryRepositoryReference) async throws {
        syncStatus = .syncing
        let snapshot = try await remoteService.refreshRepository(repository)
        let synchronizedAt = Date()
        try await replaceCache(
            books: snapshot.books.map(\.book),
            locations: snapshot.locations,
            coverDataByAssetID: snapshot.books.reduce(into: [String: Data]()) { partialResult, snapshot in
                guard let assetID = snapshot.book.coverAssetID, let coverData = snapshot.coverData else {
                    return
                }

                partialResult[assetID] = coverData
            },
            repositoryID: snapshot.repository.id,
            synchronizedAt: synchronizedAt
        )

        currentRepositoryChanged(snapshot.repository)
        try await reloadFromCache(repositoryID: snapshot.repository.id)
        validateSelectedLocation()
        syncStatus = .upToDate(synchronizedAt)
        try await refreshAvailableRepositories(selecting: snapshot.repository)
        persistSessionState()
    }

    private func replaceCache(
        books: [Book],
        locations: [LibraryLocation],
        coverDataByAssetID: [String: Data],
        repositoryID: String,
        synchronizedAt: Date
    ) async throws {
        let cacheStore = self.cacheStore

        try await Task.detached(priority: .utility) {
            try cacheStore.replaceAllContent(
                books: books,
                locations: locations,
                coverDataByAssetID: coverDataByAssetID,
                repositoryID: repositoryID,
                synchronizedAt: synchronizedAt
            )
        }.value

        coverCache.merge(coverDataByAssetID) { _, new in new }
    }

    private func writeSnapshotToCache(
        _ snapshot: RemoteBookSnapshot,
        repositoryID: String,
        synchronizedAt: Date
    ) async throws {
        let cacheStore = self.cacheStore

        let storedBook = try await Task.detached(priority: .utility) {
            try cacheStore.upsert(book: snapshot.book, coverData: snapshot.coverData, repositoryID: repositoryID)
        }.value

        if let assetID = storedBook.coverAssetID, let coverData = snapshot.coverData {
            coverCache[assetID] = coverData
        }

        try await Task.detached(priority: .utility) {
            try cacheStore.markSyncSuccess(at: synchronizedAt, repositoryID: repositoryID)
        }.value
    }

    private func reloadFromCache(repositoryID: String) async throws {
        let snapshot = try await loadCacheSnapshot(repositoryID: repositoryID)
        books = snapshot.books
        locations = snapshot.locations
        coverCache = coverCache.filter { snapshot.referencedAssetIDs.contains($0.key) }
    }

    private func loadCacheSnapshot(repositoryID: String) async throws -> LibraryCacheSnapshot {
        let cacheStore = self.cacheStore
        return try await Task.detached(priority: .utility) {
            try cacheStore.loadSnapshot(repositoryID: repositoryID)
        }.value
    }

    private func restoreCachedContentIfAvailable(repositoryID: String) async -> Bool {
        do {
            try await reloadFromCache(repositoryID: repositoryID)
            validateSelectedLocation()
            return !books.isEmpty || !locations.isEmpty
        } catch {
            return false
        }
    }

    private func ensureOwnedRepositoryForImport() async throws -> LibraryRepositoryReference {
        if let currentRepository, currentRepository.isOwner {
            return currentRepository
        }

        if let ownedRepository = availableRepositories.first(where: \.isOwner) {
            sessionState.currentRepository = ownedRepository
            persistSessionState()
            return ownedRepository
        }

        let repository = try await remoteService.createOwnedRepository(preferredName: configuration.preferredOwnedRepositoryName)
        sessionState.currentRepository = repository
        persistSessionState()
        return repository
    }

    private func loadImportBundle(from fileURL: URL) async throws -> LegacyImportBundle {
        let didStartAccessingSecurityScopedResource = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessingSecurityScopedResource {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let importer = configuration.legacyImporter
        return try await Task.detached(priority: .utility) {
            try importer.loadImportBundle(from: fileURL)
        }.value
    }

    private func normalizeImportedLocations(_ importedLocations: [LibraryLocation]) -> [LibraryLocation] {
        let base = importedLocations.isEmpty ? LibraryLocation.defaultLocations() : importedLocations
        return base
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .enumerated()
            .map { index, location in
                LibraryLocation(
                    id: location.id.trimmed.nilIfEmpty ?? UUID().uuidString,
                    name: location.name.trimmed.nilIfEmpty ?? "地点 \(index + 1)",
                    sortOrder: index,
                    isVisible: location.isVisible
                )
            }
    }

    private func validateSelectedLocation() {
        if let selectedLocationID,
           visibleLocations.contains(where: { $0.id == selectedLocationID }) {
            return
        }

        selectedLocationID = nil
    }

    private func persistSessionState() {
        sessionStore.save(sessionState)
        currentRepositoryChanged(sessionState.currentRepository)
    }

    private func currentRepositoryChanged(_ repository: LibraryRepositoryReference?) {
        currentRepository = repository
    }
}
