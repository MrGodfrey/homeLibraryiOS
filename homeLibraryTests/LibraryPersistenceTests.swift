//
//  LibraryPersistenceTests.swift
//  homeLibraryTests
//
//  Created by Codex on 2026/4/14.
//

import Foundation
import XCTest
@testable import homeLibrary

final class LibraryPersistenceTests: XCTestCase {

    func testSeparatesCoverAssetsFromBookMetadata() throws {
        let rootURL = try makeTemporaryDirectory()
        let store = LibraryDiskStore(rootURL: rootURL)
        try store.prepareForUse(allowBundledSeed: false)

        let coverData = Data("cover-image-data".utf8)
        let storedBook = try store.upsert(
            book: Book(
                id: "book-1",
                title: "重构",
                author: "Martin Fowler",
                publisher: "Addison-Wesley",
                year: "2018",
                isbn: "9780134757599",
                location: .chengdu,
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 2)
            ),
            coverData: coverData
        )

        XCTAssertNotNil(storedBook.coverAssetID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("books/book-1.json").path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: rootURL.appendingPathComponent("covers/\(storedBook.coverAssetID!).bin").path
            )
        )

        let metadataString = try XCTUnwrap(
            String(data: Data(contentsOf: rootURL.appendingPathComponent("books/book-1.json")), encoding: .utf8)
        )
        XCTAssertFalse(metadataString.contains("coverData"))
        XCTAssertEqual(try store.coverData(for: storedBook.coverAssetID!), coverData)
    }

    func testCloudSyncPrefersNewerMetadataAndCopiesCoverAsset() throws {
        let localRootURL = try makeTemporaryDirectory()
        let cloudRootURL = try makeTemporaryDirectory()

        let localStore = LibraryDiskStore(rootURL: localRootURL)
        let cloudStore = LibraryDiskStore(rootURL: cloudRootURL)

        try localStore.prepareForUse(allowBundledSeed: false)
        try cloudStore.prepareForUse(allowBundledSeed: false)

        _ = try localStore.upsert(
            book: Book(
                id: "book-1",
                title: "领域驱动设计",
                author: "Eric Evans",
                publisher: "Pearson",
                year: "2003",
                isbn: "9780321125217",
                location: .chengdu,
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 20)
            ),
            coverData: nil
        )

        let cloudBook = try cloudStore.upsert(
            book: Book(
                id: "book-1",
                title: "领域驱动设计（修订版）",
                author: "Eric Evans",
                publisher: "Pearson",
                year: "2026",
                isbn: "9780321125217",
                location: .chongqing,
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 30)
            ),
            coverData: Data("new-cover".utf8)
        )

        let engine = LibrarySyncEngine(
            localStore: localStore,
            configuration: CloudSyncConfiguration(
                isEnabled: true,
                overrideRootURL: cloudRootURL,
                containerIdentifier: nil,
                syncTarget: .personalCloud
            )
        )

        let result = try engine.sync()
        XCTAssertTrue(result.isCloudAvailable)

        let localSnapshot = try localStore.loadSnapshot()
        let synchronizedBook = try XCTUnwrap(localSnapshot.books.first)

        XCTAssertEqual(synchronizedBook.title, "领域驱动设计（修订版）")
        XCTAssertEqual(synchronizedBook.location, .chongqing)
        XCTAssertEqual(synchronizedBook.coverAssetID, cloudBook.coverAssetID)
        XCTAssertEqual(try localStore.coverData(for: try XCTUnwrap(cloudBook.coverAssetID)), Data("new-cover".utf8))
    }

    func testCloudSyncPropagatesDeletionTombstones() throws {
        let localRootURL = try makeTemporaryDirectory()
        let cloudRootURL = try makeTemporaryDirectory()

        let localStore = LibraryDiskStore(rootURL: localRootURL)
        let cloudStore = LibraryDiskStore(rootURL: cloudRootURL)

        try localStore.prepareForUse(allowBundledSeed: false)
        try cloudStore.prepareForUse(allowBundledSeed: false)

        let book = Book(
            id: "book-2",
            title: "代码整洁之道",
            author: "Robert C. Martin",
            publisher: "Prentice Hall",
            year: "2008",
            isbn: "9780132350884",
            location: .chengdu,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        _ = try localStore.upsert(book: book, coverData: nil)
        _ = try cloudStore.upsert(book: book, coverData: nil)
        try cloudStore.recordDeletion(for: book.id, deletedAt: Date(timeIntervalSince1970: 200))

        let engine = LibrarySyncEngine(
            localStore: localStore,
            configuration: CloudSyncConfiguration(
                isEnabled: true,
                overrideRootURL: cloudRootURL,
                containerIdentifier: nil,
                syncTarget: .personalCloud
            )
        )

        _ = try engine.sync()

        let localSnapshot = try localStore.loadSnapshot()
        XCTAssertTrue(localSnapshot.books.isEmpty)
        XCTAssertEqual(localSnapshot.tombstonesByID[book.id]?.deletedAt, Date(timeIntervalSince1970: 200))
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
