//
//  LibraryPersistence.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import CryptoKit
import Foundation

enum LibraryJSONCodec {
    nonisolated(unsafe) private static let formatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let formatterWithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)

            if let date = decodeDate(rawValue) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date format: \(rawValue)"
            )
        }
        return decoder
    }

    nonisolated static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(encodeDate(date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    nonisolated static func decodeDate(_ rawValue: String) -> Date? {
        formatterWithFractionalSeconds.date(from: rawValue) ?? formatterWithoutFractionalSeconds.date(from: rawValue)
    }

    nonisolated static func encodeDate(_ date: Date) -> String {
        formatterWithFractionalSeconds.string(from: date)
    }
}

nonisolated struct LibraryCacheManifest: Codable, Equatable, Sendable {
    nonisolated static let currentSchemaVersion = 1

    var schemaVersion: Int
    var repositoryID: String
    var lastSuccessfulSyncAt: Date?

    nonisolated static func makeNew(repositoryID: String) -> LibraryCacheManifest {
        LibraryCacheManifest(
            schemaVersion: currentSchemaVersion,
            repositoryID: repositoryID,
            lastSuccessfulSyncAt: nil
        )
    }
}

nonisolated struct LibraryCacheSnapshot: Sendable {
    let books: [Book]

    nonisolated var referencedAssetIDs: Set<String> {
        Set(books.compactMap(\.coverAssetID))
    }
}

nonisolated struct LegacyImportedBook: Sendable {
    let book: Book
    let coverData: Data?
}

nonisolated struct LegacyDeletionRecord: Codable, Sendable {
    let id: String
    let deletedAt: Date
}

nonisolated struct LibraryCacheStore: Sendable {
    let rootURL: URL

    nonisolated func prepareForUse(repositoryID: String) throws {
        try ensureDirectoriesExist(for: repositoryID)

        if try readManifest(for: repositoryID) == nil {
            try writeManifest(.makeNew(repositoryID: repositoryID), for: repositoryID)
        }
    }

    nonisolated func loadSnapshot(repositoryID: String) throws -> LibraryCacheSnapshot {
        try prepareForUse(repositoryID: repositoryID)

        let books = try loadRecords(of: Book.self, from: booksDirectoryURL(for: repositoryID))
            .sorted { left, right in
                if left.updatedAt != right.updatedAt {
                    return left.updatedAt > right.updatedAt
                }

                return left.createdAt > right.createdAt
            }

        return LibraryCacheSnapshot(books: books)
    }

    @discardableResult
    nonisolated func upsert(book: Book, coverData: Data?, repositoryID: String) throws -> Book {
        try prepareForUse(repositoryID: repositoryID)

        var storedBook = book
        storedBook.coverAssetID = try writeCoverAssetIfNeeded(coverData, repositoryID: repositoryID)

        let data = try LibraryJSONCodec.makeEncoder().encode(storedBook)
        try data.write(to: bookRecordURL(for: storedBook.id, repositoryID: repositoryID), options: [.atomic])
        try garbageCollectAssets(repositoryID: repositoryID)
        return storedBook
    }

    nonisolated func replaceAllBooks(
        _ books: [Book],
        coverDataByAssetID: [String: Data],
        repositoryID: String,
        synchronizedAt: Date?
    ) throws {
        try prepareForUse(repositoryID: repositoryID)

        try resetBooksDirectory(for: repositoryID)

        for book in books {
            if let assetID = book.coverAssetID, let data = coverDataByAssetID[assetID] {
                _ = try writeCoverAsset(data, preferredAssetID: assetID, repositoryID: repositoryID)
            }

            let data = try LibraryJSONCodec.makeEncoder().encode(book)
            try data.write(to: bookRecordURL(for: book.id, repositoryID: repositoryID), options: [.atomic])
        }

        try mutateManifest(for: repositoryID) { manifest in
            manifest.lastSuccessfulSyncAt = synchronizedAt
        }
        try garbageCollectAssets(repositoryID: repositoryID)
    }

    nonisolated func removeBook(id: String, repositoryID: String) throws {
        try removeItemIfPresent(at: bookRecordURL(for: id, repositoryID: repositoryID))
        try garbageCollectAssets(repositoryID: repositoryID)
    }

    nonisolated func coverData(for assetID: String, repositoryID: String) throws -> Data? {
        let url = coverURL(for: assetID, repositoryID: repositoryID)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        return try Data(contentsOf: url)
    }

    nonisolated func markSyncSuccess(at date: Date, repositoryID: String) throws {
        try prepareForUse(repositoryID: repositoryID)
        try mutateManifest(for: repositoryID) { manifest in
            manifest.lastSuccessfulSyncAt = date
        }
    }

    nonisolated func clearRepository(_ repositoryID: String) throws {
        try removeItemIfPresent(at: repositoryRootURL(for: repositoryID))
    }

    @discardableResult
    nonisolated func writeCoverAsset(
        _ data: Data,
        preferredAssetID: String? = nil,
        repositoryID: String
    ) throws -> String {
        try prepareForUse(repositoryID: repositoryID)

        let assetID = preferredAssetID ?? makeCoverAssetID(from: data)
        let assetURL = coverURL(for: assetID, repositoryID: repositoryID)

        if !FileManager.default.fileExists(atPath: assetURL.path) {
            try data.write(to: assetURL, options: [.atomic])
        }

        return assetID
    }

    nonisolated private func readManifest(for repositoryID: String) throws -> LibraryCacheManifest? {
        let manifestURL = manifestURL(for: repositoryID)

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: manifestURL)
        return try LibraryJSONCodec.makeDecoder().decode(LibraryCacheManifest.self, from: data)
    }

    nonisolated private func writeManifest(_ manifest: LibraryCacheManifest, for repositoryID: String) throws {
        let data = try LibraryJSONCodec.makeEncoder().encode(manifest)
        try data.write(to: manifestURL(for: repositoryID), options: [.atomic])
    }

    nonisolated private func mutateManifest(
        for repositoryID: String,
        _ mutate: (inout LibraryCacheManifest) -> Void
    ) throws {
        var manifest = try readManifest(for: repositoryID) ?? .makeNew(repositoryID: repositoryID)
        mutate(&manifest)
        try writeManifest(manifest, for: repositoryID)
    }

    nonisolated private func loadRecords<Record: Decodable>(of type: Record.Type, from directoryURL: URL) throws -> [Record] {
        let recordURLs = try jsonFiles(in: directoryURL)
        let decoder = LibraryJSONCodec.makeDecoder()

        return try recordURLs.map { url in
            let data = try Data(contentsOf: url)
            return try decoder.decode(Record.self, from: data)
        }
    }

    nonisolated private func garbageCollectAssets(repositoryID: String) throws {
        let snapshot = try loadSnapshot(repositoryID: repositoryID)
        let referencedAssetIDs = snapshot.referencedAssetIDs
        let assetFiles = try binaryFiles(in: coversDirectoryURL(for: repositoryID))

        for assetFile in assetFiles where !referencedAssetIDs.contains(assetFile.deletingPathExtension().lastPathComponent) {
            try removeItemIfPresent(at: assetFile)
        }
    }

    nonisolated private func resetBooksDirectory(for repositoryID: String) throws {
        let booksDirectoryURL = booksDirectoryURL(for: repositoryID)
        try removeItemIfPresent(at: booksDirectoryURL)
        try FileManager.default.createDirectory(at: booksDirectoryURL, withIntermediateDirectories: true)
    }

    nonisolated private func ensureDirectoriesExist(for repositoryID: String) throws {
        let fileManager = FileManager.default

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: repositoryRootURL(for: repositoryID), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: booksDirectoryURL(for: repositoryID), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: coversDirectoryURL(for: repositoryID), withIntermediateDirectories: true)
    }

    nonisolated private func writeCoverAssetIfNeeded(_ data: Data?, repositoryID: String) throws -> String? {
        guard let data, !data.isEmpty else {
            return nil
        }

        return try writeCoverAsset(data, repositoryID: repositoryID)
    }

    nonisolated private func repositoryRootURL(for repositoryID: String) -> URL {
        rootURL.appendingPathComponent(repositoryID, isDirectory: true)
    }

    nonisolated private func booksDirectoryURL(for repositoryID: String) -> URL {
        repositoryRootURL(for: repositoryID).appendingPathComponent("books", isDirectory: true)
    }

    nonisolated private func coversDirectoryURL(for repositoryID: String) -> URL {
        repositoryRootURL(for: repositoryID).appendingPathComponent("covers", isDirectory: true)
    }

    nonisolated private func manifestURL(for repositoryID: String) -> URL {
        repositoryRootURL(for: repositoryID).appendingPathComponent("manifest.json")
    }

    nonisolated private func bookRecordURL(for bookID: String, repositoryID: String) -> URL {
        booksDirectoryURL(for: repositoryID).appendingPathComponent("\(bookID).json")
    }

    nonisolated private func coverURL(for assetID: String, repositoryID: String) -> URL {
        coversDirectoryURL(for: repositoryID).appendingPathComponent("\(assetID).bin")
    }

    nonisolated private func jsonFiles(in directoryURL: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    nonisolated private func binaryFiles(in directoryURL: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "bin" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    nonisolated private func makeCoverAssetID(from data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "cover-\(hex)"
    }

    nonisolated private func removeItemIfPresent(at url: URL) throws {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try fileManager.removeItem(at: url)
    }
}

nonisolated struct LegacyLibraryImporter: Sendable {
    let storageRootURL: URL

    nonisolated func loadBooks() throws -> [LegacyImportedBook] {
        if try hasStructuredRecords() {
            return try loadStructuredBooks()
        }

        if FileManager.default.fileExists(atPath: legacyBooksJSONURL.path) {
            return try loadLegacyBooksJSON()
        }

        return []
    }

    nonisolated func cleanupAfterMigration() throws {
        let urlsToRemove = [
            storageRootURL.appendingPathComponent("books", isDirectory: true),
            storageRootURL.appendingPathComponent("covers", isDirectory: true),
            storageRootURL.appendingPathComponent("deletions", isDirectory: true),
            storageRootURL.appendingPathComponent("manifest.json"),
            legacyBooksJSONURL,
            storageRootURL.appendingPathComponent("books.legacy.backup.json")
        ]

        for url in urlsToRemove where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    nonisolated private var legacyBooksJSONURL: URL {
        storageRootURL.appendingPathComponent("books.json")
    }

    nonisolated private func hasStructuredRecords() throws -> Bool {
        let booksURL = storageRootURL.appendingPathComponent("books", isDirectory: true)
        guard FileManager.default.fileExists(atPath: booksURL.path) else {
            return false
        }

        return try !FileManager.default.contentsOfDirectory(
            at: booksURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).isEmpty
    }

    nonisolated private func loadStructuredBooks() throws -> [LegacyImportedBook] {
        let booksDirectoryURL = storageRootURL.appendingPathComponent("books", isDirectory: true)
        let coversDirectoryURL = storageRootURL.appendingPathComponent("covers", isDirectory: true)
        let deletionsDirectoryURL = storageRootURL.appendingPathComponent("deletions", isDirectory: true)
        let decoder = LibraryJSONCodec.makeDecoder()

        let tombstones = try FileManager.default.fileExists(atPath: deletionsDirectoryURL.path) ?
            FileManager.default.contentsOfDirectory(
                at: deletionsDirectoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension == "json" }
            .map { url in
                try decoder.decode(LegacyDeletionRecord.self, from: Data(contentsOf: url))
            } : []

        let tombstonesByID = Dictionary(uniqueKeysWithValues: tombstones.map { ($0.id, $0) })
        let bookURLs = try FileManager.default.contentsOfDirectory(
            at: booksDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }

        var importedBooks: [LegacyImportedBook] = []

        for url in bookURLs {
            let book = try decoder.decode(Book.self, from: Data(contentsOf: url))

            if let tombstone = tombstonesByID[book.id], tombstone.deletedAt >= book.updatedAt {
                continue
            }

            let coverData: Data?
            if let assetID = book.coverAssetID {
                let assetURL = coversDirectoryURL.appendingPathComponent("\(assetID).bin")
                coverData = FileManager.default.fileExists(atPath: assetURL.path) ? try Data(contentsOf: assetURL) : nil
            } else {
                coverData = nil
            }

            importedBooks.append(LegacyImportedBook(book: book, coverData: coverData))
        }

        return importedBooks
    }

    nonisolated private func loadLegacyBooksJSON() throws -> [LegacyImportedBook] {
        let data = try Data(contentsOf: legacyBooksJSONURL)

        guard !data.isEmpty else {
            return []
        }

        let decoder = LibraryJSONCodec.makeDecoder()
        let legacyBooks = try decoder.decode([LegacyBook].self, from: data)

        return legacyBooks.map { legacyBook in
            let book = Book(
                id: legacyBook.id,
                title: legacyBook.title,
                author: legacyBook.author,
                publisher: legacyBook.publisher,
                year: legacyBook.year,
                location: legacyBook.location,
                createdAt: legacyBook.createdAt,
                updatedAt: legacyBook.updatedAt
            )

            return LegacyImportedBook(book: book, coverData: legacyBook.coverData)
        }
    }
}
