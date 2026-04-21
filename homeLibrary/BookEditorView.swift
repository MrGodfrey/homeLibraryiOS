//
//  BookEditorView.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import PhotosUI
import SwiftUI

struct BookEditorView: View {
    let editingBook: Book?
    let initialCoverData: Data?
    let locations: [LibraryLocation]
    let defaultLocationID: String
    let onDelete: ((Book) async -> Bool)?
    let onSave: (BookDraft, Book?) async -> Bool
    let onDraftChange: ((BookDraft) -> Void)?
    let onCancel: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var draft: BookDraft
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var isProcessingCover = false
    @State private var activeAlert: EditorAlert?

    init(
        editingBook: Book?,
        initialCoverData: Data?,
        initialDraft: BookDraft? = nil,
        locations: [LibraryLocation],
        defaultLocationID: String,
        onDelete: ((Book) async -> Bool)? = nil,
        onSave: @escaping (BookDraft, Book?) async -> Bool,
        onDraftChange: ((BookDraft) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.editingBook = editingBook
        self.initialCoverData = initialCoverData
        self.locations = locations
        self.defaultLocationID = defaultLocationID
        self.onDelete = onDelete
        self.onSave = onSave
        self.onDraftChange = onDraftChange
        self.onCancel = onCancel
        _draft = State(initialValue: initialDraft ?? BookDraft(
            book: editingBook,
            coverData: initialCoverData,
            defaultLocationID: defaultLocationID
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                informationSection
                coverSection

                if editingBook != nil {
                    deleteSection
                }
            }
            .libraryFormChrome()
            .listSectionSpacing(18)
            .tint(LibraryTheme.accent)
            .navigationTitle(editingBook == nil ? localized("添加新书", en: "Add Book") : localized("编辑书籍", en: "Edit Book"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(LibraryTheme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("取消", en: "Cancel")) {
                        onCancel?()
                        dismiss()
                    }
                    .disabled(isSaving || isDeleting)
                    .accessibilityIdentifier("cancelBookButton")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        isSaving ?
                            localized("保存中...", en: "Saving...") :
                            (editingBook == nil ? localized("确认添加", en: "Add") : localized("保存修改", en: "Save Changes"))
                    ) {
                        Task {
                            await saveBook()
                        }
                    }
                    .disabled(isSaving || isDeleting || isProcessingCover || !draft.canSave)
                    .accessibilityIdentifier("saveBookButton")
                }
            }
            .task(id: selectedPhotoItem) {
                guard let selectedPhotoItem else {
                    return
                }

                await loadCover(from: selectedPhotoItem)
            }
            .task(id: locations.map(\.id)) {
                syncLocationSelectionIfNeeded()
            }
            .onChange(of: draft) { _, newDraft in
                onDraftChange?(newDraft)
            }
            .alert(item: $activeAlert) { alert in
                makeAlert(for: alert)
            }
        }
    }

    private var locationSelection: Binding<String> {
        Binding(
            get: {
                draft.resolvedLocationID(
                    in: locations,
                    fallback: defaultLocationID
                )
            },
            set: { newValue in
                draft.locationID = newValue.trimmed
            }
        )
    }

    private var informationSection: some View {
        Section {
            TextField(localized("书名", en: "Title"), text: $draft.title)
                .accessibilityIdentifier("titleField")
            TextField(localized("作者", en: "Author"), text: $draft.author)
                .accessibilityIdentifier("authorField")
            TextField(localized("译者", en: "Translator"), text: $draft.translator)
                .accessibilityIdentifier("translatorField")
            TextField(localized("出版社", en: "Publisher"), text: $draft.publisher)
                .accessibilityIdentifier("publisherField")
            TextField(localized("出版年份", en: "Publication Year"), text: $draft.year)
                .keyboardType(.numbersAndPunctuation)
                .accessibilityIdentifier("yearField")
            TextField(localized("ISBN", en: "ISBN"), text: $draft.isbn)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("isbnField")

            Picker(localized("所在地点", en: "Location"), selection: locationSelection) {
                ForEach(locations) { location in
                    Text(location.name).tag(location.id)
                }
            }
            .accessibilityIdentifier("editorLocationPicker")
        }
        header: {
            sectionHeader(localized("图书信息", en: "Book Details"))
        }
        .listRowBackground(LibraryTheme.surface)
    }

    private var coverSection: some View {
        Section {
            BookCoverPreview(data: draft.coverData, title: draft.title)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                formActionLabel(
                    title: draft.coverData == nil && !draft.keepsExistingCoverReference ?
                        localized("从 iPhone 上传封面", en: "Upload Cover from iPhone") :
                        localized("更换封面", en: "Replace Cover"),
                    systemName: "photo",
                    tint: LibraryTheme.accent
                )
            }
            .disabled(isProcessingCover || isSaving || isDeleting)
            .accessibilityIdentifier("pickCoverButton")

            if draft.coverData != nil || draft.keepsExistingCoverReference {
                Button(role: .destructive) {
                    selectedPhotoItem = nil
                    draft.coverData = nil
                    draft.keepsExistingCoverReference = false
                } label: {
                    formActionLabel(
                        title: localized("移除封面", en: "Remove Cover"),
                        systemName: "trash",
                        tint: LibraryTheme.destructive,
                        textColor: LibraryTheme.destructive
                    )
                }
                .disabled(isProcessingCover || isSaving || isDeleting)
                .accessibilityIdentifier("removeCoverButton")
            }

            if isProcessingCover {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(LibraryTheme.accent)

                    Text(localized("正在压缩封面…", en: "Compressing cover..."))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(LibraryTheme.bodyText)
                }
                .accessibilityIdentifier("compressingCoverStatus")
            }
        }
        header: {
            sectionHeader(localized("封面", en: "Cover"))
        }
        .listRowBackground(LibraryTheme.surface)
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                activeAlert = .deleteConfirmation
            } label: {
                formActionLabel(
                    title: localized("删除书籍", en: "Delete Book"),
                    systemName: "trash",
                    tint: LibraryTheme.destructive,
                    textColor: LibraryTheme.destructive
                )
            }
            .disabled(isSaving || isDeleting)
            .accessibilityIdentifier("deleteBookButton")
        } header: {
            sectionHeader(localized("危险操作", en: "Destructive Actions"))
        }
        .listRowBackground(LibraryTheme.surface)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(LibraryTheme.secondaryText)
            .textCase(nil)
    }

    private func formActionLabel(
        title: String,
        systemName: String,
        tint: Color,
        textColor: Color = LibraryTheme.bodyText
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.14))
                )

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(textColor)
        }
    }

    @MainActor
    private func syncLocationSelectionIfNeeded() {
        let resolvedLocationID = draft.resolvedLocationID(
            in: locations,
            fallback: defaultLocationID
        )

        guard draft.locationID != resolvedLocationID else {
            return
        }

        draft.locationID = resolvedLocationID
    }

    @MainActor
    private func loadCover(from item: PhotosPickerItem) async {
        isProcessingCover = true
        defer { isProcessingCover = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                activeAlert = .message(localized("读取封面失败，请换一张图片重试。", en: "Failed to read the cover. Try a different image."))
                return
            }

            let compressionResult = await Task.detached(priority: .utility) {
                LibraryCoverCompressor.compressIfNeeded(data)
            }.value

            guard !Task.isCancelled else {
                return
            }

            draft.coverData = compressionResult.data
            draft.keepsExistingCoverReference = false
        } catch {
            activeAlert = .message(localized("读取封面失败，请换一张图片重试。", en: "Failed to read the cover. Try a different image."))
        }
    }

    @MainActor
    private func saveBook() async {
        isSaving = true
        defer { isSaving = false }

        let didSave = await onSave(draft, editingBook)

        if didSave {
            dismiss()
        }
    }

    @MainActor
    private func deleteBook() async {
        guard let editingBook, let onDelete else {
            return
        }

        isDeleting = true
        defer { isDeleting = false }

        let didDelete = await onDelete(editingBook)

        if didDelete {
            dismiss()
        }
    }

    private func makeAlert(for alert: EditorAlert) -> Alert {
        switch alert {
        case .message(let message):
            return Alert(
                title: Text(localized("提示", en: "Notice")),
                message: Text(message),
                dismissButton: .cancel(Text(localized("知道了", en: "OK")))
            )
        case .deleteConfirmation:
            return Alert(
                title: Text(localized("确认删除这本书？", en: "Delete this book?")),
                message: Text(localized("删除后会立即写入当前仓库。", en: "The deletion will be saved to the current library immediately.")),
                primaryButton: .destructive(Text(localized("确认删除", en: "Delete"))) {
                    Task {
                        await deleteBook()
                    }
                },
                secondaryButton: .cancel(Text(localized("暂不删除", en: "Not Now")))
            )
        }
    }
}

private enum EditorAlert: Identifiable {
    case message(String)
    case deleteConfirmation

    var id: String {
        switch self {
        case .message(let message):
            return "message-\(message)"
        case .deleteConfirmation:
            return "delete-confirmation"
        }
    }
}

private struct BookCoverPreview: View {
    let data: Data?
    let title: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LibraryTheme.surfaceSecondary)

            if let image = platformImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 28))
                        .foregroundStyle(LibraryTheme.accent)
                    Text(title.trimmed.isEmpty ? localized("未设置封面", en: "No Cover") : title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(LibraryTheme.secondaryText)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            }
        }
        .frame(width: 132, height: 180)
    }

    private var platformImage: PlatformImage? {
        guard let data else {
            return nil
        }

        return PlatformImage(data: data)
    }
}
