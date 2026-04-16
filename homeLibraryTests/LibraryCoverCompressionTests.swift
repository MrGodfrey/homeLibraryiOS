//
//  LibraryCoverCompressionTests.swift
//  homeLibraryTests
//
//  Created by Codex on 2026/4/16.
//

import Foundation
import UIKit
import XCTest
@testable import homeLibrary

final class LibraryCoverCompressionTests: XCTestCase {

    func testCoverCompressorDownsamplesOversizedImage() throws {
        let oversizedCoverData = try makeOversizedCoverData()

        let result = LibraryCoverCompressor.compressIfNeeded(oversizedCoverData)

        XCTAssertTrue(result.didCompress)
        XCTAssertEqual(result.originalSize?.width, 1600)
        XCTAssertEqual(result.originalSize?.height, 2400)
        XCTAssertLessThanOrEqual(
            try XCTUnwrap(result.outputSize).longestEdge,
            LibraryCoverCompressor.thumbnailMaxPixelSize
        )
    }

    func testCoverCompressorKeepsSmallImageUntouched() throws {
        let smallCoverData = try makeCoverData(size: CGSize(width: 240, height: 360))

        let result = LibraryCoverCompressor.compressIfNeeded(smallCoverData)

        XCTAssertFalse(result.didCompress)
        XCTAssertEqual(result.data, smallCoverData)
        XCTAssertEqual(result.outputSize, LibraryCoverImageSize(width: 240, height: 360))
    }

    @MainActor
    func testStoreSaveBookCompressesOversizedCover() async throws {
        let namespace = "store-cover-save-\(UUID().uuidString)"
        let sessionStore = RepositorySessionStore(namespace: namespace)
        let tempRoot = try makeTemporaryDirectory()
        let remoteService = InMemoryLibraryRemoteService()
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

        let oversizedCoverData = try makeOversizedCoverData()
        let didSave = await store.saveBook(
            draft: BookDraft(
                title: "大封面测试",
                author: "测试作者",
                publisher: "测试出版社",
                year: "2026",
                locationID: store.defaultLocationID,
                coverData: oversizedCoverData
            ),
            editing: nil
        )

        XCTAssertTrue(didSave)

        let savedBook = try XCTUnwrap(store.books.first)
        let savedCoverData = try XCTUnwrap(store.coverDataSynchronously(for: savedBook.coverAssetID))

        XCTAssertNotEqual(savedCoverData, oversizedCoverData)
        XCTAssertLessThanOrEqual(
            try pixelSize(for: savedCoverData).longestEdge,
            LibraryCoverCompressor.thumbnailMaxPixelSize
        )
    }

    @MainActor
    func testStoreRepositoryCleanupCompressesExistingOversizedCoversAndTracksProgress() async throws {
        let namespace = "store-cover-cleanup-\(UUID().uuidString)"
        let sessionStore = RepositorySessionStore(namespace: namespace)
        let tempRoot = try makeTemporaryDirectory()
        let remoteService = InMemoryLibraryRemoteService()
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

        let repository = try XCTUnwrap(store.currentRepository)
        let createdAt = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 200)
        let oversizedCoverData = try makeOversizedCoverData()
        let oversizedBook = Book(
            id: "oversized-cover",
            title: "历史大封面",
            author: "测试作者",
            publisher: "测试出版社",
            year: "2025",
            locationID: store.defaultLocationID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        _ = try await remoteService.upsertBook(oversizedBook, coverData: oversizedCoverData, in: repository)
        await store.loadBooks(force: true)

        let originalBook = try XCTUnwrap(store.books.first)
        let originalAssetID = try XCTUnwrap(originalBook.coverAssetID)

        let didCompressRepositoryCovers = await store.compressOversizedCoversInCurrentRepository()
        XCTAssertTrue(didCompressRepositoryCovers)

        let progress = try XCTUnwrap(store.coverCompressionProgress)
        XCTAssertEqual(progress.phase, .completed)
        XCTAssertEqual(progress.totalCount, 1)
        XCTAssertEqual(progress.processedCount, 1)
        XCTAssertEqual(progress.compressedCount, 1)

        let compressedBook = try XCTUnwrap(store.books.first)
        let compressedAssetID = try XCTUnwrap(compressedBook.coverAssetID)
        let compressedCoverData = try XCTUnwrap(store.coverDataSynchronously(for: compressedAssetID))

        XCTAssertEqual(compressedBook.updatedAt, updatedAt)
        XCTAssertNotEqual(compressedAssetID, originalAssetID)
        XCTAssertLessThanOrEqual(
            try pixelSize(for: compressedCoverData).longestEdge,
            LibraryCoverCompressor.thumbnailMaxPixelSize
        )
    }

    private func pixelSize(for data: Data) throws -> LibraryCoverImageSize {
        let image = try XCTUnwrap(UIImage(data: data))
        return LibraryCoverImageSize(
            width: Int(image.size.width.rounded()),
            height: Int(image.size.height.rounded())
        )
    }

    private func makeOversizedCoverData() throws -> Data {
        try makeCoverData(size: CGSize(width: 1600, height: 2400))
    }

    private func makeCoverData(size: CGSize) throws -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            for column in stride(from: 0, to: Int(size.width), by: 24) {
                UIColor(
                    hue: CGFloat((column * 19) % 360) / 360,
                    saturation: 0.65,
                    brightness: 0.88,
                    alpha: 1
                ).setFill()
                context.fill(CGRect(x: CGFloat(column), y: 0, width: 12, height: size.height))
            }

            for row in stride(from: 0, to: Int(size.height), by: 36) {
                UIColor(
                    hue: CGFloat((row * 11) % 360) / 360,
                    saturation: 0.4,
                    brightness: 0.7,
                    alpha: 0.85
                ).setFill()
                context.fill(CGRect(x: 0, y: CGFloat(row), width: size.width, height: 18))
            }
        }

        return try XCTUnwrap(image.pngData())
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
