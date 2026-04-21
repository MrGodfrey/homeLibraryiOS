//
//  RepositoryManagementView.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct RepositoryManagementView: View {
    @ObservedObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var draftLocations: [LibraryLocation] = []
    @State private var isShowingLegacyImportPicker = false
    @State private var isShowingClearConfirmation = false
    @State private var isShowingCoverCompressionConfirmation = false
    @State private var activitySheetItem: ActivitySheetItem?
    @State private var sharingControllerItem: SharingControllerItem?
    @State private var incomingShareLink = ""
    @State private var pendingLocationSaveTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                currentRepositorySection
                repositoriesSection

                if store.hasRepository {
                    sortingSection
                    locationsSection

                    if store.canManageSharing || store.canAcceptShareLinks {
                        sharingSection
                    }

                    advancedManagementSection
                } else {
                    createRepositorySection

                    if store.canAcceptShareLinks {
                        sharingSection
                    }
                }
            }
            .libraryFormChrome()
            .listSectionSpacing(18)
            .tint(LibraryTheme.accent)
            .navigationTitle(localized("仓库设置", en: "Library Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(LibraryTheme.background, for: .navigationBar)
            .fileImporter(
                isPresented: $isShowingLegacyImportPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleLegacyImportSelection(result)
            }
            .confirmationDialog(localized("确认清空当前仓库？", en: "Clear the current library?"), isPresented: $isShowingClearConfirmation, titleVisibility: .visible) {
                Button(localized("清空", en: "Clear"), role: .destructive) {
                    Task {
                        _ = await store.clearCurrentRepository()
                    }
                }

                Button(localized("取消", en: "Cancel"), role: .cancel) {}
            } message: {
                Text(localized("书籍和地点配置都会重置，当前仓库的缓存也会一起刷新。", en: "Books, location settings, and the local cache for this library will all be reset."))
            }
            .alert(localized("确认整理当前仓库封面？", en: "Optimize covers in the current library?"), isPresented: $isShowingCoverCompressionConfirmation) {
                Button(localized("取消", en: "Cancel"), role: .cancel) {}
                Button(localized("确认整理", en: "Optimize"), role: .destructive) {
                    Task {
                        _ = await store.compressOversizedCoversInCurrentRepository()
                    }
                }
            } message: {
                Text(localized("此操作会替换所有的封面。", en: "This action will replace every cover image."))
            }
            .sheet(item: $activitySheetItem) { item in
                ActivityView(activityItems: [item.url])
            }
            .sheet(item: $sharingControllerItem) { item in
                CloudSharingControllerContainer(controller: item.controller)
            }
            .onAppear {
                syncDraftLocations()
            }
            .onChange(of: store.locations) {
                syncDraftLocations()
            }
            .onDisappear {
                scheduleLocationSave(immediately: true)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("关闭", en: "Close")) {
                        Task {
                            guard await persistLocationChangesIfNeeded() else {
                                return
                            }
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("repositorySettingsCloseButton")
                }
            }
        }
        .overlay {
            if let progress = store.exportProgress {
                exportProgressOverlay(progress)
            }
        }
    }

    private var currentRepositorySection: some View {
        Section {
            if let currentRepository = store.currentRepository {
                VStack(alignment: .leading, spacing: 8) {
                    Text(currentRepository.name)
                        .font(.headline)
                        .foregroundStyle(LibraryTheme.title)

                    LabeledContent(localized("角色", en: "Role"), value: store.repositoryRoleTitle)
                    LabeledContent(localized("数据库", en: "Database"), value: store.repositoryScopeTitle)
                    LabeledContent(localized("共享状态", en: "Sharing"), value: store.shareStatusTitle)
                }
                .padding(.vertical, 4)
            } else {
                Text(localized("当前设备还没有可访问的家庭书库。", en: "There is no accessible family library on this device yet."))
                    .foregroundStyle(LibraryTheme.secondaryText)
            }
        }
        header: {
            sectionHeader(localized("当前仓库", en: "Current Library"))
        }
        .listRowBackground(LibraryTheme.surface)
    }

    private var sortingSection: some View {
        Section {
            Picker(
                localized("图书排序方式", en: "Book Sort Order"),
                selection: Binding(
                    get: { store.bookSortOrder },
                    set: { store.setBookSortOrder($0) }
                )
            ) {
                ForEach(LibraryBookSortOrder.allCases) { sortOrder in
                    Text(sortOrder.title)
                        .tag(sortOrder)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("bookSortPicker")
        }
        header: {
            sectionHeader(localized("图书排序", en: "Book Sorting"))
        }
        .listRowBackground(LibraryTheme.surface)
    }

    private var repositoriesSection: some View {
        Section {
            if store.availableRepositories.isEmpty {
                Text(localized("还没有发现任何可访问仓库。", en: "No accessible libraries have been found yet."))
                    .foregroundStyle(LibraryTheme.secondaryText)
            } else {
                ForEach(store.availableRepositories) { repository in
                    repositoryRow(for: repository)
                }
            }

            if !store.hasOwnedRepository {
                Button {
                    Task {
                        guard await persistLocationChangesIfNeeded() else {
                            return
                        }
                        _ = await store.createOwnedRepository()
                    }
                } label: {
                    formActionLabel(
                        title: store.isCreatingRepository ? localized("创建中...", en: "Creating...") : localized("创建我的仓库", en: "Create My Library"),
                        systemName: "books.vertical",
                        tint: LibraryTheme.accent
                    )
                }
                .disabled(store.isCreatingRepository || store.isImportingLegacyData)
                .buttonStyle(RepositoryManagementActionButtonStyle())
                .accessibilityIdentifier("createOwnedRepositoryButton")
            }
        }
        header: {
            sectionHeader(localized("可访问的仓库", en: "Accessible Libraries"))
        }
        .listRowBackground(LibraryTheme.surface)
    }

    private var createRepositorySection: some View {
        Section {
            Text(localized("创建后即可开始录入书籍，并通过系统共享邀请家人加入。", en: "Once created, you can start adding books and invite family members with system sharing."))
                .font(.footnote)
                .foregroundStyle(LibraryTheme.secondaryText)

            Button {
                Task {
                    guard await persistLocationChangesIfNeeded() else {
                        return
                    }
                    let didCreate = await store.createOwnedRepository()
                    if didCreate {
                        dismiss()
                    }
                }
            } label: {
                formActionLabel(
                    title: store.isCreatingRepository ? localized("创建中...", en: "Creating...") : localized("创建我的仓库", en: "Create My Library"),
                    systemName: "books.vertical",
                    tint: LibraryTheme.accent
                )
            }
            .disabled(store.isCreatingRepository || store.isImportingLegacyData)
            .buttonStyle(RepositoryManagementActionButtonStyle())
            .accessibilityIdentifier("createOwnedRepositoryButton")
        }
        header: {
            sectionHeader(localized("创建我的仓库", en: "Create My Library"))
        }
        .listRowBackground(LibraryTheme.surface)
    }

    private var locationsSection: some View {
        Section {
            ForEach(draftLocations) { location in
                locationRow(for: location)
                    .moveDisabled(draftLocations.count < 2)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if draftLocations.count > 1 {
                            Button(role: .destructive) {
                                removeLocation(location.id)
                            } label: {
                                Label(localized("删除", en: "Delete"), systemImage: "trash")
                            }
                        }
                    }
            }
            .onMove(perform: moveLocations)

            Button {
                addLocation()
            } label: {
                formActionLabel(title: localized("新增地点", en: "Add Location"), systemName: "plus", tint: LibraryTheme.accent)
            }
            .buttonStyle(RepositoryManagementActionButtonStyle())
            .accessibilityIdentifier("addLocationButton")
        }
        header: {
            sectionHeader(localized("地点配置", en: "Location Settings"))
        } footer: {
            Text(localized("拖动右侧把手调整顺序，修改后会自动保存。", en: "Drag the handle on the right to reorder. Changes save automatically."))
        }
        .listRowBackground(LibraryTheme.surface)
        .environment(\.editMode, .constant(.active))
    }

    private var sharingSection: some View {
        Section {
            if store.canManageSharing {
                Text(localized("通过系统共享把这座家庭书库发给家人，加入和权限管理都交给 Apple ID 完成。", en: "Share this family library with the system share flow. Joining and permissions are handled through Apple ID."))
                    .font(.footnote)
                    .foregroundStyle(LibraryTheme.secondaryText)

                Button {
                    Task {
                        await openSharingController()
                    }
                } label: {
                    formActionLabel(title: localized("邀请家人加入", en: "Invite Family Members"), systemName: "person.crop.circle.badge.plus", tint: LibraryTheme.accent)
                }
                .buttonStyle(RepositoryManagementActionButtonStyle())
            }

            if store.canAcceptShareLinks {
                VStack(alignment: .leading, spacing: 12) {
                    Text(localized("如果系统邀请没有自动打开共享仓库，可以把 iCloud 共享链接粘贴到这里手动处理。首先，你需要在“邀请家人加入”中通过 Message（最好是通过 iMessage）发送邀请，这样才能够打开这个仓库，否则这个仓库会显示不存在。", en: "If the system invite does not open the shared library automatically, paste the iCloud share link here to handle it manually. First send the invitation from “Invite Family Members” through Messages, preferably iMessage, or the library may appear unavailable."))
                        .font(.footnote)
                        .foregroundStyle(LibraryTheme.secondaryText)

                    TextField(localized("https://www.icloud.com/share/...", en: "https://www.icloud.com/share/..."), text: $incomingShareLink, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                        .foregroundStyle(LibraryTheme.bodyText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(LibraryTheme.surfaceSecondary)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(LibraryTheme.stroke, lineWidth: 1)
                        }
                        .accessibilityIdentifier("shareLinkTextField")

                    if store.isAcceptingShareLink {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(LibraryTheme.accent)

                            Text(localized("正在处理共享链接…", en: "Processing share link..."))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(LibraryTheme.bodyText)
                        }
                    }

                    HStack(spacing: 12) {
                        Button(localized("粘贴剪贴板", en: "Paste from Clipboard")) {
                            pasteShareLinkFromClipboard()
                        }
                        .disabled(store.isAcceptingShareLink)

                        Button {
                            Task {
                                let didAccept = await store.acceptShareLink(incomingShareLink)
                                if didAccept {
                                    incomingShareLink = ""
                                    dismiss()
                                }
                            }
                        } label: {
                            Text(store.isAcceptingShareLink ? localized("处理中...", en: "Processing...") : localized("打开共享仓库", en: "Open Shared Library"))
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(LibraryTheme.accent)
                        .disabled(incomingShareLink.trimmed.isEmpty || store.isAcceptingShareLink)
                        .accessibilityIdentifier("acceptShareLinkButton")
                    }
                }
            }
        }
        header: {
            sectionHeader(localized("共享", en: "Sharing"))
        }
        .listRowBackground(LibraryTheme.surface)
    }

    private var advancedManagementSection: some View {
        Section {
            if let progress = store.coverCompressionProgress {
                managementStatusText(progress.statusText)
            }

            if let progress = store.importProgress {
                managementStatusText(progress.statusText)
            }

            Button {
                isShowingCoverCompressionConfirmation = true
            } label: {
                formActionLabel(
                    title: store.isCompressingCovers ?
                        localized("整理中...", en: "Optimizing...") :
                        localized("整理当前仓库封面", en: "Optimize Current Library Covers"),
                    systemName: "arrow.triangle.2.circlepath",
                    tint: LibraryTheme.accent
                )
            }
            .disabled(store.isCreatingRepository || store.isImportingLegacyData || store.isCompressingCovers)
            .buttonStyle(RepositoryManagementActionButtonStyle())
            .accessibilityIdentifier("compressRepositoryCoversButton")

            Button {
                isShowingLegacyImportPicker = true
            } label: {
                formActionLabel(
                    title: store.isImportingLegacyData ? localized("导入中...", en: "Importing...") : localized("迁移旧数据 JSON", en: "Import Legacy JSON"),
                    systemName: "square.and.arrow.down",
                    tint: LibraryTheme.accent
                )
            }
            .disabled(store.isCreatingRepository || store.isImportingLegacyData)
            .buttonStyle(RepositoryManagementActionButtonStyle())
            .accessibilityIdentifier("importLegacyJSONButton")

            Button {
                Task {
                    if let url = await store.exportCurrentRepository() {
                        activitySheetItem = ActivitySheetItem(url: url)
                    }
                }
            } label: {
                formActionLabel(
                    title: store.isExportingRepository ? localized("导出中...", en: "Exporting...") : localized("导出当前仓库 ZIP", en: "Export Current Library ZIP"),
                    systemName: "square.and.arrow.up",
                    tint: LibraryTheme.accent
                )
            }
            .disabled(store.isExportingRepository)
            .buttonStyle(RepositoryManagementActionButtonStyle())
            .accessibilityIdentifier("exportRepositoryButton")

            Button(role: .destructive) {
                isShowingClearConfirmation = true
            } label: {
                formActionLabel(
                    title: localized("清空当前仓库", en: "Clear Current Library"),
                    systemName: "trash",
                    tint: LibraryTheme.destructive,
                    textColor: LibraryTheme.destructive
                )
            }
            .buttonStyle(RepositoryManagementActionButtonStyle())
            .accessibilityIdentifier("clearRepositoryButton")
        }
        header: {
            sectionHeader(localized("高级管理", en: "Advanced Management"))
        }
        .listRowBackground(LibraryTheme.surface)
    }

    private func managementStatusText(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(LibraryTheme.bodyText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("repositoryManagementStatusText")
    }

    private func exportProgressOverlay(_ progress: RepositoryExportProgress) -> some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text(localized("正在导出当前仓库", en: "Exporting Current Library"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(LibraryTheme.title)

                Text(localized("请稍候，导出完成后会自动打开系统共享。", en: "Please wait. The system share sheet will open automatically when export finishes."))
                    .font(.footnote)
                    .foregroundStyle(LibraryTheme.secondaryText)

                ProgressView(value: progress.progressValue, total: 1)
                    .tint(LibraryTheme.accent)
                    .accessibilityIdentifier("repositoryExportProgressBar")

                Text(progress.statusText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(LibraryTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("repositoryExportProgressText")
            }
            .padding(20)
            .frame(maxWidth: 320, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LibraryTheme.surface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(LibraryTheme.stroke, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 10)
            .padding(.horizontal, 24)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("repositoryExportProgressOverlay")
        }
    }

    private func repositoryRow(for repository: LibraryRepositoryReference) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repository.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(LibraryTheme.title)
                    Text("\(repository.role.title) · \(repository.databaseScope.title)")
                        .font(.footnote)
                        .foregroundStyle(LibraryTheme.secondaryText)
                }

                Spacer()

                if store.isCurrentRepository(repository) {
                    Text(localized("当前", en: "Current"))
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(LibraryTheme.bodyText)
                        .background(LibraryTheme.surfaceSecondary, in: Capsule())
                } else {
                    Button(localized("切换", en: "Switch")) {
                        Task {
                            guard await persistLocationChangesIfNeeded() else {
                                return
                            }
                            await store.switchRepository(to: repository)
                        }
                    }
                }
            }

            if !store.isCurrentRepository(repository) {
                Text(repository.subtitle)
                    .font(.footnote)
                    .foregroundStyle(LibraryTheme.secondaryText)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if store.canRemoveRepository(repository) {
                Button(role: .destructive) {
                    Task {
                        _ = await store.removeRepository(repository)
                    }
                } label: {
                    Label(localized("删除", en: "Delete"), systemImage: "trash")
                }
            }
        }
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

    private func pasteShareLinkFromClipboard() {
        if let url = UIPasteboard.general.url {
            incomingShareLink = url.absoluteString
            return
        }

        if let string = UIPasteboard.general.string?.trimmed.nilIfEmpty {
            incomingShareLink = string
            return
        }

        store.alertMessage = localized("剪贴板里没有可用的共享链接。", en: "There is no usable share link on the clipboard.")
    }

    private func syncDraftLocations() {
        draftLocations = store.locations.isEmpty ? LibraryLocation.defaultLocations() : store.locations
    }

    private func locationRow(for location: LibraryLocation) -> some View {
        let locationBinding = draftLocationBinding(for: location)
        return VStack(alignment: .leading, spacing: 10) {
            TextField(localized("地点名称", en: "Location Name"), text: locationBinding.name)
                .accessibilityIdentifier("locationNameField-\(location.id)")

            Toggle(localized("显示在首页筛选中", en: "Show in Home Filters"), isOn: locationBinding.isVisible)
                .font(.footnote)
                .accessibilityIdentifier("locationVisibilityToggle-\(location.id)")
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("locationRow-\(location.id)")
    }

    private func draftLocationBinding(for location: LibraryLocation) -> Binding<LibraryLocation> {
        // Repository switches replace the whole locations array. Keep this binding ID-based so
        // SwiftUI does not hold on to a stale array index while the Toggle is reconciling.
        Binding(
            get: {
                draftLocations.first(where: { $0.id == location.id }) ?? location
            },
            set: { updatedLocation in
                guard let index = draftLocations.firstIndex(where: { $0.id == location.id }) else {
                    return
                }

                draftLocations[index] = updatedLocation
                scheduleLocationSave()
            }
        )
    }

    private func normalizedDraftLocations() -> [LibraryLocation] {
        draftLocations
            .enumerated()
            .map { index, location in
                LibraryLocation(
                    id: location.id,
                    name: location.name.trimmed.nilIfEmpty ?? localized("地点 %d", en: "Location %d", arguments: [index + 1]),
                    sortOrder: index,
                    isVisible: location.isVisible
                )
            }
    }

    private func addLocation() {
        draftLocations.append(
            LibraryLocation(
                name: localized("新地点 %d", en: "New Location %d", arguments: [draftLocations.count + 1]),
                sortOrder: draftLocations.count
            )
        )
        draftLocations = normalizedDraftLocations()
        scheduleLocationSave(immediately: true)
    }

    private func removeLocation(_ locationID: String) {
        guard draftLocations.count > 1 else {
            return
        }

        draftLocations.removeAll { $0.id == locationID }
        draftLocations = normalizedDraftLocations()
        scheduleLocationSave(immediately: true)
    }

    private func moveLocations(from source: IndexSet, to destination: Int) {
        draftLocations.move(fromOffsets: source, toOffset: destination)
        draftLocations = normalizedDraftLocations()
        scheduleLocationSave(immediately: true)
    }

    private func scheduleLocationSave(immediately: Bool = false) {
        pendingLocationSaveTask?.cancel()
        guard store.currentRepository != nil else {
            return
        }

        let pendingLocations = normalizedDraftLocations()
        guard pendingLocations != store.locations else {
            return
        }

        pendingLocationSaveTask = Task { @MainActor in
            if !immediately {
                try? await Task.sleep(for: .milliseconds(350))
            }

            guard !Task.isCancelled else {
                return
            }

            let latestLocations = normalizedDraftLocations()
            guard latestLocations != store.locations else {
                return
            }

            _ = await store.saveLocations(latestLocations)
        }
    }

    @MainActor
    private func persistLocationChangesIfNeeded() async -> Bool {
        pendingLocationSaveTask?.cancel()
        guard store.currentRepository != nil else {
            return true
        }

        let latestLocations = normalizedDraftLocations()
        guard latestLocations != store.locations else {
            return true
        }

        return await store.saveLocations(latestLocations)
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

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    @MainActor
    private func openSharingController() async {
        do {
            let controller = try await store.makeSharingControllerForCurrentRepository()
            sharingControllerItem = SharingControllerItem(controller: controller)
        } catch {
            store.alertMessage = LibraryStore.userFacingMessage(for: error)
        }
    }
}

private struct ActivitySheetItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct RepositoryManagementActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? LibraryTheme.surfaceSecondary : Color.clear)
            )
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct SharingControllerItem: Identifiable {
    let id = UUID()
    let controller: UICloudSharingController
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct CloudSharingControllerContainer: UIViewControllerRepresentable {
    let controller: UICloudSharingController

    func makeUIViewController(context: Context) -> UICloudSharingController {
        controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}
}
