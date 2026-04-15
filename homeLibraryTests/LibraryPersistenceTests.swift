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

    func testCacheStoreSeparatesCoverAssetsFromBookMetadata() throws {
        let rootURL = try makeTemporaryDirectory()
        let store = LibraryCacheStore(rootURL: rootURL)
        let repositoryID = "repo-1"
        let defaultLocationID = LibraryLocation.defaultLocations()[0].id

        let coverData = Data("cover-image-data".utf8)
        let storedBook = try store.upsert(
            book: Book(
                id: "book-1",
                title: "重构",
                author: "Martin Fowler",
                publisher: "Addison-Wesley",
                year: "2018",
                locationID: defaultLocationID,
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 2)
            ),
            coverData: coverData,
            repositoryID: repositoryID
        )

        XCTAssertNotNil(storedBook.coverAssetID)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: rootURL.appendingPathComponent("\(repositoryID)/books/book-1.json").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: rootURL.appendingPathComponent("\(repositoryID)/covers/\(storedBook.coverAssetID!).bin").path
            )
        )

        let metadataString = try XCTUnwrap(
            String(
                data: Data(contentsOf: rootURL.appendingPathComponent("\(repositoryID)/books/book-1.json")),
                encoding: .utf8
            )
        )
        XCTAssertFalse(metadataString.contains("coverData"))
        XCTAssertEqual(try store.coverData(for: storedBook.coverAssetID!, repositoryID: repositoryID), coverData)
    }

    func testReplaceAllContentGarbageCollectsStaleAssetsAndPersistsLocations() throws {
        let rootURL = try makeTemporaryDirectory()
        let store = LibraryCacheStore(rootURL: rootURL)
        let repositoryID = "repo-2"
        let defaultLocations = LibraryLocation.defaultLocations()

        let firstBook = try store.upsert(
            book: Book(
                id: "book-1",
                title: "旧书",
                locationID: defaultLocations[0].id,
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 2)
            ),
            coverData: Data("old-cover".utf8),
            repositoryID: repositoryID
        )

        let staleCoverURL = rootURL.appendingPathComponent("\(repositoryID)/covers/\(firstBook.coverAssetID!).bin")
        XCTAssertTrue(FileManager.default.fileExists(atPath: staleCoverURL.path))

        let replacementBook = Book(
            id: "book-2",
            title: "新书",
            locationID: "location.study",
            coverAssetID: "cover-new",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 11)
        )
        let replacementLocations = [
            LibraryLocation(id: "location.study", name: "书房", sortOrder: 0),
            LibraryLocation(id: "location.storage", name: "储藏室", sortOrder: 1, isVisible: false)
        ]

        try store.replaceAllContent(
            books: [replacementBook],
            locations: replacementLocations,
            coverDataByAssetID: ["cover-new": Data("new-cover".utf8)],
            repositoryID: repositoryID,
            synchronizedAt: Date(timeIntervalSince1970: 99)
        )

        let snapshot = try store.loadSnapshot(repositoryID: repositoryID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleCoverURL.path))
        XCTAssertEqual(
            try store.coverData(for: "cover-new", repositoryID: repositoryID),
            Data("new-cover".utf8)
        )
        XCTAssertEqual(snapshot.books.map(\.id), ["book-2"])
        XCTAssertEqual(snapshot.locations.map(\.name), ["书房", "储藏室"])
        XCTAssertEqual(snapshot.locations.last?.isVisible, false)
    }

    func testCacheStoreExportsImportPackageWithEmbeddedCoverData() throws {
        let rootURL = try makeTemporaryDirectory()
        let store = LibraryCacheStore(rootURL: rootURL)
        let repositoryID = "repo-export"
        let locations = [
            LibraryLocation(id: "location.study", name: "书房", sortOrder: 0)
        ]

        try store.saveLocations(locations, repositoryID: repositoryID)
        let storedBook = try store.upsert(
            book: Book(
                id: "book-export",
                title: "导出测试",
                author: "王宇",
                publisher: "自有出版社",
                year: "2026",
                locationID: "location.study",
                customFields: ["备注": "带封面"],
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 20)
            ),
            coverData: Data("embedded-cover".utf8),
            repositoryID: repositoryID
        )

        let package = try store.makeImportPackage(repositoryID: repositoryID, source: "unit-test")

        XCTAssertEqual(package.source, "unit-test")
        XCTAssertEqual(package.locations.map(\.name), ["书房"])
        XCTAssertEqual(package.books.count, 1)
        XCTAssertEqual(package.books.first?.locationID, "location.study")
        XCTAssertEqual(package.books.first?.locationName, "书房")
        XCTAssertEqual(package.books.first?.coverData, Data("embedded-cover".utf8))
        XCTAssertEqual(package.books.first?.id, storedBook.id)
    }

    func testLegacyImporterLoadsStructuredBooksAndSkipsDeletedRecords() throws {
        let rootURL = try makeTemporaryDirectory()
        let booksDirectoryURL = rootURL.appendingPathComponent("books", isDirectory: true)
        let coversDirectoryURL = rootURL.appendingPathComponent("covers", isDirectory: true)
        let deletionsDirectoryURL = rootURL.appendingPathComponent("deletions", isDirectory: true)
        try FileManager.default.createDirectory(at: booksDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: coversDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: deletionsDirectoryURL, withIntermediateDirectories: true)

        let defaultLocations = LibraryLocation.defaultLocations()
        let activeBook = Book(
            id: "active-book",
            title: "保留",
            author: "作者 A",
            locationID: defaultLocations[0].id,
            coverAssetID: "cover-active",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let deletedBook = Book(
            id: "deleted-book",
            title: "删除",
            author: "作者 B",
            locationID: defaultLocations[1].id,
            createdAt: Date(timeIntervalSince1970: 3),
            updatedAt: Date(timeIntervalSince1970: 4)
        )

        let encoder = LibraryJSONCodec.makeEncoder()
        try encoder.encode(activeBook).write(
            to: booksDirectoryURL.appendingPathComponent("active-book.json"),
            options: [.atomic]
        )
        try encoder.encode(deletedBook).write(
            to: booksDirectoryURL.appendingPathComponent("deleted-book.json"),
            options: [.atomic]
        )
        try Data("active-cover".utf8).write(
            to: coversDirectoryURL.appendingPathComponent("cover-active.bin"),
            options: [.atomic]
        )
        try encoder.encode(
            LegacyDeletionRecord(
                id: "deleted-book",
                deletedAt: Date(timeIntervalSince1970: 10)
            )
        ).write(
            to: deletionsDirectoryURL.appendingPathComponent("deleted-book.json"),
            options: [.atomic]
        )

        let importer = LegacyLibraryImporter(storageRootURL: rootURL)
        let importedBundle = try importer.loadImportBundle()

        XCTAssertEqual(importedBundle.locations.map(\.name), ["成都", "重庆"])
        XCTAssertEqual(importedBundle.books.count, 1)
        XCTAssertEqual(importedBundle.books.first?.book.id, "active-book")
        XCTAssertEqual(importedBundle.books.first?.coverData, Data("active-cover".utf8))
    }

    func testLegacyImporterLoadsLegacyStructuredBooksWithISBNAndCoverAsset() throws {
        let rootURL = try makeTemporaryDirectory()
        let booksDirectoryURL = rootURL.appendingPathComponent("books", isDirectory: true)
        let coversDirectoryURL = rootURL.appendingPathComponent("covers", isDirectory: true)
        try FileManager.default.createDirectory(at: booksDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: coversDirectoryURL, withIntermediateDirectories: true)

        let legacyJSON = """
        {
          "id" : "legacy-book",
          "title" : "旧书",
          "author" : "作者 A",
          "publisher" : "出版社 A",
          "year" : "2024",
          "isbn" : "9787111123456",
          "location" : "成都",
          "coverAssetID" : "cover-legacy",
          "createdAt" : "\(LibraryJSONCodec.encodeDate(Date(timeIntervalSince1970: 1)))",
          "updatedAt" : "\(LibraryJSONCodec.encodeDate(Date(timeIntervalSince1970: 2)))"
        }
        """

        try Data(legacyJSON.utf8).write(
            to: booksDirectoryURL.appendingPathComponent("legacy-book.json"),
            options: [.atomic]
        )
        try Data("legacy-cover".utf8).write(
            to: coversDirectoryURL.appendingPathComponent("cover-legacy.bin"),
            options: [.atomic]
        )

        let importer = LegacyLibraryImporter(storageRootURL: rootURL)
        let importedBundle = try importer.loadImportBundle()

        XCTAssertEqual(importedBundle.books.count, 1)
        XCTAssertEqual(importedBundle.books.first?.book.id, "legacy-book")
        XCTAssertEqual(importedBundle.books.first?.book.customFields["ISBN"], "9787111123456")
        XCTAssertEqual(importedBundle.books.first?.book.locationID, "location.chengdu")
        XCTAssertEqual(importedBundle.books.first?.coverData, Data("legacy-cover".utf8))
    }

    func testLegacyImporterLoadsBooksFromExplicitImportFile() throws {
        let rootURL = try makeTemporaryDirectory()
        let importURL = rootURL.appendingPathComponent("LibraryImport.json")
        let payload = """
        {
          "schemaVersion" : 2,
          "source" : "unit-test",
          "locations" : [
            {
              "id" : "location.study",
              "name" : "书房",
              "sortOrder" : 0,
              "isVisible" : true
            }
          ],
          "books" : [
            {
              "id" : "import-book",
              "title" : "显式导入",
              "author" : "作者 A",
              "publisher" : "出版社 A",
              "year" : "2024",
              "locationID" : "location.study",
              "locationName" : "书房",
              "customFields" : {
                "备注" : "外部文件"
              },
              "createdAt" : "\(LibraryJSONCodec.encodeDate(Date(timeIntervalSince1970: 1)))",
              "updatedAt" : "\(LibraryJSONCodec.encodeDate(Date(timeIntervalSince1970: 2)))"
            }
          ]
        }
        """
        try Data(payload.utf8).write(to: importURL, options: [.atomic])

        let importer = LegacyLibraryImporter(storageRootURL: rootURL)
        let importedBundle = try importer.loadImportBundle(from: importURL)

        XCTAssertEqual(importedBundle.locations.map(\.name), ["书房"])
        XCTAssertEqual(importedBundle.books.count, 1)
        XCTAssertEqual(importedBundle.books.first?.book.id, "import-book")
        XCTAssertEqual(importedBundle.books.first?.book.title, "显式导入")
        XCTAssertEqual(importedBundle.books.first?.book.locationID, "location.study")
        XCTAssertEqual(importedBundle.books.first?.book.customFields["备注"], "外部文件")
    }

    func testLegacyImporterLoadsStructuredSeedFileWithoutLocationsArray() throws {
        let rootURL = try makeTemporaryDirectory()
        let importURL = rootURL.appendingPathComponent("SeedBooks.json")
        let payload = """
        {
          "schemaVersion" : 1,
          "source" : "unit-test-seed",
          "exportedAt" : "\(LibraryJSONCodec.encodeDate(Date(timeIntervalSince1970: 5)))",
          "books" : [
            {
              "id" : "seed-book",
              "title" : "种子导入",
              "author" : "作者 Seed",
              "publisher" : "出版社 Seed",
              "year" : "2025",
              "location" : "成都",
              "customFields" : {},
              "createdAt" : "\(LibraryJSONCodec.encodeDate(Date(timeIntervalSince1970: 1)))",
              "updatedAt" : "\(LibraryJSONCodec.encodeDate(Date(timeIntervalSince1970: 2)))"
            }
          ]
        }
        """
        try Data(payload.utf8).write(to: importURL, options: [.atomic])

        let importer = LegacyLibraryImporter(storageRootURL: rootURL)
        let importedBundle = try importer.loadImportBundle(from: importURL)

        XCTAssertEqual(importedBundle.locations.map(\.name), ["成都"])
        XCTAssertEqual(importedBundle.books.count, 1)
        XCTAssertEqual(importedBundle.books.first?.book.id, "seed-book")
        XCTAssertEqual(importedBundle.books.first?.book.locationID, "location.chengdu")
    }

    func testLegacyImporterNormalizesSeedLocationsWhenLocationIDContainsName() throws {
        let rootURL = try makeTemporaryDirectory()
        let importURL = rootURL.appendingPathComponent("SeedBooks.json")
        let payload = """
        {
          "schemaVersion" : 2,
          "source" : "unit-test-seed",
          "locations" : [
            {
              "id" : " ",
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
        try Data(payload.utf8).write(to: importURL, options: [.atomic])

        let importer = LegacyLibraryImporter(storageRootURL: rootURL)
        let importedBundle = try importer.loadImportBundle(from: importURL)

        XCTAssertEqual(importedBundle.locations.map(\.name), ["成都"])
        XCTAssertEqual(importedBundle.locations.map(\.id), ["location.chengdu"])
        XCTAssertEqual(importedBundle.books.first?.book.locationID, "location.chengdu")
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
