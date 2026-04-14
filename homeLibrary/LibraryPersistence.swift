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

struct LibraryManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var initializedAt: Date
    var lastLocalMutationAt: Date?
    var lastSuccessfulSyncAt: Date?

    nonisolated static func makeNew(now: Date = .now) -> LibraryManifest {
        LibraryManifest(
            schemaVersion: currentSchemaVersion,
            initializedAt: now,
            lastLocalMutationAt: nil,
            lastSuccessfulSyncAt: nil
        )
    }
}

struct LibrarySnapshot: Sendable {
    let books: [Book]
    let tombstonesByID: [String: BookDeletionTombstone]

    nonisolated var booksByID: [String: Book] {
        Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
    }

    nonisolated var referencedAssetIDs: Set<String> {
        Set(books.compactMap(\.coverAssetID))
    }
}

struct LibraryDiskStore: Sendable {
    let rootURL: URL

    var booksDirectoryURL: URL {
        rootURL.appendingPathComponent("books", isDirectory: true)
    }

    var coversDirectoryURL: URL {
        rootURL.appendingPathComponent("covers", isDirectory: true)
    }

    var deletionsDirectoryURL: URL {
        rootURL.appendingPathComponent("deletions", isDirectory: true)
    }

    var manifestURL: URL {
        rootURL.appendingPathComponent("manifest.json")
    }

    var legacyBooksFileURL: URL {
        rootURL.appendingPathComponent("books.json")
    }

    nonisolated func prepareForUse(
        legacyBooksURL: URL? = nil,
        bundledSeedURL: URL? = nil,
        allowBundledSeed: Bool = true
    ) throws {
        try ensureDirectoriesExist()

        if try readManifest() != nil {
            return
        }

        if try hasStructuredContent() {
            try writeManifest(.makeNew())
            try garbageCollectAssets()
            return
        }

        if let sourceURL = preferredLegacySource(legacyBooksURL: legacyBooksURL, bundledSeedURL: allowBundledSeed ? bundledSeedURL : nil) {
            try importLegacyLibrary(from: sourceURL)

            if sourceURL.standardizedFileURL == legacyBooksFileURL.standardizedFileURL {
                try archiveLegacyBooksFile(sourceURL)
            }
        } else {
            try writeManifest(.makeNew())
        }

        try garbageCollectAssets()
    }

    nonisolated func loadSnapshot() throws -> LibrarySnapshot {
        try ensureDirectoriesExist()

        let books = try loadRecords(of: Book.self, from: booksDirectoryURL)
        let tombstones = try loadRecords(of: BookDeletionTombstone.self, from: deletionsDirectoryURL)
        let tombstonesByID = Dictionary(uniqueKeysWithValues: tombstones.map { ($0.id, $0) })

        let visibleBooks = books
            .filter { book in
                guard let tombstone = tombstonesByID[book.id] else {
                    return true
                }

                return tombstone.deletedAt < book.updatedAt
            }
            .sorted { left, right in
                if left.updatedAt != right.updatedAt {
                    return left.updatedAt > right.updatedAt
                }

                return left.createdAt > right.createdAt
            }

        return LibrarySnapshot(books: visibleBooks, tombstonesByID: tombstonesByID)
    }

    nonisolated func upsert(book: Book, coverData: Data?) throws -> Book {
        try ensureWritableManifestExists()

        var storedBook = book
        storedBook.coverAssetID = try writeCoverAssetIfNeeded(coverData)

        try writeBookRecord(storedBook)
        try removeTombstone(for: storedBook.id)
        try mutateManifest { manifest in
            manifest.lastLocalMutationAt = storedBook.updatedAt
        }
        try garbageCollectAssets()

        return storedBook
    }

    nonisolated func recordDeletion(for bookID: String, deletedAt: Date) throws {
        try ensureWritableManifestExists()
        try removeBookRecord(for: bookID)
        try writeTombstone(BookDeletionTombstone(id: bookID, deletedAt: deletedAt))
        try mutateManifest { manifest in
            manifest.lastLocalMutationAt = deletedAt
        }
        try garbageCollectAssets()
    }

    nonisolated func writeBookRecord(_ book: Book) throws {
        try ensureDirectoriesExist()
        let encoder = LibraryJSONCodec.makeEncoder()
        let data = try encoder.encode(book)
        try data.write(to: bookRecordURL(for: book.id), options: [.atomic])
    }

    nonisolated func removeBookRecord(for bookID: String) throws {
        try removeItemIfPresent(at: bookRecordURL(for: bookID))
    }

    nonisolated func writeTombstone(_ tombstone: BookDeletionTombstone) throws {
        try ensureDirectoriesExist()
        let encoder = LibraryJSONCodec.makeEncoder()
        let data = try encoder.encode(tombstone)
        try data.write(to: tombstoneURL(for: tombstone.id), options: [.atomic])
    }

    nonisolated func removeTombstone(for bookID: String) throws {
        try removeItemIfPresent(at: tombstoneURL(for: bookID))
    }

    nonisolated func coverData(for assetID: String) throws -> Data? {
        let url = coverURL(for: assetID)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        return try Data(contentsOf: url)
    }

    nonisolated func hasCoverAsset(_ assetID: String) -> Bool {
        FileManager.default.fileExists(atPath: coverURL(for: assetID).path)
    }

    @discardableResult
    nonisolated func writeCoverAsset(_ data: Data, preferredAssetID: String? = nil) throws -> String {
        try ensureDirectoriesExist()

        let assetID = preferredAssetID ?? makeCoverAssetID(from: data)
        let assetURL = coverURL(for: assetID)

        if !FileManager.default.fileExists(atPath: assetURL.path) {
            try data.write(to: assetURL, options: [.atomic])
        }

        return assetID
    }

    nonisolated func copyCoverAssetIfNeeded(_ assetID: String, from sourceStore: LibraryDiskStore) throws {
        guard !hasCoverAsset(assetID), let data = try sourceStore.coverData(for: assetID) else {
            return
        }

        try writeCoverAsset(data, preferredAssetID: assetID)
    }

    nonisolated func garbageCollectAssets() throws {
        try ensureDirectoriesExist()

        let snapshot = try loadSnapshot()
        let referencedAssetIDs = snapshot.referencedAssetIDs
        let assetFiles = try jsonAndBinaryFiles(in: coversDirectoryURL)

        for assetFile in assetFiles where !referencedAssetIDs.contains(assetFile.deletingPathExtension().lastPathComponent) {
            try removeItemIfPresent(at: assetFile)
        }
    }

    nonisolated func markSyncSuccess(at date: Date) throws {
        try ensureWritableManifestExists()
        try mutateManifest { manifest in
            manifest.lastSuccessfulSyncAt = date
        }
    }

    nonisolated func readManifest() throws -> LibraryManifest? {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: manifestURL)
        return try LibraryJSONCodec.makeDecoder().decode(LibraryManifest.self, from: data)
    }

    nonisolated private func importLegacyLibrary(from url: URL) throws {
        let data = try Data(contentsOf: url)

        if data.isEmpty {
            try writeManifest(.makeNew())
            return
        }

        let decoder = LibraryJSONCodec.makeDecoder()
        let legacyBooks = try decoder.decode([LegacyBook].self, from: data)

        for legacyBook in legacyBooks {
            var migratedBook = Book(
                id: legacyBook.id,
                title: legacyBook.title,
                author: legacyBook.author,
                publisher: legacyBook.publisher,
                year: legacyBook.year,
                isbn: legacyBook.isbn,
                location: legacyBook.location,
                createdAt: legacyBook.createdAt,
                updatedAt: legacyBook.updatedAt
            )

            if let coverData = legacyBook.coverData, !coverData.isEmpty {
                migratedBook.coverAssetID = try writeCoverAsset(coverData)
            }

            try writeBookRecord(migratedBook)
        }

        try writeManifest(.makeNew())
    }

    nonisolated private func archiveLegacyBooksFile(_ sourceURL: URL) throws {
        let backupURL = rootURL.appendingPathComponent("books.legacy.backup.json")

        if FileManager.default.fileExists(atPath: backupURL.path) {
            try removeItemIfPresent(at: backupURL)
        }

        try FileManager.default.moveItem(at: sourceURL, to: backupURL)
    }

    nonisolated private func preferredLegacySource(legacyBooksURL: URL?, bundledSeedURL: URL?) -> URL? {
        let fileManager = FileManager.default

        if let legacyBooksURL, fileManager.fileExists(atPath: legacyBooksURL.path) {
            return legacyBooksURL
        }

        if let bundledSeedURL, fileManager.fileExists(atPath: bundledSeedURL.path) {
            return bundledSeedURL
        }

        return nil
    }

    nonisolated private func loadRecords<Record: Decodable>(of type: Record.Type, from directoryURL: URL) throws -> [Record] {
        let recordURLs = try jsonFiles(in: directoryURL)
        let decoder = LibraryJSONCodec.makeDecoder()

        return try recordURLs.map { url in
            let data = try Data(contentsOf: url)
            return try decoder.decode(Record.self, from: data)
        }
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

    nonisolated private func jsonAndBinaryFiles(in directoryURL: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.hasDirectoryPath == false }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    nonisolated private func writeManifest(_ manifest: LibraryManifest) throws {
        let data = try LibraryJSONCodec.makeEncoder().encode(manifest)
        try data.write(to: manifestURL, options: [.atomic])
    }

    nonisolated private func mutateManifest(_ mutate: (inout LibraryManifest) -> Void) throws {
        var manifest = try readManifest() ?? .makeNew()
        mutate(&manifest)
        try writeManifest(manifest)
    }

    nonisolated private func ensureWritableManifestExists() throws {
        try ensureDirectoriesExist()

        if try readManifest() == nil {
            try writeManifest(.makeNew())
        }
    }

    nonisolated private func ensureDirectoriesExist() throws {
        let fileManager = FileManager.default

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: booksDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: coversDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: deletionsDirectoryURL, withIntermediateDirectories: true)
    }

    nonisolated private func hasStructuredContent() throws -> Bool {
        try !jsonFiles(in: booksDirectoryURL).isEmpty ||
            !jsonFiles(in: deletionsDirectoryURL).isEmpty ||
            !jsonAndBinaryFiles(in: coversDirectoryURL).isEmpty
    }

    nonisolated private func makeCoverAssetID(from data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "cover-\(hex)"
    }

    nonisolated private func writeCoverAssetIfNeeded(_ data: Data?) throws -> String? {
        guard let data, !data.isEmpty else {
            return nil
        }

        return try writeCoverAsset(data)
    }

    nonisolated private func bookRecordURL(for bookID: String) -> URL {
        booksDirectoryURL.appendingPathComponent("\(bookID).json")
    }

    nonisolated private func tombstoneURL(for bookID: String) -> URL {
        deletionsDirectoryURL.appendingPathComponent("\(bookID).json")
    }

    nonisolated private func coverURL(for assetID: String) -> URL {
        coversDirectoryURL.appendingPathComponent("\(assetID).bin")
    }

    nonisolated private func removeItemIfPresent(at url: URL) throws {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try fileManager.removeItem(at: url)
    }
}
