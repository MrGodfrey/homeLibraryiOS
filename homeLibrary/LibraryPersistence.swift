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
    nonisolated static let currentSchemaVersion = 2

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
    let locations: [LibraryLocation]
    let books: [Book]

    nonisolated var referencedAssetIDs: Set<String> {
        Set(books.compactMap(\.coverAssetID))
    }

    nonisolated var locationsByID: [String: LibraryLocation] {
        Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
    }
}

nonisolated struct LegacyImportedBook: Sendable {
    let book: Book
    let coverData: Data?
}

nonisolated struct LegacyImportBundle: Sendable {
    let locations: [LibraryLocation]
    let books: [LegacyImportedBook]
}

nonisolated struct LibraryImportPackage: Codable, Sendable {
    nonisolated static let currentSchemaVersion = 2

    var schemaVersion: Int
    var source: String?
    var exportedAt: Date?
    var locations: [LibraryImportLocation]
    var books: [LibraryImportBook]
}

nonisolated struct LibraryImportLocation: Codable, Sendable {
    var id: String
    var name: String
    var sortOrder: Int
    var isVisible: Bool

    init(location: LibraryLocation) {
        id = location.id
        name = location.name
        sortOrder = location.sortOrder
        isVisible = location.isVisible
    }

    nonisolated func makeLocation() -> LibraryLocation {
        LibraryLocation(id: id, name: name, sortOrder: sortOrder, isVisible: isVisible)
    }
}

nonisolated struct LibraryImportBook: Codable, Sendable {
    var id: String
    var title: String
    var author: String
    var publisher: String
    var year: String
    var locationID: String?
    var locationName: String?
    var customFields: [String: String]
    var isbn: String?
    var coverData: Data?
    var createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case author
        case publisher
        case year
        case locationID
        case locationName
        case location
        case customFields
        case isbn
        case coverData
        case createdAt
        case updatedAt
    }

    init(
        id: String,
        title: String,
        author: String,
        publisher: String,
        year: String,
        locationID: String?,
        locationName: String?,
        customFields: [String: String],
        isbn: String?,
        coverData: Data?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.publisher = publisher
        self.year = year
        self.locationID = locationID
        self.locationName = locationName
        self.customFields = customFields
        self.isbn = isbn
        self.coverData = coverData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher) ?? ""
        year = try container.decodeIfPresent(String.self, forKey: .year) ?? ""
        locationID = try container.decodeIfPresent(String.self, forKey: .locationID)
        let decodedLocationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        let decodedLegacyLocation = try container.decodeIfPresent(String.self, forKey: .location)
        locationName = decodedLocationName ?? decodedLegacyLocation
        customFields = try container.decodeIfPresent([String: String].self, forKey: .customFields) ?? [:]
        isbn = try container.decodeIfPresent(String.self, forKey: .isbn)
        coverData = try container.decodeIfPresent(Data.self, forKey: .coverData)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(author, forKey: .author)
        try container.encode(publisher, forKey: .publisher)
        try container.encode(year, forKey: .year)
        try container.encodeIfPresent(locationID, forKey: .locationID)
        try container.encodeIfPresent(locationName, forKey: .locationName)
        try container.encode(customFields, forKey: .customFields)
        try container.encodeIfPresent(isbn, forKey: .isbn)
        try container.encodeIfPresent(coverData, forKey: .coverData)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    init(book: Book, coverData: Data?, locationsByID: [String: LibraryLocation]) {
        id = book.id
        title = book.title
        author = book.author
        publisher = book.publisher
        year = book.year
        locationID = book.locationID
        locationName = locationsByID[book.locationID]?.name
        customFields = book.customFields
        isbn = book.customFields["ISBN"]
        self.coverData = coverData
        createdAt = book.createdAt
        updatedAt = book.updatedAt
    }

    nonisolated func makeImportedBook(using locations: [LibraryLocation]) -> LegacyImportedBook {
        let resolvedLocationID = resolveLocationID(using: locations)
        var mergedCustomFields = customFields

        if let isbn, !isbn.trimmed.isEmpty, mergedCustomFields["ISBN"]?.nilIfEmpty == nil {
            mergedCustomFields["ISBN"] = isbn.trimmed
        }

        let book = Book(
            id: id,
            title: title,
            author: author,
            publisher: publisher,
            year: year,
            locationID: resolvedLocationID,
            customFields: mergedCustomFields,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        return LegacyImportedBook(book: book, coverData: coverData)
    }

    nonisolated func resolveLocationID(using locations: [LibraryLocation]) -> String {
        if let locationID, locations.contains(where: { $0.id == locationID }) {
            return locationID
        }

        if let locationName = locationName?.trimmed.nilIfEmpty,
           let matchedLocation = locations.first(where: { $0.name == locationName }) {
            return matchedLocation.id
        }

        return locations.sorted(by: { $0.sortOrder < $1.sortOrder }).first?.id ?? LibraryLocation.defaultLocations()[0].id
    }
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

        if !FileManager.default.fileExists(atPath: locationsURL(for: repositoryID).path) {
            let data = try LibraryJSONCodec.makeEncoder().encode(LibraryLocation.defaultLocations())
            try data.write(to: locationsURL(for: repositoryID), options: [.atomic])
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

        let locations = try loadLocations(repositoryID: repositoryID)

        return LibraryCacheSnapshot(locations: locations, books: books)
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

    nonisolated func replaceAllContent(
        books: [Book],
        locations: [LibraryLocation],
        coverDataByAssetID: [String: Data],
        repositoryID: String,
        synchronizedAt: Date?
    ) throws {
        try prepareForUse(repositoryID: repositoryID)

        try resetBooksDirectory(for: repositoryID)
        try saveLocations(locations, repositoryID: repositoryID)

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

    nonisolated func loadLocations(repositoryID: String) throws -> [LibraryLocation] {
        try prepareForUse(repositoryID: repositoryID)

        let url = locationsURL(for: repositoryID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return LibraryLocation.defaultLocations()
        }

        let data = try Data(contentsOf: url)
        let decoder = LibraryJSONCodec.makeDecoder()
        return try decoder.decode([LibraryLocation].self, from: data)
            .sorted { left, right in
                if left.sortOrder != right.sortOrder {
                    return left.sortOrder < right.sortOrder
                }

                return left.name < right.name
            }
    }

    nonisolated func saveLocations(_ locations: [LibraryLocation], repositoryID: String) throws {
        try prepareForUse(repositoryID: repositoryID)
        let normalizedLocations = locations
            .sorted { left, right in
                if left.sortOrder != right.sortOrder {
                    return left.sortOrder < right.sortOrder
                }

                return left.name < right.name
            }
            .enumerated()
            .map { index, location in
                LibraryLocation(
                    id: location.id,
                    name: location.name.trimmed,
                    sortOrder: index,
                    isVisible: location.isVisible
                )
            }

        let data = try LibraryJSONCodec.makeEncoder().encode(normalizedLocations)
        try data.write(to: locationsURL(for: repositoryID), options: [.atomic])
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

    nonisolated func makeImportPackage(repositoryID: String, source: String?) throws -> LibraryImportPackage {
        let snapshot = try loadSnapshot(repositoryID: repositoryID)
        let locationsByID = snapshot.locationsByID

        let books = try snapshot.books.map { book in
            let resolvedCoverData: Data?
            if let assetID = book.coverAssetID {
                resolvedCoverData = try coverData(for: assetID, repositoryID: repositoryID)
            } else {
                resolvedCoverData = nil
            }

            return LibraryImportBook(book: book, coverData: resolvedCoverData, locationsByID: locationsByID)
        }

        return LibraryImportPackage(
            schemaVersion: LibraryImportPackage.currentSchemaVersion,
            source: source,
            exportedAt: .now,
            locations: snapshot.locations.map(LibraryImportLocation.init(location:)),
            books: books
        )
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

    nonisolated private func locationsURL(for repositoryID: String) -> URL {
        repositoryRootURL(for: repositoryID).appendingPathComponent("locations.json")
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

    nonisolated init(storageRootURL: URL) {
        self.storageRootURL = storageRootURL
    }

    nonisolated func loadImportBundle() throws -> LegacyImportBundle {
        if try hasStructuredRecords() {
            return try loadStructuredBooks()
        }

        if FileManager.default.fileExists(atPath: legacyBooksJSONURL.path) {
            return try loadLegacyBooksJSON()
        }

        if let seedImportURL = firstExistingImportURL(in: [storageRootURL]) {
            return try loadImportBundle(from: seedImportURL)
        }

        return LegacyImportBundle(locations: LibraryLocation.defaultLocations(), books: [])
    }

    nonisolated func loadImportBundle(from importFileURL: URL) throws -> LegacyImportBundle {
        let data = try Data(contentsOf: importFileURL)

        guard !data.isEmpty else {
            return LegacyImportBundle(locations: LibraryLocation.defaultLocations(), books: [])
        }

        let decoder = LibraryJSONCodec.makeDecoder()
        if let package = try? decoder.decode(LibraryImportPackage.self, from: data) {
            let locations = package.locations.map { $0.makeLocation() }
            let normalizedLocations = locations.isEmpty ? LibraryLocation.defaultLocations() : locations
            let books = package.books.map { $0.makeImportedBook(using: normalizedLocations) }
            return LegacyImportBundle(locations: normalizedLocations, books: books)
        }

        if let legacyBooks = try? decoder.decode([LegacyBook].self, from: data) {
            let locations = Self.locations(from: legacyBooks.map(\.locationName))
            return LegacyImportBundle(locations: locations, books: legacyBooks.map { Self.makeImportedBook(from: $0, using: locations) })
        }

        throw CocoaError(.fileReadCorruptFile)
    }

    nonisolated func cleanupAfterMigration() throws {
        let urlsToRemove = [
            storageRootURL.appendingPathComponent("books", isDirectory: true),
            storageRootURL.appendingPathComponent("covers", isDirectory: true),
            storageRootURL.appendingPathComponent("deletions", isDirectory: true),
            storageRootURL.appendingPathComponent("manifest.json"),
            storageRootURL.appendingPathComponent("locations.json"),
            legacyBooksJSONURL,
            storageRootURL.appendingPathComponent("SeedBooks.json"),
            storageRootURL.appendingPathComponent("LibraryImport.json"),
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

    nonisolated private func loadStructuredBooks() throws -> LegacyImportBundle {
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
        var locationNames: [String] = []

        for url in bookURLs {
            let data = try Data(contentsOf: url)
            let importedBook = try decodeStructuredImportedBook(
                from: data,
                coversDirectoryURL: coversDirectoryURL,
                decoder: decoder
            )
            let book = importedBook.book

            if let tombstone = tombstonesByID[book.id], tombstone.deletedAt >= book.updatedAt {
                continue
            }

            locationNames.append(book.locationID)
            importedBooks.append(importedBook)
        }

        let locations = deduplicateLocationsFromStructuredBooks(importedBooks)
        return LegacyImportBundle(locations: locations, books: importedBooks)
    }

    nonisolated private func decodeStructuredImportedBook(
        from data: Data,
        coversDirectoryURL: URL,
        decoder: JSONDecoder
    ) throws -> LegacyImportedBook {
        let legacyBook = try? decoder.decode(LegacyBook.self, from: data)

        do {
            let book = try decoder.decode(Book.self, from: data)
            let coverData = try coverData(for: book.coverAssetID, in: coversDirectoryURL) ?? legacyBook?.coverData
            return LegacyImportedBook(book: book, coverData: coverData)
        } catch {
            if let legacyBook {
                let locations = Self.locations(from: [legacyBook.locationName])
                return Self.makeImportedBook(from: legacyBook, using: locations)
            }

            throw error
        }
    }

    nonisolated private func coverData(for assetID: String?, in coversDirectoryURL: URL) throws -> Data? {
        guard let assetID else {
            return nil
        }

        let assetURL = coversDirectoryURL.appendingPathComponent("\(assetID).bin")
        guard FileManager.default.fileExists(atPath: assetURL.path) else {
            return nil
        }

        return try Data(contentsOf: assetURL)
    }

    nonisolated private func loadLegacyBooksJSON() throws -> LegacyImportBundle {
        let data = try Data(contentsOf: legacyBooksJSONURL)

        guard !data.isEmpty else {
            return LegacyImportBundle(locations: LibraryLocation.defaultLocations(), books: [])
        }

        let decoder = LibraryJSONCodec.makeDecoder()
        let legacyBooks = try decoder.decode([LegacyBook].self, from: data)
        let locations = Self.locations(from: legacyBooks.map(\.locationName))
        return LegacyImportBundle(locations: locations, books: legacyBooks.map { Self.makeImportedBook(from: $0, using: locations) })
    }

    nonisolated private func firstExistingImportURL(in directories: [URL]) -> URL? {
        let fileManager = FileManager.default

        for directoryURL in directories {
            let libraryImportURL = directoryURL.appendingPathComponent("LibraryImport.json")
            if fileManager.fileExists(atPath: libraryImportURL.path) {
                return libraryImportURL
            }

            let seedBooksURL = directoryURL.appendingPathComponent("SeedBooks.json")
            if fileManager.fileExists(atPath: seedBooksURL.path) {
                return seedBooksURL
            }
        }

        return nil
    }

    nonisolated private func deduplicateLocationsFromStructuredBooks(_ books: [LegacyImportedBook]) -> [LibraryLocation] {
        let locationIDs = Set(books.map { $0.book.locationID })
        let defaults = LibraryLocation.defaultLocations()
        let remaining = locationIDs.subtracting(defaults.map(\.id))
        let extra = remaining.sorted().enumerated().map { index, locationID in
            LibraryLocation(id: locationID, name: locationID.replacingOccurrences(of: "location.legacy.", with: ""), sortOrder: defaults.count + index)
        }
        return defaults + extra
    }

    nonisolated private static func locations(from names: [String]) -> [LibraryLocation] {
        let normalizedNames = names
            .map(\.trimmed)
            .filter { !$0.isEmpty }

        guard !normalizedNames.isEmpty else {
            return LibraryLocation.defaultLocations()
        }

        let uniqueNames = Array(NSOrderedSet(array: normalizedNames)) as? [String] ?? normalizedNames
        return uniqueNames.enumerated().map { index, name in
            LibraryLocation(
                id: BookPayload.makeLocationID(fromLegacyName: name),
                name: name,
                sortOrder: index
            )
        }
    }

    nonisolated private static func makeImportedBook(
        from legacyBook: LegacyBook,
        using locations: [LibraryLocation]
    ) -> LegacyImportedBook {
        var customFields: [String: String] = [:]

        if !legacyBook.isbn.trimmed.isEmpty {
            customFields["ISBN"] = legacyBook.isbn.trimmed
        }

        let locationID = locations.first(where: { $0.name == legacyBook.locationName })?.id
            ?? BookPayload.makeLocationID(fromLegacyName: legacyBook.locationName)

        let book = Book(
            id: legacyBook.id,
            title: legacyBook.title,
            author: legacyBook.author,
            publisher: legacyBook.publisher,
            year: legacyBook.year,
            locationID: locationID,
            customFields: customFields,
            createdAt: legacyBook.createdAt,
            updatedAt: legacyBook.updatedAt
        )

        return LegacyImportedBook(book: book, coverData: legacyBook.coverData)
    }
}

enum LibraryZipArchiveWriter {
    nonisolated static func writeSingleFileArchive(filename: String, fileData: Data, to url: URL) throws {
        let filenameData = Data(filename.utf8)
        let crc = CRC32.checksum(fileData)
        let compressedSize = UInt32(fileData.count)
        let uncompressedSize = UInt32(fileData.count)
        let localHeaderOffset = UInt32(0)

        var archive = Data()
        archive.append(uint32: 0x04034b50)
        archive.append(uint16: 20)
        archive.append(uint16: 0)
        archive.append(uint16: 0)
        archive.append(uint16: 0)
        archive.append(uint16: 0)
        archive.append(uint32: crc)
        archive.append(uint32: compressedSize)
        archive.append(uint32: uncompressedSize)
        archive.append(uint16: UInt16(filenameData.count))
        archive.append(uint16: 0)
        archive.append(filenameData)
        archive.append(fileData)

        let centralDirectoryOffset = UInt32(archive.count)
        archive.append(uint32: 0x02014b50)
        archive.append(uint16: 20)
        archive.append(uint16: 20)
        archive.append(uint16: 0)
        archive.append(uint16: 0)
        archive.append(uint16: 0)
        archive.append(uint16: 0)
        archive.append(uint32: crc)
        archive.append(uint32: compressedSize)
        archive.append(uint32: uncompressedSize)
        archive.append(uint16: UInt16(filenameData.count))
        archive.append(uint16: 0)
        archive.append(uint16: 0)
        archive.append(uint16: 0)
        archive.append(uint16: 0)
        archive.append(uint32: 0)
        archive.append(uint32: localHeaderOffset)
        archive.append(filenameData)

        let centralDirectorySize = UInt32(archive.count) - centralDirectoryOffset
        archive.append(uint32: 0x06054b50)
        archive.append(uint16: 0)
        archive.append(uint16: 0)
        archive.append(uint16: 1)
        archive.append(uint16: 1)
        archive.append(uint32: centralDirectorySize)
        archive.append(uint32: centralDirectoryOffset)
        archive.append(uint16: 0)

        try archive.write(to: url, options: [.atomic])
    }
}

private enum CRC32 {
    nonisolated static let table: [UInt32] = (0..<256).map { value in
        var current = UInt32(value)
        for _ in 0..<8 {
            if current & 1 == 1 {
                current = 0xEDB88320 ^ (current >> 1)
            } else {
                current >>= 1
            }
        }
        return current
    }

    nonisolated static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = CRC32.table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    nonisolated mutating func append(uint16 value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { buffer in
            append(contentsOf: buffer)
        }
    }

    nonisolated mutating func append(uint32 value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { buffer in
            append(contentsOf: buffer)
        }
    }
}
