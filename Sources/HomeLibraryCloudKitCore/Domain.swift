import CloudKit
import Foundation

public enum HomeLibraryCloudKitConstants {
    public static let defaultContainerIdentifier = "iCloud.yu.homeLibrary"
    public static let defaultBundleIdentifier = "yu.homeLibrary.cloudkit-cli"
    public static let defaultTeamIdentifier = "8VG8636JLY"
    public static let workflowDirectory = ".derived/AIWorkflow"
}

public enum BookInfoFieldKey {
    public static let isbn = "ISBN"
    public static let translator = "译者"
}

public struct LibraryLocation: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var name: String
    public var sortOrder: Int
    public var isVisible: Bool

    public init(id: String = UUID().uuidString, name: String, sortOrder: Int, isVisible: Bool = true) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.isVisible = isVisible
    }

    public static func defaultLocations() -> [LibraryLocation] {
        [
            LibraryLocation(id: "location.chengdu", name: "成都", sortOrder: 0),
            LibraryLocation(id: "location.chongqing", name: "重庆", sortOrder: 1)
        ]
    }
}

public struct BookPayload: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 2

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case title
        case author
        case publisher
        case year
        case locationID
        case location
        case customFields
        case isbn
    }

    public var schemaVersion: Int
    public var title: String
    public var author: String
    public var publisher: String
    public var year: String
    public var locationID: String
    public var customFields: [String: String]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        title: String,
        author: String = "",
        publisher: String = "",
        year: String = "",
        locationID: String,
        customFields: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.title = title
        self.author = author
        self.publisher = publisher
        self.year = year
        self.locationID = locationID
        self.customFields = customFields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        title = try container.decode(String.self, forKey: .title)
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher) ?? ""
        year = try container.decodeIfPresent(String.self, forKey: .year) ?? ""

        if let locationID = try container.decodeIfPresent(String.self, forKey: .locationID)?.nilIfEmpty {
            self.locationID = locationID
        } else {
            let legacyLocation = try container.decodeIfPresent(String.self, forKey: .location)?.nilIfEmpty ?? ""
            self.locationID = Self.makeLocationID(fromLegacyName: legacyLocation)
        }

        var resolvedCustomFields = try container.decodeIfPresent([String: String].self, forKey: .customFields) ?? [:]
        if let isbn = try container.decodeIfPresent(String.self, forKey: .isbn)?.nilIfEmpty,
           resolvedCustomFields[BookInfoFieldKey.isbn]?.nilIfEmpty == nil {
            resolvedCustomFields[BookInfoFieldKey.isbn] = isbn
        }
        customFields = resolvedCustomFields
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(title, forKey: .title)
        try container.encode(author, forKey: .author)
        try container.encode(publisher, forKey: .publisher)
        try container.encode(year, forKey: .year)
        try container.encode(locationID, forKey: .locationID)
        try container.encode(customFields, forKey: .customFields)
    }

    public static func makeLocationID(fromLegacyName name: String) -> String {
        switch name.trimmed.lowercased() {
        case "成都", "chengdu":
            return "location.chengdu"
        case "重庆", "chongqing":
            return "location.chongqing"
        default:
            return "location.legacy.\(name.trimmed.nilIfEmpty ?? "unknown")"
        }
    }
}

public struct Book: Identifiable, Hashable, Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case author
        case publisher
        case year
        case locationID
        case location
        case customFields
        case coverAssetID
        case createdAt
        case updatedAt
        case isbn
    }

    public let id: String
    public var title: String
    public var author: String
    public var publisher: String
    public var year: String
    public var locationID: String
    public var customFields: [String: String]
    public var coverAssetID: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        title: String,
        author: String = "",
        publisher: String = "",
        year: String = "",
        locationID: String,
        customFields: [String: String] = [:],
        coverAssetID: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.publisher = publisher
        self.year = year
        self.locationID = locationID
        self.customFields = customFields
        self.coverAssetID = coverAssetID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher) ?? ""
        year = try container.decodeIfPresent(String.self, forKey: .year) ?? ""

        if let locationID = try container.decodeIfPresent(String.self, forKey: .locationID)?.nilIfEmpty {
            self.locationID = locationID
        } else {
            let legacyLocation = try container.decodeIfPresent(String.self, forKey: .location)?.nilIfEmpty ?? ""
            self.locationID = BookPayload.makeLocationID(fromLegacyName: legacyLocation)
        }

        var resolvedCustomFields = try container.decodeIfPresent([String: String].self, forKey: .customFields) ?? [:]
        if let isbn = try container.decodeIfPresent(String.self, forKey: .isbn)?.nilIfEmpty,
           resolvedCustomFields[BookInfoFieldKey.isbn]?.nilIfEmpty == nil {
            resolvedCustomFields[BookInfoFieldKey.isbn] = isbn
        }
        customFields = resolvedCustomFields

        coverAssetID = try container.decodeIfPresent(String.self, forKey: .coverAssetID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    public init(id: String, payload: BookPayload, coverAssetID: String? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
        self.init(
            id: id,
            title: payload.title,
            author: payload.author,
            publisher: payload.publisher,
            year: payload.year,
            locationID: payload.locationID,
            customFields: payload.customFields,
            coverAssetID: coverAssetID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(author, forKey: .author)
        try container.encode(publisher, forKey: .publisher)
        try container.encode(year, forKey: .year)
        try container.encode(locationID, forKey: .locationID)
        try container.encode(customFields, forKey: .customFields)
        try container.encodeIfPresent(coverAssetID, forKey: .coverAssetID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    public var payload: BookPayload {
        BookPayload(
            title: title,
            author: author,
            publisher: publisher,
            year: year,
            locationID: locationID,
            customFields: customFields
        )
    }

    public var isbn: String {
        customFields[BookInfoFieldKey.isbn]?.trimmed ?? ""
    }

    public var translator: String {
        customFields[BookInfoFieldKey.translator]?.trimmed ?? ""
    }
}

public enum CloudDatabaseScope: String, Codable, Sendable {
    case `private`
    case shared

    public var ckScope: CKDatabase.Scope {
        switch self {
        case .private:
            return .private
        case .shared:
            return .shared
        }
    }
}

public enum RepositoryRole: String, Codable, Sendable {
    case owner
    case member
}

public enum RepositoryShareStatus: String, Codable, Sendable {
    case notShared
    case shared
}

public struct LibraryRepositoryReference: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var name: String
    public var role: RepositoryRole
    public var databaseScope: CloudDatabaseScope
    public var zoneName: String
    public var zoneOwnerName: String
    public var shareRecordName: String?
    public var shareStatus: RepositoryShareStatus

    public init(
        id: String,
        name: String,
        role: RepositoryRole,
        databaseScope: CloudDatabaseScope,
        zoneName: String,
        zoneOwnerName: String,
        shareRecordName: String? = nil,
        shareStatus: RepositoryShareStatus = .notShared
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.databaseScope = databaseScope
        self.zoneName = zoneName
        self.zoneOwnerName = zoneOwnerName
        self.shareRecordName = shareRecordName
        self.shareStatus = shareStatus
    }

    public var isOwner: Bool {
        role == .owner
    }

    public var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwnerName)
    }

    public var canWrite: Bool {
        role == .owner || databaseScope == .shared
    }
}

public struct RemoteBookSnapshot: Codable, Sendable {
    public var book: Book
    public var coverData: Data?
    public var recordChangeTag: String?

    public init(book: Book, coverData: Data?, recordChangeTag: String? = nil) {
        self.book = book
        self.coverData = coverData
        self.recordChangeTag = recordChangeTag
    }
}

public struct RemoteRepositorySnapshot: Sendable {
    public var repository: LibraryRepositoryReference
    public var locations: [LibraryLocation]
    public var books: [RemoteBookSnapshot]
    public var changeTokenData: Data?

    public init(
        repository: LibraryRepositoryReference,
        locations: [LibraryLocation],
        books: [RemoteBookSnapshot],
        changeTokenData: Data? = nil
    ) {
        self.repository = repository
        self.locations = locations
        self.books = books
        self.changeTokenData = changeTokenData
    }

    public var booksByID: [String: RemoteBookSnapshot] {
        Dictionary(uniqueKeysWithValues: books.map { ($0.book.id, $0) })
    }

    public var locationsByID: [String: LibraryLocation] {
        Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
    }
}

public struct LibraryImportPackage: Codable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var source: String?
    public var exportedAt: Date?
    public var locations: [LibraryImportLocation]
    public var books: [LibraryImportBook]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        source: String? = nil,
        exportedAt: Date? = nil,
        locations: [LibraryImportLocation] = [],
        books: [LibraryImportBook]
    ) {
        self.schemaVersion = schemaVersion
        self.source = source
        self.exportedAt = exportedAt
        self.locations = locations
        self.books = books
    }
}

public struct LibraryImportLocation: Codable, Sendable {
    public var id: String
    public var name: String
    public var sortOrder: Int
    public var isVisible: Bool

    public init(location: LibraryLocation) {
        id = location.id
        name = location.name
        sortOrder = location.sortOrder
        isVisible = location.isVisible
    }
}

public struct LibraryImportBook: Codable, Sendable {
    public var id: String
    public var title: String
    public var author: String
    public var publisher: String
    public var year: String
    public var locationID: String?
    public var locationName: String?
    public var customFields: [String: String]
    public var isbn: String?
    public var coverData: Data?
    public var createdAt: Date
    public var updatedAt: Date

    public init(book: Book, coverData: Data?, locationsByID: [String: LibraryLocation]) {
        id = book.id
        title = book.title
        author = book.author
        publisher = book.publisher
        year = book.year
        locationID = book.locationID
        locationName = locationsByID[book.locationID]?.name
        customFields = book.customFields
        isbn = book.isbn.nilIfEmpty
        self.coverData = coverData
        createdAt = book.createdAt
        updatedAt = book.updatedAt
    }
}

public struct RepositorySummary: Codable, Sendable {
    public var id: String
    public var name: String
    public var role: RepositoryRole
    public var databaseScope: CloudDatabaseScope
    public var zoneID: String
    public var canWrite: Bool
    public var bookCount: Int
    public var locationCount: Int

    public init(
        id: String,
        name: String,
        role: RepositoryRole,
        databaseScope: CloudDatabaseScope,
        zoneID: String,
        canWrite: Bool,
        bookCount: Int,
        locationCount: Int
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.databaseScope = databaseScope
        self.zoneID = zoneID
        self.canWrite = canWrite
        self.bookCount = bookCount
        self.locationCount = locationCount
    }
}
