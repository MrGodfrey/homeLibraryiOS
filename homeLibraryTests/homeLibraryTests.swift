//
//  homeLibraryTests.swift
//  homeLibraryTests
//
//  Created by Codex on 2026/4/14.
//

import CloudKit
import Foundation
import XCTest
@testable import homeLibrary

final class homeLibraryTests: XCTestCase {

    func testFiltersBooksByDynamicLocationAndKeyword() {
        let locations = [
            LibraryLocation(id: "cd", name: "成都", sortOrder: 0),
            LibraryLocation(id: "cq", name: "重庆", sortOrder: 1)
        ]
        let locationsByID = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
        let books = [
            Book(
                id: "1",
                title: "三体",
                author: "刘慈欣",
                publisher: "重庆出版社",
                year: "2008",
                locationID: "cd",
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 20)
            ),
            Book(
                id: "2",
                title: "白夜行",
                author: "东野圭吾",
                publisher: "南海出版公司",
                year: "2013",
                locationID: "cq",
                customFields: ["备注": "已借出"],
                createdAt: Date(timeIntervalSince1970: 2),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        ]

        let filtered = LibraryFilter.filteredBooks(
            from: books,
            query: "借出",
            selectedLocationID: "cq",
            locationsByID: locationsByID
        )

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.id, "2")
    }

    func testNormalizesDraftFieldsAndCustomFieldsBeforeSave() {
        let draft = BookDraft(
            title: "  家庭书库  ",
            author: "  王宇  ",
            publisher: "  自有出版社 ",
            year: " 2026 ",
            locationID: "  cd ",
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
        XCTAssertEqual(normalized.locationID, "cd")
        XCTAssertEqual(normalized.customFields, ["备注": "已整理"])
        XCTAssertTrue(normalized.keepsExistingCoverReference)
    }

    func testBookPayloadDecodesLegacyLocationIntoDynamicLocationID() throws {
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
        XCTAssertEqual(payload.locationID, "location.chengdu")
        XCTAssertEqual(payload.schemaVersion, 1)
    }

    func testRepositorySessionStorePersistsCurrentRepositoryPerNamespace() throws {
        let suiteName = "homeLibraryTests.session.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let store = RepositorySessionStore(namespace: "primary")
        let currentRepository = LibraryRepositoryReference(
            id: "repo-owner",
            name: "我的书库",
            role: .owner,
            databaseScope: .private,
            zoneName: "library.test",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: nil,
            shareStatus: .notShared
        )
        let state = LibrarySessionState(currentRepository: currentRepository)

        store.save(state, userDefaults: userDefaults)

        let restoredState = store.load(userDefaults: userDefaults)
        XCTAssertEqual(restoredState, state)

        let secondaryState = RepositorySessionStore(namespace: "secondary").load(userDefaults: userDefaults)
        XCTAssertNil(secondaryState.currentRepository)
    }

    func testLiveConfigurationDefaultsToPrimaryStorageNamespace() {
        let configuration = LibraryAppConfiguration.live(
            environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]
        )

        XCTAssertEqual(configuration.sessionStore.namespace, "default")
        XCTAssertEqual(configuration.cacheStore.rootURL.lastPathComponent, "cloudkit-cache")
        XCTAssertTrue(configuration.remoteService is InMemoryLibraryRemoteService)
    }

    func testCloudKitOverrideWinsInsideXCTestHost() {
        let configuration = LibraryAppConfiguration.live(
            environment: [
                "XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration",
                "HOME_LIBRARY_REMOTE_DRIVER": "cloudkit"
            ]
        )

        XCTAssertTrue(configuration.remoteService is CloudKitLibraryService)
    }

    func testCloudKitOverrideWinsInsideXCTestHostWithTestRunnerPrefixedEnvironment() {
        let configuration = LibraryAppConfiguration.live(
            environment: [
                "XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration",
                "TEST_RUNNER_HOME_LIBRARY_REMOTE_DRIVER": "cloudkit",
                "TEST_RUNNER_HOME_LIBRARY_STORAGE_NAMESPACE": "cloudkit-live-tests"
            ]
        )

        XCTAssertTrue(configuration.remoteService is CloudKitLibraryService)
        XCTAssertEqual(configuration.sessionStore.namespace, "cloudkit-live-tests")
        XCTAssertEqual(configuration.cacheStore.rootURL.lastPathComponent, "cloudkit-cache")
    }

    func testLiveConfigurationUsesPreferredOwnedRepositoryNameOverride() {
        let configuration = LibraryAppConfiguration.live(
            environment: [
                "HOME_LIBRARY_PREFERRED_REPOSITORY_NAME": "Dual Sim Owner Repo"
            ]
        )

        XCTAssertEqual(configuration.preferredOwnedRepositoryName, "Dual Sim Owner Repo")
    }

    func testLiveConfigurationUsesTestRunnerPrefixedPreferredOwnedRepositoryNameOverride() {
        let configuration = LibraryAppConfiguration.live(
            environment: [
                "XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration",
                "TEST_RUNNER_HOME_LIBRARY_PREFERRED_REPOSITORY_NAME": "Runner Repo"
            ]
        )

        XCTAssertEqual(configuration.preferredOwnedRepositoryName, "Runner Repo")
    }

    func testUserFacingMessageForCloudKitNetworkFailureIsReadable() {
        let message = LibraryStore.userFacingMessage(for: LibraryRemoteServiceError.networkUnavailable)

        XCTAssertEqual(message, "CloudKit 网络连接失败，请确认 iPhone 已联网并关闭代理或 VPN 后重试。")
    }

    func testPreferredRepositoryAfterAcceptUsesSharedZoneMatch() {
        let ownerRepository = LibraryRepositoryReference(
            id: "library.owner",
            name: "我的书库",
            role: .owner,
            databaseScope: .private,
            zoneName: "library.owner",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: nil,
            shareStatus: .shared
        )
        let sharedRepository = LibraryRepositoryReference(
            id: "library.shared",
            name: "家庭共享书库",
            role: .member,
            databaseScope: .shared,
            zoneName: "library.shared",
            zoneOwnerName: "_ownerA_",
            shareRecordName: "share-record",
            shareStatus: .shared
        )

        let existingIDs: Set<String> = [
            "\(ownerRepository.databaseScope.rawValue):\(ownerRepository.id)",
            "\(sharedRepository.databaseScope.rawValue):\(sharedRepository.id)"
        ]
        let selectedRepository = AcceptedShareRepositoryResolver.preferredRepository(
            from: [ownerRepository, sharedRepository],
            existingIDs: existingIDs,
            preferredSharedZoneID: CKRecordZone.ID(zoneName: "library.shared", ownerName: "_ownerA_")
        )

        XCTAssertEqual(selectedRepository, sharedRepository)
    }

    func testPreferredRepositoryAfterAcceptFallsBackToNewSharedRepository() {
        let ownerRepository = LibraryRepositoryReference(
            id: "library.owner",
            name: "我的书库",
            role: .owner,
            databaseScope: .private,
            zoneName: "library.owner",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: nil,
            shareStatus: .shared
        )
        let sharedRepository = LibraryRepositoryReference(
            id: "library.shared",
            name: "家庭共享书库",
            role: .member,
            databaseScope: .shared,
            zoneName: "library.shared",
            zoneOwnerName: "_ownerB_",
            shareRecordName: "share-record",
            shareStatus: .shared
        )

        let selectedRepository = AcceptedShareRepositoryResolver.preferredRepository(
            from: [ownerRepository, sharedRepository],
            existingIDs: ["\(ownerRepository.databaseScope.rawValue):\(ownerRepository.id)"],
            preferredSharedZoneID: Optional<CKRecordZone.ID>.none
        )

        XCTAssertEqual(selectedRepository, sharedRepository)
    }

    @MainActor
    func testStoreCreatesRepositoryAndLoadsDefaultLocations() async throws {
        let namespace = "store-create-\(UUID().uuidString)"
        let sessionStore = RepositorySessionStore(namespace: namespace)
        let tempRoot = try makeTemporaryDirectory()
        let configuration = LibraryAppConfiguration(
            cacheStore: LibraryCacheStore(rootURL: tempRoot.appendingPathComponent("cloudkit-cache", isDirectory: true)),
            legacyImporter: LegacyLibraryImporter(storageRootURL: tempRoot),
            sessionStore: sessionStore,
            remoteService: InMemoryLibraryRemoteService(),
            preferredOwnedRepositoryName: "我的家庭书库"
        )

        let store = LibraryStore(configuration: configuration)
        let didCreate = await store.createOwnedRepository()

        XCTAssertTrue(didCreate)
        XCTAssertEqual(store.currentRepository?.role, .owner)
        XCTAssertEqual(store.locations.map(\.name), ["成都", "重庆"])
    }

    @MainActor
    func testStoreAllowsRemovingOnlyNonCurrentRepositoryWhenMultipleRepositoriesExist() async throws {
        let namespace = "store-remove-rules-\(UUID().uuidString)"
        let sessionStore = RepositorySessionStore(namespace: namespace)
        let tempRoot = try makeTemporaryDirectory()
        let configuration = LibraryAppConfiguration(
            cacheStore: LibraryCacheStore(rootURL: tempRoot.appendingPathComponent("cloudkit-cache", isDirectory: true)),
            legacyImporter: LegacyLibraryImporter(storageRootURL: tempRoot),
            sessionStore: sessionStore,
            remoteService: InMemoryLibraryRemoteService(),
            preferredOwnedRepositoryName: "我的家庭书库"
        )

        let store = LibraryStore(configuration: configuration)

        let didCreateFirstRepository = await store.createOwnedRepository()
        XCTAssertTrue(didCreateFirstRepository)
        let firstRepository = try XCTUnwrap(store.currentRepository)
        XCTAssertFalse(store.canRemoveRepository(firstRepository))

        let didCreateSecondRepository = await store.createOwnedRepository()
        XCTAssertTrue(didCreateSecondRepository)
        let secondRepository = try XCTUnwrap(store.currentRepository)

        XCTAssertTrue(store.canRemoveRepository(firstRepository))
        XCTAssertFalse(store.canRemoveRepository(secondRepository))
    }

    @MainActor
    func testStoreRemovesNonCurrentRepositoryAndKeepsCurrentSelection() async throws {
        let namespace = "store-remove-\(UUID().uuidString)"
        let sessionStore = RepositorySessionStore(namespace: namespace)
        let tempRoot = try makeTemporaryDirectory()
        let configuration = LibraryAppConfiguration(
            cacheStore: LibraryCacheStore(rootURL: tempRoot.appendingPathComponent("cloudkit-cache", isDirectory: true)),
            legacyImporter: LegacyLibraryImporter(storageRootURL: tempRoot),
            sessionStore: sessionStore,
            remoteService: InMemoryLibraryRemoteService(),
            preferredOwnedRepositoryName: "我的家庭书库"
        )

        let store = LibraryStore(configuration: configuration)

        let didCreateFirstRepository = await store.createOwnedRepository()
        XCTAssertTrue(didCreateFirstRepository)
        let firstRepository = try XCTUnwrap(store.currentRepository)

        let didCreateSecondRepository = await store.createOwnedRepository()
        XCTAssertTrue(didCreateSecondRepository)
        let secondRepository = try XCTUnwrap(store.currentRepository)

        let didRemove = await store.removeRepository(firstRepository)

        XCTAssertTrue(didRemove)
        XCTAssertEqual(store.availableRepositories.count, 1)
        XCTAssertEqual(store.currentRepository?.id, secondRepository.id)
        XCTAssertEqual(store.currentRepository?.databaseScope, secondRepository.databaseScope)
        XCTAssertFalse(
            store.availableRepositories.contains {
                $0.id == firstRepository.id && $0.databaseScope == firstRepository.databaseScope
            }
        )
    }

    @MainActor
    func testStoreCanExportCurrentRepositoryAsZip() async throws {
        let namespace = "store-export-\(UUID().uuidString)"
        let sessionStore = RepositorySessionStore(namespace: namespace)
        let tempRoot = try makeTemporaryDirectory()
        let configuration = LibraryAppConfiguration(
            cacheStore: LibraryCacheStore(rootURL: tempRoot.appendingPathComponent("cloudkit-cache", isDirectory: true)),
            legacyImporter: LegacyLibraryImporter(storageRootURL: tempRoot),
            sessionStore: sessionStore,
            remoteService: InMemoryLibraryRemoteService(),
            preferredOwnedRepositoryName: "我的家庭书库"
        )

        let store = LibraryStore(configuration: configuration)
        let didCreate = await store.createOwnedRepository()
        XCTAssertTrue(didCreate)

        let draft = BookDraft(
            title: "测试驱动开发",
            author: "Kent Beck",
            publisher: "Addison-Wesley",
            year: "2002",
            locationID: store.defaultLocationID,
            coverData: nil
        )
        let didSave = await store.saveBook(draft: draft, editing: nil)
        XCTAssertTrue(didSave)

        let exportURL = await store.exportCurrentRepository()
        XCTAssertNotNil(exportURL)
        XCTAssertEqual(exportURL?.pathExtension, "zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(exportURL).path))
    }

    @MainActor
    func testStoreImportsPackageAndUpdatesProgress() async throws {
        let namespace = "store-import-\(UUID().uuidString)"
        let sessionStore = RepositorySessionStore(namespace: namespace)
        let tempRoot = try makeTemporaryDirectory()
        let configuration = LibraryAppConfiguration(
            cacheStore: LibraryCacheStore(rootURL: tempRoot.appendingPathComponent("cloudkit-cache", isDirectory: true)),
            legacyImporter: LegacyLibraryImporter(storageRootURL: tempRoot),
            sessionStore: sessionStore,
            remoteService: InMemoryLibraryRemoteService(),
            preferredOwnedRepositoryName: "我的家庭书库"
        )

        let importURL = tempRoot.appendingPathComponent("LibraryImport.json")
        let package = LibraryImportPackage(
            schemaVersion: LibraryImportPackage.currentSchemaVersion,
            source: "test",
            exportedAt: Date(),
            locations: [LibraryImportLocation(location: LibraryLocation(id: "cd", name: "成都", sortOrder: 0))],
            books: [
                LibraryImportBook(
                    id: "b1",
                    title: "被导入的书",
                    author: "王宇",
                    publisher: "自有出版社",
                    year: "2026",
                    locationID: "cd",
                    locationName: "成都",
                    customFields: [:],
                    isbn: nil,
                    coverData: nil,
                    createdAt: Date(timeIntervalSince1970: 10),
                    updatedAt: Date(timeIntervalSince1970: 20)
                )
            ]
        )
        let data = try LibraryJSONCodec.makeEncoder().encode(package)
        try data.write(to: importURL)

        let store = LibraryStore(configuration: configuration)
        let didImport = await store.importLegacyJSON(from: importURL)
        XCTAssertTrue(didImport)
        XCTAssertEqual(store.importProgress?.phase, .completed)
        XCTAssertEqual(store.books.count, 1)
        XCTAssertEqual(store.books.first?.title, "被导入的书")
    }

    @MainActor
    func testStoreImportNormalizesSeedLocationNamesIntoUsableLocationIDs() async throws {
        let namespace = "store-seed-import-\(UUID().uuidString)"
        let sessionStore = RepositorySessionStore(namespace: namespace)
        let tempRoot = try makeTemporaryDirectory()
        let configuration = LibraryAppConfiguration(
            cacheStore: LibraryCacheStore(rootURL: tempRoot.appendingPathComponent("cloudkit-cache", isDirectory: true)),
            legacyImporter: LegacyLibraryImporter(storageRootURL: tempRoot),
            sessionStore: sessionStore,
            remoteService: InMemoryLibraryRemoteService(),
            preferredOwnedRepositoryName: "我的家庭书库"
        )

        let importURL = tempRoot.appendingPathComponent("SeedBooks.json")
        let payload = """
        {
          "schemaVersion" : 2,
          "source" : "seed-test",
          "locations" : [
            {
              "id" : "",
              "name" : "成都"
            }
          ],
          "books" : [
            {
              "id" : "seed-book",
              "title" : "种子导入",
              "author" : "作者 Seed",
              "publisher" : "出版社 Seed",
              "year" : "2025",
              "locationID" : "成都",
              "customFields" : {},
              "createdAt" : "\(LibraryJSONCodec.encodeDate(Date(timeIntervalSince1970: 1)))",
              "updatedAt" : "\(LibraryJSONCodec.encodeDate(Date(timeIntervalSince1970: 2)))"
            }
          ]
        }
        """
        try Data(payload.utf8).write(to: importURL)

        let store = LibraryStore(configuration: configuration)
        let didImport = await store.importLegacyJSON(from: importURL)

        XCTAssertTrue(didImport)
        XCTAssertEqual(store.locations.map(\.name), ["成都"])
        XCTAssertEqual(store.locations.map(\.id), ["location.chengdu"])
        XCTAssertEqual(store.books.first?.locationID, "location.chengdu")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
