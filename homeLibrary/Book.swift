//
//  Book.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import Foundation
import UIKit

typealias PlatformImage = UIImage

nonisolated enum BookLocation: String, CaseIterable, Codable, Identifiable, Sendable {
    case chengdu = "成都"
    case chongqing = "重庆"

    var id: String { rawValue }
}

nonisolated enum LibraryFilterTab: String, CaseIterable, Identifiable, Sendable {
    case all = "全部"
    case chengdu = "成都"
    case chongqing = "重庆"

    var id: String { rawValue }

    var location: BookLocation? {
        switch self {
        case .all:
            return nil
        case .chengdu:
            return .chengdu
        case .chongqing:
            return .chongqing
        }
    }
}

nonisolated struct BookPayload: Hashable, Codable, Sendable {
    nonisolated static let currentSchemaVersion = 1

    var schemaVersion: Int
    var title: String
    var author: String
    var publisher: String
    var year: String
    var location: BookLocation
    var customFields: [String: String]

    nonisolated init(
        schemaVersion: Int = currentSchemaVersion,
        title: String,
        author: String = "",
        publisher: String = "",
        year: String = "",
        location: BookLocation,
        customFields: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.title = title
        self.author = author
        self.publisher = publisher
        self.year = year
        self.location = location
        self.customFields = customFields
    }
}

nonisolated struct Book: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var title: String
    var author: String
    var publisher: String
    var year: String
    var location: BookLocation
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
        location: BookLocation,
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
        self.location = location
        self.customFields = customFields
        self.coverAssetID = coverAssetID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
            location: payload.location,
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
            location: location,
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

    var searchCorpus: String {
        [
            title,
            author,
            publisher,
            year,
            location.rawValue,
            customFields.values.sorted().joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()
    }
}

nonisolated struct LegacyBook: Hashable, Codable, Sendable {
    let id: String
    var title: String
    var author: String
    var publisher: String
    var year: String
    var isbn: String
    var location: BookLocation
    var coverData: Data?
    var createdAt: Date
    var updatedAt: Date
}

nonisolated struct BookDraft: Equatable, Sendable {
    var title: String
    var author: String
    var publisher: String
    var year: String
    var location: BookLocation
    var customFields: [String: String]
    var coverData: Data?
    var keepsExistingCoverReference: Bool

    init(book: Book? = nil, coverData: Data? = nil, defaultLocation: BookLocation = .chengdu) {
        title = book?.title ?? ""
        author = book?.author ?? ""
        publisher = book?.publisher ?? ""
        year = book?.year ?? ""
        location = book?.location ?? defaultLocation
        customFields = book?.customFields ?? [:]
        self.coverData = coverData
        keepsExistingCoverReference = book?.coverAssetID != nil
    }

    init(
        title: String,
        author: String,
        publisher: String,
        year: String,
        location: BookLocation,
        customFields: [String: String] = [:],
        coverData: Data?,
        keepsExistingCoverReference: Bool = false
    ) {
        self.title = title
        self.author = author
        self.publisher = publisher
        self.year = year
        self.location = location
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
            location: location,
            customFields: normalizedCustomFields,
            coverData: coverData,
            keepsExistingCoverReference: keepsExistingCoverReference && coverData == nil
        )
    }

    var canSave: Bool {
        !title.trimmed.isEmpty
    }
}

nonisolated enum LibraryFilter {
    static func filteredBooks(from books: [Book], query: String, tab: LibraryFilterTab) -> [Book] {
        let keyword = query.trimmed.lowercased()

        return books
            .filter { book in
                let matchesLocation = tab.location == nil || book.location == tab.location

                guard matchesLocation else {
                    return false
                }

                guard !keyword.isEmpty else {
                    return true
                }

                return book.searchCorpus.contains(keyword)
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
