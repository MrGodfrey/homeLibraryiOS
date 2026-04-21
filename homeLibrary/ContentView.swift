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
    @State private var createDraftCache: CreateBookDraftCache?
    @State private var isShowingRepositorySheet = false
    @State private var libraryContentWidth: CGFloat = 0

    var body: some View {
        ZStack {
            LibraryTheme.background
                .ignoresSafeArea()

            if store.hasRepository {
                libraryContent
            } else {
                emptyRepositoryState
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
                initialDraft: target.initialDraft,
                locations: store.locations.isEmpty ? LibraryLocation.defaultLocations() : store.locations,
                defaultLocationID: target.defaultLocationID,
                onDelete: { book in
                    await store.deleteBook(book)
                },
                onSave: { draft, book in
                    let didSave = await store.saveBook(draft: draft, editing: book)

                    if didSave && target.isCreating {
                        createDraftCache = nil
                    }

                    return didSave
                },
                onDraftChange: target.isCreating ? { draft in
                    cacheCreateDraft(draft)
                } : nil,
                onCancel: target.isCreating ? {
                    createDraftCache = nil
                } : nil
            )
        }
        .alert(localized("提示", en: "Notice"), isPresented: alertBinding) {
            Button(localized("知道了", en: "OK"), role: .cancel) {
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
        }
    }

    private var fixedHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerIntro

            headerControls(compact: false)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .background {
            LibraryTheme.background
                .ignoresSafeArea(edges: .top)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(LibraryTheme.divider)
                        .frame(height: 1)
                }
        }
    }

    private var headerIntro: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(localized("家藏万卷", en: "Home Library"))
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

            HStack(spacing: 10) {
                addBookButton

                headerActionButton(
                    systemName: "gearshape",
                    identifier: "repositoryManagementButton"
                ) {
                    isShowingRepositorySheet = true
                }
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
        fill: Color = LibraryTheme.surface,
        foreground: Color = LibraryTheme.icon,
        stroke: Color = LibraryTheme.stroke,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(fill)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(stroke, lineWidth: 1)
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
                prompt: Text(localized("搜索书名、作者、译者或 ISBN", en: "Search by title, author, translator, or ISBN"))
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
            Text(localized("共 %d 本", en: "%d books", arguments: [store.visibleBooks.count]))
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
                    coverLoader: store.coverData(for:),
                    onTap: {
                        editorTarget = .edit(
                            book,
                            initialCoverData: store.coverDataSynchronously(for: book.coverAssetID),
                            defaultLocationID: book.locationID
                        )
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadingState: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(LibraryTheme.accent)

            Text(localized("正在读取书库…", en: "Loading library..."))
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

            Text(
                hasActiveFilters ?
                    localized("当前没有匹配的书籍", en: "No matching books") :
                    localized("仓库还是空的", en: "Library is empty")
            )
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(LibraryTheme.title)

            Text(
                hasActiveFilters ?
                    localized("试试切换地点或清空搜索。", en: "Try switching locations or clearing the search.") :
                    localized("点右上角的加号，先录入第一本书。", en: "Tap the plus button in the top-right to add your first book.")
            )
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
        headerActionButton(
            systemName: "plus",
            identifier: "addBookButton",
            fill: LibraryTheme.accent,
            foreground: .white,
            stroke: LibraryTheme.accent
        ) {
            editorTarget = .create(
                initialDraft: currentCreateDraft(),
                defaultLocationID: store.defaultLocationID
            )
        }
        .accessibilityLabel(localized("添加", en: "Add"))
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
                Button(localized("关闭", en: "Close")) {
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

            Text(localized("家藏万卷", en: "Home Library"))
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(LibraryTheme.title)

            Text(localized("先创建一座家庭书库，再开始录入和共享。", en: "Create a family library first, then start adding and sharing books."))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LibraryTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button(store.isCreatingRepository ? localized("创建中...", en: "Creating...") : localized("创建我的仓库", en: "Create My Library")) {
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

            Button(localized("设置", en: "Settings")) {
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
            let shareSummary = currentRepository.shareStatus == .shared ?
                localized("已共享", en: "Shared") :
                localized("未共享", en: "Not Shared")
            return "\(currentRepository.role.title) / \(shareSummary)"
        }

        return localized("当前设备还没有可访问的家庭书库。", en: "There is no accessible family library on this device yet.")
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

    private func cacheCreateDraft(_ draft: BookDraft) {
        guard let repositoryID = store.currentRepository?.id else {
            return
        }

        createDraftCache = CreateBookDraftCache(repositoryID: repositoryID, draft: draft)
    }

    private func currentCreateDraft() -> BookDraft? {
        guard let repositoryID = store.currentRepository?.id,
              createDraftCache?.repositoryID == repositoryID else {
            return nil
        }

        return createDraftCache?.draft
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
            return localized("未同步", en: "Not Synced")
        case .syncing:
            return localized("同步中", en: "Syncing")
        case .upToDate:
            return localized("已同步", en: "Synced")
        case .failed:
            return localized("同步失败", en: "Sync Failed")
        }
    }
}

private struct LibraryBookCard: View {
    private static let coverAspectRatio: CGFloat = 0.72

    let book: Book
    let cardWidth: CGFloat
    let coverLoader: (String?) async -> Data?
    let onTap: () -> Void

    private var coverHeight: CGFloat {
        cardWidth / Self.coverAspectRatio
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                BookThumbnail(assetID: book.coverAssetID, coverLoader: coverLoader)
                    .frame(width: cardWidth, height: coverHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(book.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LibraryTheme.bodyText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: cardWidth, alignment: .topLeading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("bookCard-\(book.id)")
    }
}

struct LibraryBookGridLayout {
    static let minimumCardWidth: CGFloat = 152
    static let columnSpacing: CGFloat = 16
    static let rowSpacing: CGFloat = 20
    private static let compactColumnCount = 3
    private static let regularMaximumColumnCount = 4

    let availableWidth: CGFloat
    let horizontalSizeClass: UserInterfaceSizeClass?

    var rowSpacing: CGFloat { Self.rowSpacing }

    var columnCount: Int {
        if horizontalSizeClass != .regular {
            return Self.compactColumnCount
        }

        let maxColumnsThatFit = max(
            1,
            Int((availableWidth + Self.columnSpacing) / (Self.minimumCardWidth + Self.columnSpacing))
        )

        return min(maxColumnsThatFit, Self.regularMaximumColumnCount)
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
    case create(initialDraft: BookDraft?, defaultLocationID: String)
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

    var initialDraft: BookDraft? {
        if case .create(let initialDraft, _) = self {
            return initialDraft
        }

        return nil
    }

    var defaultLocationID: String {
        switch self {
        case .create(_, let defaultLocationID):
            return defaultLocationID
        case .edit(_, _, let defaultLocationID):
            return defaultLocationID
        }
    }

    var isCreating: Bool {
        if case .create = self {
            return true
        }

        return false
    }
}

private struct CreateBookDraftCache {
    let repositoryID: String
    let draft: BookDraft
}

private extension LibraryStore {
    var locationsDictionary: [String: LibraryLocation] {
        Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
    }
}
