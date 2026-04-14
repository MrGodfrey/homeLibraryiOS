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
    @Published private(set) var syncTarget: LibrarySyncTarget
    @Published var alertMessage: String?

    private let configuration: LibraryAppConfiguration
    private let localStore: LibraryDiskStore
    private var hasLoaded = false
    private var coverCache: [String: Data] = [:]

    init(configuration: LibraryAppConfiguration) {
        self.configuration = configuration
        self.localStore = configuration.localStore
        self.syncTarget = configuration.initialSyncTarget
        self.syncStatus = configuration.cloudSyncConfiguration.isEnabled ? .idle : .unavailable
    }

    var visibleBooks: [Book] {
        LibraryFilter.filteredBooks(from: books, query: searchText, tab: activeTab)
    }

    var syncDestinationTitle: String {
        syncTarget.destinationTitle
    }

    var syncDestinationSubtitle: String {
        syncTarget.destinationSubtitle
    }

    var hasStoredSharedFolder: Bool {
        syncTarget.hasStoredSharedFolder
    }

    var usesSharedFolder: Bool {
        syncTarget.usesSharedFolder
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
            try await prepareLocalStoreIfNeeded()
            try await reloadFromLocal()
            hasLoaded = true
            await synchronizeWithCloud(showAlertOnFailure: false)
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
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
            try await prepareLocalStoreIfNeeded()

            let now = Date()
            let book = Book(
                id: existingBook?.id ?? UUID().uuidString,
                title: normalizedDraft.title,
                author: normalizedDraft.author,
                publisher: normalizedDraft.publisher,
                year: normalizedDraft.year,
                isbn: normalizedDraft.isbn,
                location: normalizedDraft.location,
                coverAssetID: existingBook?.coverAssetID,
                createdAt: existingBook?.createdAt ?? now,
                updatedAt: now
            )

            let localStore = self.localStore
            let storedBook = try await Task.detached(priority: .utility) {
                try localStore.upsert(book: book, coverData: normalizedDraft.coverData)
            }.value

            if let assetID = storedBook.coverAssetID, let coverData = normalizedDraft.coverData {
                coverCache[assetID] = coverData
            }

            try await reloadFromLocal()
            await synchronizeWithCloud(
                showAlertOnFailure: true,
                failureMessagePrefix: "本地已保存，但同步失败"
            )
            return true
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
            return false
        }
    }

    @discardableResult
    func deleteBook(_ book: Book) async -> Bool {
        isSaving = true
        defer { isSaving = false }

        do {
            try await prepareLocalStoreIfNeeded()

            let localStore = self.localStore
            let deletedAt = Date()

            try await Task.detached(priority: .utility) {
                try localStore.recordDeletion(for: book.id, deletedAt: deletedAt)
            }.value

            try await reloadFromLocal()
            await synchronizeWithCloud(
                showAlertOnFailure: true,
                failureMessagePrefix: "本地已保存，但同步失败"
            )
            return true
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
            return false
        }
    }

    func coverData(for assetID: String?) async -> Data? {
        guard let assetID else {
            return nil
        }

        if let cached = coverCache[assetID] {
            return cached
        }

        let localStore = self.localStore

        do {
            let data = try await Task.detached(priority: .utility) {
                try localStore.coverData(for: assetID)
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
        guard let assetID else {
            return nil
        }

        if let cached = coverCache[assetID] {
            return cached
        }

        guard let data = try? localStore.coverData(for: assetID) else {
            return nil
        }

        coverCache[assetID] = data
        return data
    }

    func connectSharedFolder(at folderURL: URL) async {
        do {
            let bookmark = try SharedLibraryFolderBookmark.make(from: folderURL)
            let candidateTarget = syncTarget.switchingToSharedFolder(bookmark)

            try await prepareLocalStoreIfNeeded()

            let didSync = await synchronizeWithCloud(
                using: candidateTarget,
                showAlertOnFailure: true,
                failureMessagePrefix: "同步失败"
            )

            guard didSync else {
                return
            }

            persistSyncTarget(candidateTarget)
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
        }
    }

    func usePersonalCloudSync() async {
        let candidateTarget = syncTarget.switchingToPersonalCloud()
        persistSyncTarget(candidateTarget)
        await synchronizeWithCloud(showAlertOnFailure: true, failureMessagePrefix: "同步失败")
    }

    func useStoredSharedFolderIfAvailable() async {
        guard let sharedFolderBookmark = syncTarget.sharedFolderBookmark else {
            alertMessage = "还没有配置共享书库文件夹。"
            return
        }

        let candidateTarget = syncTarget.switchingToSharedFolder(sharedFolderBookmark)
        let didSync = await synchronizeWithCloud(
            using: candidateTarget,
            showAlertOnFailure: true,
            failureMessagePrefix: "同步失败"
        )

        guard didSync else {
            return
        }

        persistSyncTarget(candidateTarget)
    }

    func clearSharedFolderConfiguration() async {
        let candidateTarget = syncTarget.removingSharedFolder()
        persistSyncTarget(candidateTarget)
        await synchronizeWithCloud(showAlertOnFailure: false)
    }

    static func userFacingMessage(for error: Error) -> String {
        if let localizedDescription = error.localizedDescription.trimmed.nilIfEmpty {
            return localizedDescription
        }

        return "发生了未预期的错误。"
    }

    private func prepareLocalStoreIfNeeded() async throws {
        let localStore = self.localStore
        let legacyBooksURL = configuration.legacyBooksURL
        let bundledSeedURL = configuration.bundledSeedURL
        let allowBundledSeed = configuration.allowBundledSeed

        try await Task.detached(priority: .utility) {
            try localStore.prepareForUse(
                legacyBooksURL: legacyBooksURL,
                bundledSeedURL: bundledSeedURL,
                allowBundledSeed: allowBundledSeed
            )
        }.value
    }

    private func reloadFromLocal() async throws {
        let localStore = self.localStore
        let snapshot = try await Task.detached(priority: .utility) {
            try localStore.loadSnapshot()
        }.value

        books = snapshot.books
        coverCache = coverCache.filter { snapshot.referencedAssetIDs.contains($0.key) }
    }

    private func synchronizeWithCloud(
        showAlertOnFailure: Bool,
        failureMessagePrefix: String = "同步失败"
    ) async {
        _ = await synchronizeWithCloud(
            using: syncTarget,
            showAlertOnFailure: showAlertOnFailure,
            failureMessagePrefix: failureMessagePrefix
        )
    }

    @discardableResult
    private func synchronizeWithCloud(
        using syncTarget: LibrarySyncTarget,
        showAlertOnFailure: Bool,
        failureMessagePrefix: String
    ) async -> Bool {
        guard configuration.cloudSyncConfiguration.isEnabled else {
            syncStatus = .unavailable
            return false
        }

        syncStatus = .syncing
        let syncEngine = makeSyncEngine(using: syncTarget)

        do {
            let result = try await Task.detached(priority: .utility) {
                try syncEngine.sync()
            }.value

            if result.isCloudAvailable {
                syncStatus = .upToDate(result.synchronizedAt ?? .now)

                do {
                    try await reloadFromLocal()
                } catch {
                    alertMessage = Self.userFacingMessage(for: error)
                }

                return true
            }

            syncStatus = .unavailable
            return false
        } catch {
            let message = Self.userFacingMessage(for: error)
            syncStatus = .failed(message)

            if showAlertOnFailure {
                alertMessage = "\(failureMessagePrefix)：\(message)"
            }

            return false
        }
    }

    private func makeSyncEngine(using syncTarget: LibrarySyncTarget) -> LibrarySyncEngine {
        var cloudSyncConfiguration = configuration.cloudSyncConfiguration
        cloudSyncConfiguration.syncTarget = syncTarget
        return LibrarySyncEngine(localStore: localStore, configuration: cloudSyncConfiguration)
    }

    private func persistSyncTarget(_ syncTarget: LibrarySyncTarget) {
        self.syncTarget = syncTarget
        configuration.syncSettingsStore.save(syncTarget)
    }
}
