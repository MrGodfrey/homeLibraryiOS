//
//  ContentView.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = LibraryStore()
    @State private var editorTarget: EditorTarget?
    @State private var pendingDeleteBook: Book?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("家藏万卷")
                .searchable(text: $store.searchText, prompt: "搜索书名、作者或 ISBN")
                .toolbar {
                    ToolbarItemGroup(placement: .automatic) {
                        Button {
                            Task {
                                await store.loadBooks(force: true)
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("刷新")

                        Button {
                            editorTarget = .create(defaultLocation: store.activeTab.location ?? .chengdu)
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("添加书籍")
                    }
                }
        }
        .task {
            await store.loadBooksIfNeeded()
        }
        .sheet(item: $editorTarget) { target in
            BookEditorView(
                editingBook: target.book,
                defaultLocation: target.defaultLocation
            ) { draft, book in
                await store.saveBook(draft: draft, editing: book)
            }
        }
        .confirmationDialog("确认删除这本书？", isPresented: deleteDialogBinding, titleVisibility: .visible) {
            if let pendingDeleteBook {
                Button("删除", role: .destructive) {
                    Task {
                        let didDelete = await store.deleteBook(pendingDeleteBook)

                        if didDelete {
                            self.pendingDeleteBook = nil
                        }
                    }
                }
            }

            Button("取消", role: .cancel) {
                pendingDeleteBook = nil
            }
        } message: {
            Text("删除后不会自动恢复。")
        }
        .alert("提示", isPresented: alertBinding) {
            Button("知道了", role: .cancel) {
                store.alertMessage = nil
            }
        } message: {
            Text(store.alertMessage ?? "")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("所在地", selection: $store.activeTab) {
                ForEach(LibraryFilterTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("共 \(store.visibleBooks.count) 本可见藏书")
                    .font(.headline)

                Spacer()

                if store.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if store.visibleBooks.isEmpty && !store.isLoading {
                Spacer()

                ContentUnavailableView(
                    "当前没有匹配的书籍",
                    systemImage: "books.vertical",
                    description: Text("试试切换地点、搜索关键词，或者直接添加一本新书。")
                )

                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.visibleBooks) { book in
                            BookRowCard(book: book) {
                                editorTarget = .edit(book)
                            } onDelete: {
                                pendingDeleteBook = book
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
                .refreshable {
                    await store.loadBooks(force: true)
                }
            }
        }
        .padding()
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteBook != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteBook = nil
                }
            }
        )
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { store.alertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    store.alertMessage = nil
                }
            }
        )
    }
}

private struct BookRowCard: View {
    let book: Book
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BookThumbnail(data: book.coverData, title: book.title)
                .frame(width: 68, height: 92)

            VStack(alignment: .leading, spacing: 8) {
                Text(book.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(book.displayAuthor)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(book.displayPublisherLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(book.location.rawValue)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(locationTint.opacity(0.16), in: Capsule())
                    .foregroundStyle(locationTint)
            }

            Spacer(minLength: 12)

            VStack(spacing: 10) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .frame(width: 36, height: 36)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑 \(book.title)")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 36, height: 36)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除 \(book.title)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
    }

    private var locationTint: Color {
        switch book.location {
        case .chengdu:
            return .blue
        case .chongqing:
            return .orange
        }
    }
}

private struct BookThumbnail: View {
    let data: Data?
    let title: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))

            if let platformImage {
                imageView(platformImage)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 22))
                        .foregroundStyle(.tint)

                    Text(title.trimmed.isEmpty ? "未命名" : title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 8)
                }
            }
        }
    }

    private var platformImage: PlatformImage? {
        guard let data else {
            return nil
        }

        return PlatformImage(data: data)
    }

    @ViewBuilder
    private func imageView(_ image: PlatformImage) -> some View {
        #if canImport(UIKit)
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
        #elseif canImport(AppKit)
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
        #endif
    }
}

private enum EditorTarget: Identifiable {
    case create(defaultLocation: BookLocation)
    case edit(Book)

    var id: String {
        switch self {
        case .create(let defaultLocation):
            return "create-\(defaultLocation.rawValue)"
        case .edit(let book):
            return "edit-\(book.id)"
        }
    }

    var book: Book? {
        switch self {
        case .create:
            return nil
        case .edit(let book):
            return book
        }
    }

    var defaultLocation: BookLocation {
        switch self {
        case .create(let defaultLocation):
            return defaultLocation
        case .edit(let book):
            return book.location
        }
    }
}
