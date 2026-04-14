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
    let defaultLocation: BookLocation
    let onSave: (BookDraft, Book?) async -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var draft: BookDraft
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isLookingUp = false
    @State private var isSaving = false
    @State private var isShowingScanner = false
    @State private var alertMessage: String?

    init(
        editingBook: Book?,
        defaultLocation: BookLocation,
        onSave: @escaping (BookDraft, Book?) async -> Bool
    ) {
        self.editingBook = editingBook
        self.defaultLocation = defaultLocation
        self.onSave = onSave
        _draft = State(initialValue: BookDraft(book: editingBook, defaultLocation: defaultLocation))
    }

    var body: some View {
        NavigationStack {
            Form {
                isbnSection
                informationSection
                coverSection
            }
            .navigationTitle(editingBook == nil ? "添加新书" : "编辑书籍")
            .editorNavigationTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中..." : (editingBook == nil ? "确认添加" : "保存修改")) {
                        Task {
                            await saveBook()
                        }
                    }
                    .disabled(isSaving || !draft.canSave)
                }
            }
            .sheet(isPresented: $isShowingScanner) {
                scannerSheet
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

    private var isbnSection: some View {
        Section("ISBN 自动录入") {
            TextField("输入 ISBN 号", text: $draft.isbn)
                .isbnTextFieldBehavior()

            HStack {
                Button {
                    Task {
                        await lookupISBN()
                    }
                } label: {
                    if isLookingUp {
                        Label("查询中", systemImage: "hourglass")
                    } else {
                        Label("自动补全", systemImage: "magnifyingglass")
                    }
                }
                .disabled(isLookingUp)

                Spacer()

                Button {
                    if ISBNScannerAvailability.isScannerAvailable {
                        isShowingScanner = true
                    } else {
                        alertMessage = "当前设备不支持扫码，请直接输入 ISBN。"
                    }
                } label: {
                    Label("扫码", systemImage: "barcode.viewfinder")
                }
            }

            Text("扫描或输入 ISBN 后，自动补全书名、作者、出版社和年份。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var informationSection: some View {
        Section("图书信息") {
            TextField("书名", text: $draft.title)
            TextField("作者", text: $draft.author)
            TextField("出版社", text: $draft.publisher)
            TextField("出版年份", text: $draft.year)

            Picker("所在地", selection: $draft.location) {
                ForEach(BookLocation.allCases) { location in
                    Text(location.rawValue).tag(location)
                }
            }
        }
    }

    private var coverSection: some View {
        Section("封面") {
            BookCoverPreview(data: draft.coverData, title: draft.title)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label(draft.coverData == nil ? "选择封面" : "更换封面", systemImage: "photo")
            }

            if draft.coverData != nil {
                Button("移除封面", role: .destructive) {
                    selectedPhotoItem = nil
                    draft.coverData = nil
                }
            }
        }
    }

    private var scannerSheet: some View {
        NavigationStack {
            Group {
                if ISBNScannerAvailability.isScannerAvailable {
                    ISBNScannerView { scannedText in
                        handleScan(scannedText)
                    } onFailure: { message in
                        alertMessage = message
                        isShowingScanner = false
                    }
                    .ignoresSafeArea()
                } else {
                    ContentUnavailableView(
                        "当前设备不支持扫码",
                        systemImage: "barcode.viewfinder",
                        description: Text("请直接输入 ISBN。")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        isShowingScanner = false
                    }
                }
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
        } catch {
            alertMessage = "读取封面失败，请换一张图片重试。"
        }
    }

    @MainActor
    private func lookupISBN() async {
        let isbn = ISBNLookupService.normalizeISBN(draft.isbn)

        guard !isbn.isEmpty else {
            alertMessage = "请先输入或扫描 ISBN。"
            return
        }

        isLookingUp = true
        defer { isLookingUp = false }

        do {
            let metadata = try await ISBNLookupService.fetchMetadata(for: isbn)
            draft.isbn = isbn
            draft.title = metadata.title
            draft.author = metadata.author
            draft.publisher = metadata.publisher
            draft.year = metadata.year
        } catch let lookupError as ISBNLookupService.LookupError {
            alertMessage = lookupError.errorDescription
        } catch {
            alertMessage = "外部书籍接口暂时不可用，请稍后重试。"
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
    private func handleScan(_ scannedText: String) {
        let isbn = ISBNLookupService.extractISBN(from: scannedText)

        guard !isbn.isEmpty else {
            alertMessage = "没有识别到有效的 ISBN，请重试。"
            isShowingScanner = false
            return
        }

        draft.isbn = isbn
        isShowingScanner = false

        Task {
            await lookupISBN()
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
                imageView(image)
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

private extension View {
    @ViewBuilder
    func isbnTextFieldBehavior() -> some View {
        #if canImport(UIKit)
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
        #else
        self
        #endif
    }

    @ViewBuilder
    func editorNavigationTitleDisplayMode() -> some View {
        #if canImport(UIKit)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
