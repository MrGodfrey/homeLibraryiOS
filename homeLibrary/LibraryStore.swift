//
//  LibraryStore.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import Combine
import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published var searchText = ""
    @Published var activeTab: LibraryFilterTab = .all
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var alertMessage: String?

    private let persistenceURL: URL
    private var hasLoaded = false

    init(persistenceURL: URL? = nil) {
        self.persistenceURL = persistenceURL ?? Self.defaultPersistenceURL()
    }

    var visibleBooks: [Book] {
        LibraryFilter.filteredBooks(from: books, query: searchText, tab: activeTab)
    }

    func loadBooksIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        await loadBooks(force: true)
    }

    func loadBooks(force: Bool = false) async {
        guard force || !isLoading else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            books = try readBooks()
            hasLoaded = true
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
        }
    }

    @discardableResult
    func saveBook(draft: BookDraft, editing existingBook: Book?) async -> Bool {
        let normalizedDraft = draft.normalized

        guard normalizedDraft.canSave else {
            alertMessage = "书名不能为空。"
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let now = Date()
            let book: Book

            if let existingBook {
                book = Book(
                    id: existingBook.id,
                    title: normalizedDraft.title,
                    author: normalizedDraft.author,
                    publisher: normalizedDraft.publisher,
                    year: normalizedDraft.year,
                    isbn: normalizedDraft.isbn,
                    location: normalizedDraft.location,
                    coverData: normalizedDraft.coverData,
                    createdAt: existingBook.createdAt,
                    updatedAt: now
                )
            } else {
                book = Book(
                    id: UUID().uuidString,
                    title: normalizedDraft.title,
                    author: normalizedDraft.author,
                    publisher: normalizedDraft.publisher,
                    year: normalizedDraft.year,
                    isbn: normalizedDraft.isbn,
                    location: normalizedDraft.location,
                    coverData: normalizedDraft.coverData,
                    createdAt: now,
                    updatedAt: now
                )
            }

            let nextBooks = upserting(book, into: books)
            try writeBooks(nextBooks)
            books = nextBooks
            return true
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
            return false
        }
    }

    @discardableResult
    func deleteBook(_ book: Book) async -> Bool {
        isSaving = true
        defer { isSaving = false }

        do {
            let nextBooks = books.filter { $0.id != book.id }
            try writeBooks(nextBooks)
            books = nextBooks
            return true
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
            return false
        }
    }

    static func userFacingMessage(for error: Error) -> String {
        if let localizedDescription = error.localizedDescription.trimmed.nilIfEmpty {
            return localizedDescription
        }

        return "发生了未预期的错误。"
    }

    private func upserting(_ book: Book, into currentBooks: [Book]) -> [Book] {
        var nextBooks = currentBooks

        if let index = nextBooks.firstIndex(where: { $0.id == book.id }) {
            nextBooks[index] = book
        } else {
            nextBooks.append(book)
        }

        nextBooks.sort { left, right in
            if left.updatedAt != right.updatedAt {
                return left.updatedAt > right.updatedAt
            }

            return left.createdAt > right.createdAt
        }

        return nextBooks
    }

    private func readBooks() throws -> [Book] {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: persistenceURL.path) else {
            return []
        }

        let data = try Data(contentsOf: persistenceURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let books = try decoder.decode([Book].self, from: data)

        return books.sorted { left, right in
            if left.updatedAt != right.updatedAt {
                return left.updatedAt > right.updatedAt
            }

            return left.createdAt > right.createdAt
        }
    }

    private func writeBooks(_ books: [Book]) throws {
        try Self.ensureParentDirectoryExists(for: persistenceURL)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let sortedBooks = books.sorted { left, right in
            if left.updatedAt != right.updatedAt {
                return left.updatedAt > right.updatedAt
            }

            return left.createdAt > right.createdAt
        }

        let data = try encoder.encode(sortedBooks)
        try data.write(to: persistenceURL, options: [.atomic])
    }

    private static func defaultPersistenceURL() -> URL {
        let baseDirectory =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ??
            FileManager.default.homeDirectoryForCurrentUser

        let appDirectory = baseDirectory.appendingPathComponent("homeLibrary", isDirectory: true)
        return appDirectory.appendingPathComponent("books.json")
    }

    private static func ensureParentDirectoryExists(for url: URL) throws {
        let directoryURL = url.deletingLastPathComponent()

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
