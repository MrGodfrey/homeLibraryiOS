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
            return "共享仓库"
        }
    }
}

nonisolated enum CloudDatabaseScope: String, Codable, Sendable {
    case `private`
    case shared

    var title: String {
        switch self {
        case .private:
            return "私人数据库"
        case .shared:
            return "共享数据库"
        }
    }
}

nonisolated enum RepositoryShareStatus: String, Codable, Sendable {
    case notShared
    case shared

    var title: String {
        switch self {
        case .notShared:
            return "尚未共享"
        case .shared:
            return "已开启共享"
        }
    }
}

nonisolated struct LibraryRepositoryReference: Identifiable, Equatable, Codable, Sendable {
    let id: String
    var name: String
    var role: RepositoryRole
    var databaseScope: CloudDatabaseScope
    var zoneName: String
    var zoneOwnerName: String
    var shareRecordName: String?
    var shareStatus: RepositoryShareStatus

    var subtitle: String {
        switch (role, databaseScope) {
        case (.owner, .private):
            return "书库保存在你的 iCloud 私人数据库中，可通过系统共享邀请家人加入。"
        case (.member, .shared):
            return "这是别人共享给你的家庭书库。"
        case (.owner, .shared):
            return "你正在查看一座已共享的书库。"
        case (.member, .private):
            return "这是当前设备保存的私人仓库。"
        }
    }

    var zoneIDDescription: String {
        "\(zoneOwnerName)/\(zoneName)"
    }

    var isOwner: Bool {
        role == .owner
    }

    var persistenceID: String {
        "\(databaseScope.rawValue):\(id)"
    }
}

nonisolated struct RemoteRepositorySnapshot: Sendable {
    let repository: LibraryRepositoryReference
    let locations: [LibraryLocation]
    let books: [RemoteBookSnapshot]
}

nonisolated struct LibrarySessionState: Equatable, Codable, Sendable {
    var currentRepository: LibraryRepositoryReference?
    var bookSortOrderByRepositoryID: [String: LibraryBookSortOrder]

    private enum CodingKeys: String, CodingKey {
        case currentRepository
        case bookSortOrderByRepositoryID
    }

    init(
        currentRepository: LibraryRepositoryReference?,
        bookSortOrderByRepositoryID: [String: LibraryBookSortOrder] = [:]
    ) {
        self.currentRepository = currentRepository
        self.bookSortOrderByRepositoryID = bookSortOrderByRepositoryID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentRepository = try container.decodeIfPresent(LibraryRepositoryReference.self, forKey: .currentRepository)
        bookSortOrderByRepositoryID = try container.decodeIfPresent(
            [String: LibraryBookSortOrder].self,
            forKey: .bookSortOrderByRepositoryID
        ) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(currentRepository, forKey: .currentRepository)
        try container.encode(bookSortOrderByRepositoryID, forKey: .bookSortOrderByRepositoryID)
    }

    nonisolated static func makeNew() -> LibrarySessionState {
        LibrarySessionState(currentRepository: nil)
    }

    func bookSortOrder(for repository: LibraryRepositoryReference?) -> LibraryBookSortOrder {
        guard let repository else {
            return .defaultValue
        }

        return bookSortOrderByRepositoryID[repository.persistenceID] ?? .defaultValue
    }

    mutating func setBookSortOrder(_ sortOrder: LibraryBookSortOrder, for repository: LibraryRepositoryReference) {
        bookSortOrderByRepositoryID[repository.persistenceID] = sortOrder
    }

    mutating func removeBookSortOrder(for repository: LibraryRepositoryReference) {
        bookSortOrderByRepositoryID[repository.persistenceID] = nil
    }
}

nonisolated struct RepositoryImportProgress: Equatable, Sendable {
    enum Phase: String, Equatable, Sendable {
        case counting
        case importing
        case completed
    }

    let phase: Phase
    let totalCount: Int
    let importedCount: Int

    var statusText: String {
        switch phase {
        case .counting:
            return "正在统计导入内容..."
        case .importing:
            return "已导入 \(importedCount) / \(totalCount)"
        case .completed:
            return "导入完成，共 \(totalCount) 本"
        }
    }
}

nonisolated struct RepositoryExportProgress: Equatable, Sendable {
    enum Phase: String, Equatable, Sendable {
        case preparing
        case encoding
        case archiving
    }

    let phase: Phase
    let bookCount: Int?

    var progressValue: Double {
        switch phase {
        case .preparing:
            return 0.2
        case .encoding:
            return 0.62
        case .archiving:
            return 0.9
        }
    }

    var statusText: String {
        switch phase {
        case .preparing:
            return "正在读取当前仓库内容..."
        case .encoding:
            if let bookCount {
                return "正在整理 \(bookCount) 本书与封面..."
            }

            return "正在整理导出内容..."
        case .archiving:
            return "正在生成 ZIP 文件..."
        }
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

        return .makeNew()
    }

    nonisolated func save(_ state: LibrarySessionState, userDefaults: UserDefaults = .standard) {
        let encoder = JSONEncoder()

        if let data = try? encoder.encode(state) {
            userDefaults.set(data, forKey: key("session"))
        }
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

    nonisolated private func key(_ suffix: String) -> String {
        "homeLibrary.repository.\(namespace).\(suffix)"
    }
}
