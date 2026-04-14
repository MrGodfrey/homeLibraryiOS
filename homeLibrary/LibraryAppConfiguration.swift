//
//  LibraryAppConfiguration.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import Foundation

struct LibraryAppConfiguration {
    static let defaultCloudContainerIdentifier = "iCloud.yu.homeLibrary"
    static let localDebugNamespace = "local-debug"

    let cacheStore: LibraryCacheStore
    let legacyImporter: LegacyLibraryImporter
    let sessionStore: RepositorySessionStore
    let remoteService: (any LibraryRemoteSyncing)?
    let preferredOwnedRepositoryName: String

    static func live(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LibraryAppConfiguration {
        let cloudSyncEnabled = resolvedCloudSyncEnabled(environment: environment)
        let defaultRoot = defaultApplicationSupportDirectory().appendingPathComponent("homeLibrary", isDirectory: true)
        let defaultStorageNamespace = cloudSyncEnabled ? nil : localDebugNamespace

        let storageRootURL: URL
        if let overrideRoot = environment["HOME_LIBRARY_STORAGE_ROOT"]?.nilIfEmpty {
            storageRootURL = URL(fileURLWithPath: overrideRoot, isDirectory: true)
        } else if let namespace = environment["HOME_LIBRARY_STORAGE_NAMESPACE"]?.nilIfEmpty ?? defaultStorageNamespace {
            storageRootURL = defaultRoot.appendingPathComponent(namespace, isDirectory: true)
        } else {
            storageRootURL = defaultRoot
        }

        let sessionNamespace = environment["HOME_LIBRARY_SESSION_NAMESPACE"]?.nilIfEmpty ??
            environment["HOME_LIBRARY_STORAGE_NAMESPACE"]?.nilIfEmpty ??
            defaultStorageNamespace ??
            "default"
        let containerIdentifier = environment["HOME_LIBRARY_CLOUDKIT_CONTAINER"]?.nilIfEmpty ??
            defaultCloudContainerIdentifier

        return LibraryAppConfiguration(
            cacheStore: LibraryCacheStore(rootURL: storageRootURL.appendingPathComponent("cloudkit-cache", isDirectory: true)),
            legacyImporter: LegacyLibraryImporter(
                storageRootURL: storageRootURL,
                bundleResourceURL: bundle.resourceURL
            ),
            sessionStore: RepositorySessionStore(namespace: sessionNamespace),
            remoteService: cloudSyncEnabled ? CloudKitLibraryService(containerIdentifier: containerIdentifier) : nil,
            preferredOwnedRepositoryName: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ??
                "我的家庭书库"
        )
    }

    static func resolvedCloudSyncEnabled(environment: [String: String]) -> Bool {
        if environment["XCTestConfigurationFilePath"] != nil {
            return false
        }

        if environment["HOME_LIBRARY_ENABLE_CLOUD_SYNC"] == "1" {
            return true
        }

        if environment["HOME_LIBRARY_DISABLE_CLOUD_SYNC"] == "1" {
            return false
        }

        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    private static func defaultApplicationSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ??
            FileManager.default.temporaryDirectory
    }
}
