//
//  homeLibraryTests.swift
//  homeLibraryTests
//
//  Created by Codex on 2026/4/14.
//

import CloudKit
import Foundation
import SwiftUI
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
            locationsByID: locationsByID,
            sortOrder: .updatedAt
        )

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.id, "2")
    }

    func testSortsBooksByCreatedTimeDescendingByDefault() {
        let books = [
            Book(
                id: "old",
                title: "旧书",
                author: "作者 A",
                locationID: "cd",
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            Book(
                id: "new",
                title: "新书",
                author: "作者 B",
                locationID: "cd",
                createdAt: Date(timeIntervalSince1970: 20),
                updatedAt: Date(timeIntervalSince1970: 50)
            )
        ]

        let filtered = LibraryFilter.filteredBooks(
            from: books,
            query: "",
            selectedLocationID: nil,
            locationsByID: [:],
            sortOrder: .defaultValue
        )

        XCTAssertEqual(filtered.map(\.id), ["new", "old"])
    }

    func testSortsBooksByUpdatedTimeDescending() {
        let books = [
            Book(
                id: "stale",
                title: "旧版本",
                author: "作者 A",
                locationID: "cd",
                createdAt: Date(timeIntervalSince1970: 20),
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            Book(
                id: "fresh",
                title: "新版本",
                author: "作者 B",
                locationID: "cd",
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 200)
            )
        ]

        let filtered = LibraryFilter.filteredBooks(
            from: books,
            query: "",
            selectedLocationID: nil,
            locationsByID: [:],
            sortOrder: .updatedAt
        )

        XCTAssertEqual(filtered.map(\.id), ["fresh", "stale"])
    }

    func testSortsBooksByAuthorUsingChineseAndEnglishCollation() {
        let books = [
            Book(id: "zhang", title: "第一本", author: "张爱玲", locationID: "cd"),
            Book(id: "alice", title: "第二本", author: "Alice Munro", locationID: "cd"),
            Book(id: "liu", title: "第三本", author: "刘慈欣", locationID: "cd")
        ]

        let filtered = LibraryFilter.filteredBooks(
            from: books,
            query: "",
            selectedLocationID: nil,
            locationsByID: [:],
            sortOrder: .author
        )

        XCTAssertEqual(filtered.map(\.id), ["alice", "liu", "zhang"])
    }

    func testSortsBooksByTitleUsingChineseAndEnglishCollation() {
        let books = [
            Book(id: "san-ti", title: "三体", author: "刘慈欣", locationID: "cd"),
            Book(id: "algorithms", title: "Algorithms", author: "Sedgewick", locationID: "cd"),
            Book(id: "bai-ye-xing", title: "白夜行", author: "东野圭吾", locationID: "cd")
        ]

        let filtered = LibraryFilter.filteredBooks(
            from: books,
            query: "",
            selectedLocationID: nil,
            locationsByID: [:],
            sortOrder: .title
        )

        XCTAssertEqual(filtered.map(\.id), ["algorithms", "bai-ye-xing", "san-ti"])
    }

    func testBookGridLayoutUsesThreeColumnsOnCompactWidth() {
        let layout = LibraryBookGridLayout(availableWidth: 353, horizontalSizeClass: .compact)

        XCTAssertEqual(layout.columnCount, 3)
        XCTAssertEqual(layout.cardWidth, 107, accuracy: 0.001)
    }

    func testBookGridLayoutKeepsAdaptiveColumnsOnRegularWidth() {
        let layout = LibraryBookGridLayout(availableWidth: 720, horizontalSizeClass: .regular)

        XCTAssertEqual(layout.columnCount, 4)
    }

    func testNormalizesDraftFieldsAndManagedBookInfoBeforeSave() {
        let draft = BookDraft(
            title: "  家庭书库  ",
            author: "  王宇  ",
            translator: "  张三  ",
            publisher: "  自有出版社 ",
            year: " 2026 ",
            isbn: " 9787111123456 ",
            locationID: "  cd ",
            customFields: [
                "  \(BookInfoFieldKey.translator)  ": "  旧译者  ",
                "  \(BookInfoFieldKey.isbn)  ": "  1111111111111  ",
                "  备注  ": "  已整理  ",
                "空字段": "   "
            ],
            coverData: nil,
            keepsExistingCoverReference: true
        )

        let normalized = draft.normalized

        XCTAssertEqual(normalized.title, "家庭书库")
        XCTAssertEqual(normalized.author, "王宇")
        XCTAssertEqual(normalized.translator, "张三")
        XCTAssertEqual(normalized.publisher, "自有出版社")
        XCTAssertEqual(normalized.year, "2026")
        XCTAssertEqual(normalized.isbn, "9787111123456")
        XCTAssertEqual(normalized.locationID, "cd")
        XCTAssertEqual(
            normalized.customFields,
            [
                "备注": "已整理",
                BookInfoFieldKey.translator: "张三",
                BookInfoFieldKey.isbn: "9787111123456"
            ]
        )
        XCTAssertTrue(normalized.keepsExistingCoverReference)
    }

    func testDraftLoadsTranslatorAndISBNFromManagedBookInfo() {
        let book = Book(
            id: "book-1",
            title: "示例书",
            author: "作者甲",
            locationID: "cd",
            customFields: [
                BookInfoFieldKey.translator: "  译者乙  ",
                BookInfoFieldKey.isbn: " 9787300000000 "
            ]
        )

        let draft = BookDraft(book: book, coverData: nil, defaultLocationID: "fallback")

        XCTAssertEqual(draft.translator, "译者乙")
        XCTAssertEqual(draft.isbn, "9787300000000")
    }

    func testDraftFallsBackToAvailableLocationWhenSelectionIsMissingForNewBook() {
        let locations = [
            LibraryLocation(id: "study", name: "书房", sortOrder: 0),
            LibraryLocation(id: "living-room", name: "客厅", sortOrder: 1)
        ]
        let draft = BookDraft(
            title: "家庭书库",
            author: "",
            publisher: "",
            year: "",
            locationID: "location.chengdu",
            coverData: nil
        )

        XCTAssertEqual(
            draft.resolvedLocationID(in: locations, fallback: "location.chengdu"),
            "study"
        )
    }

    func testDraftFallsBackToFirstAvailableLocationWhenEditingBookUsesMissingLocation() {
        let locations = [
            LibraryLocation(id: "study", name: "书房", sortOrder: 0),
            LibraryLocation(id: "living-room", name: "客厅", sortOrder: 1)
        ]
        let draft = BookDraft(
            title: "家庭书库",
            author: "",
            publisher: "",
            year: "",
            locationID: "location.chengdu",
            coverData: nil
        )

        XCTAssertEqual(
            draft.resolvedLocationID(
                in: locations,
                fallback: "location.chengdu"
            ),
            "study"
        )
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

    func testLocalizationSupportsEnglishStrings() {
        let previousLanguage = LibraryLocalization.overrideLanguage
        LibraryLocalization.overrideLanguage = .english
        defer { LibraryLocalization.overrideLanguage = previousLanguage }

        XCTAssertEqual(LibraryLocation.defaultLocations().map(\.name), ["Chengdu", "Chongqing"])
        XCTAssertEqual(RepositoryRole.owner.title, "My Library")
        XCTAssertEqual(LibraryBookSortOrder.author.title, "Sort by author")
        XCTAssertEqual(
            LibraryStore.userFacingMessage(for: LibraryRemoteServiceError.networkUnavailable),
            "CloudKit network access failed. Make sure your iPhone is online and any proxy or VPN is disabled, then try again."
        )
        XCTAssertEqual(
            RepositoryImportProgress(phase: .completed, totalCount: 12, importedCount: 12).statusText,
            "Import complete, 12 books"
        )
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
    func testStoreRefreshUsesCachedCloudKitChangeTokenAndMergesIncrementalChanges() async throws {
        let namespace = "store-incremental-\(UUID().uuidString)"
        let sessionStore = RepositorySessionStore(namespace: namespace)
        let tempRoot = try makeTemporaryDirectory()
        let cacheStore = LibraryCacheStore(rootURL: tempRoot.appendingPathComponent("cloudkit-cache", isDirectory: true))
        let repository = LibraryRepositoryReference(
            id: "library.incremental",
            name: "增量书库",
            role: .owner,
            databaseScope: .private,
            zoneName: "library.incremental",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: nil,
            shareStatus: .notShared
        )
        let initialToken = Data("token-1".utf8)
        let updatedToken = Data("token-2".utf8)
        let unchangedBook = Book(
            id: "unchanged",
            title: "不应重新下载的书",
            locationID: "study",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let deletedBook = Book(
            id: "deleted",
            title: "远端删除的书",
            locationID: "study",
            createdAt: Date(timeIntervalSince1970: 3),
            updatedAt: Date(timeIntervalSince1970: 4)
        )

        try cacheStore.replaceAllContent(
            books: [unchangedBook, deletedBook],
            locations: [LibraryLocation(id: "study", name: "书房", sortOrder: 0)],
            coverDataByAssetID: [:],
            repositoryID: repository.id,
            synchronizedAt: Date(timeIntervalSince1970: 10),
            cloudKitChangeTokenData: initialToken,
            updatesCloudKitChangeToken: true
        )
        sessionStore.save(LibrarySessionState(currentRepository: repository))

        let remoteBook = RemoteBookSnapshot(
            book: Book(
                id: "remote-new",
                title: "远端新增",
                locationID: "study",
                createdAt: Date(timeIntervalSince1970: 5),
                updatedAt: Date(timeIntervalSince1970: 6)
            ),
            coverData: nil
        )
        let remoteService = ScriptedIncrementalLibraryRemoteService(
            repository: repository,
            changeSet: RemoteRepositoryChangeSet(
                repository: repository,
                locations: [],
                deletedLocationIDs: [],
                books: [remoteBook],
                deletedBookIDs: ["deleted"],
                changeTokenData: updatedToken,
                isFullRefresh: false
            )
        )
        let configuration = LibraryAppConfiguration(
            cacheStore: cacheStore,
            legacyImporter: LegacyLibraryImporter(storageRootURL: tempRoot),
            sessionStore: sessionStore,
            remoteService: remoteService,
            preferredOwnedRepositoryName: "我的家庭书库"
        )

        let store = LibraryStore(configuration: configuration)
        await store.loadBooks(force: true)

        let requestedChangeTokens = await remoteService.recordedRequestedChangeTokens()
        let fullRefreshCallCount = await remoteService.recordedFullRefreshCallCount()

        XCTAssertEqual(Set(store.books.map(\.id)), ["unchanged", "remote-new"])
        XCTAssertEqual(requestedChangeTokens, [initialToken])
        XCTAssertEqual(fullRefreshCallCount, 0)
        XCTAssertEqual(try cacheStore.cloudKitChangeTokenData(repositoryID: repository.id), updatedToken)
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
    func testStoreSwitchesRepositoriesAndLoadsMatchingLocations() async throws {
        let namespace = "store-switch-\(UUID().uuidString)"
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
        let didSaveFirstLocations = await store.saveLocations([
            LibraryLocation(id: "study", name: "书房", sortOrder: 0)
        ])
        XCTAssertTrue(didSaveFirstLocations)

        let didCreateSecondRepository = await store.createOwnedRepository()
        XCTAssertTrue(didCreateSecondRepository)
        let secondRepository = try XCTUnwrap(store.currentRepository)
        let didSaveSecondLocations = await store.saveLocations([
            LibraryLocation(id: "living-room", name: "客厅", sortOrder: 0),
            LibraryLocation(id: "bedroom", name: "卧室", sortOrder: 1, isVisible: false)
        ])
        XCTAssertTrue(didSaveSecondLocations)

        await store.switchRepository(to: firstRepository)
        XCTAssertEqual(store.currentRepository?.id, firstRepository.id)
        XCTAssertEqual(store.locations.map(\.name), ["书房"])

        await store.switchRepository(to: secondRepository)
        XCTAssertEqual(store.currentRepository?.id, secondRepository.id)
        XCTAssertEqual(store.locations.map(\.name), ["客厅", "卧室"])
        XCTAssertEqual(store.locations.map(\.isVisible), [true, false])
    }

    @MainActor
    func testStorePersistsBookSortOrderPerRepository() async throws {
        let namespace = "store-sort-\(UUID().uuidString)"
        let sessionStore = RepositorySessionStore(namespace: namespace)
        let tempRoot = try makeTemporaryDirectory()
        let remoteService = InMemoryLibraryRemoteService()
        let configuration = LibraryAppConfiguration(
            cacheStore: LibraryCacheStore(rootURL: tempRoot.appendingPathComponent("cloudkit-cache", isDirectory: true)),
            legacyImporter: LegacyLibraryImporter(storageRootURL: tempRoot),
            sessionStore: sessionStore,
            remoteService: remoteService,
            preferredOwnedRepositoryName: "我的家庭书库"
        )

        let store = LibraryStore(configuration: configuration)

        let didCreateFirstRepository = await store.createOwnedRepository()
        XCTAssertTrue(didCreateFirstRepository)
        let firstRepository = try XCTUnwrap(store.currentRepository)
        store.setBookSortOrder(.author)

        let didCreateSecondRepository = await store.createOwnedRepository()
        XCTAssertTrue(didCreateSecondRepository)
        let secondRepository = try XCTUnwrap(store.currentRepository)
        store.setBookSortOrder(.title)

        await store.switchRepository(to: firstRepository)
        XCTAssertEqual(store.bookSortOrder, .author)

        let restoredStore = LibraryStore(configuration: configuration)
        XCTAssertEqual(restoredStore.currentRepository?.id, firstRepository.id)
        XCTAssertEqual(restoredStore.bookSortOrder, .author)

        await restoredStore.loadBooks(force: true)
        await restoredStore.switchRepository(to: secondRepository)
        XCTAssertEqual(restoredStore.bookSortOrder, .title)
    }

    @MainActor
    func testStoreLocationVisibilityUpdatesFiltersAndDefaultLocationImmediately() async throws {
        let namespace = "store-location-visibility-\(UUID().uuidString)"
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
        let didCreateRepository = await store.createOwnedRepository()
        XCTAssertTrue(didCreateRepository)
        store.selectedLocationID = store.defaultLocationID

        let didSaveLocations = await store.saveLocations([
            LibraryLocation(id: "study", name: "书房", sortOrder: 0, isVisible: false),
            LibraryLocation(id: "living-room", name: "客厅", sortOrder: 1)
        ])
        XCTAssertTrue(didSaveLocations)

        XCTAssertEqual(store.visibleLocationFilters.map(\.title), ["全部", "客厅"])
        XCTAssertNil(store.selectedLocationID)
        XCTAssertEqual(store.defaultLocationID, "living-room")
    }

    @MainActor
    func testStoreSaveLocationsAppliesReorderedLocations() async throws {
        let namespace = "store-location-order-\(UUID().uuidString)"
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
        let didCreateRepository = await store.createOwnedRepository()
        XCTAssertTrue(didCreateRepository)
        let didSaveInitialLocations = await store.saveLocations([
            LibraryLocation(id: "study", name: "书房", sortOrder: 0),
            LibraryLocation(id: "bedroom", name: "卧室", sortOrder: 1)
        ])
        XCTAssertTrue(didSaveInitialLocations)

        let didSaveReorderedLocations = await store.saveLocations([
            LibraryLocation(id: "bedroom", name: "卧室", sortOrder: 0),
            LibraryLocation(id: "study", name: "书房", sortOrder: 1)
        ])
        XCTAssertTrue(didSaveReorderedLocations)

        XCTAssertEqual(store.locations.map(\.id), ["bedroom", "study"])
        XCTAssertEqual(store.locations.map(\.sortOrder), [0, 1])
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
    func testStoreDeleteBookRemovesSavedBook() async throws {
        let namespace = "store-delete-book-\(UUID().uuidString)"
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
        let didCreateRepository = await store.createOwnedRepository()
        XCTAssertTrue(didCreateRepository)

        let didSaveBook = await store.saveBook(
            draft: BookDraft(
                title: "可删除的书",
                author: "测试作者",
                publisher: "测试出版社",
                year: "2026",
                locationID: store.defaultLocationID,
                coverData: nil
            ),
            editing: nil
        )
        XCTAssertTrue(didSaveBook)

        let book = try XCTUnwrap(store.books.first)
        let didDeleteBook = await store.deleteBook(book)

        XCTAssertTrue(didDeleteBook)
        XCTAssertTrue(store.books.isEmpty)
        XCTAssertTrue(store.visibleBooks.isEmpty)
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

    @MainActor
    func testStoreClearCurrentRepositoryResetsBooksAndLocations() async throws {
        let namespace = "store-clear-\(UUID().uuidString)"
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
        let didCreateRepository = await store.createOwnedRepository()
        XCTAssertTrue(didCreateRepository)
        let didSaveLocations = await store.saveLocations([
            LibraryLocation(id: "study", name: "书房", sortOrder: 0)
        ])
        XCTAssertTrue(didSaveLocations)
        let didSaveBook = await store.saveBook(
            draft: BookDraft(
                title: "可清空的书",
                author: "测试作者",
                publisher: "测试出版社",
                year: "2026",
                locationID: "study",
                coverData: nil
            ),
            editing: nil
        )
        XCTAssertTrue(didSaveBook)

        let didClearRepository = await store.clearCurrentRepository()
        XCTAssertTrue(didClearRepository)
        XCTAssertTrue(store.books.isEmpty)
        XCTAssertEqual(store.locations.map(\.name), ["成都", "重庆"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private actor ScriptedIncrementalLibraryRemoteService: LibraryRemoteSyncing, LibraryRemoteIncrementalSyncing {
    private enum ScriptedError: Error {
        case unsupported
    }

    let repository: LibraryRepositoryReference
    var changeSet: RemoteRepositoryChangeSet
    private(set) var requestedChangeTokens: [Data?] = []
    private(set) var fullRefreshCallCount = 0

    init(repository: LibraryRepositoryReference, changeSet: RemoteRepositoryChangeSet) {
        self.repository = repository
        self.changeSet = changeSet
    }

    func listRepositories() async throws -> [LibraryRepositoryReference] {
        [repository]
    }

    func createOwnedRepository(preferredName: String) async throws -> LibraryRepositoryReference {
        throw ScriptedError.unsupported
    }

    func refreshRepository(_ repository: LibraryRepositoryReference) async throws -> RemoteRepositorySnapshot {
        fullRefreshCallCount += 1
        throw ScriptedError.unsupported
    }

    func refreshRepositoryChanges(
        _ repository: LibraryRepositoryReference,
        since changeTokenData: Data?
    ) async throws -> RemoteRepositoryChangeSet {
        requestedChangeTokens.append(changeTokenData)
        return changeSet
    }

    func recordedRequestedChangeTokens() -> [Data?] {
        requestedChangeTokens
    }

    func recordedFullRefreshCallCount() -> Int {
        fullRefreshCallCount
    }

    func saveLocations(_ locations: [LibraryLocation], in repository: LibraryRepositoryReference) async throws -> [LibraryLocation] {
        throw ScriptedError.unsupported
    }

    func upsertBook(_ book: Book, coverData: Data?, in repository: LibraryRepositoryReference) async throws -> RemoteBookSnapshot {
        throw ScriptedError.unsupported
    }

    func deleteBook(id: String, deletedAt: Date, in repository: LibraryRepositoryReference) async throws {
        throw ScriptedError.unsupported
    }

    func clearRepository(_ repository: LibraryRepositoryReference, resetLocations: [LibraryLocation]) async throws {
        throw ScriptedError.unsupported
    }

    func exportRepository(_ repository: LibraryRepositoryReference) async throws -> LibraryImportPackage {
        throw ScriptedError.unsupported
    }

    func deleteRepository(_ repository: LibraryRepositoryReference) async throws {
        throw ScriptedError.unsupported
    }
}
