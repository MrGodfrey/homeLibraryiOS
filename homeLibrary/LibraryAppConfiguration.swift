//
//  LibraryAppConfiguration.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import Foundation

nonisolated struct LibraryAppConfiguration: Sendable {
    nonisolated static let defaultCloudContainerIdentifier = "iCloud.yu.homeLibrary"

    let localStore: LibraryDiskStore
    let legacyBooksURL: URL?
    let bundledSeedURL: URL?
    let allowBundledSeed: Bool
    let initialSyncTarget: LibrarySyncTarget
    let syncSettingsStore: LibrarySyncSettingsStore
    let cloudSyncConfiguration: CloudSyncConfiguration

    nonisolated static func live(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> LibraryAppConfiguration {
        let environment = processInfo.environment
        let defaultRoot = defaultApplicationSupportDirectory().appendingPathComponent("homeLibrary", isDirectory: true)

        let localRootURL: URL
        if let overrideRoot = environment["HOME_LIBRARY_STORAGE_ROOT"]?.nilIfEmpty {
            localRootURL = URL(fileURLWithPath: overrideRoot, isDirectory: true)
        } else if let namespace = environment["HOME_LIBRARY_STORAGE_NAMESPACE"]?.nilIfEmpty {
            localRootURL = defaultRoot.appendingPathComponent(namespace, isDirectory: true)
        } else {
            localRootURL = defaultRoot
        }

        let legacyBooksURL: URL?
        if let overrideLegacyBooksURL = environment["HOME_LIBRARY_LEGACY_BOOKS_FILE"]?.nilIfEmpty {
            legacyBooksURL = URL(fileURLWithPath: overrideLegacyBooksURL)
        } else {
            legacyBooksURL = localRootURL.appendingPathComponent("books.json")
        }

        let cloudRootOverrideURL = environment["HOME_LIBRARY_CLOUD_ROOT"]?.nilIfEmpty.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }

        let cloudSyncEnabled = environment["HOME_LIBRARY_DISABLE_CLOUD_SYNC"] != "1"
        let allowBundledSeed = environment["HOME_LIBRARY_DISABLE_BUNDLED_SEED"] != "1"
        let syncNamespace = environment["HOME_LIBRARY_SYNC_NAMESPACE"]?.nilIfEmpty ??
            environment["HOME_LIBRARY_STORAGE_NAMESPACE"]?.nilIfEmpty ??
            "default"
        let syncSettingsStore = LibrarySyncSettingsStore(namespace: syncNamespace)
        let initialSyncTarget = syncSettingsStore.load()

        return LibraryAppConfiguration(
            localStore: LibraryDiskStore(rootURL: localRootURL),
            legacyBooksURL: legacyBooksURL,
            bundledSeedURL: bundle.url(forResource: "SeedBooks", withExtension: "json"),
            allowBundledSeed: allowBundledSeed,
            initialSyncTarget: initialSyncTarget,
            syncSettingsStore: syncSettingsStore,
            cloudSyncConfiguration: CloudSyncConfiguration(
                isEnabled: cloudSyncEnabled,
                overrideRootURL: cloudRootOverrideURL,
                containerIdentifier: defaultCloudContainerIdentifier,
                syncTarget: initialSyncTarget
            )
        )
    }

    nonisolated private static func defaultApplicationSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ??
            fallbackDirectory()
    }

    nonisolated private static func fallbackDirectory() -> URL {
        #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser
        #else
        FileManager.default.temporaryDirectory
        #endif
    }
}
