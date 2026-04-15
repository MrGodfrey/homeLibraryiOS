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
    @State private var activitySheetItem: ActivitySheetItem?
    @State private var sharingControllerItem: SharingControllerItem?

    var body: some View {
        NavigationStack {
            Form {
                currentRepositorySection
                repositoriesSection

                if store.hasRepository {
                    locationsSection

                    if store.canManageSharing {
                        sharingSection
                    }

                    advancedManagementSection
                } else {
                    createRepositorySection
                }
            }
            .libraryFormChrome()
            .listSectionSpacing(18)
            .tint(LibraryTheme.accent)
            .navigationTitle("仓库设置")
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
            .confirmationDialog("确认清空当前仓库？", isPresented: $isShowingClearConfirmation, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    Task {
                        _ = await store.clearCurrentRepository()
                    }
                }

                Button("取消", role: .cancel) {}
            } message: {
                Text("书籍和地点配置都会重置，当前仓库的缓存也会一起刷新。")
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
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

                    LabeledContent("角色", value: store.repositoryRoleTitle)
                    LabeledContent("数据库", value: store.repositoryScopeTitle)
                    LabeledContent("共享状态", value: store.shareStatusTitle)

                    Text(currentRepository.zoneIDDescription)
                        .font(.footnote.monospaced())
                        .foregroundStyle(LibraryTheme.secondaryText)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            } else {
                Text("当前设备还没有可访问的家庭书库。")
                    .foregroundStyle(LibraryTheme.secondaryText)
            }
        }
        header: {
            sectionHeader("当前仓库")
        }
        .listRowBackground(LibraryTheme.surface)
    }

    private var repositoriesSection: some View {
        Section {
            if store.availableRepositories.isEmpty {
                Text("还没有发现任何可访问仓库。")
                    .foregroundStyle(LibraryTheme.secondaryText)
            } else {
                ForEach(store.availableRepositories) { repository in
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

                            if store.currentRepository?.id == repository.id &&
                                store.currentRepository?.databaseScope == repository.databaseScope {
                                Text("当前")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .foregroundStyle(LibraryTheme.bodyText)
                                    .background(LibraryTheme.surfaceSecondary, in: Capsule())
                            } else {
                                Button("切换") {
                                    Task {
                                        await store.switchRepository(to: repository)
                                    }
                                }
                            }
                        }

                        Text(repository.subtitle)
                            .font(.footnote)
                            .foregroundStyle(LibraryTheme.secondaryText)
                    }
                    .padding(.vertical, 4)
                }
            }

            if !store.hasOwnedRepository {
                Button {
                    Task {
                        _ = await store.createOwnedRepository()
                    }
                } label: {
                    formActionLabel(
                        title: store.isCreatingRepository ? "创建中..." : "创建我的仓库",
                        systemName: "books.vertical",
                        tint: LibraryTheme.accent
                    )
                }
                .disabled(store.isCreatingRepository || store.isImportingLegacyData)
                .accessibilityIdentifier("createOwnedRepositoryButton")
            }
        }
        header: {
            sectionHeader("可访问的仓库")
        }
        .listRowBackground(LibraryTheme.surface)
    }

    private var createRepositorySection: some View {
        Section {
            Text("创建后即可开始录入书籍，并通过系统共享邀请家人加入。")
                .font(.footnote)
                .foregroundStyle(LibraryTheme.secondaryText)

            Button {
                Task {
                    let didCreate = await store.createOwnedRepository()
                    if didCreate {
                        dismiss()
                    }
                }
            } label: {
                formActionLabel(
                    title: store.isCreatingRepository ? "创建中..." : "创建我的仓库",
                    systemName: "books.vertical",
                    tint: LibraryTheme.accent
                )
            }
            .disabled(store.isCreatingRepository || store.isImportingLegacyData)
            .accessibilityIdentifier("createOwnedRepositoryButton")
        }
        header: {
            sectionHeader("创建我的仓库")
        }
        .listRowBackground(LibraryTheme.surface)
    }

    private var locationsSection: some View {
        Section {
            ForEach($draftLocations) { $location in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("地点名称", text: $location.name)

                    HStack {
                        Toggle("显示在首页筛选中", isOn: $location.isVisible)

                        Spacer()

                        locationMoveButton(systemName: "arrow.up", enabled: canMove(location, direction: -1)) {
                            move(location.id, by: -1)
                        }

                        locationMoveButton(systemName: "arrow.down", enabled: canMove(location, direction: 1)) {
                            move(location.id, by: 1)
                        }

                        if draftLocations.count > 1 {
                            Button(role: .destructive) {
                                draftLocations.removeAll { $0.id == location.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                    .font(.footnote)
                }
                .padding(.vertical, 4)
            }

            Button {
                draftLocations.append(
                    LibraryLocation(
                        name: "新地点 \(draftLocations.count + 1)",
                        sortOrder: draftLocations.count
                    )
                )
            } label: {
                formActionLabel(title: "新增地点", systemName: "plus", tint: LibraryTheme.accent)
            }

            Button {
                Task {
                    _ = await store.saveLocations(normalizedDraftLocations())
                }
            } label: {
                formActionLabel(title: "保存地点配置", systemName: "checkmark", tint: LibraryTheme.accent)
            }
            .disabled(draftLocations.isEmpty)
        }
        header: {
            sectionHeader("地点配置")
        }
        .listRowBackground(LibraryTheme.surface)
    }

    private var sharingSection: some View {
        Section {
            Text("通过系统共享把这座家庭书库发给家人，加入和权限管理都交给 Apple ID 完成。")
                .font(.footnote)
                .foregroundStyle(LibraryTheme.secondaryText)

            Button {
                Task {
                    await openSharingController()
                }
            } label: {
                formActionLabel(title: "邀请家人加入", systemName: "person.crop.circle.badge.plus", tint: LibraryTheme.accent)
            }
        }
        header: {
            sectionHeader("共享")
        }
        .listRowBackground(LibraryTheme.surface)
    }

    private var advancedManagementSection: some View {
        Section {
            if let progress = store.importProgress {
                HStack {
                    ProgressView(value: Double(progress.importedCount), total: Double(max(progress.totalCount, 1)))
                    Text(progress.statusText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(LibraryTheme.bodyText)
                }
            }

            Button {
                isShowingLegacyImportPicker = true
            } label: {
                formActionLabel(
                    title: store.isImportingLegacyData ? "导入中..." : "迁移旧数据 JSON",
                    systemName: "square.and.arrow.down",
                    tint: LibraryTheme.accent
                )
            }
            .disabled(store.isCreatingRepository || store.isImportingLegacyData)
            .accessibilityIdentifier("importLegacyJSONButton")

            Button {
                Task {
                    if let url = await store.exportCurrentRepository() {
                        activitySheetItem = ActivitySheetItem(url: url)
                    }
                }
            } label: {
                formActionLabel(title: "导出当前仓库 ZIP", systemName: "square.and.arrow.up", tint: LibraryTheme.accent)
            }
            .accessibilityIdentifier("exportRepositoryButton")

            Button(role: .destructive) {
                isShowingClearConfirmation = true
            } label: {
                formActionLabel(
                    title: "清空当前仓库",
                    systemName: "trash",
                    tint: LibraryTheme.destructive,
                    textColor: LibraryTheme.destructive
                )
            }
            .accessibilityIdentifier("clearRepositoryButton")
        }
        header: {
            sectionHeader("高级管理")
        }
        .listRowBackground(LibraryTheme.surface)
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

    private func syncDraftLocations() {
        draftLocations = store.locations.isEmpty ? LibraryLocation.defaultLocations() : store.locations
    }

    private func normalizedDraftLocations() -> [LibraryLocation] {
        draftLocations
            .enumerated()
            .map { index, location in
                LibraryLocation(
                    id: location.id,
                    name: location.name.trimmed.nilIfEmpty ?? "地点 \(index + 1)",
                    sortOrder: index,
                    isVisible: location.isVisible
                )
            }
    }

    private func canMove(_ location: LibraryLocation, direction: Int) -> Bool {
        guard let index = draftLocations.firstIndex(where: { $0.id == location.id }) else {
            return false
        }

        let targetIndex = index + direction
        return draftLocations.indices.contains(targetIndex)
    }

    private func move(_ locationID: String, by offset: Int) {
        guard let index = draftLocations.firstIndex(where: { $0.id == locationID }) else {
            return
        }

        let targetIndex = index + offset
        guard draftLocations.indices.contains(targetIndex) else {
            return
        }

        let item = draftLocations.remove(at: index)
        draftLocations.insert(item, at: targetIndex)
        draftLocations = normalizedDraftLocations()
    }

    private func locationMoveButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundStyle(enabled ? LibraryTheme.icon : LibraryTheme.tertiaryText)
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
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
