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
    let defaultLocation: BookLocation
    let onSave: (BookDraft, Book?) async -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var draft: BookDraft
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isSaving = false
    @State private var alertMessage: String?

    init(
        editingBook: Book?,
        initialCoverData: Data?,
        defaultLocation: BookLocation,
        onSave: @escaping (BookDraft, Book?) async -> Bool
    ) {
        self.editingBook = editingBook
        self.initialCoverData = initialCoverData
        self.defaultLocation = defaultLocation
        self.onSave = onSave
        _draft = State(initialValue: BookDraft(book: editingBook, coverData: initialCoverData, defaultLocation: defaultLocation))
    }

    var body: some View {
        NavigationStack {
            Form {
                informationSection
                coverSection
            }
            .navigationTitle(editingBook == nil ? "添加新书" : "编辑书籍")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .accessibilityIdentifier("cancelBookButton")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中..." : (editingBook == nil ? "确认添加" : "保存修改")) {
                        Task {
                            await saveBook()
                        }
                    }
                    .disabled(isSaving || !draft.canSave)
                    .accessibilityIdentifier("saveBookButton")
                }
            }
            .task(id: selectedPhotoItem) {
                guard let selectedPhotoItem else {
                    return
                }

                await loadCover(from: selectedPhotoItem)
            }
            .alert("提示", isPresented: alertBinding) {
                Button("知道了", role: .cancel) {
                    alertMessage = nil
                }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private var informationSection: some View {
        Section("图书信息") {
            TextField("书名", text: $draft.title)
                .accessibilityIdentifier("titleField")
            TextField("作者", text: $draft.author)
                .accessibilityIdentifier("authorField")
            TextField("出版社", text: $draft.publisher)
                .accessibilityIdentifier("publisherField")
            TextField("出版年份", text: $draft.year)
                .keyboardType(.numbersAndPunctuation)
                .accessibilityIdentifier("yearField")

            Picker("所在地", selection: $draft.location) {
                ForEach(BookLocation.allCases) { location in
                    Text(location.rawValue).tag(location)
                }
            }
            .accessibilityIdentifier("editorLocationPicker")

            Text("当前版本只保留手动录入。书名、作者、出版社、年份和封面都请直接在 iPhone 上维护。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var coverSection: some View {
        Section("封面") {
            BookCoverPreview(data: draft.coverData, title: draft.title)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label(draft.coverData == nil && !draft.keepsExistingCoverReference ? "从 iPhone 上传封面" : "更换封面", systemImage: "photo")
            }
            .accessibilityIdentifier("pickCoverButton")

            if draft.coverData != nil || draft.keepsExistingCoverReference {
                Button("移除封面", role: .destructive) {
                    selectedPhotoItem = nil
                    draft.coverData = nil
                    draft.keepsExistingCoverReference = false
                }
                .accessibilityIdentifier("removeCoverButton")
            }
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { alertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    alertMessage = nil
                }
            }
        )
    }

    @MainActor
    private func loadCover(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                alertMessage = "读取封面失败，请换一张图片重试。"
                return
            }

            draft.coverData = data
            draft.keepsExistingCoverReference = false
        } catch {
            alertMessage = "读取封面失败，请换一张图片重试。"
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
}

private struct BookCoverPreview: View {
    let data: Data?
    let title: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.08))

            if let image = platformImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 28))
                        .foregroundStyle(.tint)
                    Text(title.trimmed.isEmpty ? "未设置封面" : title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
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
