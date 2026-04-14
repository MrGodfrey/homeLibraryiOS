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
                isbn: "9787536692930",
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
                isbn: "9787544258609",
                location: .chongqing,
                createdAt: Date(timeIntervalSince1970: 2),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        ]

        let filtered = LibraryFilter.filteredBooks(from: books, query: "三体", tab: .chengdu)

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.id, "1")
    }

    func testNormalizesDraftFieldsBeforeSave() {
        let draft = BookDraft(
            title: "  家庭书库  ",
            author: "  王宇  ",
            publisher: "  自有出版社 ",
            year: " 2026 ",
            isbn: " 978-7-111-22222-3 ",
            location: .chengdu,
            coverData: nil
        )

        let normalized = draft.normalized

        XCTAssertEqual(normalized.title, "家庭书库")
        XCTAssertEqual(normalized.author, "王宇")
        XCTAssertEqual(normalized.publisher, "自有出版社")
        XCTAssertEqual(normalized.year, "2026")
        XCTAssertEqual(normalized.isbn, "9787111222223")
    }

    func testExtractsEmbeddedISBNFromScannerPayload() {
        let payload = "EAN-13 9787111122334"

        XCTAssertEqual(ISBNLookupService.extractISBN(from: payload), "9787111122334")
    }

    func testSyncSettingsStorePersistsSharedFolderSelectionPerNamespace() throws {
        let suiteName = "homeLibraryTests.syncSettings.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let store = LibrarySyncSettingsStore(namespace: "primary")
        let bookmark = SharedLibraryFolderBookmark(
            displayName: "家庭共享书库",
            bookmarkData: Data("bookmark".utf8)
        )
        let target = LibrarySyncTarget(mode: .sharedFolder, sharedFolderBookmark: bookmark)

        store.save(target, userDefaults: userDefaults)

        XCTAssertEqual(store.load(userDefaults: userDefaults), target)
        XCTAssertEqual(
            LibrarySyncSettingsStore(namespace: "secondary").load(userDefaults: userDefaults),
            .personalCloud
        )
    }

}
