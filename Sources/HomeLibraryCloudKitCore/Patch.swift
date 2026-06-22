import Foundation

public struct AITargetRepository: Codable, Equatable, Sendable {
    public var id: String
    public var name: String?
    public var databaseScope: CloudDatabaseScope
    public var zoneID: String?

    public init(id: String, name: String? = nil, databaseScope: CloudDatabaseScope, zoneID: String? = nil) {
        self.id = id
        self.name = name
        self.databaseScope = databaseScope
        self.zoneID = zoneID
    }
}

public struct AIBaseSnapshot: Codable, Equatable, Sendable {
    public var id: String
    public var createdAt: Date
    public var changeTokenDigest: String?

    public init(id: String, createdAt: Date, changeTokenDigest: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.changeTokenDigest = changeTokenDigest
    }
}

public struct LibraryAIPatch: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var source: String
    public var createdAt: Date
    public var targetRepository: AITargetRepository
    public var baseSnapshot: AIBaseSnapshot?
    public var operations: [LibraryAIPatchOperation]
    public var notes: [String]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        source: String,
        createdAt: Date,
        targetRepository: AITargetRepository,
        baseSnapshot: AIBaseSnapshot? = nil,
        operations: [LibraryAIPatchOperation],
        notes: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.source = source
        self.createdAt = createdAt
        self.targetRepository = targetRepository
        self.baseSnapshot = baseSnapshot
        self.operations = operations
        self.notes = notes
    }
}

public enum LibraryAIPatchOperation: Codable, Sendable {
    case createBook(CreateBookOperation)
    case updateBook(UpdateBookOperation)
    case updateBookCover(UpdateBookCoverOperation)
    case removeBookCover(RemoveBookCoverOperation)
    case deleteBook(DeleteBookOperation)

    private enum CodingKeys: String, CodingKey {
        case op
    }

    private enum OperationName: String, Codable {
        case createBook
        case updateBook
        case updateBookCover
        case removeBookCover
        case deleteBook
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let op = try container.decode(OperationName.self, forKey: .op)
        switch op {
        case .createBook:
            self = .createBook(try CreateBookOperation(from: decoder))
        case .updateBook:
            self = .updateBook(try UpdateBookOperation(from: decoder))
        case .updateBookCover:
            self = .updateBookCover(try UpdateBookCoverOperation(from: decoder))
        case .removeBookCover:
            self = .removeBookCover(try RemoveBookCoverOperation(from: decoder))
        case .deleteBook:
            self = .deleteBook(try DeleteBookOperation(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .createBook(let operation):
            try operation.encode(to: encoder)
        case .updateBook(let operation):
            try operation.encode(to: encoder)
        case .updateBookCover(let operation):
            try operation.encode(to: encoder)
        case .removeBookCover(let operation):
            try operation.encode(to: encoder)
        case .deleteBook(let operation):
            try operation.encode(to: encoder)
        }
    }

    public var opName: String {
        switch self {
        case .createBook:
            return "createBook"
        case .updateBook:
            return "updateBook"
        case .updateBookCover:
            return "updateBookCover"
        case .removeBookCover:
            return "removeBookCover"
        case .deleteBook:
            return "deleteBook"
        }
    }

    public var clientOperationID: String {
        switch self {
        case .createBook(let operation):
            return operation.clientOperationID
        case .updateBook(let operation):
            return operation.clientOperationID
        case .updateBookCover(let operation):
            return operation.clientOperationID
        case .removeBookCover(let operation):
            return operation.clientOperationID
        case .deleteBook(let operation):
            return operation.clientOperationID
        }
    }

    public var targetBookID: String? {
        switch self {
        case .createBook(let operation):
            return operation.id
        case .updateBook(let operation):
            return operation.id
        case .updateBookCover(let operation):
            return operation.id
        case .removeBookCover(let operation):
            return operation.id
        case .deleteBook(let operation):
            return operation.id
        }
    }

    public var confidence: Double {
        switch self {
        case .createBook(let operation):
            return operation.confidence
        case .updateBook(let operation):
            return operation.confidence
        case .updateBookCover(let operation):
            return operation.confidence
        case .removeBookCover:
            return 1
        case .deleteBook:
            return 1
        }
    }

    public var evidence: [PatchEvidence] {
        switch self {
        case .createBook(let operation):
            return operation.evidence
        case .updateBook(let operation):
            return operation.evidence
        case .updateBookCover(let operation):
            return operation.evidence
        case .removeBookCover(let operation):
            return operation.evidence
        case .deleteBook(let operation):
            return operation.evidence
        }
    }

    public var isDestructive: Bool {
        switch self {
        case .removeBookCover, .deleteBook:
            return true
        case .createBook, .updateBook, .updateBookCover:
            return false
        }
    }
}

public struct CreateBookOperation: Codable, Sendable {
    public let op: String
    public var clientOperationID: String
    public var id: String?
    public var confidence: Double
    public var idempotencyKey: String?
    public var fields: PatchBookFields
    public var cover: PatchCoverPayload?
    public var evidence: [PatchEvidence]
    public var warnings: [String]

    public init(
        clientOperationID: String,
        id: String? = nil,
        confidence: Double = 1,
        idempotencyKey: String? = nil,
        fields: PatchBookFields,
        cover: PatchCoverPayload? = nil,
        evidence: [PatchEvidence] = [],
        warnings: [String] = []
    ) {
        op = "createBook"
        self.clientOperationID = clientOperationID
        self.id = id
        self.confidence = confidence
        self.idempotencyKey = idempotencyKey
        self.fields = fields
        self.cover = cover
        self.evidence = evidence
        self.warnings = warnings
    }
}

public struct UpdateBookOperation: Codable, Sendable {
    public let op: String
    public var clientOperationID: String
    public var id: String
    public var expectedUpdatedAt: Date?
    public var expectedRecordChangeTag: String?
    public var confidence: Double
    public var fields: [String: PatchFieldUpdate]
    public var evidence: [PatchEvidence]
    public var warnings: [String]

    public init(
        clientOperationID: String,
        id: String,
        expectedUpdatedAt: Date? = nil,
        expectedRecordChangeTag: String? = nil,
        confidence: Double = 1,
        fields: [String: PatchFieldUpdate],
        evidence: [PatchEvidence] = [],
        warnings: [String] = []
    ) {
        op = "updateBook"
        self.clientOperationID = clientOperationID
        self.id = id
        self.expectedUpdatedAt = expectedUpdatedAt
        self.expectedRecordChangeTag = expectedRecordChangeTag
        self.confidence = confidence
        self.fields = fields
        self.evidence = evidence
        self.warnings = warnings
    }
}

public struct UpdateBookCoverOperation: Codable, Sendable {
    public let op: String
    public var clientOperationID: String
    public var id: String
    public var expectedUpdatedAt: Date?
    public var expectedRecordChangeTag: String?
    public var confidence: Double
    public var expectedCurrentCoverAssetID: String?
    public var cover: PatchCoverPayload
    public var evidence: [PatchEvidence]
    public var warnings: [String]

    public init(
        clientOperationID: String,
        id: String,
        expectedUpdatedAt: Date? = nil,
        expectedRecordChangeTag: String? = nil,
        confidence: Double = 1,
        expectedCurrentCoverAssetID: String? = nil,
        cover: PatchCoverPayload,
        evidence: [PatchEvidence] = [],
        warnings: [String] = []
    ) {
        op = "updateBookCover"
        self.clientOperationID = clientOperationID
        self.id = id
        self.expectedUpdatedAt = expectedUpdatedAt
        self.expectedRecordChangeTag = expectedRecordChangeTag
        self.confidence = confidence
        self.expectedCurrentCoverAssetID = expectedCurrentCoverAssetID
        self.cover = cover
        self.evidence = evidence
        self.warnings = warnings
    }
}

public struct RemoveBookCoverOperation: Codable, Sendable {
    public let op: String
    public var clientOperationID: String
    public var id: String
    public var expectedUpdatedAt: Date?
    public var expectedRecordChangeTag: String?
    public var expectedCurrentCoverAssetID: String
    public var reason: String
    public var evidence: [PatchEvidence]
    public var warnings: [String]

    public init(
        clientOperationID: String,
        id: String,
        expectedUpdatedAt: Date? = nil,
        expectedRecordChangeTag: String? = nil,
        expectedCurrentCoverAssetID: String,
        reason: String,
        evidence: [PatchEvidence] = [],
        warnings: [String] = []
    ) {
        op = "removeBookCover"
        self.clientOperationID = clientOperationID
        self.id = id
        self.expectedUpdatedAt = expectedUpdatedAt
        self.expectedRecordChangeTag = expectedRecordChangeTag
        self.expectedCurrentCoverAssetID = expectedCurrentCoverAssetID
        self.reason = reason
        self.evidence = evidence
        self.warnings = warnings
    }
}

public struct DeleteBookOperation: Codable, Sendable {
    public let op: String
    public var clientOperationID: String
    public var id: String
    public var expectedUpdatedAt: Date?
    public var expectedRecordChangeTag: String?
    public var reason: String
    public var evidence: [PatchEvidence]
    public var warnings: [String]

    public init(
        clientOperationID: String,
        id: String,
        expectedUpdatedAt: Date? = nil,
        expectedRecordChangeTag: String? = nil,
        reason: String,
        evidence: [PatchEvidence] = [],
        warnings: [String] = []
    ) {
        op = "deleteBook"
        self.clientOperationID = clientOperationID
        self.id = id
        self.expectedUpdatedAt = expectedUpdatedAt
        self.expectedRecordChangeTag = expectedRecordChangeTag
        self.reason = reason
        self.evidence = evidence
        self.warnings = warnings
    }
}

public struct PatchBookFields: Codable, Equatable, Sendable {
    public var title: String
    public var author: String?
    public var translator: String?
    public var publisher: String?
    public var year: String?
    public var isbn: String?
    public var locationID: String
    public var customFields: [String: String]?

    public init(
        title: String,
        author: String? = nil,
        translator: String? = nil,
        publisher: String? = nil,
        year: String? = nil,
        isbn: String? = nil,
        locationID: String,
        customFields: [String: String]? = nil
    ) {
        self.title = title
        self.author = author
        self.translator = translator
        self.publisher = publisher
        self.year = year
        self.isbn = isbn
        self.locationID = locationID
        self.customFields = customFields
    }
}

public struct PatchFieldUpdate: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case fillIfEmpty
        case replaceIfCurrentValue
    }

    public var mode: Mode
    public var expectedValue: String?
    public var value: String

    public init(mode: Mode, expectedValue: String? = nil, value: String) {
        self.mode = mode
        self.expectedValue = expectedValue
        self.value = value
    }
}

public struct PatchCoverPayload: Codable, Equatable, Sendable {
    public var kind: String
    public var preferredMimeType: String?
    public var mimeType: String?
    public var originalPixelSize: LibraryCoverImageSize?
    public var compressedPixelSize: LibraryCoverImageSize?
    public var compressedByteSize: Int?
    public var expectedCoverAssetID: String?
    public var sourceURL: String?
    public var data: String

    public init(
        kind: String = "coverDataBase64",
        preferredMimeType: String? = "image/jpeg",
        mimeType: String? = nil,
        originalPixelSize: LibraryCoverImageSize? = nil,
        compressedPixelSize: LibraryCoverImageSize? = nil,
        compressedByteSize: Int? = nil,
        expectedCoverAssetID: String? = nil,
        sourceURL: String? = nil,
        data: String
    ) {
        self.kind = kind
        self.preferredMimeType = preferredMimeType
        self.mimeType = mimeType
        self.originalPixelSize = originalPixelSize
        self.compressedPixelSize = compressedPixelSize
        self.compressedByteSize = compressedByteSize
        self.expectedCoverAssetID = expectedCoverAssetID
        self.sourceURL = sourceURL
        self.data = data
    }
}

public struct PatchEvidence: Codable, Equatable, Sendable {
    public var sourceName: String
    public var url: String?
    public var matchedFields: [String]

    public init(sourceName: String, url: String? = nil, matchedFields: [String] = []) {
        self.sourceName = sourceName
        self.url = url
        self.matchedFields = matchedFields
    }
}

public enum OperationStatus: String, Codable, Sendable {
    case valid
    case applied
    case needsReview
    case skipped
    case conflict
    case failed
    case retryableFailed
}

public struct OperationValidation: Codable, Sendable {
    public var clientOperationID: String
    public var op: String
    public var status: OperationStatus
    public var message: String
    public var requiresApproval: Bool
    public var risks: [String]
    public var warnings: [String]
    public var candidateCoverAssetID: String?
    public var candidateCoverByteSize: Int?
    public var candidateCoverPixelSize: LibraryCoverImageSize?

    public init(
        clientOperationID: String,
        op: String,
        status: OperationStatus,
        message: String,
        requiresApproval: Bool = false,
        risks: [String] = [],
        warnings: [String] = [],
        candidateCoverAssetID: String? = nil,
        candidateCoverByteSize: Int? = nil,
        candidateCoverPixelSize: LibraryCoverImageSize? = nil
    ) {
        self.clientOperationID = clientOperationID
        self.op = op
        self.status = status
        self.message = message
        self.requiresApproval = requiresApproval
        self.risks = risks
        self.warnings = warnings
        self.candidateCoverAssetID = candidateCoverAssetID
        self.candidateCoverByteSize = candidateCoverByteSize
        self.candidateCoverPixelSize = candidateCoverPixelSize
    }
}

public struct PatchValidationResult: Codable, Sendable {
    public var ok: Bool
    public var patchDigest: String
    public var operationCount: Int
    public var acceptedCount: Int
    public var needsReviewCount: Int
    public var skippedCount: Int
    public var conflictCount: Int
    public var failedCount: Int
    public var operations: [OperationValidation]
    public var errors: [String]
    public var warnings: [String]

    public init(
        ok: Bool,
        patchDigest: String,
        operationCount: Int,
        acceptedCount: Int,
        needsReviewCount: Int,
        skippedCount: Int,
        conflictCount: Int,
        failedCount: Int,
        operations: [OperationValidation],
        errors: [String] = [],
        warnings: [String] = []
    ) {
        self.ok = ok
        self.patchDigest = patchDigest
        self.operationCount = operationCount
        self.acceptedCount = acceptedCount
        self.needsReviewCount = needsReviewCount
        self.skippedCount = skippedCount
        self.conflictCount = conflictCount
        self.failedCount = failedCount
        self.operations = operations
        self.errors = errors
        self.warnings = warnings
    }
}

public struct ReviewDecision: Codable, Sendable {
    public var approved: Bool
    public var approvedAt: Date?
    public var rejectedAt: Date?
    public var reason: String?
    public var patchDigest: String
    public var approvedOperationIDs: [String]
    public var rejectedOperationIDs: [String]
    public var includeLowConfidence: Bool

    public init(
        approved: Bool,
        approvedAt: Date? = nil,
        rejectedAt: Date? = nil,
        reason: String? = nil,
        patchDigest: String,
        approvedOperationIDs: [String] = [],
        rejectedOperationIDs: [String] = [],
        includeLowConfidence: Bool = false
    ) {
        self.approved = approved
        self.approvedAt = approvedAt
        self.rejectedAt = rejectedAt
        self.reason = reason
        self.patchDigest = patchDigest
        self.approvedOperationIDs = approvedOperationIDs
        self.rejectedOperationIDs = rejectedOperationIDs
        self.includeLowConfidence = includeLowConfidence
    }
}

public struct OperationApplyResult: Codable, Sendable {
    public var clientOperationID: String
    public var op: String
    public var status: OperationStatus
    public var bookID: String?
    public var message: String
    public var coverAssetID: String?
    public var retryable: Bool

    public init(
        clientOperationID: String,
        op: String,
        status: OperationStatus,
        bookID: String? = nil,
        message: String,
        coverAssetID: String? = nil,
        retryable: Bool = false
    ) {
        self.clientOperationID = clientOperationID
        self.op = op
        self.status = status
        self.bookID = bookID
        self.message = message
        self.coverAssetID = coverAssetID
        self.retryable = retryable
    }
}

public struct PatchApplyResult: Codable, Sendable {
    public var ok: Bool
    public var patchDigest: String
    public var appliedCount: Int
    public var skippedCount: Int
    public var conflictCount: Int
    public var failedCount: Int
    public var retryableFailedCount: Int
    public var operations: [OperationApplyResult]

    public init(
        ok: Bool,
        patchDigest: String,
        appliedCount: Int,
        skippedCount: Int,
        conflictCount: Int,
        failedCount: Int,
        retryableFailedCount: Int,
        operations: [OperationApplyResult]
    ) {
        self.ok = ok
        self.patchDigest = patchDigest
        self.appliedCount = appliedCount
        self.skippedCount = skippedCount
        self.conflictCount = conflictCount
        self.failedCount = failedCount
        self.retryableFailedCount = retryableFailedCount
        self.operations = operations
    }
}

public struct PreparedCover: Sendable {
    public var data: Data
    public var assetID: String
    public var originalSize: LibraryCoverImageSize?
    public var outputSize: LibraryCoverImageSize?
    public var didCompress: Bool
}

public enum PatchRules {
    public static let maxOperations = 500
    public static let maxPatchByteCount = 10 * 1024 * 1024
    public static let lowConfidenceThreshold = 0.75

    public static func normalizeISBN(_ rawValue: String?) -> String {
        rawValue?.filter { $0.isNumber || $0 == "X" || $0 == "x" }.uppercased() ?? ""
    }

    public static func isValidISBN(_ rawValue: String?) -> Bool {
        let value = normalizeISBN(rawValue)
        guard !value.isEmpty else {
            return true
        }
        return isValidISBN10(value) || isValidISBN13(value)
    }

    private static func isValidISBN10(_ value: String) -> Bool {
        guard value.count == 10 else {
            return false
        }
        var sum = 0
        for (index, character) in value.enumerated() {
            let digit: Int
            if character == "X", index == 9 {
                digit = 10
            } else if let number = character.wholeNumberValue {
                digit = number
            } else {
                return false
            }
            sum += digit * (10 - index)
        }
        return sum % 11 == 0
    }

    private static func isValidISBN13(_ value: String) -> Bool {
        guard value.count == 13, value.allSatisfy(\.isNumber) else {
            return false
        }
        let digits = value.compactMap(\.wholeNumberValue)
        let sum = digits.dropLast().enumerated().reduce(0) { partial, entry in
            partial + entry.element * (entry.offset.isMultiple(of: 2) ? 1 : 3)
        }
        let check = (10 - (sum % 10)) % 10
        return check == digits.last
    }

    public static func normalizedTitle(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_Hans_CN"))
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "：", with: ":")
            .trimmed
            .lowercased()
    }

    public static func prepareCover(_ payload: PatchCoverPayload) throws -> PreparedCover {
        guard payload.kind == "coverDataBase64" || payload.kind == "compressedThumbnailBase64" else {
            throw CLIError("unsupported cover kind: \(payload.kind)")
        }
        guard let data = Data(base64Encoded: payload.data), !data.isEmpty else {
            throw CLIError("cover data is not valid base64")
        }
        guard LibraryCoverCompressor.canDecode(data) else {
            throw CLIError("cover data is not a decodable image")
        }
        if payload.sourceURL?.nilIfEmpty == nil {
            throw CLIError("cover sourceURL is required")
        }
        let result = LibraryCoverCompressor.compressIfNeeded(data)
        let assetID = HomeLibraryHash.coverAssetID(for: result.data)
        if let expected = payload.expectedCoverAssetID?.nilIfEmpty,
           expected != assetID {
            throw CLIError("expectedCoverAssetID mismatch: expected \(expected), got \(assetID)")
        }
        return PreparedCover(
            data: result.data,
            assetID: assetID,
            originalSize: result.originalSize,
            outputSize: result.outputSize,
            didCompress: result.didCompress
        )
    }
}

public enum LibraryAIPatchValidator {
    public static func validate(patch: LibraryAIPatch, patchData: Data, snapshot: RemoteRepositorySnapshot) -> PatchValidationResult {
        let digest = HomeLibraryHash.digestString(for: patchData)
        var errors: [String] = []
        let warnings: [String] = []
        var results: [OperationValidation] = []

        if patch.schemaVersion != LibraryAIPatch.currentSchemaVersion {
            errors.append("unsupported schemaVersion \(patch.schemaVersion)")
        }
        if patchData.count > PatchRules.maxPatchByteCount {
            errors.append("patch is too large: \(patchData.count) bytes")
        }
        if patch.operations.count > PatchRules.maxOperations {
            errors.append("too many operations: \(patch.operations.count)")
        }
        if patch.targetRepository.id != snapshot.repository.id {
            errors.append("target repository mismatch: patch=\(patch.targetRepository.id) current=\(snapshot.repository.id)")
        }
        if patch.targetRepository.databaseScope != snapshot.repository.databaseScope {
            errors.append("database scope mismatch")
        }

        let locationIDs = Set(snapshot.locations.map(\.id))
        let booksByID = snapshot.booksByID
        let currentISBNs = Dictionary(grouping: snapshot.books, by: { PatchRules.normalizeISBN($0.book.isbn) })
        let currentTitleKeys = Dictionary(grouping: snapshot.books, by: { PatchRules.normalizedTitle($0.book.title) })
        var patchISBNs: [String: String] = [:]

        for operation in patch.operations {
            results.append(validateOperation(
                operation,
                locationIDs: locationIDs,
                booksByID: booksByID,
                currentISBNs: currentISBNs,
                currentTitleKeys: currentTitleKeys,
                patchISBNs: &patchISBNs
            ))
        }

        let accepted = results.filter { $0.status == .valid }.count
        let needsReview = results.filter { $0.status == .needsReview }.count
        let skipped = results.filter { $0.status == .skipped }.count
        let conflicts = results.filter { $0.status == .conflict }.count
        let failed = results.filter { $0.status == .failed || $0.status == .retryableFailed }.count

        return PatchValidationResult(
            ok: errors.isEmpty && failed == 0,
            patchDigest: digest,
            operationCount: patch.operations.count,
            acceptedCount: accepted,
            needsReviewCount: needsReview,
            skippedCount: skipped,
            conflictCount: conflicts,
            failedCount: failed,
            operations: results,
            errors: errors,
            warnings: warnings
        )
    }

    private static func validateOperation(
        _ operation: LibraryAIPatchOperation,
        locationIDs: Set<String>,
        booksByID: [String: RemoteBookSnapshot],
        currentISBNs: [String: [RemoteBookSnapshot]],
        currentTitleKeys: [String: [RemoteBookSnapshot]],
        patchISBNs: inout [String: String]
    ) -> OperationValidation {
        switch operation {
        case .createBook(let op):
            return validateCreateBook(op, locationIDs: locationIDs, currentISBNs: currentISBNs, currentTitleKeys: currentTitleKeys, patchISBNs: &patchISBNs)
        case .updateBook(let op):
            return validateUpdateBook(op, booksByID: booksByID)
        case .updateBookCover(let op):
            return validateUpdateBookCover(op, booksByID: booksByID)
        case .removeBookCover(let op):
            return validateRemoveBookCover(op, booksByID: booksByID)
        case .deleteBook(let op):
            return validateDeleteBook(op, booksByID: booksByID)
        }
    }

    private static func validateCreateBook(
        _ op: CreateBookOperation,
        locationIDs: Set<String>,
        currentISBNs: [String: [RemoteBookSnapshot]],
        currentTitleKeys: [String: [RemoteBookSnapshot]],
        patchISBNs: inout [String: String]
    ) -> OperationValidation {
        var risks: [String] = []
        var warnings = op.warnings

        guard !op.fields.title.trimmed.isEmpty else {
            return failed(op, "title is required")
        }
        guard locationIDs.contains(op.fields.locationID) else {
            return failed(op, "locationID does not exist: \(op.fields.locationID)")
        }
        guard PatchRules.isValidISBN(op.fields.isbn) else {
            return failed(op, "invalid ISBN")
        }

        let isbn = PatchRules.normalizeISBN(op.fields.isbn)
        if !isbn.isEmpty {
            if currentISBNs[isbn]?.isEmpty == false {
                return OperationValidation(
                    clientOperationID: op.clientOperationID,
                    op: op.op,
                    status: .skipped,
                    message: "duplicate ISBN already exists: \(isbn)",
                    warnings: warnings
                )
            }
            if let existingPatchOp = patchISBNs[isbn] {
                return OperationValidation(
                    clientOperationID: op.clientOperationID,
                    op: op.op,
                    status: .skipped,
                    message: "duplicate ISBN in patch: \(isbn) already used by \(existingPatchOp)",
                    warnings: warnings
                )
            }
            patchISBNs[isbn] = op.clientOperationID
        } else {
            let titleKey = PatchRules.normalizedTitle(op.fields.title)
            if currentTitleKeys[titleKey]?.isEmpty == false {
                risks.append("similar title")
            }
        }

        var candidateCoverAssetID: String?
        var candidateCoverByteSize: Int?
        var candidateCoverPixelSize: LibraryCoverImageSize?
        if let cover = op.cover {
            do {
                let prepared = try PatchRules.prepareCover(cover)
                candidateCoverAssetID = prepared.assetID
                candidateCoverByteSize = prepared.data.count
                candidateCoverPixelSize = prepared.outputSize
            } catch {
                return failed(op, "invalid cover: \(error)")
            }
        }

        if op.confidence < PatchRules.lowConfidenceThreshold {
            risks.append("low confidence")
        }
        let requiresApproval = risks.contains("similar title") || risks.contains("low confidence")
        let status: OperationStatus = requiresApproval ? .needsReview : .valid
        if requiresApproval {
            warnings.append("operation requires review")
        }
        return OperationValidation(
            clientOperationID: op.clientOperationID,
            op: op.op,
            status: status,
            message: requiresApproval ? "valid but requires review" : "valid",
            requiresApproval: requiresApproval,
            risks: risks,
            warnings: warnings,
            candidateCoverAssetID: candidateCoverAssetID,
            candidateCoverByteSize: candidateCoverByteSize,
            candidateCoverPixelSize: candidateCoverPixelSize
        )
    }

    private static func validateUpdateBook(_ op: UpdateBookOperation, booksByID: [String: RemoteBookSnapshot]) -> OperationValidation {
        guard let snapshot = booksByID[op.id] else {
            return OperationValidation(clientOperationID: op.clientOperationID, op: op.op, status: .skipped, message: "book not found")
        }
        if let conflict = conflictMessage(expectedUpdatedAt: op.expectedUpdatedAt, expectedRecordChangeTag: op.expectedRecordChangeTag, snapshot: snapshot) {
            return OperationValidation(clientOperationID: op.clientOperationID, op: op.op, status: .conflict, message: conflict)
        }
        guard !op.fields.isEmpty else {
            return failed(op, "fields are required")
        }

        var risks: [String] = []
        for (key, update) in op.fields {
            if !isSupportedField(key) {
                return failed(op, "unsupported field: \(key)")
            }
            if key == "isbn", !PatchRules.isValidISBN(update.value) {
                return failed(op, "invalid ISBN")
            }
            let current = fieldValue(key, in: snapshot.book)
            switch update.mode {
            case .fillIfEmpty:
                if !current.trimmed.isEmpty {
                    return OperationValidation(clientOperationID: op.clientOperationID, op: op.op, status: .skipped, message: "\(key) is not empty")
                }
            case .replaceIfCurrentValue:
                if current != (update.expectedValue ?? "") {
                    return OperationValidation(clientOperationID: op.clientOperationID, op: op.op, status: .conflict, message: "\(key) does not match expectedValue")
                }
                if !current.trimmed.isEmpty {
                    risks.append("replace non-empty field")
                }
            }
        }

        if op.confidence < PatchRules.lowConfidenceThreshold {
            risks.append("low confidence")
        }

        let requiresApproval = !risks.isEmpty
        return OperationValidation(
            clientOperationID: op.clientOperationID,
            op: op.op,
            status: requiresApproval ? .needsReview : .valid,
            message: requiresApproval ? "valid but requires review" : "valid",
            requiresApproval: requiresApproval,
            risks: risks,
            warnings: op.warnings
        )
    }

    private static func validateUpdateBookCover(_ op: UpdateBookCoverOperation, booksByID: [String: RemoteBookSnapshot]) -> OperationValidation {
        guard let snapshot = booksByID[op.id] else {
            return OperationValidation(clientOperationID: op.clientOperationID, op: op.op, status: .skipped, message: "book not found")
        }
        if let conflict = conflictMessage(expectedUpdatedAt: op.expectedUpdatedAt, expectedRecordChangeTag: op.expectedRecordChangeTag, snapshot: snapshot) {
            return OperationValidation(clientOperationID: op.clientOperationID, op: op.op, status: .conflict, message: conflict)
        }
        if let currentCoverAssetID = snapshot.book.coverAssetID {
            guard let expected = op.expectedCurrentCoverAssetID else {
                return OperationValidation(
                    clientOperationID: op.clientOperationID,
                    op: op.op,
                    status: .skipped,
                    message: "book already has a cover; replacing it requires expectedCurrentCoverAssetID"
                )
            }
            guard currentCoverAssetID == expected else {
                return OperationValidation(clientOperationID: op.clientOperationID, op: op.op, status: .conflict, message: "coverAssetID does not match expectedCurrentCoverAssetID")
            }
        } else if let expected = op.expectedCurrentCoverAssetID,
                  expected.nilIfEmpty != nil {
            return OperationValidation(clientOperationID: op.clientOperationID, op: op.op, status: .conflict, message: "book has no current coverAssetID")
        }

        let prepared: PreparedCover
        do {
            prepared = try PatchRules.prepareCover(op.cover)
        } catch {
            return failed(op, "invalid cover: \(error)")
        }

        var risks: [String] = []
        if snapshot.book.coverAssetID != nil {
            risks.append("replace existing cover")
        }
        if op.confidence < PatchRules.lowConfidenceThreshold {
            risks.append("low confidence")
        }

        return OperationValidation(
            clientOperationID: op.clientOperationID,
            op: op.op,
            status: risks.isEmpty ? .valid : .needsReview,
            message: risks.isEmpty ? "valid" : "valid but requires review",
            requiresApproval: !risks.isEmpty,
            risks: risks,
            warnings: op.warnings,
            candidateCoverAssetID: prepared.assetID,
            candidateCoverByteSize: prepared.data.count,
            candidateCoverPixelSize: prepared.outputSize
        )
    }

    private static func validateRemoveBookCover(_ op: RemoveBookCoverOperation, booksByID: [String: RemoteBookSnapshot]) -> OperationValidation {
        guard let snapshot = booksByID[op.id] else {
            return OperationValidation(clientOperationID: op.clientOperationID, op: op.op, status: .skipped, message: "book not found")
        }
        if let conflict = conflictMessage(expectedUpdatedAt: op.expectedUpdatedAt, expectedRecordChangeTag: op.expectedRecordChangeTag, snapshot: snapshot) {
            return OperationValidation(clientOperationID: op.clientOperationID, op: op.op, status: .conflict, message: conflict)
        }
        guard snapshot.book.coverAssetID == op.expectedCurrentCoverAssetID else {
            return OperationValidation(clientOperationID: op.clientOperationID, op: op.op, status: .conflict, message: "coverAssetID does not match expectedCurrentCoverAssetID")
        }
        return OperationValidation(
            clientOperationID: op.clientOperationID,
            op: op.op,
            status: .needsReview,
            message: "destructive cover operation requires approval",
            requiresApproval: true,
            risks: ["remove cover"],
            warnings: op.warnings
        )
    }

    private static func validateDeleteBook(_ op: DeleteBookOperation, booksByID: [String: RemoteBookSnapshot]) -> OperationValidation {
        guard let snapshot = booksByID[op.id] else {
            return OperationValidation(clientOperationID: op.clientOperationID, op: op.op, status: .skipped, message: "book not found")
        }
        if let conflict = conflictMessage(expectedUpdatedAt: op.expectedUpdatedAt, expectedRecordChangeTag: op.expectedRecordChangeTag, snapshot: snapshot) {
            return OperationValidation(clientOperationID: op.clientOperationID, op: op.op, status: .conflict, message: conflict)
        }
        return OperationValidation(
            clientOperationID: op.clientOperationID,
            op: op.op,
            status: .needsReview,
            message: "deleteBook requires approval",
            requiresApproval: true,
            risks: ["delete book record"],
            warnings: op.warnings
        )
    }

    private static func conflictMessage(expectedUpdatedAt: Date?, expectedRecordChangeTag: String?, snapshot: RemoteBookSnapshot) -> String? {
        if let expectedUpdatedAt,
           abs(snapshot.book.updatedAt.timeIntervalSince1970 - expectedUpdatedAt.timeIntervalSince1970) > 0.001 {
            return "expectedUpdatedAt mismatch"
        }
        if let expectedRecordChangeTag,
           let current = snapshot.recordChangeTag,
           current != expectedRecordChangeTag {
            return "expectedRecordChangeTag mismatch"
        }
        return nil
    }

    private static func failed(_ op: CreateBookOperation, _ message: String) -> OperationValidation {
        OperationValidation(clientOperationID: op.clientOperationID, op: op.op, status: .failed, message: message, warnings: op.warnings)
    }

    private static func failed(_ op: UpdateBookOperation, _ message: String) -> OperationValidation {
        OperationValidation(clientOperationID: op.clientOperationID, op: op.op, status: .failed, message: message, warnings: op.warnings)
    }

    private static func failed(_ op: UpdateBookCoverOperation, _ message: String) -> OperationValidation {
        OperationValidation(clientOperationID: op.clientOperationID, op: op.op, status: .failed, message: message, warnings: op.warnings)
    }

    private static func isSupportedField(_ field: String) -> Bool {
        ["title", "author", "translator", "publisher", "year", "isbn", "locationID"].contains(field)
    }

    public static func fieldValue(_ field: String, in book: Book) -> String {
        switch field {
        case "title":
            return book.title
        case "author":
            return book.author
        case "translator":
            return book.translator
        case "publisher":
            return book.publisher
        case "year":
            return book.year
        case "isbn":
            return book.isbn
        case "locationID":
            return book.locationID
        default:
            return book.customFields[field] ?? ""
        }
    }

    public static func setField(_ field: String, value: String, in book: inout Book) {
        switch field {
        case "title":
            book.title = value.trimmed
        case "author":
            book.author = value.trimmed
        case "translator":
            if value.trimmed.isEmpty {
                book.customFields[BookInfoFieldKey.translator] = nil
            } else {
                book.customFields[BookInfoFieldKey.translator] = value.trimmed
            }
        case "publisher":
            book.publisher = value.trimmed
        case "year":
            book.year = value.trimmed
        case "isbn":
            if value.trimmed.isEmpty {
                book.customFields[BookInfoFieldKey.isbn] = nil
            } else {
                book.customFields[BookInfoFieldKey.isbn] = value.trimmed
            }
        case "locationID":
            book.locationID = value.trimmed
        default:
            book.customFields[field] = value.trimmed
        }
    }
}
