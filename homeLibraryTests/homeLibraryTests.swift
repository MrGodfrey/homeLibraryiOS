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

    func testDebugBuildDefaultsToLocalDebugStorageWithoutCloudSync() {
        let configuration = LibraryAppConfiguration.live(environment: [:])

        XCTAssertEqual(configuration.sessionStore.namespace, LibraryAppConfiguration.localDebugNamespace)
        XCTAssertNil(configuration.remoteService)
        XCTAssertEqual(configuration.cacheStore.rootURL.lastPathComponent, "cloudkit-cache")
        XCTAssertEqual(
            configuration.cacheStore.rootURL.deletingLastPathComponent().lastPathComponent,
            LibraryAppConfiguration.localDebugNamespace
        )
    }

    func testExplicitEnvironmentCanReenableCloudSyncOutsideXCTest() {
        XCTAssertTrue(
            LibraryAppConfiguration.resolvedCloudSyncEnabled(
                environment: ["HOME_LIBRARY_ENABLE_CLOUD_SYNC": "1"]
            )
        )
        XCTAssertFalse(
            LibraryAppConfiguration.resolvedCloudSyncEnabled(
                environment: [
                    "HOME_LIBRARY_ENABLE_CLOUD_SYNC": "1",
                    "XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"
                ]
            )
        )
    }

    @MainActor
    func testStorePromotesLocalSessionToCloudRepositoryWhenCloudSyncBecomesAvailable() async throws {
        let namespace = "store-transition-\(UUID().uuidString)"
        let sessionStore = RepositorySessionStore(namespace: namespace)
        let sessionKey = "homeLibrary.repository.\(namespace).session"
        let ownerKey = "homeLibrary.repository.\(namespace).ownerProfileID"
        let migrationKey = "homeLibrary.repository.\(namespace).migration.cloud-owned"
        let currentRepository = LibraryRepositoryReference(
            id: "local-default",
            name: "本地调试仓库",
            role: .localOnly,
            accessAccount: nil,
            savedPassword: nil
        )
        let initialState = LibrarySessionState(
            ownerProfileID: "owner-profile",
            ownedRepository: nil,
            currentRepository: currentRepository
        )
        sessionStore.save(initialState)
        addTeardownBlock {
            UserDefaults.standard.removeObject(forKey: sessionKey)
            UserDefaults.standard.removeObject(forKey: ownerKey)
            UserDefaults.standard.removeObject(forKey: migrationKey)
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

        XCTAssertEqual(store.currentRepository?.id, "cloud-owned")
        XCTAssertEqual(store.currentRepository?.role, .owner)
        XCTAssertEqual(store.ownedRepository?.id, "cloud-owned")
        let bootstrapCallCount = await remoteService.bootstrapCallCountValue()
        XCTAssertEqual(bootstrapCallCount, 1)
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
    private var bootstrapCallCount = 0

    func bootstrapOwnedRepository(ownerProfileID: String, preferredName: String) async throws -> RepositoryBootstrapResult {
        bootstrapCallCount += 1

        let descriptor = RepositoryDescriptor(
            id: "cloud-owned",
            name: preferredName,
            ownerProfileID: ownerProfileID,
            accessAccount: "HL1001"
        )
        let credentials = RepositoryCredentials(account: "HL1001", password: "PASS-1001")
        return RepositoryBootstrapResult(descriptor: descriptor, credentials: credentials)
    }

    func fetchRepository(id: String) async throws -> RepositoryDescriptor {
        RepositoryDescriptor(
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

    func bootstrapCallCountValue() -> Int {
        bootstrapCallCount
    }
}
