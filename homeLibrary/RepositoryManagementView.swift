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
            .navigationTitle("仓库设置")
            .navigationBarTitleDisplayMode(.inline)
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
        Section("当前仓库") {
            if let currentRepository = store.currentRepository {
                VStack(alignment: .leading, spacing: 8) {
                    Text(currentRepository.name)
                        .font(.headline)

                    LabeledContent("角色", value: store.repositoryRoleTitle)
                    LabeledContent("数据库", value: store.repositoryScopeTitle)
                    LabeledContent("共享状态", value: store.shareStatusTitle)

                    Text(currentRepository.zoneIDDescription)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            } else {
                Text("当前设备还没有可访问的家庭书库。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var repositoriesSection: some View {
        Section("可访问的仓库") {
            if store.availableRepositories.isEmpty {
                Text("还没有发现任何可访问仓库。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.availableRepositories) { repository in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(repository.name)
                                    .font(.body.weight(.semibold))
                                Text("\(repository.role.title) · \(repository.databaseScope.title)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if store.currentRepository?.id == repository.id &&
                                store.currentRepository?.databaseScope == repository.databaseScope {
                                Text("当前")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.primary.opacity(0.1), in: Capsule())
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
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            if !store.hasOwnedRepository {
                Button(store.isCreatingRepository ? "创建中..." : "创建我的仓库") {
                    Task {
                        _ = await store.createOwnedRepository()
                    }
                }
                .disabled(store.isCreatingRepository || store.isImportingLegacyData)
                .accessibilityIdentifier("createOwnedRepositoryButton")
            }
        }
    }

    private var createRepositorySection: some View {
        Section("创建我的仓库") {
            Text("创建后即可开始录入书籍，并通过系统共享邀请家人加入。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(store.isCreatingRepository ? "创建中..." : "创建我的仓库") {
                Task {
                    let didCreate = await store.createOwnedRepository()
                    if didCreate {
                        dismiss()
                    }
                }
            }
            .disabled(store.isCreatingRepository || store.isImportingLegacyData)
            .accessibilityIdentifier("createOwnedRepositoryButton")
        }
    }

    private var locationsSection: some View {
        Section("地点配置") {
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
                Label("新增地点", systemImage: "plus")
            }

            Button("保存地点配置") {
                Task {
                    _ = await store.saveLocations(normalizedDraftLocations())
                }
            }
            .disabled(draftLocations.isEmpty)
        }
    }

    private var sharingSection: some View {
        Section("共享") {
            Text("通过系统共享把这座家庭书库发给家人，加入和权限管理都交给 Apple ID 完成。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("邀请家人加入") {
                Task {
                    await openSharingController()
                }
            }
        }
    }

    private var advancedManagementSection: some View {
        Section("高级管理") {
            if let progress = store.importProgress {
                HStack {
                    ProgressView(value: Double(progress.importedCount), total: Double(max(progress.totalCount, 1)))
                    Text(progress.statusText)
                        .font(.footnote.weight(.semibold))
                }
            }

            Button(store.isImportingLegacyData ? "导入中..." : "迁移旧数据 JSON") {
                isShowingLegacyImportPicker = true
            }
            .disabled(store.isCreatingRepository || store.isImportingLegacyData)
            .accessibilityIdentifier("importLegacyJSONButton")

            Button("导出当前仓库 ZIP") {
                Task {
                    if let url = await store.exportCurrentRepository() {
                        activitySheetItem = ActivitySheetItem(url: url)
                    }
                }
            }
            .accessibilityIdentifier("exportRepositoryButton")

            Button("清空当前仓库", role: .destructive) {
                isShowingClearConfirmation = true
            }
            .accessibilityIdentifier("clearRepositoryButton")
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
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
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
