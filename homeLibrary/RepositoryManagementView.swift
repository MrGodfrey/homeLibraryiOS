//
//  RepositoryManagementView.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RepositoryManagementView: View {
    @ObservedObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var joinAccount = ""
    @State private var joinPassword = ""
    @State private var isJoining = false
    @State private var isRegenerating = false
    @State private var isShowingLegacyImportPicker = false

    var body: some View {
        NavigationStack {
            Form {
                currentRepositorySection

                if store.hasOwnedRepository {
                    ownerAccessSection
                } else {
                    createOwnedRepositorySection
                }

                if store.canSwitchToOwnedRepository {
                    Section {
                        Button("切回我的仓库") {
                            Task {
                                await store.switchToOwnedRepository()
                                dismiss()
                            }
                        }
                        .accessibilityIdentifier("switchToOwnedRepositoryButton")
                    }
                }

                legacyMigrationSection
                joinRepositorySection
            }
            .navigationTitle("仓库管理")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $isShowingLegacyImportPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleLegacyImportSelection(result)
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
            VStack(alignment: .leading, spacing: 8) {
                Text(store.repositoryTitle)
                    .font(.headline)

                Text(store.repositoryRoleTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)

                Text(store.repositorySubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    private var ownerAccessSection: some View {
        Section("邀请别人加入") {
            if let credentials = store.repositoryCredentials {
                credentialRow(title: "仓库账号", value: credentials.account) {
                    UIPasteboard.general.string = credentials.account
                }

                credentialRow(title: "仓库密码", value: credentials.password) {
                    UIPasteboard.general.string = credentials.password
                }
            } else {
                Text("当前设备还没有保存这座仓库的加入密码。你可以重新生成一组新的账号密码。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button(isRegenerating ? "生成中..." : "重新生成账号密码") {
                Task {
                    isRegenerating = true
                    defer { isRegenerating = false }
                    _ = await store.regenerateOwnedRepositoryCredentials()
                }
            }
            .disabled(isRegenerating)
            .accessibilityIdentifier("regenerateRepositoryCredentialsButton")
        }
    }

    private var createOwnedRepositorySection: some View {
        Section("创建我的仓库") {
            Text("当前 iCloud 账号下还没有自己的仓库。创建后，你可以直接录入书籍，或者把旧 JSON 迁移进来。")
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

    private var legacyMigrationSection: some View {
        Section("迁移旧数据") {
            Text("选择旧版导出的 JSON 文件后，应用会把里面的书籍自动导入到我的仓库；如果当前还没有自己的仓库，会先创建。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(store.isImportingLegacyData ? "导入中..." : "选择旧数据 JSON") {
                isShowingLegacyImportPicker = true
            }
            .disabled(store.isCreatingRepository || store.isImportingLegacyData)
            .accessibilityIdentifier("importLegacyJSONButton")
        }
    }

    private var joinRepositorySection: some View {
        Section("加入别人的仓库") {
            TextField("仓库账号", text: $joinAccount)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("joinRepositoryAccountField")

            SecureField("仓库密码", text: $joinPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("joinRepositoryPasswordField")

            Button(isJoining ? "加入中..." : "加入仓库") {
                Task {
                    isJoining = true
                    defer { isJoining = false }

                    let didJoin = await store.joinRepository(account: joinAccount, password: joinPassword)

                    if didJoin {
                        dismiss()
                    }
                }
            }
            .disabled(isJoining || joinAccount.trimmed.isEmpty || joinPassword.trimmed.isEmpty)
            .accessibilityIdentifier("joinRepositoryButton")
        }
    }

    private func credentialRow(title: String, value: String, copyAction: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }

            Spacer()

            Button("复制", action: copyAction)
        }
    }

    private func handleLegacyImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                return
            }

            Task {
                let didImport = await store.importLegacyJSON(from: url)

                if didImport {
                    dismiss()
                }
            }
        case .failure(let error):
            store.alertMessage = LibraryStore.userFacingMessage(for: error)
        }
    }
}
