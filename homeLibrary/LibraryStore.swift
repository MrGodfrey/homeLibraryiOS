//
//  LibraryStore.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import Combine
import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published var searchText = ""
    @Published var activeTab: LibraryFilterTab = .all
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var syncStatus: LibrarySyncStatus
    @Published private(set) var currentRepository: LibraryRepositoryReference?
    @Published private(set) var ownedRepository: LibraryRepositoryReference?
    @Published var alertMessage: String?

    private let configuration: LibraryAppConfiguration
    private let cacheStore: LibraryCacheStore
    private let sessionStore: RepositorySessionStore
    private let remoteService: any LibraryRemoteSyncing

    private var sessionState: LibrarySessionState
    private var hasLoaded = false
    private var coverCache: [String: Data] = [:]

    init(configuration: LibraryAppConfiguration) {
        self.configuration = configuration
        self.cacheStore = configuration.cacheStore
        self.sessionStore = configuration.sessionStore
        self.remoteService = configuration.remoteService
        self.sessionState = configuration.sessionStore.load()
        self.ownedRepository = sessionState.ownedRepository
        self.currentRepository = sessionState.currentRepository
        self.syncStatus = .idle
    }

    var visibleBooks: [Book] {
        LibraryFilter.filteredBooks(from: books, query: searchText, tab: activeTab)
    }

    var repositoryTitle: String {
        currentRepository?.name ?? "正在准备仓库"
    }

    var repositorySubtitle: String {
        currentRepository?.subtitle ?? "首次启动时会自动创建你的 CloudKit 仓库。"
    }

    var repositoryRoleTitle: String {
        currentRepository?.role.title ?? "未连接"
    }

    var repositoryCredentials: RepositoryCredentials? {
        guard currentRepository?.isOwner == true else {
            return nil
        }

        return currentRepository?.credentials
    }

    var canManageCloudRepository: Bool {
        true
    }

    var canSwitchToOwnedRepository: Bool {
        guard let ownedRepository else {
            return false
        }

        return currentRepository?.id != ownedRepository.id
    }

    func loadBooksIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        await loadBooks(force: true)
    }

    func loadBooks(force: Bool = false) async {
        guard force || !isLoading else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let repository = try await ensureCurrentRepositoryIfNeeded()

            if repository.isOwner {
                try await seedOwnedRepositoryIfNeeded(into: repository)
            }

            try await refreshFromCloud()
            hasLoaded = true
        } catch {
            let message = Self.userFacingMessage(for: error)
            alertMessage = message
            syncStatus = .failed(message)
        }
    }

    @discardableResult
    func saveBook(draft: BookDraft, editing existingBook: Book?) async -> Bool {
        let normalizedDraft = draft.normalized

        guard normalizedDraft.canSave else {
            alertMessage = "书名不能为空。"
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let repository = try await ensureCurrentRepositoryIfNeeded()
            let now = Date()
            let preservedCoverAssetID = normalizedDraft.keepsExistingCoverReference ? existingBook?.coverAssetID : nil
            let book = Book(
                id: existingBook?.id ?? UUID().uuidString,
                title: normalizedDraft.title,
                author: normalizedDraft.author,
                publisher: normalizedDraft.publisher,
                year: normalizedDraft.year,
                location: normalizedDraft.location,
                customFields: normalizedDraft.customFields,
                coverAssetID: preservedCoverAssetID,
                createdAt: existingBook?.createdAt ?? now,
                updatedAt: now
            )

            syncStatus = .syncing

            let snapshot = try await remoteService.upsertBook(
                book,
                coverData: normalizedDraft.coverData,
                in: repository.id
            )

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
        isSaving = true
        defer { isSaving = false }

        do {
            let repository = try await ensureCurrentRepositoryIfNeeded()
            let deletedAt = Date()

            syncStatus = .syncing
            try await remoteService.deleteBook(id: book.id, deletedAt: deletedAt, in: repository.id)
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

        let cacheStore = self.cacheStore

        do {
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
    func joinRepository(account: String, password: String) async -> Bool {
        do {
            let descriptor = try await remoteService.joinRepository(account: account, password: password)
            let joinedRepository = LibraryRepositoryReference(
                id: descriptor.id,
                name: descriptor.name,
                role: .member,
                accessAccount: descriptor.accessAccount,
                savedPassword: password.trimmed
            )

            sessionState.currentRepository = joinedRepository
            persistSessionState()
            await loadBooks(force: true)
            return true
        } catch {
            let message = Self.userFacingMessage(for: error)
            alertMessage = message
            syncStatus = .failed(message)
            return false
        }
    }

    func switchToOwnedRepository() async {
        guard let ownedRepository = sessionState.ownedRepository else {
            alertMessage = "当前设备还没有自己的仓库。"
            return
        }

        sessionState.currentRepository = ownedRepository
        persistSessionState()
        await loadBooks(force: true)
    }

    @discardableResult
    func regenerateOwnedRepositoryCredentials() async -> Bool {
        guard let ownedRepository = sessionState.ownedRepository else {
            alertMessage = "当前没有可管理的 CloudKit 仓库。"
            return false
        }

        do {
            let credentials = try await remoteService.rotateCredentials(
                for: ownedRepository.id,
                ownerProfileID: sessionState.ownerProfileID
            )

            let updatedOwnedRepository = LibraryRepositoryReference(
                id: ownedRepository.id,
                name: ownedRepository.name,
                role: .owner,
                accessAccount: credentials.account,
                savedPassword: credentials.password
            )

            sessionState.ownedRepository = updatedOwnedRepository

            if sessionState.currentRepository?.id == updatedOwnedRepository.id {
                sessionState.currentRepository = updatedOwnedRepository
            }

            persistSessionState()
            alertMessage = "已生成新的仓库账号密码。"
            return true
        } catch {
            let message = Self.userFacingMessage(for: error)
            alertMessage = message
            syncStatus = .failed(message)
            return false
        }
    }

    static func userFacingMessage(for error: Error) -> String {
        if let localizedDescription = error.localizedDescription.trimmed.nilIfEmpty {
            return localizedDescription
        }

        return "发生了未预期的错误。"
    }

    private func refreshFromCloud() async throws {
        guard let repository = currentRepository else {
            return
        }

        syncStatus = .syncing
        let snapshots = try await remoteService.fetchBooks(in: repository.id)
        let synchronizedAt = Date()
        try await replaceCache(with: snapshots, repositoryID: repository.id, synchronizedAt: synchronizedAt)
        try await reloadFromCache(repositoryID: repository.id)
        try await reconcileRepositoryMetadata(for: repository.id)
        syncStatus = .upToDate(synchronizedAt)
    }

    private func ensureCurrentRepositoryIfNeeded() async throws -> LibraryRepositoryReference {
        if let currentRepository = sessionState.currentRepository {
            currentRepositoryChanged(currentRepository)
            return currentRepository
        }

        if let ownedRepository = sessionState.ownedRepository {
            sessionState.currentRepository = ownedRepository
            persistSessionState()
            return ownedRepository
        }

        let bootstrap = try await remoteService.bootstrapOwnedRepository(
            ownerProfileID: sessionState.ownerProfileID,
            preferredName: configuration.preferredOwnedRepositoryName
        )

        let ownedRepository = LibraryRepositoryReference(
            id: bootstrap.descriptor.id,
            name: bootstrap.descriptor.name,
            role: .owner,
            accessAccount: bootstrap.credentials.account,
            savedPassword: bootstrap.credentials.password
        )

        sessionState.ownedRepository = ownedRepository
        sessionState.currentRepository = ownedRepository
        persistSessionState()
        return ownedRepository
    }

    private func seedOwnedRepositoryIfNeeded(into repository: LibraryRepositoryReference) async throws {
        guard !sessionStore.hasCompletedLegacyMigration(for: repository.id) else {
            return
        }

        let importer = configuration.legacyImporter
        let importedBooks = try await Task.detached(priority: .utility) {
            try importer.loadBooks()
        }.value

        if importedBooks.isEmpty {
            sessionStore.markLegacyMigrationCompleted(for: repository.id)
            return
        }

        let remoteBooks = try await remoteService.fetchBooks(in: repository.id)
        guard remoteBooks.isEmpty else {
            sessionStore.markLegacyMigrationCompleted(for: repository.id)
            return
        }

        for imported in importedBooks.sorted(by: { $0.book.updatedAt < $1.book.updatedAt }) {
            _ = try await remoteService.upsertBook(imported.book, coverData: imported.coverData, in: repository.id)
        }

        try await Task.detached(priority: .utility) {
            try importer.cleanupAfterMigration()
        }.value

        sessionStore.markLegacyMigrationCompleted(for: repository.id)
    }

    private func reconcileRepositoryMetadata(for repositoryID: String) async throws {
        let descriptor = try await remoteService.fetchRepository(id: repositoryID)

        if var ownedRepository = sessionState.ownedRepository, ownedRepository.id == repositoryID {
            ownedRepository.name = descriptor.name
            ownedRepository.accessAccount = descriptor.accessAccount
            sessionState.ownedRepository = ownedRepository
        }

        if var currentRepository = sessionState.currentRepository, currentRepository.id == repositoryID {
            currentRepository.name = descriptor.name
            currentRepository.accessAccount = descriptor.accessAccount
            sessionState.currentRepository = currentRepository
        }

        persistSessionState()
    }

    private func replaceCache(
        with snapshots: [RemoteBookSnapshot],
        repositoryID: String,
        synchronizedAt: Date
    ) async throws {
        let books = snapshots.map(\.book)
        let coverDataByAssetID = snapshots.reduce(into: [String: Data]()) { partialResult, snapshot in
            guard let assetID = snapshot.book.coverAssetID, let coverData = snapshot.coverData else {
                return
            }

            partialResult[assetID] = coverData
        }

        let cacheStore = self.cacheStore

        try await Task.detached(priority: .utility) {
            try cacheStore.replaceAllBooks(
                books,
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
            try cacheStore.upsert(
                book: snapshot.book,
                coverData: snapshot.coverData,
                repositoryID: repositoryID
            )
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
        coverCache = coverCache.filter { snapshot.referencedAssetIDs.contains($0.key) }
    }

    private func loadCacheSnapshot(repositoryID: String) async throws -> LibraryCacheSnapshot {
        let cacheStore = self.cacheStore
        return try await Task.detached(priority: .utility) {
            try cacheStore.loadSnapshot(repositoryID: repositoryID)
        }.value
    }

    private func persistSessionState() {
        sessionStore.save(sessionState)
        currentRepositoryChanged(sessionState.currentRepository)
    }

    private func currentRepositoryChanged(_ repository: LibraryRepositoryReference?) {
        currentRepository = repository
        ownedRepository = sessionState.ownedRepository
    }
}
