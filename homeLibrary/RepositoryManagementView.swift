//
//  RepositoryManagementView.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import SwiftUI
import UIKit

struct RepositoryManagementView: View {
    @ObservedObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var joinAccount = ""
    @State private var joinPassword = ""
    @State private var isJoining = false
    @State private var isRegenerating = false

    var body: some View {
        NavigationStack {
            Form {
                currentRepositorySection

                if let credentials = store.repositoryCredentials {
                    ownerCredentialsSection(credentials: credentials)
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

                joinRepositorySection
            }
            .navigationTitle("仓库管理")
            .navigationBarTitleDisplayMode(.inline)
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

    private func ownerCredentialsSection(credentials: RepositoryCredentials) -> some View {
        Section("邀请别人加入") {
            credentialRow(title: "仓库账号", value: credentials.account) {
                UIPasteboard.general.string = credentials.account
            }

            credentialRow(title: "仓库密码", value: credentials.password) {
                UIPasteboard.general.string = credentials.password
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

    private var joinRepositorySection: some View {
        Section("加入别人的仓库") {
            if store.canManageCloudRepository {
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
            } else {
                Text("当前是本地调试模式，没有连接 CloudKit。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
}
