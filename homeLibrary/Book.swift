//
//  Book.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import Foundation

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

enum BookLocation: String, CaseIterable, Codable, Identifiable {
    case chengdu = "成都"
    case chongqing = "重庆"

    var id: String { rawValue }
}

enum LibraryFilterTab: String, CaseIterable, Identifiable {
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

struct Book: Identifiable, Hashable, Codable {
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

    init(
        id: String,
        title: String,
        author: String = "",
        publisher: String = "",
        year: String = "",
        isbn: String = "",
        location: BookLocation,
        coverData: Data? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.publisher = publisher
        self.year = year
        self.isbn = isbn
        self.location = location
        self.coverData = coverData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
}

struct BookDraft: Equatable {
    var title: String
    var author: String
    var publisher: String
    var year: String
    var isbn: String
    var location: BookLocation
    var coverData: Data?

    init(book: Book? = nil, defaultLocation: BookLocation = .chengdu) {
        title = book?.title ?? ""
        author = book?.author ?? ""
        publisher = book?.publisher ?? ""
        year = book?.year ?? ""
        isbn = book?.isbn ?? ""
        location = book?.location ?? defaultLocation
        coverData = book?.coverData
    }

    var normalized: BookDraft {
        BookDraft(
            title: title.trimmed,
            author: author.trimmed,
            publisher: publisher.trimmed,
            year: year.trimmed,
            isbn: isbn.normalizedISBN,
            location: location,
            coverData: coverData
        )
    }

    var canSave: Bool {
        !title.trimmed.isEmpty
    }
}

enum LibraryFilter {
    static func filteredBooks(from books: [Book], query: String, tab: LibraryFilterTab) -> [Book] {
        let keyword = query.trimmed.lowercased()
        let normalizedISBNKeyword = query.normalizedISBN

        return books
            .filter { book in
                let matchesLocation = tab.location == nil || book.location == tab.location

                guard matchesLocation else {
                    return false
                }

                if keyword.isEmpty {
                    return true
                }

                let matchesSearch =
                    book.title.lowercased().contains(keyword) ||
                    book.author.lowercased().contains(keyword) ||
                    (!normalizedISBNKeyword.isEmpty && book.isbn.normalizedISBN.contains(normalizedISBNKeyword))

                return matchesSearch
            }
            .sorted { left, right in
                if left.updatedAt != right.updatedAt {
                    return left.updatedAt > right.updatedAt
                }

                return left.createdAt > right.createdAt
            }
    }
}

extension BookDraft {
    init(
        title: String,
        author: String,
        publisher: String,
        year: String,
        isbn: String,
        location: BookLocation,
        coverData: Data?
    ) {
        self.title = title
        self.author = author
        self.publisher = publisher
        self.year = year
        self.isbn = isbn
        self.location = location
        self.coverData = coverData
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedISBN: String {
        replacingOccurrences(of: "[^0-9Xx]", with: "", options: .regularExpression)
            .uppercased()
    }
}

#if canImport(UIKit) || canImport(AppKit)
extension Book {
    var coverImage: PlatformImage? {
        guard let coverData else {
            return nil
        }

        return PlatformImage(data: coverData)
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
#endif
