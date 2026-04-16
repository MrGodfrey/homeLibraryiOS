//
//  LibraryExportProgressTests.swift
//  homeLibraryTests
//
//  Created by Codex on 2026/4/16.
//

import Foundation
import XCTest
@testable import homeLibrary

final class LibraryExportProgressTests: XCTestCase {
    @MainActor
    func testStoreExportCurrentRepositoryPublishesProgressWhilePreparingZip() async throws {
        let namespace = "store-export-progress-\(UUID().uuidString)"
        let sessionStore = RepositorySessionStore(namespace: namespace)
        let tempRoot = try makeTemporaryDirectory()
        let remoteService = PausedExportLibraryRemoteService()
        let configuration = LibraryAppConfiguration(
            cacheStore: LibraryCacheStore(rootURL: tempRoot.appendingPathComponent("cloudkit-cache", isDirectory: true)),
            legacyImporter: LegacyLibraryImporter(storageRootURL: tempRoot),
            sessionStore: sessionStore,
            remoteService: remoteService,
            preferredOwnedRepositoryName: "我的家庭书库"
        )

        let store = LibraryStore(configuration: configuration)
        let didCreateRepository = await store.createOwnedRepository()
        XCTAssertTrue(didCreateRepository)

        let didSaveBook = await store.saveBook(
            draft: BookDraft(
                title: "导出中的书",
                author: "测试作者",
                publisher: "测试出版社",
                year: "2026",
                locationID: store.defaultLocationID,
                coverData: nil
            ),
            editing: nil
        )
        XCTAssertTrue(didSaveBook)

        let exportTask = Task { await store.exportCurrentRepository() }

        try await waitUntil {
            store.isExportingRepository && store.exportProgress?.phase == .preparing
        }

        let didStartExport = remoteService.hasStartedExport()
        XCTAssertTrue(didStartExport)
        XCTAssertEqual(store.exportProgress?.statusText, "正在读取当前仓库内容...")

        remoteService.resumeExport()

        let exportURL = await exportTask.value
        XCTAssertNotNil(exportURL)
        XCTAssertEqual(exportURL?.pathExtension, "zip")
        XCTAssertFalse(store.isExportingRepository)
        XCTAssertNil(store.exportProgress)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(exportURL).path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if await condition() {
                return
            }

            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("Timed out waiting for condition.")
    }
}

@MainActor
private final class PausedExportLibraryRemoteService: LibraryRemoteSyncing {
    private let base = InMemoryLibraryRemoteService()
    private var exportHasStarted = false
    private var exportContinuation: CheckedContinuation<Void, Never>?

    func hasStartedExport() -> Bool {
        exportHasStarted
    }

    func resumeExport() {
        exportContinuation?.resume()
        exportContinuation = nil
    }

    func listRepositories() async throws -> [LibraryRepositoryReference] {
        try await base.listRepositories()
    }

    func createOwnedRepository(preferredName: String) async throws -> LibraryRepositoryReference {
        try await base.createOwnedRepository(preferredName: preferredName)
    }

    func refreshRepository(_ repository: LibraryRepositoryReference) async throws -> RemoteRepositorySnapshot {
        try await base.refreshRepository(repository)
    }

    func saveLocations(
        _ locations: [LibraryLocation],
        in repository: LibraryRepositoryReference
    ) async throws -> [LibraryLocation] {
        try await base.saveLocations(locations, in: repository)
    }

    func upsertBook(_ book: Book, coverData: Data?, in repository: LibraryRepositoryReference) async throws -> RemoteBookSnapshot {
        try await base.upsertBook(book, coverData: coverData, in: repository)
    }

    func deleteBook(id: String, deletedAt: Date, in repository: LibraryRepositoryReference) async throws {
        try await base.deleteBook(id: id, deletedAt: deletedAt, in: repository)
    }

    func clearRepository(_ repository: LibraryRepositoryReference, resetLocations: [LibraryLocation]) async throws {
        try await base.clearRepository(repository, resetLocations: resetLocations)
    }

    func exportRepository(_ repository: LibraryRepositoryReference) async throws -> LibraryImportPackage {
        exportHasStarted = true

        await withCheckedContinuation { continuation in
            exportContinuation = continuation
        }

        return try await base.exportRepository(repository)
    }

    func deleteRepository(_ repository: LibraryRepositoryReference) async throws {
        try await base.deleteRepository(repository)
    }
}
