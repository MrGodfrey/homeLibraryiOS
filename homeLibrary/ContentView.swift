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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var editorTarget: EditorTarget?
    @State private var pendingDeleteBook: Book?
    @State private var selectedBookID: String?
    @State private var isShowingRepositorySheet = false
    @State private var headerCollapseProgress: CGFloat = 0
    @State private var headerIntroHeight: CGFloat = 0
    @State private var libraryContentWidth: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LibraryTheme.background
                .ignoresSafeArea()

            if store.hasRepository {
                libraryContent
            } else {
                emptyRepositoryState
            }

            if store.hasRepository {
                addBookButton
                    .padding(.trailing, 24)
                    .padding(.bottom, 28)
            }
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
        VStack(spacing: 0) {
            fixedHeader

            ScrollView {
                librarySection
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
            }
            .background(LibraryTheme.background)
            .scrollIndicators(.hidden)
            .refreshable {
                await store.loadBooks(force: true)
            }
            .onScrollGeometryChange(for: CGFloat.self, of: { scrollGeometry in
                max(0, scrollGeometry.contentOffset.y + scrollGeometry.contentInsets.top)
            }) { _, offset in
                headerCollapseProgress = max(0, min(offset / 88, 1))
            }
        }
    }

    private var fixedHeader: some View {
        VStack(alignment: .leading, spacing: max(10, 18 - headerCollapseProgress * 8)) {
            headerIntro
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: HeaderIntroHeightPreferenceKey.self, value: proxy.size.height)
                    }
                }
                .onPreferenceChange(HeaderIntroHeightPreferenceKey.self) { height in
                    guard height > 0 else {
                        return
                    }

                    headerIntroHeight = height
                }
                .frame(height: headerIntroVisibleHeight, alignment: .top)
                .clipped()
                .opacity(1 - headerCollapseProgress)
                .scaleEffect(1 - headerCollapseProgress * 0.04, anchor: .topLeading)
                .offset(y: -headerCollapseProgress * 14)
                .allowsHitTesting(!isHeaderCompact)

            headerControls(compact: isHeaderCompact)
        }
        .padding(.horizontal, 20)
        .padding(.top, max(10, 16 - headerCollapseProgress * 6))
        .padding(.bottom, max(12, 18 - headerCollapseProgress * 6))
        .background {
            LibraryTheme.background
                .ignoresSafeArea(edges: .top)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(LibraryTheme.divider)
                        .frame(height: 1)
                }
        }
        .animation(.snappy(duration: 0.22), value: isHeaderCompact)
    }

    private var headerIntro: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("家藏万卷")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(LibraryTheme.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)

                HStack(alignment: .center, spacing: 8) {
                    Text(repositorySummary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(LibraryTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)

                    Text("·")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LibraryTheme.tertiaryText)

                    SyncStatusText(status: store.syncStatus)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            headerActionButton(
                systemName: "gearshape",
                identifier: "repositoryManagementButton"
            ) {
                isShowingRepositorySheet = true
            }
        }
    }

    private func headerControls(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            searchBar(compact: compact)
            locationFilterBar(compact: compact)
        }
    }

    private func headerActionButton(
        systemName: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(LibraryTheme.icon)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LibraryTheme.surface)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(LibraryTheme.stroke, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func searchBar(compact: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: compact ? 18 : 20, weight: .medium))
                .foregroundStyle(LibraryTheme.tertiaryText)

            TextField(
                "",
                text: $store.searchText,
                prompt: Text("搜索书名、作者或 ISBN")
                    .foregroundStyle(LibraryTheme.secondaryText)
            )
            .textFieldStyle(.plain)
            .font(.system(size: compact ? 16 : 18, weight: .medium))
            .foregroundStyle(LibraryTheme.bodyText)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .accessibilityIdentifier("floatingSearchField")

            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                    selectedBookID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(LibraryTheme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, compact ? 16 : 18)
        .padding(.vertical, compact ? 13 : 17)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LibraryTheme.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LibraryTheme.stroke, lineWidth: 1)
        }
    }

    private func locationFilterBar(compact: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: compact ? 8 : 12) {
                ForEach(store.visibleLocationFilters) { filter in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            store.selectedLocationID = filter.locationID
                            selectedBookID = nil
                        }
                    } label: {
                        Text(filter.title)
                            .font(.system(size: compact ? 14 : 16, weight: .semibold))
                            .foregroundStyle(isActive(filter: filter) ? Color.white : LibraryTheme.bodyText)
                            .padding(.horizontal, compact ? 16 : 20)
                            .padding(.vertical, compact ? 10 : 14)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isActive(filter: filter) ? LibraryTheme.accent : LibraryTheme.surface)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isActive(filter: filter) ? LibraryTheme.accent : LibraryTheme.stroke, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("共 \(store.visibleBooks.count) 本")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LibraryTheme.secondaryText)

            if let importProgress = store.importProgress {
                progressBanner(importProgress)
            }

            if store.isLoading && store.visibleBooks.isEmpty {
                loadingState
            } else if store.visibleBooks.isEmpty {
                emptyBooksState
            } else {
                booksGrid
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: LibraryContentWidthPreferenceKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(LibraryContentWidthPreferenceKey.self) { width in
            guard width > 0 else {
                return
            }

            libraryContentWidth = width
        }
    }

    private var booksGrid: some View {
        let layout = bookGridLayout
        return LazyVGrid(
            columns: layout.columns,
            alignment: .leading,
            spacing: layout.rowSpacing
        ) {
            ForEach(store.visibleBooks) { book in
                LibraryBookCard(
                    book: book,
                    cardWidth: layout.cardWidth,
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadingState: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(LibraryTheme.accent)

            Text("正在读取书库…")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LibraryTheme.bodyText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyBooksState: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LibraryTheme.accent.opacity(0.12))
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle" : "books.vertical")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(LibraryTheme.accent)
                }

            Text(hasActiveFilters ? "当前没有匹配的书籍" : "仓库还是空的")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(LibraryTheme.title)

            Text(hasActiveFilters ? "试试切换地点或清空搜索。" : "点右下角的“添加”，先录入第一本书。")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(LibraryTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LibraryTheme.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LibraryTheme.stroke, lineWidth: 1)
        }
    }

    private var addBookButton: some View {
        Button {
            editorTarget = .create(defaultLocationID: store.defaultLocationID)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))

                Text("添加")
                    .font(.system(size: 17, weight: .semibold))
            }
            .padding(.horizontal, 20)
            .frame(height: 56)
                .foregroundStyle(store.hasRepository ? Color.white : LibraryTheme.secondaryText)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(store.hasRepository ? LibraryTheme.accent : LibraryTheme.surfaceSecondary)
                )
                .shadow(
                    color: store.hasRepository ? LibraryTheme.accent.opacity(0.16) : Color.black.opacity(0.04),
                    radius: 12,
                    x: 0,
                    y: 6
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("addBookButton")
        .disabled(!store.hasRepository)
    }

    private func progressBanner(_ progress: RepositoryImportProgress) -> some View {
        HStack(spacing: 12) {
            if progress.phase == .importing {
                ProgressView(value: Double(progress.importedCount), total: Double(max(progress.totalCount, 1)))
                    .tint(LibraryTheme.accent)
            } else {
                ProgressView()
                    .tint(LibraryTheme.accent)
            }

            Text(progress.statusText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LibraryTheme.bodyText)

            Spacer()

            if progress.phase == .completed {
                Button("关闭") {
                    store.dismissImportProgress()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LibraryTheme.accent)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LibraryTheme.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LibraryTheme.stroke, lineWidth: 1)
        }
    }

    private var emptyRepositoryState: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("家藏万卷")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(LibraryTheme.title)

            Text("先创建一座家庭书库，再开始录入和共享。")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LibraryTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button(store.isCreatingRepository ? "创建中..." : "创建我的仓库") {
                Task {
                    _ = await store.createOwnedRepository()
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LibraryTheme.accent)
            )
            .padding(.horizontal, 24)
            .accessibilityIdentifier("createOwnedRepositoryButton")

            Button("设置") {
                isShowingRepositorySheet = true
            }
            .buttonStyle(.plain)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(LibraryTheme.bodyText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LibraryTheme.surface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(LibraryTheme.stroke, lineWidth: 1)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func isActive(filter: LibraryLocationFilter) -> Bool {
        store.selectedLocationID == filter.locationID
    }

    private var repositorySummary: String {
        if let currentRepository = store.currentRepository {
            let shareSummary = currentRepository.shareStatus == .shared ? "已共享" : "未共享"
            return "\(currentRepository.role.title) / \(shareSummary)"
        }

        return "当前设备还没有可访问的家庭书库。"
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

    private var headerIntroVisibleHeight: CGFloat? {
        guard headerIntroHeight > 0 else {
            return nil
        }

        return max(0, headerIntroHeight * (1 - headerCollapseProgress))
    }

    private var isHeaderCompact: Bool {
        headerCollapseProgress > 0.58
    }

    private var bookGridLayout: LibraryBookGridLayout {
        LibraryBookGridLayout(
            availableWidth: gridContainerWidth,
            horizontalSizeClass: horizontalSizeClass
        )
    }

    private var gridContainerWidth: CGFloat {
        let fallbackColumnCount = horizontalSizeClass == .regular ? 3 : 2
        let fallbackWidth =
            CGFloat(fallbackColumnCount) * LibraryBookGridLayout.minimumCardWidth +
            CGFloat(fallbackColumnCount - 1) * LibraryBookGridLayout.columnSpacing
        return max(libraryContentWidth, fallbackWidth)
    }
}
private struct SyncStatusText: View {
    let status: LibrarySyncStatus

    var body: some View {
        Text(status.inlineLabel)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(tintColor)
            .accessibilityIdentifier("syncStatusBadge")
    }

    private var tintColor: Color {
        switch status {
        case .idle:
            return LibraryTheme.secondaryText
        case .syncing:
            return LibraryTheme.info
        case .upToDate:
            return LibraryTheme.success
        case .failed:
            return LibraryTheme.destructive
        }
    }
}

private extension LibrarySyncStatus {
    var inlineLabel: String {
        switch self {
        case .idle:
            return "未同步"
        case .syncing:
            return "同步中"
        case .upToDate:
            return "已同步"
        case .failed:
            return "同步失败"
        }
    }
}

private struct LibraryBookCard: View {
    static let cardPadding: CGFloat = 8
    private static let coverAspectRatio: CGFloat = 0.72

    let book: Book
    let cardWidth: CGFloat
    let isSelected: Bool
    let coverLoader: (String?) async -> Data?
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var contentWidth: CGFloat {
        cardWidth - Self.cardPadding * 2
    }

    private var coverHeight: CGFloat {
        contentWidth / Self.coverAspectRatio
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                BookThumbnail(assetID: book.coverAssetID, coverLoader: coverLoader)
                    .frame(width: contentWidth, height: coverHeight)

                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.22))

                    HStack(spacing: 14) {
                        overlayButton(
                            systemName: "pencil",
                            identifier: "editBook-\(book.id)",
                            action: onEdit
                        )

                        overlayButton(
                            systemName: "trash",
                            identifier: "deleteBook-\(book.id)",
                            action: onDelete
                        )
                    }
                }
            }
            .frame(width: contentWidth, height: coverHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(LibraryTheme.title)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(book.displayAuthor)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LibraryTheme.bodyText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .padding(8)
        .frame(width: cardWidth, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LibraryTheme.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? LibraryTheme.accent.opacity(0.35) : LibraryTheme.stroke, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(perform: onTap)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTap() }
    }

    private func overlayButton(
        systemName: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(LibraryTheme.icon)
                .frame(width: 50, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LibraryTheme.surface)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

private struct LibraryBookGridLayout {
    static let minimumCardWidth: CGFloat = 152
    static let columnSpacing: CGFloat = 16
    static let rowSpacing: CGFloat = 20
    private static let compactColumnCount = 2
    private static let regularMaximumColumnCount = 4

    let availableWidth: CGFloat
    let horizontalSizeClass: UserInterfaceSizeClass?

    var rowSpacing: CGFloat { Self.rowSpacing }

    var columnCount: Int {
        let maxColumnsThatFit = max(
            1,
            Int((availableWidth + Self.columnSpacing) / (Self.minimumCardWidth + Self.columnSpacing))
        )

        if horizontalSizeClass == .regular {
            return min(maxColumnsThatFit, Self.regularMaximumColumnCount)
        }

        return min(maxColumnsThatFit, Self.compactColumnCount)
    }

    var cardWidth: CGFloat {
        let totalSpacing = CGFloat(max(0, columnCount - 1)) * Self.columnSpacing
        return (availableWidth - totalSpacing) / CGFloat(columnCount)
    }

    var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(cardWidth), spacing: Self.columnSpacing, alignment: .top),
            count: columnCount
        )
    }
}

private struct BookThumbnail: View {
    let assetID: String?
    let coverLoader: (String?) async -> Data?

    @Environment(\.displayScale) private var displayScale
    @State private var thumbnailImage: PlatformImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LibraryTheme.surfaceSecondary)

            if let thumbnailImage {
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 28))
                        .foregroundStyle(LibraryTheme.accent)
                }
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

private struct HeaderIntroHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct LibraryContentWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
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
