//
//  Book.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import Foundation
import UIKit

typealias PlatformImage = UIImage

nonisolated struct LibraryLocation: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var sortOrder: Int
    var isVisible: Bool

    nonisolated init(
        id: String = UUID().uuidString,
        name: String,
        sortOrder: Int,
        isVisible: Bool = true
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.isVisible = isVisible
    }

    nonisolated static func defaultLocations() -> [LibraryLocation] {
        [
            LibraryLocation(id: "location.chengdu", name: "成都", sortOrder: 0),
            LibraryLocation(id: "location.chongqing", name: "重庆", sortOrder: 1)
        ]
    }
}

nonisolated struct LibraryLocationFilter: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let locationID: String?

    nonisolated static let all = LibraryLocationFilter(id: "all", title: "全部", locationID: nil)

    nonisolated init(id: String, title: String, locationID: String?) {
        self.id = id
        self.title = title
        self.locationID = locationID
    }

    nonisolated init(location: LibraryLocation) {
        self.id = location.id
        self.title = location.name
        self.locationID = location.id
    }
}

nonisolated struct BookPayload: Hashable, Codable, Sendable {
    nonisolated static let currentSchemaVersion = 2

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

    var schemaVersion: Int
    var title: String
    var author: String
    var publisher: String
    var year: String
    var locationID: String
    var customFields: [String: String]

    nonisolated init(
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        title = try container.decode(String.self, forKey: .title)
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher) ?? ""
        year = try container.decodeIfPresent(String.self, forKey: .year) ?? ""

        if let locationID = try container.decodeIfPresent(String.self, forKey: .locationID)?.trimmed.nilIfEmpty {
            self.locationID = locationID
        } else {
            let legacyLocation = try container.decodeIfPresent(String.self, forKey: .location)?.trimmed.nilIfEmpty ?? ""
            self.locationID = Self.makeLocationID(fromLegacyName: legacyLocation)
        }

        var resolvedCustomFields = try container.decodeIfPresent([String: String].self, forKey: .customFields) ?? [:]
        if let isbn = try container.decodeIfPresent(String.self, forKey: .isbn)?.trimmed.nilIfEmpty,
           resolvedCustomFields["ISBN"]?.nilIfEmpty == nil {
            resolvedCustomFields["ISBN"] = isbn
        }
        customFields = resolvedCustomFields
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(title, forKey: .title)
        try container.encode(author, forKey: .author)
        try container.encode(publisher, forKey: .publisher)
        try container.encode(year, forKey: .year)
        try container.encode(locationID, forKey: .locationID)
        try container.encode(customFields, forKey: .customFields)
    }

    nonisolated static func makeLocationID(fromLegacyName name: String) -> String {
        switch name {
        case "成都":
            return "location.chengdu"
        case "重庆":
            return "location.chongqing"
        default:
            return "location.legacy.\(name.trimmed.nilIfEmpty ?? "unknown")"
        }
    }
}

nonisolated struct Book: Identifiable, Hashable, Codable, Sendable {
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

    let id: String
    var title: String
    var author: String
    var publisher: String
    var year: String
    var locationID: String
    var customFields: [String: String]
    var coverAssetID: String?
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher) ?? ""
        year = try container.decodeIfPresent(String.self, forKey: .year) ?? ""

        if let locationID = try container.decodeIfPresent(String.self, forKey: .locationID)?.trimmed.nilIfEmpty {
            self.locationID = locationID
        } else {
            let legacyLocation = try container.decodeIfPresent(String.self, forKey: .location)?.trimmed.nilIfEmpty ?? ""
            self.locationID = BookPayload.makeLocationID(fromLegacyName: legacyLocation)
        }

        var resolvedCustomFields = try container.decodeIfPresent([String: String].self, forKey: .customFields) ?? [:]
        if let isbn = try container.decodeIfPresent(String.self, forKey: .isbn)?.trimmed.nilIfEmpty,
           resolvedCustomFields["ISBN"]?.nilIfEmpty == nil {
            resolvedCustomFields["ISBN"] = isbn
        }
        customFields = resolvedCustomFields

        coverAssetID = try container.decodeIfPresent(String.self, forKey: .coverAssetID)
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
        try container.encode(locationID, forKey: .locationID)
        try container.encode(customFields, forKey: .customFields)
        try container.encodeIfPresent(coverAssetID, forKey: .coverAssetID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    nonisolated init(
        id: String,
        payload: BookPayload,
        coverAssetID: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
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

    var payload: BookPayload {
        BookPayload(
            title: title,
            author: author,
            publisher: publisher,
            year: year,
            locationID: locationID,
            customFields: customFields
        )
    }

    var displayAuthor: String {
        author.trimmed.isEmpty ? "未知作者" : author
    }

    var displayPublisherLine: String {
        let publisherText = publisher.trimmed.isEmpty ? "未填写出版社" : publisher

        if year.trimmed.isEmpty {
            return publisherText
        }

        return "\(publisherText) · \(year.trimmed)"
    }

    func locationName(in locationsByID: [String: LibraryLocation]) -> String {
        locationsByID[locationID]?.name ?? "未分配地点"
    }

    func searchCorpus(locationName: String) -> String {
        [
            title,
            author,
            publisher,
            year,
            locationName,
            customFields.values.sorted().joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()
    }
}

nonisolated struct LegacyBook: Hashable, Decodable, Sendable {
    let id: String
    var title: String
    var author: String
    var publisher: String
    var year: String
    var isbn: String
    var locationName: String
    var coverData: Data?
    var createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case author
        case publisher
        case year
        case isbn
        case locationName
        case location
        case coverData
        case createdAt
        case updatedAt
    }

    nonisolated init(
        id: String,
        title: String,
        author: String,
        publisher: String,
        year: String,
        isbn: String,
        locationName: String,
        coverData: Data?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.publisher = publisher
        self.year = year
        self.isbn = isbn
        self.locationName = locationName
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
        isbn = try container.decodeIfPresent(String.self, forKey: .isbn) ?? ""
        let decodedLocationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        let decodedLegacyLocation = try container.decodeIfPresent(String.self, forKey: .location)
        locationName = decodedLocationName ?? decodedLegacyLocation ?? "未分配地点"
        coverData = try container.decodeIfPresent(Data.self, forKey: .coverData)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

nonisolated struct BookDraft: Equatable, Sendable {
    var title: String
    var author: String
    var publisher: String
    var year: String
    var locationID: String
    var customFields: [String: String]
    var coverData: Data?
    var keepsExistingCoverReference: Bool

    init(book: Book? = nil, coverData: Data? = nil, defaultLocationID: String) {
        title = book?.title ?? ""
        author = book?.author ?? ""
        publisher = book?.publisher ?? ""
        year = book?.year ?? ""
        locationID = book?.locationID ?? defaultLocationID
        customFields = book?.customFields ?? [:]
        self.coverData = coverData
        keepsExistingCoverReference = book?.coverAssetID != nil
    }

    init(
        title: String,
        author: String,
        publisher: String,
        year: String,
        locationID: String,
        customFields: [String: String] = [:],
        coverData: Data?,
        keepsExistingCoverReference: Bool = false
    ) {
        self.title = title
        self.author = author
        self.publisher = publisher
        self.year = year
        self.locationID = locationID
        self.customFields = customFields
        self.coverData = coverData
        self.keepsExistingCoverReference = keepsExistingCoverReference
    }

    var normalized: BookDraft {
        let normalizedCustomFields = customFields.reduce(into: [String: String]()) { partialResult, entry in
            let key = entry.key.trimmed
            let value = entry.value.trimmed

            guard !key.isEmpty, !value.isEmpty else {
                return
            }

            partialResult[key] = value
        }

        return BookDraft(
            title: title.trimmed,
            author: author.trimmed,
            publisher: publisher.trimmed,
            year: year.trimmed,
            locationID: locationID.trimmed,
            customFields: normalizedCustomFields,
            coverData: coverData,
            keepsExistingCoverReference: keepsExistingCoverReference && coverData == nil
        )
    }

    var canSave: Bool {
        !title.trimmed.isEmpty && !locationID.trimmed.isEmpty
    }
}

nonisolated enum LibraryFilter {
    static func filteredBooks(
        from books: [Book],
        query: String,
        selectedLocationID: String?,
        locationsByID: [String: LibraryLocation]
    ) -> [Book] {
        let keyword = query.trimmed.lowercased()

        return books
            .filter { book in
                let matchesLocation = selectedLocationID == nil || book.locationID == selectedLocationID

                guard matchesLocation else {
                    return false
                }

                guard !keyword.isEmpty else {
                    return true
                }

                let locationName = book.locationName(in: locationsByID)
                return book.searchCorpus(locationName: locationName).contains(keyword)
            }
            .sorted { left, right in
                if left.updatedAt != right.updatedAt {
                    return left.updatedAt > right.updatedAt
                }

                return left.createdAt > right.createdAt
            }
    }
}

extension String {
    nonisolated var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var nilIfEmpty: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }
}

extension BookDraft {
    var coverImage: PlatformImage? {
        guard let coverData else {
            return nil
        }

        return PlatformImage(data: coverData)
    }
}
