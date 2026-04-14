//
//  ISBNLookupService.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import Foundation

enum ISBNLookupService {
    struct BookMetadata: Equatable {
        let title: String
        let author: String
        let publisher: String
        let year: String
    }

    enum LookupError: LocalizedError {
        case invalidISBN
        case notFound
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidISBN:
                return "请先输入有效的 ISBN。"
            case .notFound:
                return "没有查到这本书，请手动补录。"
            case .invalidResponse:
                return "书籍接口返回了无法识别的数据。"
            }
        }
    }

    static func normalizeISBN(_ candidate: String) -> String {
        candidate.normalizedISBN
    }

    static func extractISBN(from scannedText: String) -> String {
        let directMatch = scannedText.normalizedISBN

        if directMatch.count == 10 || directMatch.count == 13 {
            return directMatch
        }

        guard let embeddedMatch = scannedText.range(of: "(?:97[89][0-9]{10}|[0-9]{9}[0-9Xx])", options: .regularExpression) else {
            return ""
        }

        return String(scannedText[embeddedMatch]).normalizedISBN
    }

    static func fetchMetadata(for isbn: String) async throws -> BookMetadata {
        let cleanISBN = normalizeISBN(isbn)

        guard cleanISBN.count == 10 || cleanISBN.count == 13 else {
            throw LookupError.invalidISBN
        }

        if let googleResult = try await fetchGoogleBooks(isbn: cleanISBN) {
            return googleResult
        }

        if let openLibraryResult = try await fetchOpenLibrary(isbn: cleanISBN) {
            return openLibraryResult
        }

        throw LookupError.notFound
    }

    private static func fetchGoogleBooks(isbn: String) async throws -> BookMetadata? {
        guard let url = URL(string: "https://www.googleapis.com/books/v1/volumes?q=isbn:\(isbn)") else {
            throw LookupError.invalidResponse
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(GoogleBooksResponse.self, from: data)

        guard let volumeInfo = response.items?.first?.volumeInfo else {
            return nil
        }

        return BookMetadata(
            title: volumeInfo.title ?? "",
            author: volumeInfo.authors?.joined(separator: ", ") ?? "",
            publisher: volumeInfo.publisher ?? "",
            year: volumeInfo.publishedDate ?? ""
        )
    }

    private static func fetchOpenLibrary(isbn: String) async throws -> BookMetadata? {
        guard let url = URL(string: "https://openlibrary.org/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data") else {
            throw LookupError.invalidResponse
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode([String: OpenLibraryBook].self, from: data)

        guard let book = response["ISBN:\(isbn)"] else {
            return nil
        }

        return BookMetadata(
            title: book.title ?? "",
            author: book.authors?.compactMap(\.name).joined(separator: ", ") ?? "",
            publisher: book.publishers?.compactMap(\.name).joined(separator: ", ") ?? "",
            year: book.publishDate ?? ""
        )
    }
}

private struct GoogleBooksResponse: Decodable {
    let items: [GoogleBookItem]?
}

private struct GoogleBookItem: Decodable {
    let volumeInfo: GoogleVolumeInfo?
}

private struct GoogleVolumeInfo: Decodable {
    let title: String?
    let authors: [String]?
    let publisher: String?
    let publishedDate: String?
}

private struct OpenLibraryBook: Decodable {
    let title: String?
    let publishDate: String?
    let authors: [OpenLibraryNamedValue]?
    let publishers: [OpenLibraryNamedValue]?

    enum CodingKeys: String, CodingKey {
        case title
        case publishDate = "publish_date"
        case authors
        case publishers
    }
}

private struct OpenLibraryNamedValue: Decodable {
    let name: String?
}
