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

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LibraryHomePalette.background
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerSection

                Rectangle()
                    .fill(LibraryHomePalette.divider)
                    .frame(height: 1)
                    .padding(.top, 26)

                librarySection
                    .padding(.top, 28)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await store.loadBooks(force: true)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                homeGlyph

                VStack(alignment: .leading, spacing: 8) {
                    Text("家藏万卷")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(LibraryHomePalette.title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)

                    Text(repositorySummary)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(LibraryHomePalette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)

                    SyncStatusBadge(status: store.syncStatus)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    headerActionButton(
                        systemName: "arrow.clockwise",
                        identifier: "refreshButton"
                    ) {
                        Task {
                            await store.loadBooks(force: true)
                        }
                    }

                    headerActionButton(
                        systemName: "gearshape",
                        identifier: "repositoryManagementButton"
                    ) {
                        isShowingRepositorySheet = true
                    }
                }
            }

            searchBar
            locationFilterBar
        }
    }

    private var homeGlyph: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(LibraryHomePalette.accent)
            .frame(width: 72, height: 72)
            .overlay {
                Image(systemName: "book.pages")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white)
            }
            .shadow(color: LibraryHomePalette.accent.opacity(0.18), radius: 12, x: 0, y: 8)
    }

    private func headerActionButton(
        systemName: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(LibraryHomePalette.icon)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(LibraryHomePalette.stroke, lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(LibraryHomePalette.tertiaryText)

            TextField(
                "",
                text: $store.searchText,
                prompt: Text("搜索书名、作者或 ISBN")
                    .foregroundStyle(LibraryHomePalette.secondaryText)
            )
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(LibraryHomePalette.bodyText)
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
                        .foregroundStyle(LibraryHomePalette.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LibraryHomePalette.stroke, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.035), radius: 12, x: 0, y: 5)
    }

    private var locationFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(store.visibleLocationFilters) { filter in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            store.selectedLocationID = filter.locationID
                            selectedBookID = nil
                        }
                    } label: {
                        Text(filter.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(isActive(filter: filter) ? Color.white : LibraryHomePalette.bodyText)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isActive(filter: filter) ? LibraryHomePalette.accent : Color.white)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isActive(filter: filter) ? LibraryHomePalette.accent : LibraryHomePalette.stroke, lineWidth: 1)
                            }
                            .shadow(
                                color: isActive(filter: filter) ? LibraryHomePalette.accent.opacity(0.18) : Color.black.opacity(0.02),
                                radius: 10,
                                x: 0,
                                y: 6
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("家庭书库")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LibraryHomePalette.secondaryText)

            Text("共 \(store.visibleBooks.count) 本可见藏书")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(LibraryHomePalette.title)

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
    }

    private var booksGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 152, maximum: 240), spacing: 16, alignment: .top)],
            alignment: .leading,
            spacing: 20
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

    private var loadingState: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(LibraryHomePalette.accent)

            Text("正在读取书库…")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LibraryHomePalette.bodyText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyBooksState: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LibraryHomePalette.accent.opacity(0.12))
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle" : "books.vertical")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(LibraryHomePalette.accent)
                }

            Text(hasActiveFilters ? "当前没有匹配的书籍" : "仓库还是空的")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(LibraryHomePalette.title)

            Text(hasActiveFilters ? "试试切换地点或清空搜索。" : "点右下角的加号，先录入第一本书。")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(LibraryHomePalette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.86))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LibraryHomePalette.stroke, lineWidth: 1)
        }
    }

    private var addBookButton: some View {
        Button {
            editorTarget = .create(defaultLocationID: store.defaultLocationID)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(store.hasRepository ? LibraryHomePalette.accent : Color.gray)
                )
                .shadow(color: LibraryHomePalette.accent.opacity(0.2), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("addBookButton")
        .disabled(!store.hasRepository)
    }

    private func progressBanner(_ progress: RepositoryImportProgress) -> some View {
        HStack(spacing: 12) {
            if progress.phase == .importing {
                ProgressView(value: Double(progress.importedCount), total: Double(max(progress.totalCount, 1)))
                    .tint(LibraryHomePalette.accent)
            } else {
                ProgressView()
                    .tint(LibraryHomePalette.accent)
            }

            Text(progress.statusText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LibraryHomePalette.bodyText)

            Spacer()

            if progress.phase == .completed {
                Button("关闭") {
                    store.dismissImportProgress()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LibraryHomePalette.accent)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LibraryHomePalette.stroke, lineWidth: 1)
        }
    }

    private var emptyRepositoryState: some View {
        VStack(spacing: 20) {
            Spacer()

            homeGlyph

            Text("家藏万卷")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(LibraryHomePalette.title)

            Text("先创建一座家庭书库，再开始录入和共享。")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LibraryHomePalette.secondaryText)
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
                    .fill(LibraryHomePalette.accent)
            )
            .padding(.horizontal, 24)
            .accessibilityIdentifier("createOwnedRepositoryButton")

            Button("设置") {
                isShowingRepositorySheet = true
            }
            .buttonStyle(.plain)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(LibraryHomePalette.bodyText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(LibraryHomePalette.stroke, lineWidth: 1)
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
            return "\(currentRepository.role.title) · \(shareSummary)"
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
}

private enum LibraryHomePalette {
    static let background = Color(red: 0.969, green: 0.961, blue: 0.937)
    static let accent = Color(red: 0.012, green: 0.545, blue: 0.365)
    static let title = Color(red: 0.071, green: 0.118, blue: 0.204)
    static let bodyText = Color(red: 0.298, green: 0.349, blue: 0.451)
    static let secondaryText = Color(red: 0.596, green: 0.639, blue: 0.737)
    static let tertiaryText = Color(red: 0.651, green: 0.675, blue: 0.741)
    static let icon = Color(red: 0.431, green: 0.47, blue: 0.565)
    static let stroke = Color(red: 0.878, green: 0.89, blue: 0.925)
    static let divider = Color(red: 0.913, green: 0.921, blue: 0.941)
    static let location = Color(red: 0.073, green: 0.51, blue: 0.839)
}

private struct SyncStatusBadge: View {
    let status: LibrarySyncStatus

    var body: some View {
        Label(status.compactLabel, systemImage: status.systemImageName)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(tintColor)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tintColor.opacity(0.12))
            )
            .accessibilityIdentifier("syncStatusBadge")
    }

    private var tintColor: Color {
        switch status {
        case .idle:
            return LibraryHomePalette.secondaryText
        case .syncing:
            return .blue
        case .upToDate:
            return .green
        case .failed:
            return .red
        }
    }
}

private extension LibrarySyncStatus {
    var compactLabel: String {
        switch self {
        case .idle:
            return "等待同步"
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
    let book: Book
    let locationName: String
    let isSelected: Bool
    let coverLoader: (String?) async -> Data?
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                BookThumbnail(assetID: book.coverAssetID, title: book.title, coverLoader: coverLoader)
                    .aspectRatio(0.72, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

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

            VStack(alignment: .leading, spacing: 10) {
                Text(book.title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(LibraryHomePalette.title)
                    .lineLimit(2)
                    .frame(minHeight: 58, alignment: .topLeading)

                Text(locationName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LibraryHomePalette.location)
                    )

                Text(book.displayAuthor)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LibraryHomePalette.bodyText)
                    .lineLimit(1)

                Text(book.displayPublisherLine)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LibraryHomePalette.secondaryText)
                    .lineLimit(2)
                    .frame(minHeight: 40, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? LibraryHomePalette.accent.opacity(0.35) : LibraryHomePalette.stroke, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(perform: onTap)
        .accessibilityAddTraits(.isButton)
    }

    private func overlayButton(
        systemName: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(LibraryHomePalette.icon)
                .frame(width: 58, height: 58)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
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
                .fill(Color.white)

            if let thumbnailImage {
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 28))
                        .foregroundStyle(LibraryHomePalette.accent)

                    Text(title.trimmed.isEmpty ? "未命名" : title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LibraryHomePalette.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 10)
                }
                .padding(.horizontal, 12)
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
