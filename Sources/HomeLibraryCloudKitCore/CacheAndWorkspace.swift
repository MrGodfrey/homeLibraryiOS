import Foundation

public final class LibraryCacheStore {
    private let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public func replaceAllContent(snapshot: RemoteRepositorySnapshot) throws {
        let repositoryRoot = rootURL.appendingPathComponent(snapshot.repository.id, isDirectory: true)
        let booksDirectory = repositoryRoot.appendingPathComponent("books", isDirectory: true)
        let coversDirectory = repositoryRoot.appendingPathComponent("covers", isDirectory: true)
        try? FileManager.default.removeItem(at: repositoryRoot)
        try FileSystem.ensureDirectory(booksDirectory)
        try FileSystem.ensureDirectory(coversDirectory)
        try FileSystem.writeJSON(snapshot.locations, to: repositoryRoot.appendingPathComponent("locations.json"))

        for remoteBook in snapshot.books {
            try FileSystem.writeJSON(remoteBook.book, to: booksDirectory.appendingPathComponent("\(remoteBook.book.id).json"))
            if let coverData = remoteBook.coverData,
               let coverAssetID = remoteBook.book.coverAssetID {
                try coverData.write(to: coversDirectory.appendingPathComponent("\(coverAssetID).bin"), options: [.atomic])
            }
        }
    }

    public func makeImportPackage(snapshot: RemoteRepositorySnapshot) -> LibraryImportPackage {
        let locationsByID = snapshot.locationsByID
        return LibraryImportPackage(
            source: snapshot.repository.name,
            exportedAt: .now,
            locations: snapshot.locations.map(LibraryImportLocation.init(location:)),
            books: snapshot.books.map {
                LibraryImportBook(book: $0.book, coverData: $0.coverData, locationsByID: locationsByID)
            }
        )
    }
}

public struct AIWorkspaceManifest: Codable, Sendable {
    public var schemaVersion: Int
    public var exportedAt: Date
    public var repository: LibraryRepositoryReference
    public var bookCount: Int
    public var locationCount: Int
    public var files: [String]
}

public struct AIWorkspaceBook: Codable, Sendable {
    public var id: String
    public var title: String
    public var author: String
    public var translator: String
    public var publisher: String
    public var year: String
    public var isbn: String
    public var locationID: String
    public var coverAssetID: String?
    public var hasCover: Bool
    public var coverByteSize: Int?
    public var updatedAt: Date
    public var recordChangeTag: String?
}

public struct AIWorkspaceSnapshot: Codable, Sendable {
    public var schemaVersion: Int
    public var snapshotID: String
    public var createdAt: Date
    public var repository: LibraryRepositoryReference
    public var locations: [LibraryLocation]
    public var books: [AIWorkspaceBook]
}

public struct MissingMetadataReport: Codable, Sendable {
    public var missingISBN: [String]
    public var missingPublisher: [String]
    public var missingYear: [String]
    public var missingCover: [String]
}

public struct DuplicateCandidate: Codable, Sendable {
    public var kind: String
    public var key: String
    public var bookIDs: [String]
}

public struct CoverStatusEntry: Codable, Sendable {
    public var bookID: String
    public var coverAssetID: String?
    public var hasCover: Bool
    public var byteSize: Int?
}

public struct WorkspaceExportResult: Codable, Sendable {
    public var ok: Bool
    public var path: String
    public var snapshotID: String
    public var bookCount: Int
    public var locationCount: Int
}

public enum AIWorkspaceExporter {
    public static func export(snapshot: RemoteRepositorySnapshot, to outputURL: URL) throws -> WorkspaceExportResult {
        let snapshotID = "snapshot.\(HomeLibraryHash.sha256Hex(try HomeLibraryJSONCodec.makeEncoder(prettyPrinted: false).encode(snapshot.repository)).prefix(12)).\(Int(Date().timeIntervalSince1970))"
        let directoryURL: URL
        let finalOutputURL: URL
        let shouldZip = outputURL.pathExtension.lowercased() == "zip"

        if shouldZip {
            directoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("AIWorkspace-\(UUID().uuidString)", isDirectory: true)
            finalOutputURL = outputURL
        } else {
            directoryURL = outputURL
            finalOutputURL = outputURL
        }

        try FileSystem.ensureDirectory(directoryURL)
        let files = [
            "manifest.json",
            "LibrarySnapshot.json",
            "MissingMetadataReport.json",
            "DuplicateCandidates.json",
            "CoverStatus.json",
            "Locations.json",
            "PatchSchema.json",
            "README.md",
            "LibraryImport.json"
        ]

        let workspaceBooks = snapshot.books.map { remoteBook in
            AIWorkspaceBook(
                id: remoteBook.book.id,
                title: remoteBook.book.title,
                author: remoteBook.book.author,
                translator: remoteBook.book.translator,
                publisher: remoteBook.book.publisher,
                year: remoteBook.book.year,
                isbn: remoteBook.book.isbn,
                locationID: remoteBook.book.locationID,
                coverAssetID: remoteBook.book.coverAssetID,
                hasCover: remoteBook.book.coverAssetID != nil,
                coverByteSize: remoteBook.coverData?.count,
                updatedAt: remoteBook.book.updatedAt,
                recordChangeTag: remoteBook.recordChangeTag
            )
        }

        let aiSnapshot = AIWorkspaceSnapshot(
            schemaVersion: 1,
            snapshotID: snapshotID,
            createdAt: .now,
            repository: snapshot.repository,
            locations: snapshot.locations,
            books: workspaceBooks
        )
        let manifest = AIWorkspaceManifest(
            schemaVersion: 1,
            exportedAt: .now,
            repository: snapshot.repository,
            bookCount: snapshot.books.count,
            locationCount: snapshot.locations.count,
            files: files
        )

        try FileSystem.writeJSON(manifest, to: directoryURL.appendingPathComponent("manifest.json"))
        try FileSystem.writeJSON(aiSnapshot, to: directoryURL.appendingPathComponent("LibrarySnapshot.json"))
        try FileSystem.writeJSON(makeMissingMetadataReport(books: workspaceBooks), to: directoryURL.appendingPathComponent("MissingMetadataReport.json"))
        try FileSystem.writeJSON(makeDuplicateCandidates(books: workspaceBooks), to: directoryURL.appendingPathComponent("DuplicateCandidates.json"))
        try FileSystem.writeJSON(makeCoverStatus(books: workspaceBooks), to: directoryURL.appendingPathComponent("CoverStatus.json"))
        try FileSystem.writeJSON(snapshot.locations, to: directoryURL.appendingPathComponent("Locations.json"))
        try FileSystem.writeJSON(makePatchSchemaSummary(), to: directoryURL.appendingPathComponent("PatchSchema.json"))
        try readmeText().write(to: directoryURL.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let cache = LibraryCacheStore(rootURL: directoryURL)
        try FileSystem.writeJSON(cache.makeImportPackage(snapshot: snapshot), to: directoryURL.appendingPathComponent("LibraryImport.json"))

        if shouldZip {
            try FileSystem.ensureDirectory(finalOutputURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: finalOutputURL)
            try run("/usr/bin/ditto", arguments: ["-c", "-k", "--sequesterRsrc", directoryURL.path, finalOutputURL.path])
            try? FileManager.default.removeItem(at: directoryURL)
        }

        return WorkspaceExportResult(
            ok: true,
            path: finalOutputURL.path,
            snapshotID: snapshotID,
            bookCount: snapshot.books.count,
            locationCount: snapshot.locations.count
        )
    }

    private static func makeMissingMetadataReport(books: [AIWorkspaceBook]) -> MissingMetadataReport {
        MissingMetadataReport(
            missingISBN: books.filter { $0.isbn.trimmed.isEmpty }.map(\.id),
            missingPublisher: books.filter { $0.publisher.trimmed.isEmpty }.map(\.id),
            missingYear: books.filter { $0.year.trimmed.isEmpty }.map(\.id),
            missingCover: books.filter { !$0.hasCover }.map(\.id)
        )
    }

    private static func makeDuplicateCandidates(books: [AIWorkspaceBook]) -> [DuplicateCandidate] {
        let isbnGroups = Dictionary(grouping: books.filter { !$0.isbn.trimmed.isEmpty }, by: { PatchRules.normalizeISBN($0.isbn) })
        let titleGroups = Dictionary(grouping: books, by: { PatchRules.normalizedTitle($0.title) })
        var candidates: [DuplicateCandidate] = []
        candidates += isbnGroups
            .filter { !$0.key.isEmpty && $0.value.count > 1 }
            .map { DuplicateCandidate(kind: "isbn", key: $0.key, bookIDs: $0.value.map(\.id)) }
        candidates += titleGroups
            .filter { !$0.key.isEmpty && $0.value.count > 1 }
            .map { DuplicateCandidate(kind: "similarTitle", key: $0.key, bookIDs: $0.value.map(\.id)) }
        return candidates
    }

    private static func makeCoverStatus(books: [AIWorkspaceBook]) -> [CoverStatusEntry] {
        books.map {
            CoverStatusEntry(bookID: $0.id, coverAssetID: $0.coverAssetID, hasCover: $0.hasCover, byteSize: $0.coverByteSize)
        }
    }

    private static func makePatchSchemaSummary() -> [String: AnyCodable] {
        [
            "schemaVersion": AnyCodable(1),
            "operations": AnyCodable(["createBook", "updateBook", "updateBookCover", "removeBookCover", "deleteBook"]),
            "fieldModes": AnyCodable(["fillIfEmpty", "replaceIfCurrentValue"]),
            "coverRule": AnyCodable("coverAssetID is cover-<sha256> of LibraryCoverCompressor output; max edge 720px, target 220KB")
        ]
    }

    private static func readmeText() -> String {
        """
        # AI Workspace

        This workspace is generated by `home-library-cloudkit export-ai-workspace`.

        Use `LibrarySnapshot.json`, `MissingMetadataReport.json`, `DuplicateCandidates.json`, and `CoverStatus.json` to prepare a `.homelibpatch`.
        Do not edit CloudKit cache files directly. Validate every patch with `home-library-cloudkit validate-patch` before review or apply.
        """
    }

    private static func run(_ launchPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CLIError("\(launchPath) failed with exit code \(process.terminationStatus)")
        }
    }
}

public struct AnyCodable: Codable, Sendable {
    private var value: Sendable

    public init(_ value: Sendable) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self.value = value
        } else if let value = try? container.decode(Int.self) {
            self.value = value
        } else if let value = try? container.decode([String].self) {
            self.value = value
        } else {
            self.value = ""
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let value as String:
            try container.encode(value)
        case let value as Int:
            try container.encode(value)
        case let value as [String]:
            try container.encode(value)
        default:
            try container.encode(String(describing: value))
        }
    }
}
