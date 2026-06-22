import AppKit
import CloudKit
import XCTest
@testable import HomeLibraryCloudKitCore

final class HomeLibraryCloudKitTests: XCTestCase {
    func testPatchDecodingAndSchemaVersion() throws {
        let fixture = try makeFixture()
        let patch = makeCreatePatch(repository: fixture.repository, cover: makeCoverPayload())
        let data = try encode(patch)
        let decoded = try HomeLibraryJSONCodec.makeDecoder().decode(LibraryAIPatch.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.operations.first?.clientOperationID, "op-create")

        var wrongSchema = patch
        wrongSchema.schemaVersion = 99
        let result = LibraryAIPatchValidator.validate(patch: wrongSchema, patchData: try encode(wrongSchema), snapshot: fixture.snapshot)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.errors.contains(where: { $0.contains("schemaVersion") }))
    }

    func testCloudKitRecordNamePrefixParsingPreservesDomainIDs() {
        XCTAssertEqual(
            CloudKitLibraryRemote.idFromPrefixedRecordName("location.location.aiworkflow", prefix: "location."),
            "location.aiworkflow"
        )
        XCTAssertEqual(
            CloudKitLibraryRemote.idFromPrefixedRecordName("book.book-custom-id", prefix: "book."),
            "book-custom-id"
        )
    }

    func testTargetRepositoryOperationCountAndPatchSizeValidation() throws {
        let fixture = try makeFixture()
        var patch = makeCreatePatch(repository: fixture.repository, cover: makeCoverPayload())
        patch.targetRepository.id = "other"
        var result = LibraryAIPatchValidator.validate(patch: patch, patchData: try encode(patch), snapshot: fixture.snapshot)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.errors.contains(where: { $0.contains("target repository") }))

        patch = makeCreatePatch(repository: fixture.repository, cover: makeCoverPayload())
        patch.operations = Array(repeating: patch.operations[0], count: PatchRules.maxOperations + 1)
        result = LibraryAIPatchValidator.validate(patch: patch, patchData: try encode(patch), snapshot: fixture.snapshot)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.errors.contains(where: { $0.contains("too many operations") }))

        result = LibraryAIPatchValidator.validate(
            patch: makeCreatePatch(repository: fixture.repository, cover: makeCoverPayload()),
            patchData: Data(repeating: 1, count: PatchRules.maxPatchByteCount + 1),
            snapshot: fixture.snapshot
        )
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.errors.contains(where: { $0.contains("too large") }))
    }

    func testISBNLocationDuplicateAndSimilarTitleValidation() throws {
        let fixture = try makeFixture()

        var invalidISBN = makeCreatePatch(repository: fixture.repository, cover: makeCoverPayload(), isbn: "9780132350880")
        var result = LibraryAIPatchValidator.validate(patch: invalidISBN, patchData: try encode(invalidISBN), snapshot: fixture.snapshot)
        XCTAssertEqual(result.operations.first?.status, .failed)

        invalidISBN.operations = [
            .createBook(CreateBookOperation(
                clientOperationID: "op-create",
                fields: PatchBookFields(title: "新书", isbn: "9780132350884", locationID: "missing"),
                cover: makeCoverPayload()
            ))
        ]
        result = LibraryAIPatchValidator.validate(patch: invalidISBN, patchData: try encode(invalidISBN), snapshot: fixture.snapshot)
        XCTAssertEqual(result.operations.first?.status, .failed)

        let duplicateISBN = makeCreatePatch(repository: fixture.repository, cover: makeCoverPayload(), isbn: "9780132350884")
        result = LibraryAIPatchValidator.validate(patch: duplicateISBN, patchData: try encode(duplicateISBN), snapshot: fixture.snapshot)
        XCTAssertEqual(result.operations.first?.status, .skipped)

        let similarTitle = makeCreatePatch(repository: fixture.repository, cover: makeCoverPayload(), title: "Clean Code", isbn: nil)
        result = LibraryAIPatchValidator.validate(patch: similarTitle, patchData: try encode(similarTitle), snapshot: fixture.snapshot)
        XCTAssertEqual(result.operations.first?.status, .needsReview)
        XCTAssertTrue(result.operations.first?.risks.contains("similar title") == true)
    }

    func testFieldModesExpectedUpdatedAtAndRecordChangeTag() throws {
        let fixture = try makeFixture()
        let book = fixture.snapshot.books[0].book

        let fillEmpty = makeUpdatePatch(
            repository: fixture.repository,
            bookID: book.id,
            expectedUpdatedAt: book.updatedAt,
            expectedRecordChangeTag: "tag-1",
            fields: ["publisher": PatchFieldUpdate(mode: .fillIfEmpty, value: "New Publisher")]
        )
        var result = LibraryAIPatchValidator.validate(patch: fillEmpty, patchData: try encode(fillEmpty), snapshot: fixture.snapshot)
        XCTAssertEqual(result.operations.first?.status, .skipped)

        let replace = makeUpdatePatch(
            repository: fixture.repository,
            bookID: book.id,
            expectedUpdatedAt: book.updatedAt,
            expectedRecordChangeTag: "tag-1",
            fields: ["publisher": PatchFieldUpdate(mode: .replaceIfCurrentValue, expectedValue: "Prentice Hall", value: "Pearson")]
        )
        result = LibraryAIPatchValidator.validate(patch: replace, patchData: try encode(replace), snapshot: fixture.snapshot)
        XCTAssertEqual(result.operations.first?.status, .needsReview)
        XCTAssertTrue(result.operations.first?.risks.contains("replace non-empty field") == true)

        let updatedAtConflict = makeUpdatePatch(
            repository: fixture.repository,
            bookID: book.id,
            expectedUpdatedAt: Date(timeIntervalSince1970: 1),
            expectedRecordChangeTag: "tag-1",
            fields: ["year": PatchFieldUpdate(mode: .replaceIfCurrentValue, expectedValue: "2008", value: "2009")]
        )
        result = LibraryAIPatchValidator.validate(patch: updatedAtConflict, patchData: try encode(updatedAtConflict), snapshot: fixture.snapshot)
        XCTAssertEqual(result.operations.first?.status, .conflict)

        let tagConflict = makeUpdatePatch(
            repository: fixture.repository,
            bookID: book.id,
            expectedUpdatedAt: book.updatedAt,
            expectedRecordChangeTag: "stale-tag",
            fields: ["year": PatchFieldUpdate(mode: .replaceIfCurrentValue, expectedValue: "2008", value: "2009")]
        )
        result = LibraryAIPatchValidator.validate(patch: tagConflict, patchData: try encode(tagConflict), snapshot: fixture.snapshot)
        XCTAssertEqual(result.operations.first?.status, .conflict)
    }

    func testCoverDecodeCompressionAssetIDAndDestructiveReviewRules() throws {
        let fixture = try makeFixture(includeCover: false)
        let coverPayload = makeCoverPayload(width: 1200, height: 1800)
        let prepared = try PatchRules.prepareCover(coverPayload)
        XCTAssertLessThanOrEqual(prepared.outputSize?.longestEdge ?? 0, LibraryCoverCompressor.thumbnailMaxPixelSize)
        XCTAssertEqual(prepared.assetID, HomeLibraryHash.coverAssetID(for: prepared.data))

        let coverPatch = LibraryAIPatch(
            source: "test",
            createdAt: .now,
            targetRepository: AITargetRepository(id: fixture.repository.id, databaseScope: .private),
            operations: [
                .updateBookCover(UpdateBookCoverOperation(
                    clientOperationID: "op-cover",
                    id: fixture.snapshot.books[0].book.id,
                    expectedUpdatedAt: fixture.snapshot.books[0].book.updatedAt,
                    expectedRecordChangeTag: "tag-1",
                    cover: coverPayload
                ))
            ]
        )
        var result = LibraryAIPatchValidator.validate(patch: coverPatch, patchData: try encode(coverPatch), snapshot: fixture.snapshot)
        XCTAssertEqual(result.operations.first?.status, .valid)
        XCTAssertEqual(result.operations.first?.candidateCoverAssetID, prepared.assetID)

        let withCover = try makeFixture(includeCover: true)
        let removePatch = LibraryAIPatch(
            source: "test",
            createdAt: .now,
            targetRepository: AITargetRepository(id: withCover.repository.id, databaseScope: .private),
            operations: [
                .removeBookCover(RemoveBookCoverOperation(
                    clientOperationID: "op-remove-cover",
                    id: withCover.snapshot.books[0].book.id,
                    expectedUpdatedAt: withCover.snapshot.books[0].book.updatedAt,
                    expectedRecordChangeTag: "tag-1",
                    expectedCurrentCoverAssetID: withCover.snapshot.books[0].book.coverAssetID!,
                    reason: "wrong-cover"
                )),
                .deleteBook(DeleteBookOperation(
                    clientOperationID: "op-delete",
                    id: withCover.snapshot.books[0].book.id,
                    expectedUpdatedAt: withCover.snapshot.books[0].book.updatedAt,
                    expectedRecordChangeTag: "tag-1",
                    reason: "duplicate"
                ))
            ]
        )
        result = LibraryAIPatchValidator.validate(patch: removePatch, patchData: try encode(removePatch), snapshot: withCover.snapshot)
        XCTAssertEqual(result.needsReviewCount, 2)
        XCTAssertTrue(result.operations.allSatisfy(\.requiresApproval))

        let replaceWithoutExpected = LibraryAIPatch(
            source: "test",
            createdAt: .now,
            targetRepository: AITargetRepository(id: withCover.repository.id, databaseScope: .private),
            operations: [
                .updateBookCover(UpdateBookCoverOperation(
                    clientOperationID: "op-replace-cover-missing-expected",
                    id: withCover.snapshot.books[0].book.id,
                    expectedUpdatedAt: withCover.snapshot.books[0].book.updatedAt,
                    expectedRecordChangeTag: "tag-1",
                    cover: coverPayload
                ))
            ]
        )
        result = LibraryAIPatchValidator.validate(
            patch: replaceWithoutExpected,
            patchData: try encode(replaceWithoutExpected),
            snapshot: withCover.snapshot
        )
        XCTAssertEqual(result.operations.first?.status, .skipped)

        let replaceWithExpected = LibraryAIPatch(
            source: "test",
            createdAt: .now,
            targetRepository: AITargetRepository(id: withCover.repository.id, databaseScope: .private),
            operations: [
                .updateBookCover(UpdateBookCoverOperation(
                    clientOperationID: "op-replace-cover",
                    id: withCover.snapshot.books[0].book.id,
                    expectedUpdatedAt: withCover.snapshot.books[0].book.updatedAt,
                    expectedRecordChangeTag: "tag-1",
                    expectedCurrentCoverAssetID: withCover.snapshot.books[0].book.coverAssetID,
                    cover: coverPayload
                ))
            ]
        )
        result = LibraryAIPatchValidator.validate(
            patch: replaceWithExpected,
            patchData: try encode(replaceWithExpected),
            snapshot: withCover.snapshot
        )
        XCTAssertEqual(result.operations.first?.status, .needsReview)
        XCTAssertTrue(result.operations.first?.risks.contains("replace existing cover") == true)
    }

    func testMemoryRemoteApplyFullWorkflowAndResultEncoding() async throws {
        let remote = InMemoryLibraryRemote()
        let repository = try await remote.createOwnedRepository(preferredName: "AIWorkflowTest-Memory")
        let createPatch = makeCreatePatch(repository: repository, cover: makeCoverPayload())
        let createData = try encode(createPatch)
        let createResult = try await LibraryAIPatchApplier.apply(
            patch: createPatch,
            patchData: createData,
            reviewDecision: nil,
            remote: remote,
            repository: repository
        )
        XCTAssertEqual(createResult.appliedCount, 1)
        XCTAssertNoThrow(try HomeLibraryJSONCodec.makeEncoder().encode(createResult))

        var snapshot = try await remote.refreshRepository(repository)
        let createdBook = try XCTUnwrap(snapshot.books.first)
        XCTAssertNotNil(createdBook.book.coverAssetID)
        XCTAssertNotNil(createdBook.coverData)

        let updatePatch = makeUpdatePatch(
            repository: repository,
            bookID: createdBook.book.id,
            expectedUpdatedAt: createdBook.book.updatedAt,
            expectedRecordChangeTag: createdBook.recordChangeTag,
            fields: ["publisher": PatchFieldUpdate(mode: .fillIfEmpty, value: "Pearson")]
        )
        let updateResult = try await LibraryAIPatchApplier.apply(
            patch: updatePatch,
            patchData: try encode(updatePatch),
            reviewDecision: nil,
            remote: remote,
            repository: repository
        )
        XCTAssertEqual(updateResult.appliedCount, 1)

        snapshot = try await remote.refreshRepository(repository)
        let updatedBook = try XCTUnwrap(snapshot.books.first)
        let removePatch = LibraryAIPatch(
            source: "test",
            createdAt: .now,
            targetRepository: AITargetRepository(id: repository.id, databaseScope: .private),
            operations: [
                .removeBookCover(RemoveBookCoverOperation(
                    clientOperationID: "op-remove-cover",
                    id: updatedBook.book.id,
                    expectedUpdatedAt: updatedBook.book.updatedAt,
                    expectedRecordChangeTag: updatedBook.recordChangeTag,
                    expectedCurrentCoverAssetID: updatedBook.book.coverAssetID!,
                    reason: "test"
                ))
            ]
        )
        let removeDecision = ReviewDecision(
            approved: true,
            approvedAt: .now,
            patchDigest: HomeLibraryHash.digestString(for: try encode(removePatch)),
            approvedOperationIDs: ["op-remove-cover"]
        )
        let removeResult = try await LibraryAIPatchApplier.apply(
            patch: removePatch,
            patchData: try encode(removePatch),
            reviewDecision: removeDecision,
            remote: remote,
            repository: repository
        )
        XCTAssertEqual(removeResult.appliedCount, 1)

        snapshot = try await remote.refreshRepository(repository)
        let noCoverBook = try XCTUnwrap(snapshot.books.first)
        XCTAssertNil(noCoverBook.book.coverAssetID)

        let deletePatch = LibraryAIPatch(
            source: "test",
            createdAt: .now,
            targetRepository: AITargetRepository(id: repository.id, databaseScope: .private),
            operations: [
                .deleteBook(DeleteBookOperation(
                    clientOperationID: "op-delete",
                    id: noCoverBook.book.id,
                    expectedUpdatedAt: noCoverBook.book.updatedAt,
                    expectedRecordChangeTag: noCoverBook.recordChangeTag,
                    reason: "test"
                ))
            ]
        )
        let deleteDecision = ReviewDecision(
            approved: true,
            approvedAt: .now,
            patchDigest: HomeLibraryHash.digestString(for: try encode(deletePatch)),
            approvedOperationIDs: ["op-delete"]
        )
        let deleteResult = try await LibraryAIPatchApplier.apply(
            patch: deletePatch,
            patchData: try encode(deletePatch),
            reviewDecision: deleteDecision,
            remote: remote,
            repository: repository
        )
        XCTAssertEqual(deleteResult.appliedCount, 1)
        let afterDeleteSnapshot = try await remote.refreshRepository(repository)
        XCTAssertEqual(afterDeleteSnapshot.books.count, 0)

        let repeatedDelete = try await LibraryAIPatchApplier.apply(
            patch: deletePatch,
            patchData: try encode(deletePatch),
            reviewDecision: deleteDecision,
            remote: remote,
            repository: repository
        )
        XCTAssertEqual(repeatedDelete.skippedCount, 1)
    }

    func testMemoryRemoteConflictAndReviewGate() async throws {
        let fixture = try makeFixture(includeCover: true)
        let remote = InMemoryLibraryRemote()
        await remote.seedRepository(fixture.repository, locations: fixture.snapshot.locations, books: fixture.snapshot.books)
        let book = fixture.snapshot.books[0]
        let deletePatch = LibraryAIPatch(
            source: "test",
            createdAt: .now,
            targetRepository: AITargetRepository(id: fixture.repository.id, databaseScope: .private),
            operations: [
                .deleteBook(DeleteBookOperation(
                    clientOperationID: "op-delete",
                    id: book.book.id,
                    expectedUpdatedAt: book.book.updatedAt,
                    expectedRecordChangeTag: book.recordChangeTag,
                    reason: "duplicate"
                ))
            ]
        )
        var result = try await LibraryAIPatchApplier.apply(
            patch: deletePatch,
            patchData: try encode(deletePatch),
            reviewDecision: nil,
            remote: remote,
            repository: fixture.repository
        )
        XCTAssertEqual(result.skippedCount, 1)

        let stalePatch = makeUpdatePatch(
            repository: fixture.repository,
            bookID: book.book.id,
            expectedUpdatedAt: Date(timeIntervalSince1970: 1),
            expectedRecordChangeTag: book.recordChangeTag,
            fields: ["year": PatchFieldUpdate(mode: .replaceIfCurrentValue, expectedValue: "2008", value: "2009")]
        )
        result = try await LibraryAIPatchApplier.apply(
            patch: stalePatch,
            patchData: try encode(stalePatch),
            reviewDecision: nil,
            remote: remote,
            repository: fixture.repository
        )
        XCTAssertEqual(result.conflictCount, 1)
    }

    func testRetryableCloudKitFailureClassification() async throws {
        let fixture = try makeFixture()
        let patch = makeCreatePatch(repository: fixture.repository, cover: nil, isbn: "9780131103627")
        let patchData = try encode(patch)

        let ckErrorResult = try await LibraryAIPatchApplier.apply(
            patch: patch,
            patchData: patchData,
            reviewDecision: nil,
            remote: FailingRemote(snapshot: fixture.snapshot, error: CKError(.networkUnavailable)),
            repository: fixture.repository
        )

        XCTAssertFalse(ckErrorResult.ok)
        XCTAssertEqual(ckErrorResult.failedCount, 0)
        XCTAssertEqual(ckErrorResult.retryableFailedCount, 1)
        XCTAssertEqual(ckErrorResult.operations.first?.status, .retryableFailed)
        XCTAssertEqual(ckErrorResult.operations.first?.retryable, true)

        let mappedRetryableResult = try await LibraryAIPatchApplier.apply(
            patch: patch,
            patchData: patchData,
            reviewDecision: nil,
            remote: FailingRemote(
                snapshot: fixture.snapshot,
                error: CLIError("CloudKit service is temporarily unavailable", category: .retryableCloudKit)
            ),
            repository: fixture.repository
        )
        XCTAssertEqual(mappedRetryableResult.failedCount, 0)
        XCTAssertEqual(mappedRetryableResult.retryableFailedCount, 1)
        XCTAssertEqual(mappedRetryableResult.operations.first?.status, .retryableFailed)
        XCTAssertEqual(mappedRetryableResult.operations.first?.retryable, true)

        let mappedConflictResult = try await LibraryAIPatchApplier.apply(
            patch: patch,
            patchData: patchData,
            reviewDecision: nil,
            remote: FailingRemote(
                snapshot: fixture.snapshot,
                error: CLIError("CloudKit conflict: server record changed", category: .cloudKitConflict)
            ),
            repository: fixture.repository
        )
        XCTAssertEqual(mappedConflictResult.failedCount, 0)
        XCTAssertEqual(mappedConflictResult.conflictCount, 1)
        XCTAssertEqual(mappedConflictResult.operations.first?.status, .conflict)
    }

    func testCacheSeparationWorkspaceExportAndImportPackageCoverEmbedding() throws {
        let fixture = try makeFixture(includeCover: true)
        let root = temporaryDirectory()
        let cache = LibraryCacheStore(rootURL: root)
        try cache.replaceAllContent(snapshot: fixture.snapshot)

        let bookURL = root
            .appendingPathComponent(fixture.repository.id)
            .appendingPathComponent("books")
            .appendingPathComponent("\(fixture.snapshot.books[0].book.id).json")
        let coverURL = root
            .appendingPathComponent(fixture.repository.id)
            .appendingPathComponent("covers")
            .appendingPathComponent("\(fixture.snapshot.books[0].book.coverAssetID!).bin")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bookURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: coverURL.path))
        XCTAssertFalse(try String(contentsOf: bookURL).contains("coverData"))

        let package = cache.makeImportPackage(snapshot: fixture.snapshot)
        XCTAssertEqual(package.books.first?.coverData, fixture.snapshot.books[0].coverData)

        let workspaceURL = root.appendingPathComponent("AIWorkspace", isDirectory: true)
        let result = try AIWorkspaceExporter.export(snapshot: fixture.snapshot, to: workspaceURL)
        XCTAssertTrue(result.ok)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceURL.appendingPathComponent("LibrarySnapshot.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceURL.appendingPathComponent("PatchSchema.json").path))

        let zipURL = root.appendingPathComponent("AIWorkspace.zip")
        let zipResult = try AIWorkspaceExporter.export(snapshot: fixture.snapshot, to: zipURL)
        XCTAssertTrue(zipResult.ok)
        var isDirectory: ObjCBool = true
        XCTAssertTrue(FileManager.default.fileExists(atPath: zipURL.path, isDirectory: &isDirectory))
        XCTAssertFalse(isDirectory.boolValue)

        let unzipURL = root.appendingPathComponent("UnzippedWorkspace", isDirectory: true)
        try FileManager.default.createDirectory(at: unzipURL, withIntermediateDirectories: true)
        try runProcess("/usr/bin/ditto", arguments: ["-x", "-k", zipURL.path, unzipURL.path])
        for requiredFile in [
            "manifest.json",
            "LibrarySnapshot.json",
            "MissingMetadataReport.json",
            "DuplicateCandidates.json",
            "CoverStatus.json",
            "Locations.json",
            "PatchSchema.json",
            "README.md",
            "LibraryImport.json"
        ] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: unzipURL.appendingPathComponent(requiredFile).path),
                "Expected \(requiredFile) in exported zip"
            )
        }
    }

    func testReviewServerApproveRejectWrongTokenAndTimeout() async throws {
        let fixture = try makeFixture()
        let patch = makeCreatePatch(repository: fixture.repository, cover: makeCoverPayload())
        let patchData = try encode(patch)
        let validation = LibraryAIPatchValidator.validate(patch: patch, patchData: patchData, snapshot: fixture.snapshot)
        let resultURL = temporaryDirectory().appendingPathComponent("ReviewDecision.json")

        let server = PatchReviewServer(
            patch: patch,
            patchData: patchData,
            validation: validation,
            resultURL: resultURL,
            timeoutSeconds: 5,
            token: "token"
        )
        let reviewURL = try server.startForTesting()
        let wrongTokenURL = URL(string: reviewURL.replacingOccurrences(of: "token", with: "bad"))!
        let wrongResponse = try await urlResponse(from: wrongTokenURL)
        XCTAssertEqual(wrongResponse.statusCode, 403)

        let page = try await string(from: URL(string: reviewURL)!)
        XCTAssertTrue(page.contains("Summary"))
        XCTAssertTrue(page.contains("Creates"))
        XCTAssertTrue(page.contains("Raw JSON"))

        let rawJSONURL = URL(string: reviewURL.replacingOccurrences(of: "/review", with: "/raw.json"))!
        let rawJSON = try await string(from: rawJSONURL)
        XCTAssertTrue(rawJSON.contains(#""op" : "createBook""#))

        let destructiveFixture = try makeFixture(includeCover: true)
        let destructiveBook = destructiveFixture.snapshot.books[0]
        let destructivePatch = LibraryAIPatch(
            source: "test",
            createdAt: Date(timeIntervalSince1970: 300),
            targetRepository: AITargetRepository(id: destructiveFixture.repository.id, databaseScope: destructiveFixture.repository.databaseScope),
            operations: [
                .updateBook(UpdateBookOperation(
                    clientOperationID: "op-review-replace-field",
                    id: destructiveBook.book.id,
                    expectedUpdatedAt: destructiveBook.book.updatedAt,
                    expectedRecordChangeTag: destructiveBook.recordChangeTag,
                    confidence: 0.9,
                    fields: [
                        "publisher": PatchFieldUpdate(mode: .replaceIfCurrentValue, expectedValue: "Prentice Hall", value: "Pearson")
                    ]
                )),
                .updateBookCover(UpdateBookCoverOperation(
                    clientOperationID: "op-review-replace-cover",
                    id: destructiveBook.book.id,
                    expectedUpdatedAt: destructiveBook.book.updatedAt,
                    expectedRecordChangeTag: destructiveBook.recordChangeTag,
                    confidence: 0.9,
                    expectedCurrentCoverAssetID: destructiveBook.book.coverAssetID,
                    cover: makeCoverPayload()
                )),
                .deleteBook(DeleteBookOperation(
                    clientOperationID: "op-review-delete",
                    id: destructiveBook.book.id,
                    expectedUpdatedAt: destructiveBook.book.updatedAt,
                    expectedRecordChangeTag: destructiveBook.recordChangeTag,
                    reason: "review page coverage"
                ))
            ]
        )
        let destructivePatchData = try encode(destructivePatch)
        let destructiveValidation = LibraryAIPatchValidator.validate(
            patch: destructivePatch,
            patchData: destructivePatchData,
            snapshot: destructiveFixture.snapshot
        )
        let destructiveServer = PatchReviewServer(
            patch: destructivePatch,
            patchData: destructivePatchData,
            validation: destructiveValidation,
            resultURL: resultURL,
            timeoutSeconds: 5,
            token: "danger-token"
        )
        let destructiveReviewURL = try destructiveServer.startForTesting()
        let destructivePage = try await string(from: URL(string: destructiveReviewURL)!)
        XCTAssertTrue(destructivePage.contains("Danger zone"))
        XCTAssertTrue(destructivePage.contains("Updates: 1"))
        XCTAssertTrue(destructivePage.contains("Cover changes: 1"))
        XCTAssertTrue(destructivePage.contains("Deletes: 1"))
        XCTAssertTrue(destructivePage.contains("old -&gt; new review"))
        XCTAssertTrue(destructivePage.contains("replace non-empty field"))
        XCTAssertTrue(destructivePage.contains("replace existing cover"))
        XCTAssertTrue(destructivePage.contains("delete book record"))
        destructiveServer.stopForTesting()

        let approveURL = URL(string: reviewURL.replacingOccurrences(of: "/review", with: "/approve"))!
        var request = URLRequest(url: approveURL)
        request.httpMethod = "POST"
        request.httpBody = Data("includeLowConfidence=true".utf8)
        _ = try await URLSession.shared.data(for: request)
        let decision = await server.waitForTesting()
        XCTAssertTrue(decision.approved)
        let writtenDecision = try FileSystem.readJSON(ReviewDecision.self, from: resultURL)
        XCTAssertTrue(writtenDecision.approved)
        XCTAssertEqual(writtenDecision.patchDigest, validation.patchDigest)
        server.stopForTesting()

        let rejectServer = PatchReviewServer(
            patch: patch,
            patchData: patchData,
            validation: validation,
            resultURL: resultURL,
            timeoutSeconds: 5,
            token: "reject-token"
        )
        let rejectURL = try rejectServer.startForTesting().replacingOccurrences(of: "/review", with: "/reject")
        var rejectRequest = URLRequest(url: URL(string: rejectURL)!)
        rejectRequest.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: rejectRequest)
        let rejectDecision = await rejectServer.waitForTesting()
        XCTAssertFalse(rejectDecision.approved)
        rejectServer.stopForTesting()

        let timeoutServer = PatchReviewServer(
            patch: patch,
            patchData: patchData,
            validation: validation,
            resultURL: resultURL,
            timeoutSeconds: 0.1,
            token: "timeout-token"
        )
        let timeoutResult = try await timeoutServer.run()
        XCTAssertFalse(timeoutResult.decision.approved)
        XCTAssertEqual(timeoutResult.decision.reason, "timeout")
    }
}

private struct Fixture {
    var repository: LibraryRepositoryReference
    var snapshot: RemoteRepositorySnapshot
}

private actor FailingRemote: LibraryRemote {
    private let snapshot: RemoteRepositorySnapshot
    private let error: Error

    init(snapshot: RemoteRepositorySnapshot, error: Error) {
        self.snapshot = snapshot
        self.error = error
    }

    func accountStatus() async throws -> CKAccountStatus {
        .available
    }

    func listRepositories() async throws -> [LibraryRepositoryReference] {
        [snapshot.repository]
    }

    func createOwnedRepository(preferredName: String) async throws -> LibraryRepositoryReference {
        snapshot.repository
    }

    func refreshRepository(_ repository: LibraryRepositoryReference) async throws -> RemoteRepositorySnapshot {
        snapshot
    }

    func saveLocations(_ locations: [LibraryLocation], in repository: LibraryRepositoryReference) async throws -> [LibraryLocation] {
        locations
    }

    func upsertBook(_ book: Book, coverData: Data?, in repository: LibraryRepositoryReference) async throws -> RemoteBookSnapshot {
        throw error
    }

    func deleteBook(id: String, in repository: LibraryRepositoryReference) async throws {
        throw error
    }

    func deleteRepository(_ repository: LibraryRepositoryReference) async throws {}
}

private func makeFixture(includeCover: Bool = false) throws -> Fixture {
    let repository = LibraryRepositoryReference(
        id: "AIWorkflowTest-Unit",
        name: "AIWorkflowTest-Unit",
        role: .owner,
        databaseScope: .private,
        zoneName: "AIWorkflowTest-Unit",
        zoneOwnerName: "__defaultOwner__"
    )
    let locations = LibraryLocation.defaultLocations()
    let coverData = includeCover ? makeJPEG(width: 120, height: 180) : nil
    let coverAssetID = coverData.map(HomeLibraryHash.coverAssetID(for:))
    let book = Book(
        id: "book-clean-code",
        title: "Clean Code",
        author: "Robert C. Martin",
        publisher: "Prentice Hall",
        year: "2008",
        locationID: locations[0].id,
        customFields: [BookInfoFieldKey.isbn: "9780132350884"],
        coverAssetID: coverAssetID,
        createdAt: Date(timeIntervalSince1970: 100),
        updatedAt: Date(timeIntervalSince1970: 200)
    )
    let snapshot = RemoteRepositorySnapshot(
        repository: repository,
        locations: locations,
        books: [RemoteBookSnapshot(book: book, coverData: coverData, recordChangeTag: "tag-1")]
    )
    return Fixture(repository: repository, snapshot: snapshot)
}

private func makeCreatePatch(
    repository: LibraryRepositoryReference,
    cover: PatchCoverPayload?,
    title: String = "Working Effectively with Legacy Code",
    isbn: String? = "9780131177055"
) -> LibraryAIPatch {
    LibraryAIPatch(
        source: "test",
        createdAt: Date(timeIntervalSince1970: 300),
        targetRepository: AITargetRepository(id: repository.id, databaseScope: repository.databaseScope),
        operations: [
            .createBook(CreateBookOperation(
                clientOperationID: "op-create",
                confidence: 0.92,
                fields: PatchBookFields(
                    title: title,
                    author: "Michael Feathers",
                    publisher: "",
                    year: "2004",
                    isbn: isbn,
                    locationID: LibraryLocation.defaultLocations()[0].id
                ),
                cover: cover,
                evidence: [PatchEvidence(sourceName: "unit", url: "https://example.com/book", matchedFields: ["isbn"])]
            ))
        ]
    )
}

private func makeUpdatePatch(
    repository: LibraryRepositoryReference,
    bookID: String,
    expectedUpdatedAt: Date?,
    expectedRecordChangeTag: String?,
    fields: [String: PatchFieldUpdate]
) -> LibraryAIPatch {
    LibraryAIPatch(
        source: "test",
        createdAt: Date(timeIntervalSince1970: 300),
        targetRepository: AITargetRepository(id: repository.id, databaseScope: repository.databaseScope),
        operations: [
            .updateBook(UpdateBookOperation(
                clientOperationID: "op-update",
                id: bookID,
                expectedUpdatedAt: expectedUpdatedAt,
                expectedRecordChangeTag: expectedRecordChangeTag,
                confidence: 0.9,
                fields: fields
            ))
        ]
    )
}

private func makeCoverPayload(width: Int = 120, height: Int = 180) -> PatchCoverPayload {
    let data = makeJPEG(width: width, height: height)
    return PatchCoverPayload(
        originalPixelSize: LibraryCoverImageSize(width: width, height: height),
        compressedPixelSize: LibraryCoverImageSize(width: min(width, 720), height: min(height, 720)),
        compressedByteSize: data.count,
        sourceURL: "https://example.com/cover.jpg",
        data: data.base64EncodedString()
    )
}

private func makeJPEG(width: Int, height: Int) -> Data {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSColor.systemBlue.setFill()
    NSBezierPath(rect: NSRect(x: width / 5, y: height / 5, width: width / 2, height: height / 2)).fill()
    image.unlockFocus()
    let tiff = image.tiffRepresentation!
    let bitmap = NSBitmapImageRep(data: tiff)!
    return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
}

private func encode<T: Encodable>(_ value: T) throws -> Data {
    try HomeLibraryJSONCodec.makeEncoder().encode(value)
}

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("home-library-cloudkit-tests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func urlResponse(from url: URL) async throws -> HTTPURLResponse {
    let (_, response) = try await URLSession.shared.data(from: url)
    return try XCTUnwrap(response as? HTTPURLResponse)
}

private func string(from url: URL) async throws -> String {
    let (data, _) = try await URLSession.shared.data(from: url)
    return String(data: data, encoding: .utf8) ?? ""
}

private func runProcess(_ executable: String, arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
}
