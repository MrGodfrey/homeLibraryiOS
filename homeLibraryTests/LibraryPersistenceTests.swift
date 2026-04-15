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

        let coverData = Data("cover-image-data".utf8)
        let storedBook = try store.upsert(
            book: Book(
                id: "book-1",
                title: "重构",
                author: "Martin Fowler",
                publisher: "Addison-Wesley",
                year: "2018",
                location: .chengdu,
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

    func testReplaceAllBooksGarbageCollectsStaleAssets() throws {
        let rootURL = try makeTemporaryDirectory()
        let store = LibraryCacheStore(rootURL: rootURL)
        let repositoryID = "repo-2"

        let firstBook = try store.upsert(
            book: Book(
                id: "book-1",
                title: "旧书",
                location: .chengdu,
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
            location: .chongqing,
            coverAssetID: "cover-new",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 11)
        )

        try store.replaceAllBooks(
            [replacementBook],
            coverDataByAssetID: ["cover-new": Data("new-cover".utf8)],
            repositoryID: repositoryID,
            synchronizedAt: Date(timeIntervalSince1970: 99)
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: staleCoverURL.path))
        XCTAssertEqual(
            try store.coverData(for: "cover-new", repositoryID: repositoryID),
            Data("new-cover".utf8)
        )
    }

    func testLegacyImporterLoadsStructuredBooksAndSkipsDeletedRecords() throws {
        let rootURL = try makeTemporaryDirectory()
        let booksDirectoryURL = rootURL.appendingPathComponent("books", isDirectory: true)
        let coversDirectoryURL = rootURL.appendingPathComponent("covers", isDirectory: true)
        let deletionsDirectoryURL = rootURL.appendingPathComponent("deletions", isDirectory: true)
        try FileManager.default.createDirectory(at: booksDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: coversDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: deletionsDirectoryURL, withIntermediateDirectories: true)

        let activeBook = Book(
            id: "active-book",
            title: "保留",
            author: "作者 A",
            location: .chengdu,
            coverAssetID: "cover-active",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let deletedBook = Book(
            id: "deleted-book",
            title: "删除",
            author: "作者 B",
            location: .chongqing,
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
        let importedBooks = try importer.loadBooks()

        XCTAssertEqual(importedBooks.count, 1)
        XCTAssertEqual(importedBooks.first?.book.id, "active-book")
        XCTAssertEqual(importedBooks.first?.coverData, Data("active-cover".utf8))
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
        let importedBooks = try importer.loadBooks()

        XCTAssertEqual(importedBooks.count, 1)
        XCTAssertEqual(importedBooks.first?.book.id, "legacy-book")
        XCTAssertEqual(importedBooks.first?.book.customFields["ISBN"], "9787111123456")
        XCTAssertEqual(importedBooks.first?.coverData, Data("legacy-cover".utf8))
    }

    func testLegacyImporterLoadsBooksFromExplicitImportFile() throws {
        let rootURL = try makeTemporaryDirectory()
        let importURL = rootURL.appendingPathComponent("LibraryImport.json")
        let payload = """
        {
          "schemaVersion" : 1,
          "source" : "unit-test",
          "books" : [
            {
              "id" : "import-book",
              "title" : "显式导入",
              "author" : "作者 A",
              "publisher" : "出版社 A",
              "year" : "2024",
              "location" : "成都",
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
        let importedBooks = try importer.loadBooks(from: importURL)

        XCTAssertEqual(importedBooks.count, 1)
        XCTAssertEqual(importedBooks.first?.book.id, "import-book")
        XCTAssertEqual(importedBooks.first?.book.title, "显式导入")
        XCTAssertEqual(importedBooks.first?.book.customFields["备注"], "外部文件")
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
