import CloudKit
import Foundation

public enum LibraryAIPatchApplier {
    public static func apply(
        patch: LibraryAIPatch,
        patchData: Data,
        reviewDecision: ReviewDecision?,
        remote: LibraryRemote,
        repository: LibraryRepositoryReference
    ) async throws -> PatchApplyResult {
        let refreshedSnapshot = try await remote.refreshRepository(repository)
        let validation = LibraryAIPatchValidator.validate(patch: patch, patchData: patchData, snapshot: refreshedSnapshot)
        let validationsByID = Dictionary(uniqueKeysWithValues: validation.operations.map { ($0.clientOperationID, $0) })
        let patchDigest = validation.patchDigest

        if let reviewDecision,
           reviewDecision.patchDigest != patchDigest {
            throw CLIError("review decision patchDigest does not match patch")
        }

        var snapshot = refreshedSnapshot
        var results: [OperationApplyResult] = []

        for operation in patch.operations {
            let validation = validationsByID[operation.clientOperationID]
            if let validation,
               validation.status == .failed || validation.status == .conflict || validation.status == .skipped {
                results.append(OperationApplyResult(
                    clientOperationID: operation.clientOperationID,
                    op: operation.opName,
                    status: validation.status,
                    bookID: operation.targetBookID,
                    message: validation.message
                ))
                continue
            }

            if requiresApproval(validation: validation),
               !isApproved(operationID: operation.clientOperationID, confidence: operation.confidence, reviewDecision: reviewDecision) {
                results.append(OperationApplyResult(
                    clientOperationID: operation.clientOperationID,
                    op: operation.opName,
                    status: .skipped,
                    bookID: operation.targetBookID,
                    message: "operation requires approved ReviewDecision.json"
                ))
                continue
            }

            do {
                let result = try await applyOperation(operation, remote: remote, repository: repository, snapshot: snapshot)
                results.append(result)
                snapshot = try await remote.refreshRepository(repository)
            } catch {
                let status = failureStatus(for: error)
                results.append(OperationApplyResult(
                    clientOperationID: operation.clientOperationID,
                    op: operation.opName,
                    status: status,
                    bookID: operation.targetBookID,
                    message: "\(error)",
                    retryable: status == .retryableFailed
                ))
            }
        }

        let applied = results.filter { $0.status == .applied }.count
        let skipped = results.filter { $0.status == .skipped }.count
        let conflicts = results.filter { $0.status == .conflict }.count
        let failed = results.filter { $0.status == .failed }.count
        let retryable = results.filter { $0.status == .retryableFailed }.count

        return PatchApplyResult(
            ok: failed == 0 && retryable == 0,
            patchDigest: patchDigest,
            appliedCount: applied,
            skippedCount: skipped,
            conflictCount: conflicts,
            failedCount: failed,
            retryableFailedCount: retryable,
            operations: results
        )
    }

    private static func requiresApproval(validation: OperationValidation?) -> Bool {
        validation?.requiresApproval == true || validation?.status == .needsReview
    }

    private static func isApproved(operationID: String, confidence: Double, reviewDecision: ReviewDecision?) -> Bool {
        guard let reviewDecision, reviewDecision.approved else {
            return false
        }
        if reviewDecision.rejectedOperationIDs.contains(operationID) {
            return false
        }
        if confidence < PatchRules.lowConfidenceThreshold && !reviewDecision.includeLowConfidence {
            return false
        }
        return reviewDecision.approvedOperationIDs.isEmpty || reviewDecision.approvedOperationIDs.contains(operationID)
    }

    private static func failureStatus(for error: Error) -> OperationStatus {
        if let cliError = error as? CLIError {
            switch cliError.category {
            case .retryableCloudKit:
                return .retryableFailed
            case .cloudKitConflict:
                return .conflict
            case .general:
                break
            }
        }

        guard let cloudKitError = error as? CKError else {
            return .failed
        }

        switch cloudKitError.code {
        case .networkUnavailable,
             .networkFailure,
             .serviceUnavailable,
             .requestRateLimited,
             .zoneBusy,
             .limitExceeded,
             .serverResponseLost,
             .operationCancelled:
            return .retryableFailed
        case .serverRecordChanged:
            return .conflict
        default:
            return .failed
        }
    }

    private static func applyOperation(
        _ operation: LibraryAIPatchOperation,
        remote: LibraryRemote,
        repository: LibraryRepositoryReference,
        snapshot: RemoteRepositorySnapshot
    ) async throws -> OperationApplyResult {
        switch operation {
        case .createBook(let op):
            return try await applyCreateBook(op, remote: remote, repository: repository, snapshot: snapshot)
        case .updateBook(let op):
            return try await applyUpdateBook(op, remote: remote, repository: repository, snapshot: snapshot)
        case .updateBookCover(let op):
            return try await applyUpdateBookCover(op, remote: remote, repository: repository, snapshot: snapshot)
        case .removeBookCover(let op):
            return try await applyRemoveBookCover(op, remote: remote, repository: repository, snapshot: snapshot)
        case .deleteBook(let op):
            return try await applyDeleteBook(op, remote: remote, repository: repository, snapshot: snapshot)
        }
    }

    private static func applyCreateBook(
        _ op: CreateBookOperation,
        remote: LibraryRemote,
        repository: LibraryRepositoryReference,
        snapshot: RemoteRepositorySnapshot
    ) async throws -> OperationApplyResult {
        let isbn = PatchRules.normalizeISBN(op.fields.isbn)
        if !isbn.isEmpty,
           snapshot.books.contains(where: { PatchRules.normalizeISBN($0.book.isbn) == isbn }) {
            return OperationApplyResult(
                clientOperationID: op.clientOperationID,
                op: op.op,
                status: .skipped,
                message: "duplicate ISBN already exists"
            )
        }

        let now = Date()
        var customFields = op.fields.customFields ?? [:]
        if let isbn = op.fields.isbn?.nilIfEmpty {
            customFields[BookInfoFieldKey.isbn] = isbn
        }
        if let translator = op.fields.translator?.nilIfEmpty {
            customFields[BookInfoFieldKey.translator] = translator
        }

        var coverData: Data?
        var coverAssetID: String?
        if let cover = op.cover {
            let prepared = try PatchRules.prepareCover(cover)
            coverData = prepared.data
            coverAssetID = prepared.assetID
        }

        let book = Book(
            id: op.id?.nilIfEmpty ?? UUID().uuidString,
            title: op.fields.title.trimmed,
            author: op.fields.author?.trimmed ?? "",
            publisher: op.fields.publisher?.trimmed ?? "",
            year: op.fields.year?.trimmed ?? "",
            locationID: op.fields.locationID.trimmed,
            customFields: customFields,
            coverAssetID: coverAssetID,
            createdAt: now,
            updatedAt: now
        )
        let saved = try await remote.upsertBook(book, coverData: coverData, in: repository)
        return OperationApplyResult(
            clientOperationID: op.clientOperationID,
            op: op.op,
            status: .applied,
            bookID: saved.book.id,
            message: "created book",
            coverAssetID: saved.book.coverAssetID
        )
    }

    private static func applyUpdateBook(
        _ op: UpdateBookOperation,
        remote: LibraryRemote,
        repository: LibraryRepositoryReference,
        snapshot: RemoteRepositorySnapshot
    ) async throws -> OperationApplyResult {
        guard let current = snapshot.booksByID[op.id] else {
            return OperationApplyResult(clientOperationID: op.clientOperationID, op: op.op, status: .skipped, bookID: op.id, message: "book not found")
        }

        if let conflict = conflictMessage(expectedUpdatedAt: op.expectedUpdatedAt, expectedRecordChangeTag: op.expectedRecordChangeTag, snapshot: current) {
            return OperationApplyResult(clientOperationID: op.clientOperationID, op: op.op, status: .conflict, bookID: op.id, message: conflict)
        }

        var book = current.book
        var changed = false

        for (field, update) in op.fields {
            let currentValue = LibraryAIPatchValidator.fieldValue(field, in: book)
            switch update.mode {
            case .fillIfEmpty:
                guard currentValue.trimmed.isEmpty else {
                    continue
                }
            case .replaceIfCurrentValue:
                guard currentValue == (update.expectedValue ?? "") else {
                    return OperationApplyResult(clientOperationID: op.clientOperationID, op: op.op, status: .conflict, bookID: op.id, message: "\(field) does not match expectedValue")
                }
            }
            LibraryAIPatchValidator.setField(field, value: update.value, in: &book)
            changed = true
        }

        guard changed else {
            return OperationApplyResult(clientOperationID: op.clientOperationID, op: op.op, status: .skipped, bookID: op.id, message: "no fields changed")
        }

        book.updatedAt = Date()
        let saved = try await remote.upsertBook(book, coverData: nil, in: repository)
        return OperationApplyResult(
            clientOperationID: op.clientOperationID,
            op: op.op,
            status: .applied,
            bookID: saved.book.id,
            message: "updated book"
        )
    }

    private static func applyUpdateBookCover(
        _ op: UpdateBookCoverOperation,
        remote: LibraryRemote,
        repository: LibraryRepositoryReference,
        snapshot: RemoteRepositorySnapshot
    ) async throws -> OperationApplyResult {
        guard let current = snapshot.booksByID[op.id] else {
            return OperationApplyResult(clientOperationID: op.clientOperationID, op: op.op, status: .skipped, bookID: op.id, message: "book not found")
        }
        if let conflict = conflictMessage(expectedUpdatedAt: op.expectedUpdatedAt, expectedRecordChangeTag: op.expectedRecordChangeTag, snapshot: current) {
            return OperationApplyResult(clientOperationID: op.clientOperationID, op: op.op, status: .conflict, bookID: op.id, message: conflict)
        }
        if let currentCoverAssetID = current.book.coverAssetID {
            guard let expected = op.expectedCurrentCoverAssetID else {
                return OperationApplyResult(
                    clientOperationID: op.clientOperationID,
                    op: op.op,
                    status: .skipped,
                    bookID: op.id,
                    message: "book already has a cover; replacing it requires expectedCurrentCoverAssetID"
                )
            }
            guard currentCoverAssetID == expected else {
                return OperationApplyResult(clientOperationID: op.clientOperationID, op: op.op, status: .conflict, bookID: op.id, message: "coverAssetID mismatch")
            }
        } else if let expected = op.expectedCurrentCoverAssetID,
                  expected.nilIfEmpty != nil {
            return OperationApplyResult(clientOperationID: op.clientOperationID, op: op.op, status: .conflict, bookID: op.id, message: "book has no current coverAssetID")
        }

        let prepared = try PatchRules.prepareCover(op.cover)
        var book = current.book
        book.coverAssetID = prepared.assetID
        book.updatedAt = Date()
        let saved = try await remote.upsertBook(book, coverData: prepared.data, in: repository)
        return OperationApplyResult(
            clientOperationID: op.clientOperationID,
            op: op.op,
            status: .applied,
            bookID: saved.book.id,
            message: "updated cover",
            coverAssetID: saved.book.coverAssetID
        )
    }

    private static func applyRemoveBookCover(
        _ op: RemoveBookCoverOperation,
        remote: LibraryRemote,
        repository: LibraryRepositoryReference,
        snapshot: RemoteRepositorySnapshot
    ) async throws -> OperationApplyResult {
        guard let current = snapshot.booksByID[op.id] else {
            return OperationApplyResult(clientOperationID: op.clientOperationID, op: op.op, status: .skipped, bookID: op.id, message: "book not found")
        }
        if let conflict = conflictMessage(expectedUpdatedAt: op.expectedUpdatedAt, expectedRecordChangeTag: op.expectedRecordChangeTag, snapshot: current) {
            return OperationApplyResult(clientOperationID: op.clientOperationID, op: op.op, status: .conflict, bookID: op.id, message: conflict)
        }
        guard current.book.coverAssetID == op.expectedCurrentCoverAssetID else {
            return OperationApplyResult(clientOperationID: op.clientOperationID, op: op.op, status: .conflict, bookID: op.id, message: "coverAssetID mismatch")
        }

        var book = current.book
        book.coverAssetID = nil
        book.updatedAt = Date()
        let saved = try await remote.upsertBook(book, coverData: nil, in: repository)
        return OperationApplyResult(
            clientOperationID: op.clientOperationID,
            op: op.op,
            status: .applied,
            bookID: saved.book.id,
            message: "removed cover"
        )
    }

    private static func applyDeleteBook(
        _ op: DeleteBookOperation,
        remote: LibraryRemote,
        repository: LibraryRepositoryReference,
        snapshot: RemoteRepositorySnapshot
    ) async throws -> OperationApplyResult {
        guard let current = snapshot.booksByID[op.id] else {
            return OperationApplyResult(clientOperationID: op.clientOperationID, op: op.op, status: .skipped, bookID: op.id, message: "book not found")
        }
        if let conflict = conflictMessage(expectedUpdatedAt: op.expectedUpdatedAt, expectedRecordChangeTag: op.expectedRecordChangeTag, snapshot: current) {
            return OperationApplyResult(clientOperationID: op.clientOperationID, op: op.op, status: .conflict, bookID: op.id, message: conflict)
        }

        try await remote.deleteBook(id: op.id, in: repository)
        return OperationApplyResult(
            clientOperationID: op.clientOperationID,
            op: op.op,
            status: .applied,
            bookID: op.id,
            message: "deleted book record"
        )
    }

    private static func conflictMessage(expectedUpdatedAt: Date?, expectedRecordChangeTag: String?, snapshot: RemoteBookSnapshot) -> String? {
        if let expectedUpdatedAt,
           abs(snapshot.book.updatedAt.timeIntervalSince1970 - expectedUpdatedAt.timeIntervalSince1970) > 0.001 {
            return "expectedUpdatedAt mismatch"
        }
        if let expectedRecordChangeTag,
           let current = snapshot.recordChangeTag,
           expectedRecordChangeTag != current {
            return "expectedRecordChangeTag mismatch"
        }
        return nil
    }
}
