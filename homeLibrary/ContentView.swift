//
//  ContentView.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import SwiftUI
import UniformTypeIdentifiers
import ImageIO

struct ContentView: View {
    @ObservedObject var store: LibraryStore
    @State private var editorTarget: EditorTarget?
    @State private var pendingDeleteBook: Book?
    @State private var isShowingRepositorySheet = false
    @State private var isShowingLegacyImportPicker = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("家藏万卷")
                .modifier(LibrarySearchModifier(searchText: $store.searchText, isEnabled: store.canSearch))
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
                        .accessibilityIdentifier("refreshButton")

                        Button {
                            isShowingRepositorySheet = true
                        } label: {
                            Image(systemName: "person.2.badge.gearshape")
                        }
                        .accessibilityLabel("仓库管理")
                        .accessibilityIdentifier("repositoryManagementButton")

                        Button {
                            editorTarget = .create(defaultLocation: store.activeTab.location ?? .chengdu)
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(!store.hasRepository)
                        .accessibilityLabel("添加书籍")
                        .accessibilityIdentifier("addBookButton")
                    }
                }
        }
        .task {
            await store.loadBooksIfNeeded()
        }
        .sheet(isPresented: $isShowingRepositorySheet) {
            RepositoryManagementView(store: store)
        }
        .fileImporter(
            isPresented: $isShowingLegacyImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleLegacyImportSelection(result)
        }
        .sheet(item: $editorTarget) { target in
            BookEditorView(
                editingBook: target.book,
                initialCoverData: target.initialCoverData,
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
            Text("删除后会立即写入当前仓库。")
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
            .accessibilityIdentifier("locationPicker")

            HStack(alignment: .center, spacing: 12) {
                Text("共 \(store.visibleBooks.count) 本可见藏书")
                    .font(.headline)
                    .accessibilityIdentifier("visibleCountLabel")

                Spacer()

                SyncStatusBadge(status: store.syncStatus)

                if store.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            RepositoryPanel(
                title: store.repositoryTitle,
                roleTitle: store.repositoryRoleTitle,
                subtitle: store.repositorySubtitle
            )

            if store.visibleBooks.isEmpty && !store.isLoading {
                Spacer()

                if !store.hasRepository {
                    ContentUnavailableView {
                        Label("还没有仓库", systemImage: "books.vertical")
                    } description: {
                        Text("当前 iCloud 账号下没有可用仓库。你可以创建一个新仓库，或者从旧 JSON 迁移。")
                    } actions: {
                        Button(store.isCreatingRepository ? "创建中..." : "创建我的仓库") {
                            Task {
                                _ = await store.createOwnedRepository()
                            }
                        }
                        .disabled(store.isCreatingRepository || store.isImportingLegacyData)
                        .accessibilityIdentifier("createOwnedRepositoryButton")

                        Button(store.isImportingLegacyData ? "导入中..." : "迁移旧数据") {
                            isShowingLegacyImportPicker = true
                        }
                        .disabled(store.isCreatingRepository || store.isImportingLegacyData)
                    }
                    .accessibilityIdentifier("emptyState")
                } else if hasActiveFilters {
                    ContentUnavailableView(
                        "当前没有匹配的书籍",
                        systemImage: "books.vertical",
                        description: Text("试试切换地点、搜索关键词，或者清空筛选条件。")
                    )
                    .accessibilityIdentifier("emptyState")
                } else {
                    ContentUnavailableView {
                        Label("仓库还是空的", systemImage: "books.vertical")
                    } description: {
                        Text("你可以直接添加一本新书，或者从旧 JSON 迁移。")
                    } actions: {
                        Button("添加书籍") {
                            editorTarget = .create(defaultLocation: store.activeTab.location ?? .chengdu)
                        }

                        Button(store.isImportingLegacyData ? "导入中..." : "迁移旧数据") {
                            isShowingLegacyImportPicker = true
                        }
                        .disabled(store.isImportingLegacyData)
                    }
                    .accessibilityIdentifier("emptyState")
                }

                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.visibleBooks) { book in
                            BookRowCard(
                                book: book,
                                coverLoader: store.coverData(for:),
                                onEdit: {
                                    editorTarget = .edit(
                                        book,
                                        initialCoverData: store.coverDataSynchronously(for: book.coverAssetID)
                                    )
                                },
                                onDelete: {
                                    pendingDeleteBook = book
                                }
                            )
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

    private var hasActiveFilters: Bool {
        !store.searchText.trimmed.isEmpty || store.activeTab != .all
    }

    private func handleLegacyImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                return
            }

            Task {
                _ = await store.importLegacyJSON(from: url)
            }
        case .failure(let error):
            store.alertMessage = LibraryStore.userFacingMessage(for: error)
        }
    }
}

private struct LibrarySearchModifier: ViewModifier {
    @Binding var searchText: String
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(text: $searchText, prompt: "搜索书名、作者或出版社")
        } else {
            content
        }
    }
}

private struct RepositoryPanel: View {
    let title: String
    let roleTitle: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            Text(roleTitle)
                .font(.caption.weight(.bold))
                .foregroundStyle(.tint)

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("repositoryPanel")
    }
}

private struct SyncStatusBadge: View {
    let status: LibrarySyncStatus

    var body: some View {
        Label(status.label, systemImage: status.systemImageName)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(tintColor)
            .background(tintColor.opacity(0.12), in: Capsule())
            .accessibilityIdentifier("syncStatusBadge")
    }

    private var tintColor: Color {
        switch status {
        case .idle:
            return .secondary
        case .syncing:
            return .blue
        case .upToDate:
            return .green
        case .failed:
            return .red
        }
    }
}

private struct BookRowCard: View {
    let book: Book
    let coverLoader: (String?) async -> Data?
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BookThumbnail(assetID: book.coverAssetID, title: book.title, coverLoader: coverLoader)
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
                .accessibilityIdentifier("editBook-\(book.id)")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 36, height: 36)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除 \(book.title)")
                .accessibilityIdentifier("deleteBook-\(book.id)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityIdentifier("bookRow-\(book.id)")
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
    let assetID: String?
    let title: String
    let coverLoader: (String?) async -> Data?

    @Environment(\.displayScale) private var displayScale
    @State private var thumbnailImage: PlatformImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))

            if let thumbnailImage {
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .scaledToFill()
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
        .task(id: assetID) {
            await loadThumbnail()
        }
    }

    @MainActor
    private func loadThumbnail() async {
        guard let assetID else {
            thumbnailImage = nil
            return
        }

        let maxPixelSize = Int(92 * displayScale)

        if let cachedImage = CoverThumbnailRenderer.cachedImage(for: assetID, maxPixelSize: maxPixelSize) {
            thumbnailImage = cachedImage
            return
        }

        guard let coverData = await coverLoader(assetID) else {
            thumbnailImage = nil
            return
        }

        guard !Task.isCancelled else {
            return
        }

        let preparedImage = await Task.detached(priority: .utility) {
            SendablePlatformImage(
                image: CoverThumbnailRenderer.makeThumbnail(from: coverData, maxPixelSize: maxPixelSize)
            )
        }.value

        guard !Task.isCancelled else {
            return
        }

        if let image = preparedImage.image {
            CoverThumbnailRenderer.store(image, for: assetID, maxPixelSize: maxPixelSize)
        }

        thumbnailImage = preparedImage.image
    }
}

private struct SendablePlatformImage: @unchecked Sendable {
    let image: PlatformImage?
}

private enum CoverThumbnailRenderer {
    nonisolated(unsafe) private static let cache = NSCache<NSString, PlatformImage>()

    nonisolated static func cachedImage(for assetID: String, maxPixelSize: Int) -> PlatformImage? {
        cache.object(forKey: cacheKey(for: assetID, maxPixelSize: maxPixelSize))
    }

    nonisolated static func store(_ image: PlatformImage, for assetID: String, maxPixelSize: Int) {
        cache.setObject(image, forKey: cacheKey(for: assetID, maxPixelSize: maxPixelSize))
    }

    nonisolated static func makeThumbnail(from data: Data, maxPixelSize: Int) -> PlatformImage? {
        let sourceOptions: CFDictionary = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary

        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return PlatformImage(data: data)
        }

        let thumbnailOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) {
            return PlatformImage(cgImage: cgImage)
        }

        return PlatformImage(data: data)
    }

    nonisolated private static func cacheKey(for assetID: String, maxPixelSize: Int) -> NSString {
        "\(assetID)#\(maxPixelSize)" as NSString
    }
}

private enum EditorTarget: Identifiable {
    case create(defaultLocation: BookLocation)
    case edit(Book, initialCoverData: Data?)

    var id: String {
        switch self {
        case .create(let defaultLocation):
            return "create-\(defaultLocation.rawValue)"
        case .edit(let book, _):
            return "edit-\(book.id)"
        }
    }

    var book: Book? {
        switch self {
        case .create:
            return nil
        case .edit(let book, _):
            return book
        }
    }

    var defaultLocation: BookLocation {
        switch self {
        case .create(let defaultLocation):
            return defaultLocation
        case .edit(let book, _):
            return book.location
        }
    }

    var initialCoverData: Data? {
        switch self {
        case .create:
            return nil
        case .edit(_, let initialCoverData):
            return initialCoverData
        }
    }
}
