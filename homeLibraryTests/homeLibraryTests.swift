//
//  homeLibraryTests.swift
//  homeLibraryTests
//
//  Created by Codex on 2026/4/14.
//

import Foundation
import XCTest
@testable import homeLibrary

final class homeLibraryTests: XCTestCase {

    func testFiltersBooksByLocationAndKeyword() {
        let books = [
            Book(
                id: "1",
                title: "三体",
                author: "刘慈欣",
                publisher: "重庆出版社",
                year: "2008",
                location: .chengdu,
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 20)
            ),
            Book(
                id: "2",
                title: "白夜行",
                author: "东野圭吾",
                publisher: "南海出版公司",
                year: "2013",
                location: .chongqing,
                customFields: ["备注": "已借出"],
                createdAt: Date(timeIntervalSince1970: 2),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        ]

        let filtered = LibraryFilter.filteredBooks(from: books, query: "借出", tab: .chongqing)

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.id, "2")
    }

    func testNormalizesDraftFieldsAndCustomFieldsBeforeSave() {
        let draft = BookDraft(
            title: "  家庭书库  ",
            author: "  王宇  ",
            publisher: "  自有出版社 ",
            year: " 2026 ",
            location: .chengdu,
            customFields: [
                "  备注  ": "  已整理  ",
                "空字段": "   "
            ],
            coverData: nil,
            keepsExistingCoverReference: true
        )

        let normalized = draft.normalized

        XCTAssertEqual(normalized.title, "家庭书库")
        XCTAssertEqual(normalized.author, "王宇")
        XCTAssertEqual(normalized.publisher, "自有出版社")
        XCTAssertEqual(normalized.year, "2026")
        XCTAssertEqual(normalized.customFields, ["备注": "已整理"])
        XCTAssertTrue(normalized.keepsExistingCoverReference)
    }

    func testBookPayloadDecodesLegacyISBNIntoCustomFields() throws {
        let json = """
        {
          "title" : "家庭书库",
          "author" : "王宇",
          "publisher" : "自有出版社",
          "year" : "2026",
          "isbn" : "9787111123456",
          "location" : "成都"
        }
        """

        let payload = try LibraryJSONCodec.makeDecoder().decode(BookPayload.self, from: Data(json.utf8))

        XCTAssertEqual(payload.customFields["ISBN"], "9787111123456")
        XCTAssertEqual(payload.schemaVersion, BookPayload.currentSchemaVersion)
    }

    func testRepositorySessionStorePersistsRepositoriesPerNamespace() throws {
        let suiteName = "homeLibraryTests.session.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let store = RepositorySessionStore(namespace: "primary")
        let ownedRepository = LibraryRepositoryReference(
            id: "repo-owner",
            name: "我的书库",
            role: .owner,
            accessAccount: "HL1111",
            savedPassword: "PASS-1111"
        )
        let joinedRepository = LibraryRepositoryReference(
            id: "repo-shared",
            name: "共享书库",
            role: .member,
            accessAccount: "HL2222",
            savedPassword: "PASS-2222"
        )
        let state = LibrarySessionState(
            ownerProfileID: "owner-profile",
            ownedRepository: ownedRepository,
            currentRepository: joinedRepository
        )

        store.save(state, userDefaults: userDefaults)

        let restoredState = store.load(userDefaults: userDefaults)
        XCTAssertEqual(restoredState, state)

        let secondaryState = RepositorySessionStore(namespace: "secondary").load(userDefaults: userDefaults)
        XCTAssertNil(secondaryState.ownedRepository)
        XCTAssertNil(secondaryState.currentRepository)
    }

    func testLiveConfigurationDefaultsToPrimaryStorageNamespace() {
        let configuration = LibraryAppConfiguration.live(
            environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]
        )

        XCTAssertEqual(configuration.sessionStore.namespace, "default")
        XCTAssertEqual(configuration.cacheStore.rootURL.lastPathComponent, "cloudkit-cache")
        XCTAssertEqual(
            configuration.cacheStore.rootURL.deletingLastPathComponent().lastPathComponent,
            "homeLibrary"
        )
    }

    func testMemoryRemoteDriverCanBeSelectedExplicitly() {
        let configuration = LibraryAppConfiguration.live(
            environment: [
                "HOME_LIBRARY_REMOTE_DRIVER": "memory",
                "HOME_LIBRARY_STORAGE_NAMESPACE": "memory-tests"
            ]
        )

        XCTAssertEqual(configuration.sessionStore.namespace, "memory-tests")
        XCTAssertTrue(configuration.remoteService is InMemoryLibraryRemoteService)
    }

    func testXCTestHostDefaultsToMemoryRemoteDriver() {
        let configuration = LibraryAppConfiguration.live(
            environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]
        )

        XCTAssertTrue(configuration.remoteService is InMemoryLibraryRemoteService)
    }

    func testUserFacingMessageForCloudKitNetworkFailureIsReadable() {
        let message = LibraryStore.userFacingMessage(for: LibraryRemoteServiceError.networkUnavailable)

        XCTAssertEqual(message, "CloudKit 网络连接失败，请确认 iPhone 已联网并关闭代理或 VPN 后重试。")
    }

    func testUserFacingMessageForCloudKitServiceUnavailableIncludesRetryAfter() {
        let message = LibraryStore.userFacingMessage(for: LibraryRemoteServiceError.serviceUnavailable(retryAfter: 3.2))

        XCTAssertEqual(message, "CloudKit 当前繁忙，请在 4 秒后重试。")
    }

    @MainActor
    func testStoreLeavesNewUserWithoutRepositoryWhenCloudIsEmpty() async throws {
        let namespace = "store-transition-\(UUID().uuidString)"
        let sessionStore = RepositorySessionStore(namespace: namespace)
        let ownerKey = "homeLibrary.repository.\(namespace).ownerProfileID"
        let sessionKey = "homeLibrary.repository.\(namespace).session"
        addTeardownBlock {
            UserDefaults.standard.removeObject(forKey: ownerKey)
            UserDefaults.standard.removeObject(forKey: sessionKey)
        }

        let tempRoot = try makeTemporaryDirectory()
        let remoteService = MockLibraryRemoteService()
        let configuration = LibraryAppConfiguration(
            cacheStore: LibraryCacheStore(rootURL: tempRoot.appendingPathComponent("cloudkit-cache", isDirectory: true)),
            legacyImporter: LegacyLibraryImporter(storageRootURL: tempRoot),
            sessionStore: sessionStore,
            remoteService: remoteService,
            preferredOwnedRepositoryName: "我的家庭书库"
        )

        let store = LibraryStore(configuration: configuration)
        await store.loadBooks(force: true)

        XCTAssertNil(store.currentRepository)
        XCTAssertNil(store.ownedRepository)
        XCTAssertEqual(store.books.count, 0)
        let fetchOwnedRepositoryCallCount = await remoteService.fetchOwnedRepositoryCallCountValue()
        XCTAssertEqual(fetchOwnedRepositoryCallCount, 1)
        let createOwnedRepositoryCallCount = await remoteService.createOwnedRepositoryCallCountValue()
        XCTAssertEqual(createOwnedRepositoryCallCount, 0)
    }

    @MainActor
    func testStoreAutoLoadsOwnedRepositoryWhenCloudAlreadyHasOne() async throws {
        let namespace = "store-discovery-\(UUID().uuidString)"
        let sessionStore = RepositorySessionStore(namespace: namespace)
        let ownerKey = "homeLibrary.repository.\(namespace).ownerProfileID"
        let sessionKey = "homeLibrary.repository.\(namespace).session"
        addTeardownBlock {
            UserDefaults.standard.removeObject(forKey: ownerKey)
            UserDefaults.standard.removeObject(forKey: sessionKey)
        }

        let tempRoot = try makeTemporaryDirectory()
        let discoveredRepository = RepositoryDescriptor(
            id: "cloud-owned",
            name: "我的家庭书库",
            ownerProfileID: "remote-owner-profile",
            accessAccount: "HL1001"
        )
        let remoteService = MockLibraryRemoteService(
            fetchedOwnedRepository: discoveredRepository
        )
        let configuration = LibraryAppConfiguration(
            cacheStore: LibraryCacheStore(rootURL: tempRoot.appendingPathComponent("cloudkit-cache", isDirectory: true)),
            legacyImporter: LegacyLibraryImporter(storageRootURL: tempRoot),
            sessionStore: sessionStore,
            remoteService: remoteService,
            preferredOwnedRepositoryName: "我的家庭书库"
        )

        let store = LibraryStore(configuration: configuration)
        await store.loadBooks(force: true)

        XCTAssertEqual(store.currentRepository?.id, "cloud-owned")
        XCTAssertEqual(store.currentRepository?.role, .owner)
        XCTAssertEqual(store.ownedRepository?.id, "cloud-owned")
        XCTAssertEqual(store.repositoryTitle, "我的家庭书库")
        XCTAssertEqual(sessionStore.load().ownerProfileID, "remote-owner-profile")
        let fetchOwnedRepositoryCallCount = await remoteService.fetchOwnedRepositoryCallCountValue()
        XCTAssertEqual(fetchOwnedRepositoryCallCount, 1)
        let createOwnedRepositoryCallCount = await remoteService.createOwnedRepositoryCallCountValue()
        XCTAssertEqual(createOwnedRepositoryCallCount, 0)
    }

    @MainActor
    func testStoreRestoresCachedBooksBeforeRemoteRefreshCompletes() async throws {
        let namespace = "store-cache-restore-\(UUID().uuidString)"
        let sessionStore = RepositorySessionStore(namespace: namespace)
        let ownerKey = "homeLibrary.repository.\(namespace).ownerProfileID"
        let sessionKey = "homeLibrary.repository.\(namespace).session"
        addTeardownBlock {
            UserDefaults.standard.removeObject(forKey: ownerKey)
            UserDefaults.standard.removeObject(forKey: sessionKey)
        }

        let currentRepository = LibraryRepositoryReference(
            id: "cached-repository",
            name: "我的家庭书库",
            role: .owner,
            accessAccount: "HL1001",
            savedPassword: "PASS-1001"
        )
        sessionStore.save(
            LibrarySessionState(
                ownerProfileID: "owner-profile",
                ownedRepository: currentRepository,
                currentRepository: currentRepository
            )
        )

        let tempRoot = try makeTemporaryDirectory()
        let cacheStore = LibraryCacheStore(rootURL: tempRoot.appendingPathComponent("cloudkit-cache", isDirectory: true))
        let cachedBook = Book(
            id: "cached-book",
            title: "缓存里的书",
            author: "作者 A",
            location: .chengdu,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        try cacheStore.replaceAllBooks(
            [cachedBook],
            coverDataByAssetID: [:],
            repositoryID: currentRepository.id,
            synchronizedAt: Date(timeIntervalSince1970: 2)
        )

        let remoteService = SlowFetchLibraryRemoteService(
            repositoryDescriptor: RepositoryDescriptor(
                id: currentRepository.id,
                name: currentRepository.name,
                ownerProfileID: "owner-profile",
                accessAccount: currentRepository.accessAccount ?? "HL1001"
            ),
            snapshots: [
                RemoteBookSnapshot(
                    book: Book(
                        id: "remote-book",
                        title: "云端里的书",
                        author: "作者 B",
                        location: .chongqing,
                        createdAt: Date(timeIntervalSince1970: 10),
                        updatedAt: Date(timeIntervalSince1970: 11)
                    ),
                    coverData: nil
                )
            ]
        )
        let configuration = LibraryAppConfiguration(
            cacheStore: cacheStore,
            legacyImporter: LegacyLibraryImporter(storageRootURL: tempRoot),
            sessionStore: sessionStore,
            remoteService: remoteService,
            preferredOwnedRepositoryName: "我的家庭书库"
        )

        let store = LibraryStore(configuration: configuration)
        let loadTask = Task {
            await store.loadBooks(force: true)
        }

        await remoteService.waitUntilFetchBooksStarts()

        XCTAssertEqual(store.books.map(\.id), ["cached-book"])
        XCTAssertFalse(store.isLoading)

        await remoteService.resumeFetchBooks()
        await loadTask.value

        XCTAssertEqual(store.books.map(\.id), ["remote-book"])
    }

    @MainActor
    func testCreateOwnedRepositoryRequiresExplicitAction() async throws {
        let namespace = "store-create-\(UUID().uuidString)"
        let sessionStore = RepositorySessionStore(namespace: namespace)
        let ownerKey = "homeLibrary.repository.\(namespace).ownerProfileID"
        let sessionKey = "homeLibrary.repository.\(namespace).session"
        addTeardownBlock {
            UserDefaults.standard.removeObject(forKey: ownerKey)
            UserDefaults.standard.removeObject(forKey: sessionKey)
        }

        let tempRoot = try makeTemporaryDirectory()
        let createdRepository = RepositoryBootstrapResult(
            descriptor: RepositoryDescriptor(
                id: "created-owned",
                name: "我的家庭书库",
                ownerProfileID: "owner-profile",
                accessAccount: "HL1001"
            ),
            credentials: RepositoryCredentials(account: "HL1001", password: "PASS-1001")
        )
        let remoteService = MockLibraryRemoteService(
            fetchedOwnedRepository: nil,
            createdOwnedRepository: createdRepository
        )
        let configuration = LibraryAppConfiguration(
            cacheStore: LibraryCacheStore(rootURL: tempRoot.appendingPathComponent("cloudkit-cache", isDirectory: true)),
            legacyImporter: LegacyLibraryImporter(storageRootURL: tempRoot),
            sessionStore: sessionStore,
            remoteService: remoteService,
            preferredOwnedRepositoryName: "我的家庭书库"
        )

        let store = LibraryStore(configuration: configuration)
        let didCreate = await store.createOwnedRepository()

        XCTAssertTrue(didCreate)
        XCTAssertEqual(store.currentRepository?.id, "created-owned")
        XCTAssertEqual(store.ownedRepository?.credentials?.password, "PASS-1001")
        let createOwnedRepositoryCallCount = await remoteService.createOwnedRepositoryCallCountValue()
        XCTAssertEqual(createOwnedRepositoryCallCount, 1)
    }

    @MainActor
    func testImportLegacyJSONCreatesOwnedRepositoryAndLoadsBooks() async throws {
        let namespace = "store-import-\(UUID().uuidString)"
        let sessionStore = RepositorySessionStore(namespace: namespace)
        let ownerKey = "homeLibrary.repository.\(namespace).ownerProfileID"
        let sessionKey = "homeLibrary.repository.\(namespace).session"
        addTeardownBlock {
            UserDefaults.standard.removeObject(forKey: ownerKey)
            UserDefaults.standard.removeObject(forKey: sessionKey)
        }

        let tempRoot = try makeTemporaryDirectory()
        let importURL = tempRoot.appendingPathComponent("LegacyImport.json")
        let payload = """
        {
          "schemaVersion" : 1,
          "source" : "unit-test",
          "books" : [
            {
              "id" : "legacy-book-1",
              "title" : "旧书导入",
              "author" : "作者 A",
              "publisher" : "出版社 A",
              "year" : "2024",
              "location" : "成都",
              "customFields" : {
                "备注" : "测试"
              },
              "createdAt" : "\(LibraryJSONCodec.encodeDate(Date(timeIntervalSince1970: 1)))",
              "updatedAt" : "\(LibraryJSONCodec.encodeDate(Date(timeIntervalSince1970: 2)))"
            }
          ]
        }
        """
        try Data(payload.utf8).write(to: importURL, options: [.atomic])

        let configuration = LibraryAppConfiguration(
            cacheStore: LibraryCacheStore(rootURL: tempRoot.appendingPathComponent("cloudkit-cache", isDirectory: true)),
            legacyImporter: LegacyLibraryImporter(storageRootURL: tempRoot),
            sessionStore: sessionStore,
            remoteService: InMemoryLibraryRemoteService(),
            preferredOwnedRepositoryName: "我的家庭书库"
        )

        let store = LibraryStore(configuration: configuration)
        let didImport = await store.importLegacyJSON(from: importURL)

        XCTAssertTrue(didImport)
        XCTAssertEqual(store.currentRepository?.role, .owner)
        XCTAssertEqual(store.books.map(\.id), ["legacy-book-1"])
        XCTAssertEqual(store.books.first?.title, "旧书导入")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

private actor MockLibraryRemoteService: LibraryRemoteSyncing {
    private let fetchedOwnedRepository: RepositoryDescriptor?
    private let createdOwnedRepository: RepositoryBootstrapResult?
    private var fetchOwnedRepositoryCallCount = 0
    private var createOwnedRepositoryCallCount = 0

    init(
        fetchedOwnedRepository: RepositoryDescriptor? = nil,
        createdOwnedRepository: RepositoryBootstrapResult? = nil
    ) {
        self.fetchedOwnedRepository = fetchedOwnedRepository
        self.createdOwnedRepository = createdOwnedRepository
    }

    func fetchOwnedRepository(ownerProfileID: String) async throws -> RepositoryDescriptor? {
        _ = ownerProfileID
        fetchOwnedRepositoryCallCount += 1
        return fetchedOwnedRepository
    }

    func createOwnedRepository(ownerProfileID: String, preferredName: String) async throws -> RepositoryBootstrapResult {
        createOwnedRepositoryCallCount += 1

        if let createdOwnedRepository {
            return createdOwnedRepository
        }

        let descriptor = RepositoryDescriptor(
            id: "created-owned",
            name: preferredName,
            ownerProfileID: ownerProfileID,
            accessAccount: "HL1001"
        )
        let credentials = RepositoryCredentials(account: "HL1001", password: "PASS-1001")
        return RepositoryBootstrapResult(descriptor: descriptor, credentials: credentials)
    }

    func fetchRepository(id: String) async throws -> RepositoryDescriptor {
        if let fetchedOwnedRepository, fetchedOwnedRepository.id == id {
            return fetchedOwnedRepository
        }

        if let createdOwnedRepository, createdOwnedRepository.descriptor.id == id {
            return createdOwnedRepository.descriptor
        }

        return RepositoryDescriptor(
            id: id,
            name: "我的家庭书库",
            ownerProfileID: "owner-profile",
            accessAccount: "HL1001"
        )
    }

    func joinRepository(account: String, password: String) async throws -> RepositoryDescriptor {
        throw XCTSkip("unused in this test")
    }

    func rotateCredentials(for repositoryID: String, ownerProfileID: String) async throws -> RepositoryCredentials {
        throw XCTSkip("unused in this test")
    }

    func fetchBooks(in repositoryID: String) async throws -> [RemoteBookSnapshot] {
        []
    }

    func upsertBook(_ book: Book, coverData: Data?, in repositoryID: String) async throws -> RemoteBookSnapshot {
        throw XCTSkip("unused in this test")
    }

    func deleteBook(id: String, deletedAt: Date, in repositoryID: String) async throws {
        throw XCTSkip("unused in this test")
    }

    func fetchOwnedRepositoryCallCountValue() -> Int {
        fetchOwnedRepositoryCallCount
    }

    func createOwnedRepositoryCallCountValue() -> Int {
        createOwnedRepositoryCallCount
    }
}

private actor SlowFetchLibraryRemoteService: LibraryRemoteSyncing {
    private let repositoryDescriptor: RepositoryDescriptor
    private let snapshots: [RemoteBookSnapshot]

    private var fetchBooksStarted = false
    private var fetchBooksStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var fetchBooksResumeContinuation: CheckedContinuation<Void, Never>?

    init(repositoryDescriptor: RepositoryDescriptor, snapshots: [RemoteBookSnapshot]) {
        self.repositoryDescriptor = repositoryDescriptor
        self.snapshots = snapshots
    }

    func fetchOwnedRepository(ownerProfileID: String) async throws -> RepositoryDescriptor? {
        _ = ownerProfileID
        return repositoryDescriptor
    }

    func createOwnedRepository(ownerProfileID: String, preferredName: String) async throws -> RepositoryBootstrapResult {
        _ = ownerProfileID
        _ = preferredName
        throw XCTSkip("unused in this test")
    }

    func fetchRepository(id: String) async throws -> RepositoryDescriptor {
        XCTAssertEqual(id, repositoryDescriptor.id)
        return repositoryDescriptor
    }

    func joinRepository(account: String, password: String) async throws -> RepositoryDescriptor {
        _ = account
        _ = password
        throw XCTSkip("unused in this test")
    }

    func rotateCredentials(for repositoryID: String, ownerProfileID: String) async throws -> RepositoryCredentials {
        _ = repositoryID
        _ = ownerProfileID
        throw XCTSkip("unused in this test")
    }

    func fetchBooks(in repositoryID: String) async throws -> [RemoteBookSnapshot] {
        XCTAssertEqual(repositoryID, repositoryDescriptor.id)
        fetchBooksStarted = true
        let waiters = fetchBooksStartWaiters
        fetchBooksStartWaiters.removeAll()
        waiters.forEach { $0.resume() }

        await withCheckedContinuation { continuation in
            fetchBooksResumeContinuation = continuation
        }

        return snapshots
    }

    func upsertBook(_ book: Book, coverData: Data?, in repositoryID: String) async throws -> RemoteBookSnapshot {
        _ = book
        _ = coverData
        _ = repositoryID
        throw XCTSkip("unused in this test")
    }

    func deleteBook(id: String, deletedAt: Date, in repositoryID: String) async throws {
        _ = id
        _ = deletedAt
        _ = repositoryID
        throw XCTSkip("unused in this test")
    }

    func waitUntilFetchBooksStarts() async {
        if fetchBooksStarted {
            return
        }

        await withCheckedContinuation { continuation in
            fetchBooksStartWaiters.append(continuation)
        }
    }

    func resumeFetchBooks() {
        fetchBooksResumeContinuation?.resume()
        fetchBooksResumeContinuation = nil
    }
}
