//
//  LibrarySync.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import Foundation

enum LibrarySyncStatus: Equatable {
    case idle
    case unavailable
    case syncing
    case upToDate(Date)
    case failed(String)

    var label: String {
        switch self {
        case .idle:
            return "等待同步"
        case .unavailable:
            return "云同步未开启"
        case .syncing:
            return "云端同步中"
        case .upToDate(let date):
            return "已同步 \(Self.relativeFormatter.localizedString(for: date, relativeTo: .now))"
        case .failed:
            return "云同步失败"
        }
    }

    var systemImageName: String {
        switch self {
        case .idle:
            return "icloud"
        case .unavailable:
            return "icloud.slash"
        case .syncing:
            return "arrow.triangle.2.circlepath.icloud"
        case .upToDate:
            return "checkmark.icloud"
        case .failed:
            return "exclamationmark.icloud"
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

struct CloudSyncConfiguration: Sendable {
    var isEnabled: Bool
    var overrideRootURL: URL?
    var containerIdentifier: String?

    nonisolated func resolveCloudStore() -> LibraryDiskStore? {
        guard isEnabled else {
            return nil
        }

        if let overrideRootURL {
            return LibraryDiskStore(rootURL: overrideRootURL)
        }

        guard let containerIdentifier,
              let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier)
        else {
            return nil
        }

        let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        return LibraryDiskStore(rootURL: documentsURL.appendingPathComponent("homeLibrarySync", isDirectory: true))
    }
}

struct LibrarySyncResult: Sendable {
    let isCloudAvailable: Bool
    let synchronizedAt: Date?
}

struct LibrarySyncEngine: Sendable {
    let localStore: LibraryDiskStore
    let configuration: CloudSyncConfiguration

    nonisolated func sync() throws -> LibrarySyncResult {
        guard let cloudStore = configuration.resolveCloudStore() else {
            return LibrarySyncResult(isCloudAvailable: false, synchronizedAt: nil)
        }

        try localStore.prepareForUse(allowBundledSeed: false)
        try cloudStore.prepareForUse(allowBundledSeed: false)

        let localSnapshot = try localStore.loadSnapshot()
        let cloudSnapshot = try cloudStore.loadSnapshot()

        try merge(localSnapshot: localSnapshot, cloudSnapshot: cloudSnapshot, localStore: localStore, cloudStore: cloudStore)

        let syncDate = Date()
        try localStore.markSyncSuccess(at: syncDate)
        try cloudStore.markSyncSuccess(at: syncDate)

        return LibrarySyncResult(isCloudAvailable: true, synchronizedAt: syncDate)
    }

    nonisolated private func merge(
        localSnapshot: LibrarySnapshot,
        cloudSnapshot: LibrarySnapshot,
        localStore: LibraryDiskStore,
        cloudStore: LibraryDiskStore
    ) throws {
        let identifiers = Set(localSnapshot.booksByID.keys)
            .union(cloudSnapshot.booksByID.keys)
            .union(localSnapshot.tombstonesByID.keys)
            .union(cloudSnapshot.tombstonesByID.keys)

        for identifier in identifiers.sorted() {
            let localBook = localSnapshot.booksByID[identifier]
            let cloudBook = cloudSnapshot.booksByID[identifier]
            let localDeletion = localSnapshot.tombstonesByID[identifier]
            let cloudDeletion = cloudSnapshot.tombstonesByID[identifier]

            let winningBook = newerBook(localBook, cloudBook)
            let winningDeletion = newerDeletion(localDeletion, cloudDeletion)

            if let winningDeletion, shouldApplyDeletion(winningDeletion, over: winningBook) {
                try localStore.removeBookRecord(for: identifier)
                try cloudStore.removeBookRecord(for: identifier)
                try localStore.writeTombstone(winningDeletion)
                try cloudStore.writeTombstone(winningDeletion)
                continue
            }

            guard let winningBook else {
                continue
            }

            if let assetID = winningBook.coverAssetID {
                try localStore.copyCoverAssetIfNeeded(assetID, from: cloudStore)
                try cloudStore.copyCoverAssetIfNeeded(assetID, from: localStore)
            }

            try localStore.writeBookRecord(winningBook)
            try cloudStore.writeBookRecord(winningBook)
            try localStore.removeTombstone(for: identifier)
            try cloudStore.removeTombstone(for: identifier)
        }

        try localStore.garbageCollectAssets()
        try cloudStore.garbageCollectAssets()
    }

    nonisolated private func newerBook(_ lhs: Book?, _ rhs: Book?) -> Book? {
        switch (lhs, rhs) {
        case (.none, .none):
            return nil
        case let (.some(lhs), .none):
            return lhs
        case let (.none, .some(rhs)):
            return rhs
        case let (.some(lhs), .some(rhs)):
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt ? lhs : rhs
            }

            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt ? lhs : rhs
            }

            return lhs
        }
    }

    nonisolated private func newerDeletion(_ lhs: BookDeletionTombstone?, _ rhs: BookDeletionTombstone?) -> BookDeletionTombstone? {
        switch (lhs, rhs) {
        case (.none, .none):
            return nil
        case let (.some(lhs), .none):
            return lhs
        case let (.none, .some(rhs)):
            return rhs
        case let (.some(lhs), .some(rhs)):
            return lhs.deletedAt >= rhs.deletedAt ? lhs : rhs
        }
    }

    nonisolated private func shouldApplyDeletion(_ deletion: BookDeletionTombstone, over book: Book?) -> Bool {
        guard let book else {
            return true
        }

        return deletion.deletedAt >= book.updatedAt
    }
}
