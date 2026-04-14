//
//  LibrarySyncSettings.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import Foundation

nonisolated enum SharedLibraryBookmarkAccess {
    #if os(iOS)
    nonisolated static let creationOptions: URL.BookmarkCreationOptions = []
    nonisolated static let resolutionOptions: URL.BookmarkResolutionOptions = []
    #else
    nonisolated static let creationOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
    nonisolated static let resolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #endif
}

nonisolated enum LibrarySyncMode: String, Codable, Sendable {
    case personalCloud
    case sharedFolder
}

nonisolated struct SharedLibraryFolderBookmark: Codable, Equatable, Sendable {
    let displayName: String
    let bookmarkData: Data

    nonisolated static func make(from folderURL: URL) throws -> SharedLibraryFolderBookmark {
        let didStartAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        let resourceValues = try? folderURL.resourceValues(forKeys: [.nameKey])
        let displayName = resourceValues?.name?.trimmed.nilIfEmpty ?? folderURL.lastPathComponent
        let bookmarkData = try folderURL.bookmarkData(
            options: SharedLibraryBookmarkAccess.creationOptions,
            includingResourceValuesForKeys: [.nameKey],
            relativeTo: nil
        )

        return SharedLibraryFolderBookmark(displayName: displayName, bookmarkData: bookmarkData)
    }
}

nonisolated struct LibrarySyncTarget: Equatable, Sendable {
    var mode: LibrarySyncMode
    var sharedFolderBookmark: SharedLibraryFolderBookmark?

    nonisolated static var personalCloud: LibrarySyncTarget {
        LibrarySyncTarget(mode: .personalCloud, sharedFolderBookmark: nil)
    }

    nonisolated var activeSharedFolderBookmark: SharedLibraryFolderBookmark? {
        guard mode == .sharedFolder else {
            return nil
        }

        return sharedFolderBookmark
    }

    nonisolated var usesSharedFolder: Bool {
        activeSharedFolderBookmark != nil
    }

    nonisolated var hasStoredSharedFolder: Bool {
        sharedFolderBookmark != nil
    }

    nonisolated var destinationTitle: String {
        if let activeSharedFolderBookmark {
            return "共享书库 · \(activeSharedFolderBookmark.displayName)"
        }

        return "个人 iCloud"
    }

    nonisolated var destinationSubtitle: String {
        if usesSharedFolder {
            return "把同一个共享文件夹选到其他 Apple ID 设备后，双方会合并到同一套书库。"
        }

        return "当前仍是你自己的 iCloud 容器同步，只会在同一 Apple ID 下互通。"
    }

    nonisolated func switchingToPersonalCloud() -> LibrarySyncTarget {
        LibrarySyncTarget(mode: .personalCloud, sharedFolderBookmark: sharedFolderBookmark)
    }

    nonisolated func switchingToSharedFolder(_ bookmark: SharedLibraryFolderBookmark) -> LibrarySyncTarget {
        LibrarySyncTarget(mode: .sharedFolder, sharedFolderBookmark: bookmark)
    }

    nonisolated func removingSharedFolder() -> LibrarySyncTarget {
        .personalCloud
    }
}

nonisolated struct LibrarySyncSettingsStore: Sendable {
    let namespace: String

    nonisolated init(namespace: String) {
        self.namespace = namespace
    }

    nonisolated func load(userDefaults: UserDefaults = .standard) -> LibrarySyncTarget {
        let mode = LibrarySyncMode(rawValue: userDefaults.string(forKey: key("mode")) ?? "") ?? .personalCloud
        let bookmarkData = userDefaults.data(forKey: key("sharedFolderBookmark"))
        let displayName = userDefaults.string(forKey: key("sharedFolderName"))?.trimmed.nilIfEmpty

        let bookmark = bookmarkData.map {
            SharedLibraryFolderBookmark(
                displayName: displayName ?? "共享书库",
                bookmarkData: $0
            )
        }

        let target = LibrarySyncTarget(mode: mode, sharedFolderBookmark: bookmark)

        if mode == .sharedFolder, bookmark == nil {
            return .personalCloud
        }

        return target
    }

    nonisolated func save(_ target: LibrarySyncTarget, userDefaults: UserDefaults = .standard) {
        userDefaults.set(target.mode.rawValue, forKey: key("mode"))
        userDefaults.set(target.sharedFolderBookmark?.bookmarkData, forKey: key("sharedFolderBookmark"))
        userDefaults.set(target.sharedFolderBookmark?.displayName, forKey: key("sharedFolderName"))
    }

    nonisolated private func key(_ suffix: String) -> String {
        "homeLibrary.sync.\(namespace).\(suffix)"
    }
}

enum SharedLibrarySyncError: LocalizedError {
    case missingSharedFolder
    case cannotAccessFolder(String)

    var errorDescription: String? {
        switch self {
        case .missingSharedFolder:
            return "共享书库文件夹丢失了，请重新选择一次。"
        case .cannotAccessFolder(let name):
            return "无法访问共享书库“\(name)”，请重新选择文件夹并确认系统授权。"
        }
    }
}
