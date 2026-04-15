//
//  CloudKitLiveIntegrationTests.swift
//  homeLibraryTests
//
//  Created by Codex on 2026/4/15.
//

import CloudKit
import XCTest
@testable import homeLibrary

final class CloudKitLiveIntegrationTests: XCTestCase {
    private var service: CloudKitLibraryService!
    private var createdRepositories: [LibraryRepositoryReference] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        let environment = LibraryEnvironment.resolved(ProcessInfo.processInfo.environment)

        guard environment["HOME_LIBRARY_CLOUDKIT_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Set HOME_LIBRARY_CLOUDKIT_LIVE_TESTS=1 to run live CloudKit integration tests.")
        }

        service = CloudKitLibraryService(
            containerIdentifier: LibraryAppConfiguration.defaultCloudContainerIdentifier,
            environment: environment
        )
    }

    override func tearDownWithError() throws {
        let repositories = createdRepositories
        createdRepositories = []

        if !repositories.isEmpty {
            let expectation = expectation(description: "Cleanup live CloudKit repositories")
            Task {
                for repository in repositories {
                    try? await service.deleteRepository(repository)
                }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 30)
        }

        try super.tearDownWithError()
    }

    func testCreateWriteRefreshExportAndClearRepository() async throws {
        let repository = try await service.createOwnedRepository(preferredName: "LIVE TEST \(UUID().uuidString.prefix(8))")
        createdRepositories.append(repository)

        let repositories = try await service.listRepositories()
        XCTAssertTrue(repositories.contains(where: { $0.id == repository.id && $0.databaseScope == .private }))

        let draftBook = Book(
            id: UUID().uuidString,
            title: "真实 CloudKit 测试",
            author: "Codex",
            publisher: "OpenAI",
            year: "2026",
            locationID: LibraryLocation.defaultLocations()[0].id
        )

        _ = try await service.upsertBook(draftBook, coverData: nil, in: repository)
        let snapshot = try await service.refreshRepository(repository)
        XCTAssertEqual(snapshot.locations.map(\.name), ["成都", "重庆"])
        XCTAssertEqual(snapshot.books.count, 1)
        XCTAssertEqual(snapshot.books.first?.book.title, "真实 CloudKit 测试")

        let exportPackage = try await service.exportRepository(repository)
        XCTAssertEqual(exportPackage.books.count, 1)
        XCTAssertEqual(exportPackage.locations.count, 2)

        try await service.clearRepository(repository, resetLocations: LibraryLocation.defaultLocations())
        let clearedSnapshot = try await service.refreshRepository(repository)
        XCTAssertEqual(clearedSnapshot.books.count, 0)
        XCTAssertEqual(clearedSnapshot.locations.map(\.name), ["成都", "重庆"])
    }
}
