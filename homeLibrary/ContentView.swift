//
//  ContentView.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import ImageIO
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: LibraryStore

    @State private var editorTarget: EditorTarget?
    @State private var pendingDeleteBook: Book?
    @State private var selectedBookID: String?
    @State private var isShowingRepositorySheet = false
    @State private var isShowingSearchField = false
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            if store.hasRepository {
                libraryContent
            } else {
                emptyRepositoryState
            }

            topOverlay
            bottomFloatingControls
        }
        .task {
            await store.loadBooksIfNeeded()
        }
        .sheet(isPresented: $isShowingRepositorySheet) {
            RepositoryManagementView(store: store)
        }
        .sheet(item: $editorTarget) { target in
            BookEditorView(
                editingBook: target.book,
                initialCoverData: target.initialCoverData,
                locations: store.locations.isEmpty ? LibraryLocation.defaultLocations() : store.locations,
                defaultLocationID: target.defaultLocationID
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
                            if selectedBookID == pendingDeleteBook.id {
                                selectedBookID = nil
                            }
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

    private var libraryContent: some View {
        ScrollView {
            OffsetReader()

            VStack(alignment: .leading, spacing: 16) {
                titleBlock
                    .padding(.top, 84)
                    .opacity(titleOpacity)

                if let importProgress = store.importProgress {
                    progressBanner(importProgress)
                }

                if store.visibleBooks.isEmpty && !store.isLoading {
                    emptyBooksState
                } else {
                    booksGrid
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 140)
        }
        .coordinateSpace(name: "library-scroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { scrollOffset = $0 }
        .refreshable {
            await store.loadBooks(force: true)
        }
    }

    private var emptyRepositoryState: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("家藏万卷")
                .font(.system(size: 34, weight: .bold))

            Text("先创建一座家庭书库，再开始录入和共享。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(store.isCreatingRepository ? "创建中..." : "创建我的仓库") {
                Task {
                    _ = await store.createOwnedRepository()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("createOwnedRepositoryButton")

            Button("仓库设置") {
                isShowingRepositorySheet = true
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("家藏万卷")
                .font(.system(size: 34, weight: .bold))

            HStack(spacing: 10) {
                Text("\(store.visibleBooks.count) 本")
                    .font(.subheadline.weight(.semibold))
                SyncStatusBadge(status: store.syncStatus)
            }
            .foregroundStyle(.secondary)
        }
    }

    private var booksGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 140), spacing: 12),
                GridItem(.flexible(minimum: 140), spacing: 12)
            ],
            spacing: 14
        ) {
            ForEach(store.visibleBooks) { book in
                LibraryBookCard(
                    book: book,
                    locationName: book.locationName(in: store.locationsDictionary),
                    isSelected: selectedBookID == book.id,
                    coverLoader: store.coverData(for:),
                    onTap: {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedBookID = selectedBookID == book.id ? nil : book.id
                        }
                    },
                    onEdit: {
                        selectedBookID = nil
                        editorTarget = .edit(
                            book,
                            initialCoverData: store.coverDataSynchronously(for: book.coverAssetID),
                            defaultLocationID: book.locationID
                        )
                    },
                    onDelete: {
                        pendingDeleteBook = book
                    }
                )
                .accessibilityIdentifier("bookCard-\(book.id)")
            }
        }
    }

    private var emptyBooksState: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

            Text(hasActiveFilters ? "当前没有匹配的书籍" : "仓库还是空的")
                .font(.headline)

            Text(hasActiveFilters ? "试试切换地点或清空搜索。" : "点击右下角的加号，先录入第一本书。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private var topOverlay: some View {
        VStack(spacing: 10) {
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.visibleLocationFilters) { filter in
                            Button {
                                withAnimation(.snappy(duration: 0.2)) {
                                    store.selectedLocationID = filter.locationID
                                    selectedBookID = nil
                                }
                            } label: {
                                Text(filter.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .foregroundStyle(isActive(filter: filter) ? Color.white : Color.primary)
                                    .background(
                                        Group {
                                            if isActive(filter: filter) {
                                                Capsule().fill(Color.primary)
                                            } else {
                                                Capsule().fill(Color.clear)
                                            }
                                        }
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()
        }
        .ignoresSafeArea(edges: .top)
    }

    private var bottomFloatingControls: some View {
        VStack {
            Spacer()

            HStack(alignment: .bottom, spacing: 12) {
                floatingSearch
                Spacer()
                floatingActions
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
    }

    private var floatingSearch: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            if isShowingSearchField || !store.searchText.isEmpty {
                TextField("搜索书名、作者或出版社", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("floatingSearchField")
            } else {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        isShowingSearchField = true
                    }
                } label: {
                    Text("搜索")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("floatingSearchBar")
            }

            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                    if store.searchText.isEmpty {
                        isShowingSearchField = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: isShowingSearchField || !store.searchText.isEmpty ? 260 : 130, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var floatingActions: some View {
        VStack(spacing: 10) {
            floatingCircleButton(systemName: "arrow.clockwise", identifier: "refreshButton") {
                Task {
                    await store.loadBooks(force: true)
                }
            }

            floatingCircleButton(systemName: "person.2.badge.gearshape", identifier: "repositoryManagementButton") {
                isShowingRepositorySheet = true
            }

            floatingCircleButton(systemName: "plus", identifier: "addBookButton", prominent: true) {
                editorTarget = .create(defaultLocationID: store.defaultLocationID)
            }
            .disabled(!store.hasRepository)
        }
    }

    private func floatingCircleButton(
        systemName: String,
        identifier: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .frame(width: 48, height: 48)
                .background(
                    Group {
                        if prominent {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary)
                        } else {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.ultraThinMaterial)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func progressBanner(_ progress: RepositoryImportProgress) -> some View {
        HStack(spacing: 10) {
            if progress.phase == .importing {
                ProgressView(value: Double(progress.importedCount), total: Double(max(progress.totalCount, 1)))
            } else {
                ProgressView()
            }

            Text(progress.statusText)
                .font(.footnote.weight(.semibold))

            Spacer()

            if progress.phase == .completed {
                Button("关闭") {
                    store.dismissImportProgress()
                }
                .font(.footnote.weight(.semibold))
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func isActive(filter: LibraryLocationFilter) -> Bool {
        store.selectedLocationID == filter.locationID
    }

    private var titleOpacity: Double {
        let progress = min(max(-scrollOffset / 48, 0), 1)
        return 1 - progress
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
        !store.searchText.trimmed.isEmpty || store.selectedLocationID != nil
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

private struct LibraryBookCard: View {
    let book: Book
    let locationName: String
    let isSelected: Bool
    let coverLoader: (String?) async -> Data?
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .bottom) {
                    BookThumbnail(assetID: book.coverAssetID, title: book.title, coverLoader: coverLoader)
                        .aspectRatio(0.68, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.black.opacity(0.38))
                            }
                        }

                    if isSelected {
                        HStack(spacing: 10) {
                            actionPill(
                                title: "修改",
                                systemName: "pencil",
                                tint: .white,
                                background: .blue,
                                accessibilityIdentifier: "editBook-\(book.id)",
                                action: onEdit
                            )
                            actionPill(
                                title: "删除",
                                systemName: "trash",
                                tint: .white,
                                background: .red,
                                accessibilityIdentifier: "deleteBook-\(book.id)",
                                action: onDelete
                            )
                        }
                        .padding(10)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
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
                        .lineLimit(2)

                    Text(locationName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func actionPill(
        title: String,
        systemName: String,
        tint: Color,
        background: Color,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(tint)
                .background(background.opacity(0.92), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
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
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))

            if let thumbnailImage {
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 24))
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

        let maxPixelSize = Int(360 * displayScale)

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

private struct OffsetReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: ScrollOffsetPreferenceKey.self,
                    value: proxy.frame(in: .named("library-scroll")).minY
                )
        }
        .frame(height: 0)
    }
}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private enum EditorTarget: Identifiable {
    case create(defaultLocationID: String)
    case edit(Book, initialCoverData: Data?, defaultLocationID: String)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let book, _, _):
            return book.id
        }
    }

    var book: Book? {
        if case .edit(let book, _, _) = self {
            return book
        }

        return nil
    }

    var initialCoverData: Data? {
        if case .edit(_, let initialCoverData, _) = self {
            return initialCoverData
        }

        return nil
    }

    var defaultLocationID: String {
        switch self {
        case .create(let defaultLocationID):
            return defaultLocationID
        case .edit(_, _, let defaultLocationID):
            return defaultLocationID
        }
    }
}

private extension LibraryStore {
    var locationsDictionary: [String: LibraryLocation] {
        Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
    }
}
