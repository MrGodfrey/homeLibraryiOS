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

nonisolated enum AcceptedShareRepositoryResolver {
    static func preferredRepository(
        from repositories: [LibraryRepositoryReference],
        existingIDs: Set<String>,
        preferredSharedZoneID: CKRecordZone.ID?
    ) -> LibraryRepositoryReference? {
        if let preferredSharedZoneID,
           let matchedRepository = repositories.first(where: {
               $0.databaseScope == .shared &&
               $0.zoneName == preferredSharedZoneID.zoneName &&
               $0.zoneOwnerName == preferredSharedZoneID.ownerName
           }) {
            return matchedRepository
        }

        if let newSharedRepository = repositories.first(where: {
            $0.databaseScope == .shared && !existingIDs.contains(repositoryIdentity(for: $0))
        }) {
            return newSharedRepository
        }

        if let newRepository = repositories.first(where: { !existingIDs.contains(repositoryIdentity(for: $0)) }) {
            return newRepository
        }

        return repositories.first(where: { $0.databaseScope == .shared })
    }

    static func repositoryIdentity(for repository: LibraryRepositoryReference) -> String {
        "\(repository.databaseScope.rawValue):\(repository.id)"
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published private(set) var locations: [LibraryLocation] = []
    @Published private(set) var availableRepositories: [LibraryRepositoryReference] = []
    @Published var searchText = ""
    @Published var selectedLocationID: String?
    @Published private(set) var bookSortOrder: LibraryBookSortOrder
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isCreatingRepository = false
    @Published private(set) var isImportingLegacyData = false
    @Published private(set) var syncStatus: LibrarySyncStatus
    @Published private(set) var currentRepository: LibraryRepositoryReference?
    @Published var alertMessage: String?
    @Published private(set) var importProgress: RepositoryImportProgress?
    @Published private(set) var coverCompressionProgress: RepositoryCoverCompressionProgress?
    @Published private(set) var exportProgress: RepositoryExportProgress?
    @Published private(set) var latestExportURL: URL?
    @Published private(set) var isAcceptingShareLink = false
    @Published private(set) var isCompressingCovers = false
    @Published private(set) var isExportingRepository = false

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
        bookSortOrder = sessionState.bookSortOrder(for: sessionState.currentRepository)
        syncStatus = .idle
    }

    var visibleBooks: [Book] {
        LibraryFilter.filteredBooks(
            from: books,
            query: searchText,
            selectedLocationID: selectedLocationID,
            locationsByID: locationsByID,
            sortOrder: bookSortOrder
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

    var canAcceptShareLinks: Bool {
        remoteService is any LibraryShareLinkAccepting
    }

    func isCurrentRepository(_ repository: LibraryRepositoryReference) -> Bool {
        sameRepository(currentRepository, repository)
    }

    func canRemoveRepository(_ repository: LibraryRepositoryReference) -> Bool {
        availableRepositories.count > 1 && !isCurrentRepository(repository)
    }

    var cloudKitService: CloudKitLibraryService? {
        remoteService as? CloudKitLibraryService
    }

    var repositoryTitle: String {
        currentRepository?.name ?? localized("还没有仓库", en: "No Library Yet")
    }

    var repositorySubtitle: String {
        currentRepository?.subtitle ?? localized("当前设备还没有可访问的家庭书库。", en: "There is no accessible family library on this device yet.")
    }

    var repositoryRoleTitle: String {
        currentRepository?.role.title ?? localized("未连接", en: "Not Connected")
    }

    var repositoryScopeTitle: String {
        currentRepository?.databaseScope.title ?? localized("未连接", en: "Not Connected")
    }

    var shareStatusTitle: String {
        currentRepository?.shareStatus.title ?? localized("未共享", en: "Not Shared")
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
                coverCompressionProgress = nil
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

    func setBookSortOrder(_ sortOrder: LibraryBookSortOrder) {
        guard bookSortOrder != sortOrder else {
            return
        }

        bookSortOrder = sortOrder

        guard let currentRepository else {
            return
        }

        sessionState.setBookSortOrder(sortOrder, for: currentRepository)
        sessionStore.save(sessionState)
    }

    @discardableResult
    func saveLocations(_ draftLocations: [LibraryLocation]) async -> Bool {
        guard let repository = currentRepository else {
            alertMessage = localized("当前还没有可写入的仓库。", en: "There is no writable library yet.")
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
            alertMessage = localized("书名和地点不能为空。", en: "Title and location are required.")
            return false
        }

        guard let repository = currentRepository else {
            alertMessage = localized("请先创建或切换到一个仓库。", en: "Create or switch to a library first.")
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let now = Date()
            let preparedCoverData = await optimizedCoverData(normalizedDraft.coverData)
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
            let snapshot = try await remoteService.upsertBook(book, coverData: preparedCoverData, in: repository)
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
            alertMessage = localized("当前还没有可写入的仓库。", en: "There is no writable library yet.")
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
                alertMessage = localized("选中的 JSON 没有可导入的书籍。", en: "The selected JSON does not contain any books to import.")
                return false
            }

            importProgress = RepositoryImportProgress(phase: .importing, totalCount: totalCount, importedCount: 0)
            _ = try await remoteService.saveLocations(normalizedLocations, in: repository)

            syncStatus = .syncing
            for (index, imported) in bundle.books.sorted(by: { $0.book.updatedAt < $1.book.updatedAt }).enumerated() {
                let preparedCoverData = await optimizedCoverData(imported.coverData)
                _ = try await remoteService.upsertBook(imported.book, coverData: preparedCoverData, in: repository)
                importProgress = RepositoryImportProgress(
                    phase: .importing,
                    totalCount: totalCount,
                    importedCount: index + 1
                )
            }

            importProgress = RepositoryImportProgress(phase: .completed, totalCount: totalCount, importedCount: totalCount)
            sessionStore.markLegacyMigrationCompleted(for: repository.id)
            try await refreshFromCloud(repository: repository)
            alertMessage = localized("已完成导入，共 %d 本。", en: "Import complete, %d books.", arguments: [totalCount])
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
    func compressOversizedCoversInCurrentRepository() async -> Bool {
        guard let repository = currentRepository else {
            alertMessage = localized("当前还没有仓库。", en: "There is no library yet.")
            return false
        }

        guard !isCompressingCovers else {
            return false
        }

        let snapshot: LibraryCacheSnapshot
        do {
            snapshot = try await loadCacheSnapshot(repositoryID: repository.id)
        } catch {
            let message = Self.userFacingMessage(for: error)
            alertMessage = message
            syncStatus = .failed(message)
            return false
        }

        var booksByAssetID: [String: [Book]] = [:]
        for book in snapshot.books {
            guard let assetID = book.coverAssetID else {
                continue
            }

            booksByAssetID[assetID, default: []].append(book)
        }

        let assetIDs = booksByAssetID.keys.sorted()
        guard !assetIDs.isEmpty else {
            coverCompressionProgress = nil
            alertMessage = localized("当前仓库没有可整理的封面。", en: "There are no covers to optimize in the current library.")
            return false
        }

        isCompressingCovers = true
        coverCompressionProgress = RepositoryCoverCompressionProgress(
            phase: .running,
            totalCount: assetIDs.count,
            processedCount: 0,
            compressedCount: 0
        )
        syncStatus = .syncing
        defer { isCompressingCovers = false }

        do {
            var compressedCount = 0
            let synchronizedAt = Date()

            for (index, assetID) in assetIDs.enumerated() {
                let originalData = try await cachedCoverData(for: assetID, repositoryID: repository.id)
                let compressionResult = await compressedCoverResult(for: originalData)

                if let compressionResult, compressionResult.didCompress {
                    for book in booksByAssetID[assetID] ?? [] {
                        let updatedSnapshot = try await remoteService.upsertBook(
                            book,
                            coverData: compressionResult.data,
                            in: repository
                        )
                        try await writeSnapshotToCache(
                            updatedSnapshot,
                            repositoryID: repository.id,
                            synchronizedAt: synchronizedAt
                        )
                    }
                    compressedCount += 1
                }

                coverCompressionProgress = RepositoryCoverCompressionProgress(
                    phase: .running,
                    totalCount: assetIDs.count,
                    processedCount: index + 1,
                    compressedCount: compressedCount
                )
            }

            try await reloadFromCache(repositoryID: repository.id)
            let finishedAt = Date()
            coverCompressionProgress = RepositoryCoverCompressionProgress(
                phase: .completed,
                totalCount: assetIDs.count,
                processedCount: assetIDs.count,
                compressedCount: compressedCount
            )
            syncStatus = .upToDate(finishedAt)
            alertMessage = compressedCount == 0 ?
                localized(
                    "已检查 %d 张封面，没有需要压缩的图片。",
                    en: "Checked %d covers. None needed compression.",
                    arguments: [assetIDs.count]
                ) :
                localized(
                    "当前仓库整理完成，已压缩 %d 张封面图片。",
                    en: "Current library optimized. %d covers were compressed.",
                    arguments: [compressedCount]
                )
            return true
        } catch {
            coverCompressionProgress = nil
            let message = Self.userFacingMessage(for: error)
            alertMessage = message
            syncStatus = .failed(message)
            return false
        }
    }

    @discardableResult
    func clearCurrentRepository() async -> Bool {
        guard let repository = currentRepository else {
            alertMessage = localized("当前还没有仓库。", en: "There is no library yet.")
            return false
        }

        do {
            let resetLocations = LibraryLocation.defaultLocations()
            try await remoteService.clearRepository(repository, resetLocations: resetLocations)
            try await refreshFromCloud(repository: repository)
            alertMessage = localized("当前仓库已经清空。", en: "The current library has been cleared.")
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
            alertMessage = localized("当前还没有仓库。", en: "There is no library yet.")
            return nil
        }

        guard !isExportingRepository else {
            return nil
        }

        isExportingRepository = true
        exportProgress = RepositoryExportProgress(phase: .preparing, bookCount: nil)
        latestExportURL = nil
        defer {
            isExportingRepository = false
            exportProgress = nil
        }

        do {
            let package = try await remoteService.exportRepository(repository)
            exportProgress = RepositoryExportProgress(phase: .encoding, bookCount: package.books.count)
            let data = try LibraryJSONCodec.makeEncoder().encode(package)
            let exportDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("homeLibrary-exports", isDirectory: true)
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

            let sanitizedName = repository.name.replacingOccurrences(of: "/", with: "-").trimmed.nilIfEmpty ?? "homeLibrary"
            let url = exportDirectory.appendingPathComponent("\(sanitizedName)-\(Int(Date().timeIntervalSince1970)).zip")
            exportProgress = RepositoryExportProgress(phase: .archiving, bookCount: package.books.count)
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

    @discardableResult
    func removeRepository(_ repository: LibraryRepositoryReference) async -> Bool {
        guard availableRepositories.count > 1 else {
            alertMessage = localized("至少保留一个可访问的仓库。", en: "Keep at least one accessible library.")
            return false
        }

        guard !isCurrentRepository(repository) else {
            alertMessage = localized("不能删除当前正在使用的仓库。", en: "You can't delete the library currently in use.")
            return false
        }

        do {
            let previousCurrentRepository = currentRepository
            try await remoteService.deleteRepository(repository)
            try await clearCachedRepository(repositoryID: repository.id)
            sessionState.removeBookSortOrder(for: repository)
            try await refreshAvailableRepositories(selecting: previousCurrentRepository)
            persistSessionState()

            if !sameRepository(previousCurrentRepository, sessionState.currentRepository) {
                await loadBooks(force: true)
            }

            return true
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
            return false
        }
    }

    func makeSharingControllerForCurrentRepository() async throws -> UICloudSharingController {
        guard let repository = currentRepository,
              let service = remoteService as? CloudKitLibraryService else {
            throw LibraryRemoteServiceError.permissionDenied
        }

        return try await service.makeSharingController(for: repository)
    }

    @discardableResult
    func acceptShareLink(_ rawValue: String) async -> Bool {
        guard let service = remoteService as? any LibraryShareLinkAccepting else {
            alertMessage = localized("当前配置不支持通过链接加入共享仓库。", en: "This configuration does not support joining shared libraries by link.")
            return false
        }

        guard let url = Self.shareURL(from: rawValue) else {
            alertMessage = localized("请输入有效的 iCloud 共享链接。", en: "Enter a valid iCloud share link.")
            return false
        }

        guard !isAcceptingShareLink else {
            return false
        }

        isAcceptingShareLink = true
        defer { isAcceptingShareLink = false }

        do {
            let existingIDs = repositoryIdentitySet(from: availableRepositories)
            let metadata = try await service.acceptShare(from: url)
            try await finalizeAcceptedShare(
                existingIDs: existingIDs,
                preferredSharedZoneID: metadata.share.recordID.zoneID
            )

            if let repository = currentRepository {
                alertMessage = localized("已打开共享仓库：%@", en: "Opened shared library: %@", arguments: [repository.name])
            } else {
                alertMessage = localized("已接受共享邀请。", en: "Accepted the share invitation.")
            }

            return true
        } catch {
            let message = Self.userFacingMessage(for: error)
            alertMessage = message
            syncStatus = .failed(message)
            return false
        }
    }

    func acceptShareMetadata(_ metadata: CKShare.Metadata) async {
        guard let service = remoteService as? any LibraryShareMetadataAccepting else {
            return
        }

        do {
            let existingIDs = repositoryIdentitySet(from: availableRepositories)
            try await service.acceptShare(metadata: metadata)
            try await finalizeAcceptedShare(
                existingIDs: existingIDs,
                preferredSharedZoneID: metadata.share.recordID.zoneID
            )
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

        return localized("发生了未预期的错误。", en: "An unexpected error occurred.")
    }

    private var locationsByID: [String: LibraryLocation] {
        Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
    }

    private func finalizeAcceptedShare(
        existingIDs: Set<String>,
        preferredSharedZoneID: CKRecordZone.ID?
    ) async throws {
        let repositories = try await remoteService.listRepositories()
        availableRepositories = repositories

        if let repository = AcceptedShareRepositoryResolver.preferredRepository(
            from: repositories,
            existingIDs: existingIDs,
            preferredSharedZoneID: preferredSharedZoneID
        ) {
            sessionState.currentRepository = repository
            persistSessionState()
        }

        await loadBooks(force: true)
    }

    private func repositoryIdentitySet(from repositories: [LibraryRepositoryReference]) -> Set<String> {
        Set(repositories.map(AcceptedShareRepositoryResolver.repositoryIdentity(for:)))
    }

    private nonisolated static func shareURL(from rawValue: String) -> URL? {
        guard let trimmed = rawValue.trimmed.nilIfEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.path.contains("/share/") else {
            return nil
        }

        return url
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
           let resolvedRepository = repositories.first(where: { sameRepository($0, preferredRepository) }) {
            sessionState.currentRepository = resolvedRepository
        } else if let currentRepository = sessionState.currentRepository,
                  let resolvedRepository = repositories.first(where: { sameRepository($0, currentRepository) }) {
            sessionState.currentRepository = resolvedRepository
        } else {
            sessionState.currentRepository = repositories.first(where: \.isOwner) ?? repositories.first
        }
    }

    private func refreshFromCloud(repository: LibraryRepositoryReference) async throws {
        syncStatus = .syncing

        if let incrementalService = remoteService as? any LibraryRemoteIncrementalSyncing {
            try await refreshIncrementally(repository: repository, using: incrementalService)
            return
        }

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
            synchronizedAt: synchronizedAt,
            cloudKitChangeTokenData: nil,
            updatesCloudKitChangeToken: true
        )

        currentRepositoryChanged(snapshot.repository)
        try await reloadFromCache(repositoryID: snapshot.repository.id)
        validateSelectedLocation()
        syncStatus = .upToDate(synchronizedAt)
        try await refreshAvailableRepositories(selecting: snapshot.repository)
        persistSessionState()
    }

    private func refreshIncrementally(
        repository: LibraryRepositoryReference,
        using service: any LibraryRemoteIncrementalSyncing
    ) async throws {
        let previousChangeTokenData = try await cachedCloudKitChangeTokenData(repositoryID: repository.id)
        let changes = try await service.refreshRepositoryChanges(repository, since: previousChangeTokenData)
        let synchronizedAt = Date()
        let coverDataByAssetID = changes.books.reduce(into: [String: Data]()) { partialResult, snapshot in
            guard let assetID = snapshot.book.coverAssetID, let coverData = snapshot.coverData else {
                return
            }

            partialResult[assetID] = coverData
        }

        if changes.isFullRefresh {
            try await replaceCache(
                books: changes.books.map(\.book),
                locations: changes.locations,
                coverDataByAssetID: coverDataByAssetID,
                repositoryID: changes.repository.id,
                synchronizedAt: synchronizedAt,
                cloudKitChangeTokenData: changes.changeTokenData,
                updatesCloudKitChangeToken: true
            )
        } else {
            try await applyCacheChanges(
                changes,
                coverDataByAssetID: coverDataByAssetID,
                repositoryID: changes.repository.id,
                synchronizedAt: synchronizedAt
            )
        }

        currentRepositoryChanged(changes.repository)
        try await reloadFromCache(repositoryID: changes.repository.id)
        validateSelectedLocation()
        syncStatus = .upToDate(synchronizedAt)
        try await refreshAvailableRepositories(selecting: changes.repository)
        persistSessionState()
    }

    private func replaceCache(
        books: [Book],
        locations: [LibraryLocation],
        coverDataByAssetID: [String: Data],
        repositoryID: String,
        synchronizedAt: Date,
        cloudKitChangeTokenData: Data? = nil,
        updatesCloudKitChangeToken: Bool = false
    ) async throws {
        let cacheStore = self.cacheStore

        try await Task.detached(priority: .utility) {
            try cacheStore.replaceAllContent(
                books: books,
                locations: locations,
                coverDataByAssetID: coverDataByAssetID,
                repositoryID: repositoryID,
                synchronizedAt: synchronizedAt,
                cloudKitChangeTokenData: cloudKitChangeTokenData,
                updatesCloudKitChangeToken: updatesCloudKitChangeToken
            )
        }.value

        coverCache.merge(coverDataByAssetID) { _, new in new }
    }

    private func applyCacheChanges(
        _ changes: RemoteRepositoryChangeSet,
        coverDataByAssetID: [String: Data],
        repositoryID: String,
        synchronizedAt: Date
    ) async throws {
        let cacheStore = self.cacheStore

        try await Task.detached(priority: .utility) {
            try cacheStore.applyRemoteChanges(
                upsertingBooks: changes.books.map(\.book),
                deletingBookIDs: changes.deletedBookIDs,
                upsertingLocations: changes.locations,
                deletingLocationIDs: changes.deletedLocationIDs,
                coverDataByAssetID: coverDataByAssetID,
                repositoryID: repositoryID,
                synchronizedAt: synchronizedAt,
                cloudKitChangeTokenData: changes.changeTokenData
            )
        }.value

        coverCache.merge(coverDataByAssetID) { _, new in new }
    }

    private func cachedCloudKitChangeTokenData(repositoryID: String) async throws -> Data? {
        let cacheStore = self.cacheStore
        return try await Task.detached(priority: .utility) {
            try cacheStore.cloudKitChangeTokenData(repositoryID: repositoryID)
        }.value
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

    private func clearCachedRepository(repositoryID: String) async throws {
        let cacheStore = self.cacheStore
        try await Task.detached(priority: .utility) {
            try cacheStore.clearRepository(repositoryID)
        }.value
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
                    name: location.name.trimmed.nilIfEmpty ?? localized("地点 %d", en: "Location %d", arguments: [index + 1]),
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
        bookSortOrder = sessionState.bookSortOrder(for: repository)
        coverCompressionProgress = nil
    }

    private func sameRepository(_ lhs: LibraryRepositoryReference?, _ rhs: LibraryRepositoryReference?) -> Bool {
        guard let lhs, let rhs else {
            return false
        }

        return lhs.id == rhs.id && lhs.databaseScope == rhs.databaseScope
    }

    private func optimizedCoverData(_ data: Data?) async -> Data? {
        guard let data, !data.isEmpty else {
            return nil
        }

        return await Task.detached(priority: .utility) {
            LibraryCoverCompressor.compressIfNeeded(data).data
        }.value
    }

    private func compressedCoverResult(for data: Data?) async -> LibraryCoverCompressionResult? {
        guard let data, !data.isEmpty else {
            return nil
        }

        return await Task.detached(priority: .utility) {
            LibraryCoverCompressor.compressIfNeeded(data)
        }.value
    }

    private func cachedCoverData(for assetID: String, repositoryID: String) async throws -> Data? {
        let cacheStore = self.cacheStore
        return try await Task.detached(priority: .utility) {
            try cacheStore.coverData(for: assetID, repositoryID: repositoryID)
        }.value
    }
}
