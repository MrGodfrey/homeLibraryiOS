//
//  LibraryAppConfiguration.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import Foundation

enum LibraryEnvironment {
    nonisolated(unsafe) private static let testRunnerPrefix = "TEST_RUNNER_"

    nonisolated static func resolved(_ environment: [String: String]) -> [String: String] {
        var resolvedEnvironment = environment

        for (key, value) in environment where key.hasPrefix(testRunnerPrefix) {
            let strippedKey = String(key.dropFirst(testRunnerPrefix.count))
            if resolvedEnvironment[strippedKey] == nil {
                resolvedEnvironment[strippedKey] = value
            }
        }

        return resolvedEnvironment
    }

    nonisolated static func value(for key: String, in environment: [String: String]) -> String? {
        environment[key] ?? environment["\(testRunnerPrefix)\(key)"]
    }
}

struct LibraryAppConfiguration {
    static let defaultCloudContainerIdentifier = "iCloud.yu.homeLibrary"

    let cacheStore: LibraryCacheStore
    let legacyImporter: LegacyLibraryImporter
    let sessionStore: RepositorySessionStore
    let remoteService: any LibraryRemoteSyncing
    let preferredOwnedRepositoryName: String

    static func live(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LibraryAppConfiguration {
        let environment = LibraryEnvironment.resolved(environment)
        let defaultRoot = defaultApplicationSupportDirectory().appendingPathComponent("homeLibrary", isDirectory: true)
        let storageNamespace = environment["HOME_LIBRARY_STORAGE_NAMESPACE"]?.nilIfEmpty

        let storageRootURL: URL
        if let overrideRoot = environment["HOME_LIBRARY_STORAGE_ROOT"]?.nilIfEmpty {
            storageRootURL = URL(fileURLWithPath: overrideRoot, isDirectory: true)
        } else if let storageNamespace {
            storageRootURL = defaultRoot.appendingPathComponent(storageNamespace, isDirectory: true)
        } else {
            storageRootURL = defaultRoot
        }

        let sessionNamespace = environment["HOME_LIBRARY_SESSION_NAMESPACE"]?.nilIfEmpty ??
            storageNamespace ??
            "default"
        let containerIdentifier = environment["HOME_LIBRARY_CLOUDKIT_CONTAINER"]?.nilIfEmpty ??
            defaultCloudContainerIdentifier
        let preferredOwnedRepositoryName = environment["HOME_LIBRARY_PREFERRED_REPOSITORY_NAME"]?.nilIfEmpty ??
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ??
            "我的家庭书库"
        return LibraryAppConfiguration(
            cacheStore: LibraryCacheStore(rootURL: storageRootURL.appendingPathComponent("cloudkit-cache", isDirectory: true)),
            legacyImporter: LegacyLibraryImporter(storageRootURL: storageRootURL),
            sessionStore: RepositorySessionStore(namespace: sessionNamespace),
            remoteService: makeRemoteService(
                environment: environment,
                containerIdentifier: containerIdentifier
            ),
            preferredOwnedRepositoryName: preferredOwnedRepositoryName
        )
    }

    private static func makeRemoteService(
        environment: [String: String],
        containerIdentifier: String?
    ) -> any LibraryRemoteSyncing {
        if environment["HOME_LIBRARY_REMOTE_DRIVER"]?.lowercased() == "cloudkit" {
            return CloudKitLibraryService(
                containerIdentifier: containerIdentifier,
                environment: environment
            )
        }

        if environment["HOME_LIBRARY_REMOTE_DRIVER"]?.lowercased() == "memory" ||
            environment["XCTestConfigurationFilePath"] != nil {
            return InMemoryLibraryRemoteService()
        }

        return CloudKitLibraryService(
            containerIdentifier: containerIdentifier,
            environment: environment
        )
    }

    private static func defaultApplicationSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ??
            FileManager.default.temporaryDirectory
    }
}
