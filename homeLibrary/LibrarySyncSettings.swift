//
//  LibrarySyncSettings.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import Foundation

enum LibraryLanguage: String, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"
}

enum LibraryLocalization {
    nonisolated(unsafe) static var overrideLanguage: LibraryLanguage?

    static var currentLanguage: LibraryLanguage {
        if let overrideLanguage {
            return overrideLanguage
        }

        return resolvedLanguage()
    }

    static func text(_ chinese: String, en english: String) -> String {
        switch currentLanguage {
        case .simplifiedChinese:
            return chinese
        case .english:
            return english
        }
    }

    static func format(_ chinese: String, en english: String, arguments: [CVarArg]) -> String {
        String(
            format: text(chinese, en: english),
            locale: locale(for: currentLanguage),
            arguments: arguments
        )
    }

    private static func resolvedLanguage(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults = .standard,
        locale: Locale = .autoupdatingCurrent
    ) -> LibraryLanguage {
        if let configuredLanguage = environment["HOME_LIBRARY_LOCALE"],
           let language = language(for: configuredLanguage) {
            return language
        }

        if environment["XCTestConfigurationFilePath"] != nil {
            return .simplifiedChinese
        }

        let preferredLanguages = userDefaults.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
        for identifier in preferredLanguages {
            if let language = language(for: identifier) {
                return language
            }
        }

        return language(for: locale.identifier) ?? .simplifiedChinese
    }

    private static func language(for rawValue: String) -> LibraryLanguage? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        if normalized.hasPrefix("en") {
            return .english
        }

        if normalized.hasPrefix("zh") {
            return .simplifiedChinese
        }

        return nil
    }

    private static func locale(for language: LibraryLanguage) -> Locale {
        switch language {
        case .simplifiedChinese:
            return Locale(identifier: "zh_Hans_CN")
        case .english:
            return Locale(identifier: "en_US")
        }
    }
}

@inline(__always)
func localized(_ chinese: String, en english: String) -> String {
    LibraryLocalization.text(chinese, en: english)
}

@inline(__always)
func localized(_ chinese: String, en english: String, arguments: [CVarArg]) -> String {
    LibraryLocalization.format(chinese, en: english, arguments: arguments)
}

nonisolated enum RepositoryRole: String, Codable, Sendable {
    case owner
    case member

    var title: String {
        switch self {
        case .owner:
            return localized("我的仓库", en: "My Library")
        case .member:
            return localized("共享仓库", en: "Shared Library")
        }
    }
}

nonisolated enum CloudDatabaseScope: String, Codable, Sendable {
    case `private`
    case shared

    var title: String {
        switch self {
        case .private:
            return localized("私人数据库", en: "Private Database")
        case .shared:
            return localized("共享数据库", en: "Shared Database")
        }
    }
}

nonisolated enum RepositoryShareStatus: String, Codable, Sendable {
    case notShared
    case shared

    var title: String {
        switch self {
        case .notShared:
            return localized("尚未共享", en: "Not Shared")
        case .shared:
            return localized("已开启共享", en: "Shared")
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
            return localized(
                "书库保存在你的 iCloud 私人数据库中，可通过系统共享邀请家人加入。",
                en: "This library is stored in your private iCloud database. You can invite family members with system sharing."
            )
        case (.member, .shared):
            return localized("这是别人共享给你的家庭书库。", en: "This family library was shared with you by someone else.")
        case (.owner, .shared):
            return localized("你正在查看一座已共享的书库。", en: "You are viewing a library that has already been shared.")
        case (.member, .private):
            return localized("这是当前设备保存的私人仓库。", en: "This is a private library stored on the current device.")
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

nonisolated struct RemoteRepositoryChangeSet: Sendable {
    let repository: LibraryRepositoryReference
    let locations: [LibraryLocation]
    let deletedLocationIDs: [String]
    let books: [RemoteBookSnapshot]
    let deletedBookIDs: [String]
    let changeTokenData: Data?
    let isFullRefresh: Bool
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
            return localized("正在统计导入内容...", en: "Counting import items...")
        case .importing:
            return localized("已导入 %d / %d", en: "Imported %d / %d", arguments: [importedCount, totalCount])
        case .completed:
            return localized("导入完成，共 %d 本", en: "Import complete, %d books", arguments: [totalCount])
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
            return localized("正在读取当前仓库内容...", en: "Reading current library...")
        case .encoding:
            if let bookCount {
                return localized(
                    "正在整理 %d 本书与封面...",
                    en: "Preparing %d books and covers...",
                    arguments: [bookCount]
                )
            }

            return localized("正在整理导出内容...", en: "Preparing export...")
        case .archiving:
            return localized("正在生成 ZIP 文件...", en: "Creating ZIP archive...")
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
