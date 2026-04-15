//
//  LibrarySyncSettings.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import Foundation

nonisolated enum RepositoryRole: String, Codable, Sendable {
    case owner
    case member

    var title: String {
        switch self {
        case .owner:
            return "我的仓库"
        case .member:
            return "加入的仓库"
        }
    }
}

nonisolated struct RepositoryCredentials: Equatable, Codable, Sendable {
    var account: String
    var password: String
}

nonisolated struct LibraryRepositoryReference: Identifiable, Equatable, Codable, Sendable {
    let id: String
    var name: String
    var role: RepositoryRole
    var accessAccount: String?
    var savedPassword: String?

    var isOwner: Bool {
        role == .owner
    }

    var subtitle: String {
        switch role {
        case .owner:
            return "由你的 CloudKit 仓库承载，其他设备可通过仓库账号密码加入。"
        case .member:
            return "你当前正在协作维护别人的仓库。"
        }
    }

    var credentials: RepositoryCredentials? {
        guard let account = accessAccount, let password = savedPassword else {
            return nil
        }

        return RepositoryCredentials(account: account, password: password)
    }

    func updatingRole(_ role: RepositoryRole) -> LibraryRepositoryReference {
        LibraryRepositoryReference(
            id: id,
            name: name,
            role: role,
            accessAccount: accessAccount,
            savedPassword: savedPassword
        )
    }

    func updatingCredentials(_ credentials: RepositoryCredentials?) -> LibraryRepositoryReference {
        LibraryRepositoryReference(
            id: id,
            name: name,
            role: role,
            accessAccount: credentials?.account,
            savedPassword: credentials?.password
        )
    }
}

nonisolated struct LibrarySessionState: Equatable, Codable, Sendable {
    var ownerProfileID: String
    var ownedRepository: LibraryRepositoryReference?
    var currentRepository: LibraryRepositoryReference?

    nonisolated static func makeNew(ownerProfileID: String = UUID().uuidString) -> LibrarySessionState {
        LibrarySessionState(
            ownerProfileID: ownerProfileID,
            ownedRepository: nil,
            currentRepository: nil
        )
    }
}

nonisolated struct RepositorySessionStore: Sendable {
    let namespace: String

    nonisolated init(namespace: String) {
        self.namespace = namespace
    }

    nonisolated func load(userDefaults: UserDefaults = .standard) -> LibrarySessionState {
        let decoder = JSONDecoder()

        if let data = userDefaults.data(forKey: key("session")),
           let state = try? decoder.decode(LibrarySessionState.self, from: data) {
            return state
        }

        return .makeNew(ownerProfileID: loadOrCreateOwnerProfileID(userDefaults: userDefaults))
    }

    nonisolated func save(_ state: LibrarySessionState, userDefaults: UserDefaults = .standard) {
        let encoder = JSONEncoder()

        if let data = try? encoder.encode(state) {
            userDefaults.set(data, forKey: key("session"))
        }

        userDefaults.set(state.ownerProfileID, forKey: key("ownerProfileID"))
    }

    nonisolated func markLegacyMigrationCompleted(
        for repositoryID: String,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(true, forKey: key("migration.\(repositoryID)"))
    }

    nonisolated func hasCompletedLegacyMigration(
        for repositoryID: String,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        userDefaults.bool(forKey: key("migration.\(repositoryID)"))
    }

    nonisolated private func loadOrCreateOwnerProfileID(userDefaults: UserDefaults) -> String {
        if let existingValue = userDefaults.string(forKey: key("ownerProfileID"))?.trimmed.nilIfEmpty {
            return existingValue
        }

        let newValue = UUID().uuidString
        userDefaults.set(newValue, forKey: key("ownerProfileID"))
        return newValue
    }

    nonisolated private func key(_ suffix: String) -> String {
        "homeLibrary.repository.\(namespace).\(suffix)"
    }
}
