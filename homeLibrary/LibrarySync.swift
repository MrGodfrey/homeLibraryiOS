//
//  LibrarySync.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import CloudKit
import CryptoKit
import Foundation

nonisolated enum LibrarySyncStatus: Equatable {
    case idle
    case syncing
    case upToDate(Date)
    case failed(String)

    var label: String {
        switch self {
        case .idle:
            return "等待同步"
        case .syncing:
            return "同步中"
        case .upToDate(let date):
            return "已同步 \(Self.relativeFormatter.localizedString(for: date, relativeTo: .now))"
        case .failed:
            return "同步失败"
        }
    }

    var systemImageName: String {
        switch self {
        case .idle:
            return "circle.dashed"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .upToDate:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.circle"
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

nonisolated struct RepositoryDescriptor: Sendable {
    let id: String
    let name: String
    let ownerProfileID: String
    let accessAccount: String
}

nonisolated struct RepositoryBootstrapResult: Sendable {
    let descriptor: RepositoryDescriptor
    let credentials: RepositoryCredentials
}

nonisolated struct RemoteBookSnapshot: Sendable {
    let book: Book
    let coverData: Data?
}

protocol LibraryRemoteSyncing {
    func fetchOwnedRepository(ownerProfileID: String) async throws -> RepositoryDescriptor?
    func createOwnedRepository(ownerProfileID: String, preferredName: String) async throws -> RepositoryBootstrapResult
    func fetchRepository(id: String) async throws -> RepositoryDescriptor
    func joinRepository(account: String, password: String) async throws -> RepositoryDescriptor
    func rotateCredentials(for repositoryID: String, ownerProfileID: String) async throws -> RepositoryCredentials
    func fetchBooks(in repositoryID: String) async throws -> [RemoteBookSnapshot]
    func upsertBook(_ book: Book, coverData: Data?, in repositoryID: String) async throws -> RemoteBookSnapshot
    func deleteBook(id: String, deletedAt: Date, in repositoryID: String) async throws
}

enum LibraryRemoteServiceError: LocalizedError {
    case repositoryNotFound
    case invalidRepositoryCredentials
    case noCloudAccount
    case permissionDenied
    case invalidCloudRecord
    case networkUnavailable
    case serviceUnavailable(retryAfter: TimeInterval?)
    case accountTemporarilyUnavailable
    case invalidContainerConfiguration
    case missingEntitlement
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .repositoryNotFound:
            return "没有找到对应的共享仓库。"
        case .invalidRepositoryCredentials:
            return "仓库账号或密码不正确。"
        case .noCloudAccount:
            return "当前设备没有可用的 iCloud 账号，无法连接 CloudKit。"
        case .permissionDenied:
            return "当前账号没有权限执行这个操作。"
        case .invalidCloudRecord:
            return "CloudKit 中的数据格式无法识别，请检查远端记录。"
        case .networkUnavailable:
            return "CloudKit 网络连接失败，请确认 iPhone 已联网并关闭代理或 VPN 后重试。"
        case .serviceUnavailable(let retryAfter):
            if let retryAfter, retryAfter > 0 {
                return "CloudKit 当前繁忙，请在 \(Int(retryAfter.rounded(.up))) 秒后重试。"
            }

            return "CloudKit 当前不可用，请稍后再试。"
        case .accountTemporarilyUnavailable:
            return "当前 iCloud 账号暂时不可用于 CloudKit，请稍后重试。"
        case .invalidContainerConfiguration:
            return "CloudKit 容器配置无效，请检查 App ID、Bundle ID 和 iCloud 容器设置。"
        case .missingEntitlement:
            return "应用缺少 CloudKit 权限，请检查签名和 iCloud capability 配置。"
        case .unknown(let message):
            return message
        }
    }
}

actor InMemoryLibraryRemoteService: LibraryRemoteSyncing {
    private struct StoredRepository: Sendable {
        var descriptor: RepositoryDescriptor
        var credentials: RepositoryCredentials
    }

    private var repositoriesByID: [String: StoredRepository] = [:]
    private var repositoryIDsByOwnerProfileID: [String: String] = [:]
    private var snapshotsByRepositoryID: [String: [String: RemoteBookSnapshot]] = [:]

    func fetchOwnedRepository(ownerProfileID: String) async throws -> RepositoryDescriptor? {
        guard let repositoryID = repositoryIDsByOwnerProfileID[ownerProfileID],
              let repository = repositoriesByID[repositoryID] else {
            return nil
        }

        return repository.descriptor
    }

    func createOwnedRepository(ownerProfileID: String, preferredName: String) async throws -> RepositoryBootstrapResult {
        if let repositoryID = repositoryIDsByOwnerProfileID[ownerProfileID],
           let repository = repositoriesByID[repositoryID] {
            return RepositoryBootstrapResult(
                descriptor: repository.descriptor,
                credentials: repository.credentials
            )
        }

        let credentials = Self.generateCredentials()
        let descriptor = RepositoryDescriptor(
            id: Self.makeRepositoryID(),
            name: preferredName,
            ownerProfileID: ownerProfileID,
            accessAccount: credentials.account
        )
        let repository = StoredRepository(descriptor: descriptor, credentials: credentials)

        repositoriesByID[descriptor.id] = repository
        repositoryIDsByOwnerProfileID[ownerProfileID] = descriptor.id
        snapshotsByRepositoryID[descriptor.id] = [:]

        return RepositoryBootstrapResult(descriptor: descriptor, credentials: credentials)
    }

    func fetchRepository(id: String) async throws -> RepositoryDescriptor {
        guard let repository = repositoriesByID[id] else {
            throw LibraryRemoteServiceError.repositoryNotFound
        }

        return repository.descriptor
    }

    func joinRepository(account: String, password: String) async throws -> RepositoryDescriptor {
        let normalizedAccount = account.trimmed
        let normalizedPassword = password.trimmed

        guard !normalizedAccount.isEmpty, !normalizedPassword.isEmpty else {
            throw LibraryRemoteServiceError.invalidRepositoryCredentials
        }

        guard let repository = repositoriesByID.values.first(where: { storedRepository in
            storedRepository.credentials.account == normalizedAccount &&
                storedRepository.credentials.password == normalizedPassword
        }) else {
            throw LibraryRemoteServiceError.invalidRepositoryCredentials
        }

        return repository.descriptor
    }

    func rotateCredentials(for repositoryID: String, ownerProfileID: String) async throws -> RepositoryCredentials {
        guard var repository = repositoriesByID[repositoryID] else {
            throw LibraryRemoteServiceError.repositoryNotFound
        }

        guard repository.descriptor.ownerProfileID == ownerProfileID else {
            throw LibraryRemoteServiceError.permissionDenied
        }

        let credentials = Self.generateCredentials()
        repository.credentials = credentials
        repository.descriptor = RepositoryDescriptor(
            id: repository.descriptor.id,
            name: repository.descriptor.name,
            ownerProfileID: repository.descriptor.ownerProfileID,
            accessAccount: credentials.account
        )
        repositoriesByID[repositoryID] = repository
        return credentials
    }

    func fetchBooks(in repositoryID: String) async throws -> [RemoteBookSnapshot] {
        guard repositoriesByID[repositoryID] != nil else {
            throw LibraryRemoteServiceError.repositoryNotFound
        }

        return snapshotsByRepositoryID[repositoryID, default: [:]]
            .values
            .sorted { left, right in
                if left.book.updatedAt != right.book.updatedAt {
                    return left.book.updatedAt > right.book.updatedAt
                }

                return left.book.createdAt > right.book.createdAt
            }
    }

    func upsertBook(_ book: Book, coverData: Data?, in repositoryID: String) async throws -> RemoteBookSnapshot {
        guard repositoriesByID[repositoryID] != nil else {
            throw LibraryRemoteServiceError.repositoryNotFound
        }

        let currentSnapshots = snapshotsByRepositoryID[repositoryID, default: [:]]
        let existingSnapshot = currentSnapshots[book.id]
        let storedCoverAssetID = coverData.map(Self.makeCoverAssetID(from:)) ??
            book.coverAssetID ??
            existingSnapshot?.book.coverAssetID
        let storedCoverData: Data?

        if let coverData {
            storedCoverData = coverData
        } else if storedCoverAssetID == existingSnapshot?.book.coverAssetID {
            storedCoverData = existingSnapshot?.coverData
        } else {
            storedCoverData = nil
        }

        var storedBook = book
        storedBook.coverAssetID = storedCoverAssetID

        let snapshot = RemoteBookSnapshot(book: storedBook, coverData: storedCoverData)
        snapshotsByRepositoryID[repositoryID, default: [:]][book.id] = snapshot
        return snapshot
    }

    func deleteBook(id: String, deletedAt: Date, in repositoryID: String) async throws {
        guard repositoriesByID[repositoryID] != nil else {
            throw LibraryRemoteServiceError.repositoryNotFound
        }

        _ = deletedAt
        snapshotsByRepositoryID[repositoryID, default: [:]][id] = nil
    }

    nonisolated private static func generateCredentials() -> RepositoryCredentials {
        RepositoryCredentials(
            account: "HL\(makeRandomCode(length: 8))",
            password: makeRandomPassword()
        )
    }

    nonisolated private static func makeRandomPassword() -> String {
        [
            makeRandomCode(length: 4),
            makeRandomCode(length: 4),
            makeRandomCode(length: 4)
        ]
        .joined(separator: "-")
    }

    nonisolated private static func makeRandomCode(length: Int) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }

    nonisolated private static func makeRepositoryID() -> String {
        "repo.\(UUID().uuidString)"
    }

    nonisolated private static func makeCoverAssetID(from data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "cover-\(hex)"
    }
}

actor CloudKitLibraryService: LibraryRemoteSyncing {
    private enum RecordType {
        static let repository = "LibraryRepository"
        static let book = "LibraryBook"
    }

    private enum RepositoryField {
        static let name = "name"
        static let ownerProfileID = "ownerProfileID"
        static let accessAccount = "accessAccount"
        static let passwordSalt = "passwordSalt"
        static let passwordHash = "passwordHash"
        static let schemaVersion = "schemaVersion"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
    }

    private enum BookField {
        static let repositoryID = "repositoryID"
        static let title = "title"
        static let author = "author"
        static let location = "location"
        static let payload = "payload"
        static let coverAssetID = "coverAssetID"
        static let coverAsset = "coverAsset"
        static let schemaVersion = "schemaVersion"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        static let deletedAt = "deletedAt"
    }

    private let container: CKContainer
    private let database: CKDatabase
    private var hasValidatedCloudAccount = false
    private var cachedCurrentUserRecordID: CKRecord.ID?
    private let maxRetryAttempts = 2

    init(containerIdentifier: String?) {
        if let containerIdentifier, !containerIdentifier.isEmpty {
            container = CKContainer(identifier: containerIdentifier)
        } else {
            container = CKContainer.default()
        }

        database = container.publicCloudDatabase
    }

    func fetchOwnedRepository(ownerProfileID: String) async throws -> RepositoryDescriptor? {
        try await ensureCloudAccountAvailable()

        let currentUserRecordID = try await currentUserRecordID()
        let query = CKQuery(
            recordType: RecordType.repository,
            predicate: NSPredicate(
                format: "%K == %@",
                CKRecord.SystemFieldKey.creatorUserRecordID,
                currentUserRecordID
            )
        )

        let records = try await performQuery(query)
        guard !records.isEmpty else {
            return nil
        }

        let selectedRecord = Self.selectOwnedRepository(from: records, preferredOwnerProfileID: ownerProfileID)
        return try Self.makeRepositoryDescriptor(from: selectedRecord)
    }

    func createOwnedRepository(ownerProfileID: String, preferredName: String) async throws -> RepositoryBootstrapResult {
        try await ensureCloudAccountAvailable()

        let credentials = Self.generateCredentials()
        let passwordSalt = Self.makeSalt()
        let passwordHash = Self.makePasswordHash(password: credentials.password, salt: passwordSalt)
        let repositoryID = Self.makeRepositoryID()
        let now = Date()

        let record = CKRecord(recordType: RecordType.repository, recordID: CKRecord.ID(recordName: repositoryID))
        record[RepositoryField.name] = preferredName as CKRecordValue
        record[RepositoryField.ownerProfileID] = ownerProfileID as CKRecordValue
        record[RepositoryField.accessAccount] = credentials.account as CKRecordValue
        record[RepositoryField.passwordSalt] = passwordSalt as CKRecordValue
        record[RepositoryField.passwordHash] = passwordHash as CKRecordValue
        record[RepositoryField.schemaVersion] = Int64(BookPayload.currentSchemaVersion) as CKRecordValue
        record[RepositoryField.createdAt] = now as CKRecordValue
        record[RepositoryField.updatedAt] = now as CKRecordValue

        _ = try await save(record)

        let descriptor = RepositoryDescriptor(
            id: repositoryID,
            name: preferredName,
            ownerProfileID: ownerProfileID,
            accessAccount: credentials.account
        )

        return RepositoryBootstrapResult(descriptor: descriptor, credentials: credentials)
    }

    func fetchRepository(id: String) async throws -> RepositoryDescriptor {
        try await ensureCloudAccountAvailable()
        let record = try await fetchRecord(recordID: CKRecord.ID(recordName: id))
        return try Self.makeRepositoryDescriptor(from: record)
    }

    func joinRepository(account: String, password: String) async throws -> RepositoryDescriptor {
        try await ensureCloudAccountAvailable()

        let normalizedAccount = account.trimmed
        let normalizedPassword = password.trimmed

        guard !normalizedAccount.isEmpty, !normalizedPassword.isEmpty else {
            throw LibraryRemoteServiceError.invalidRepositoryCredentials
        }

        let query = CKQuery(
            recordType: RecordType.repository,
            predicate: NSPredicate(format: "%K == %@", RepositoryField.accessAccount, normalizedAccount)
        )

        guard let record = try await performQuery(query, resultsLimit: 1).first else {
            throw LibraryRemoteServiceError.repositoryNotFound
        }

        let salt = try Self.requireStringField(RepositoryField.passwordSalt, in: record)
        let expectedHash = try Self.requireStringField(RepositoryField.passwordHash, in: record)
        let passwordHash = Self.makePasswordHash(password: normalizedPassword, salt: salt)

        guard passwordHash == expectedHash else {
            throw LibraryRemoteServiceError.invalidRepositoryCredentials
        }

        return try Self.makeRepositoryDescriptor(from: record)
    }

    func rotateCredentials(for repositoryID: String, ownerProfileID: String) async throws -> RepositoryCredentials {
        try await ensureCloudAccountAvailable()

        let recordID = CKRecord.ID(recordName: repositoryID)
        let record = try await fetchRecord(recordID: recordID)
        let remoteOwnerProfileID = try Self.requireStringField(RepositoryField.ownerProfileID, in: record)
        let currentUserRecordID = try await currentUserRecordID()

        guard remoteOwnerProfileID == ownerProfileID ||
                record.creatorUserRecordID?.recordName == currentUserRecordID.recordName else {
            throw LibraryRemoteServiceError.permissionDenied
        }

        let credentials = Self.generateCredentials()
        let salt = Self.makeSalt()
        let hash = Self.makePasswordHash(password: credentials.password, salt: salt)

        record[RepositoryField.accessAccount] = credentials.account as CKRecordValue
        record[RepositoryField.passwordSalt] = salt as CKRecordValue
        record[RepositoryField.passwordHash] = hash as CKRecordValue
        record[RepositoryField.updatedAt] = Date() as CKRecordValue

        _ = try await saveRecordHandlingConflicts(record)
        return credentials
    }

    func fetchBooks(in repositoryID: String) async throws -> [RemoteBookSnapshot] {
        try await ensureCloudAccountAvailable()

        let query = CKQuery(
            recordType: RecordType.book,
            predicate: NSPredicate(format: "%K == %@", BookField.repositoryID, repositoryID)
        )

        let records = try await performQuery(query)
        var snapshots: [RemoteBookSnapshot] = []

        for record in records {
            if record[BookField.deletedAt] != nil {
                continue
            }

            snapshots.append(try Self.makeRemoteBookSnapshot(from: record))
        }

        return snapshots.sorted { left, right in
            if left.book.updatedAt != right.book.updatedAt {
                return left.book.updatedAt > right.book.updatedAt
            }

            return left.book.createdAt > right.book.createdAt
        }
    }

    func upsertBook(_ book: Book, coverData: Data?, in repositoryID: String) async throws -> RemoteBookSnapshot {
        try await ensureCloudAccountAvailable()

        let recordID = CKRecord.ID(recordName: Self.bookRecordName(repositoryID: repositoryID, bookID: book.id))
        let existingRecord = try await fetchRecordIfPresent(recordID: recordID)
        let record = existingRecord ?? CKRecord(recordType: RecordType.book, recordID: recordID)

        let payload = book.payload
        let payloadJSON = try Self.encodePayload(payload)
        let storedCoverAssetID = coverData.map(Self.makeCoverAssetID(from:)) ?? book.coverAssetID

        record[BookField.repositoryID] = repositoryID as CKRecordValue
        record[BookField.title] = book.title as CKRecordValue
        record[BookField.author] = book.author as CKRecordValue
        record[BookField.location] = book.location.rawValue as CKRecordValue
        record[BookField.payload] = payloadJSON as CKRecordValue
        if let storedCoverAssetID {
            record[BookField.coverAssetID] = storedCoverAssetID as CKRecordValue
        } else {
            record[BookField.coverAssetID] = nil
        }
        record[BookField.schemaVersion] = Int64(payload.schemaVersion) as CKRecordValue
        record[BookField.createdAt] = book.createdAt as CKRecordValue
        record[BookField.updatedAt] = book.updatedAt as CKRecordValue
        record[BookField.deletedAt] = nil

        let temporaryAssetFile = coverData.map { TemporaryAssetFile(data: $0, fileExtension: "bin") }
        defer {
            temporaryAssetFile?.cleanup()
        }

        if let temporaryAssetFile {
            record[BookField.coverAsset] = CKAsset(fileURL: temporaryAssetFile.url)
        } else if storedCoverAssetID == nil {
            record[BookField.coverAsset] = nil
        }

        let savedRecord = try await saveRecordHandlingConflicts(record)
        return try Self.makeRemoteBookSnapshot(from: savedRecord, fallbackCoverData: coverData)
    }

    func deleteBook(id: String, deletedAt: Date, in repositoryID: String) async throws {
        try await ensureCloudAccountAvailable()

        let recordID = CKRecord.ID(recordName: Self.bookRecordName(repositoryID: repositoryID, bookID: id))
        let record = try await fetchRecordIfPresent(recordID: recordID) ?? CKRecord(recordType: RecordType.book, recordID: recordID)

        record[BookField.repositoryID] = repositoryID as CKRecordValue
        record[BookField.updatedAt] = deletedAt as CKRecordValue
        record[BookField.deletedAt] = deletedAt as CKRecordValue

        _ = try await saveRecordHandlingConflicts(record)
    }

    private func ensureCloudAccountAvailable() async throws {
        if hasValidatedCloudAccount {
            return
        }

        do {
            let status = try await accountStatus()

            switch status {
            case .available:
                hasValidatedCloudAccount = true
                return
            case .noAccount:
                throw LibraryRemoteServiceError.noCloudAccount
            default:
                throw LibraryRemoteServiceError.unknown("当前 CloudKit 不可用，请稍后再试。")
            }
        } catch let error as LibraryRemoteServiceError {
            throw error
        } catch {
            throw mapCloudError(error)
        }
    }

    private func accountStatus() async throws -> CKAccountStatus {
        try await performRetryingCloudKitRequest {
            try await withCheckedThrowingContinuation { continuation in
                self.container.accountStatus { status, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: status)
                    }
                }
            }
        }
    }

    private func currentUserRecordID() async throws -> CKRecord.ID {
        if let cachedCurrentUserRecordID {
            return cachedCurrentUserRecordID
        }

        do {
            let recordID = try await performRetryingCloudKitRequest {
                try await self.container.userRecordID()
            }
            cachedCurrentUserRecordID = recordID
            return recordID
        } catch {
            throw mapCloudError(error)
        }
    }

    private func fetchRecord(recordID: CKRecord.ID) async throws -> CKRecord {
        if let record = try await fetchRecordIfPresent(recordID: recordID) {
            return record
        }

        throw LibraryRemoteServiceError.repositoryNotFound
    }

    private func fetchRecordIfPresent(recordID: CKRecord.ID) async throws -> CKRecord? {
        do {
            return try await performRetryingCloudKitRequest {
                try await withCheckedThrowingContinuation { continuation in
                    self.database.fetch(withRecordID: recordID) { record, error in
                        if let ckError = error as? CKError, ckError.code == .unknownItem {
                            continuation.resume(returning: nil)
                            return
                        }

                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }

                        continuation.resume(returning: record)
                    }
                }
            }
        } catch {
            throw mapCloudError(error)
        }
    }

    private func save(_ record: CKRecord) async throws -> CKRecord {
        do {
            return try await performRetryingCloudKitRequest {
                try await withCheckedThrowingContinuation { continuation in
                    self.database.save(record) { savedRecord, error in
                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }

                        if let savedRecord {
                            continuation.resume(returning: savedRecord)
                        } else {
                            continuation.resume(throwing: LibraryRemoteServiceError.invalidCloudRecord)
                        }
                    }
                }
            }
        } catch {
            throw mapCloudError(error)
        }
    }

    private func saveRecordHandlingConflicts(_ record: CKRecord) async throws -> CKRecord {
        do {
            return try await save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            guard let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord else {
                throw mapCloudError(error)
            }

            Self.copyWritableFields(from: record, to: serverRecord)
            return try await save(serverRecord)
        } catch {
            throw mapCloudError(error)
        }
    }

    private func performQuery(
        _ query: CKQuery,
        resultsLimit: Int = CKQueryOperation.maximumResults,
        desiredKeys: [String]? = nil
    ) async throws -> [CKRecord] {
        var allRecords: [CKRecord] = []
        var currentCursor: CKQueryOperation.Cursor?

        repeat {
            let page = try await performQueryPage(
                query: currentCursor == nil ? query : nil,
                cursor: currentCursor,
                resultsLimit: resultsLimit,
                desiredKeys: desiredKeys
            )
            allRecords.append(contentsOf: page.records)
            currentCursor = page.cursor
        } while currentCursor != nil

        return allRecords
    }

    private func performQueryPage(
        query: CKQuery?,
        cursor: CKQueryOperation.Cursor?,
        resultsLimit: Int,
        desiredKeys: [String]?
    ) async throws -> (records: [CKRecord], cursor: CKQueryOperation.Cursor?) {
        do {
            return try await performRetryingCloudKitRequest {
                try await withCheckedThrowingContinuation { continuation in
                    var records: [CKRecord] = []
                    let operation: CKQueryOperation = {
                        if let cursor {
                            return CKQueryOperation(cursor: cursor)
                        }

                        return CKQueryOperation(query: query!)
                    }()

                    operation.resultsLimit = resultsLimit
                    operation.desiredKeys = desiredKeys
                    operation.recordMatchedBlock = { _, result in
                        if case .success(let record) = result {
                            records.append(record)
                        }
                    }
                    operation.queryResultBlock = { result in
                        switch result {
                        case .success(let cursor):
                            continuation.resume(returning: (records, cursor))
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }

                    self.database.add(operation)
                }
            }
        } catch {
            throw mapCloudError(error)
        }
    }

    private func performRetryingCloudKitRequest<T>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 0

        while true {
            do {
                return try await operation()
            } catch {
                guard let delay = Self.retryDelay(for: error, attempt: attempt, maxRetryAttempts: maxRetryAttempts) else {
                    throw error
                }

                attempt += 1
                try await Task.sleep(for: .seconds(delay))
            }
        }
    }

    nonisolated private static func retryDelay(
        for error: Error,
        attempt: Int,
        maxRetryAttempts: Int
    ) -> TimeInterval? {
        guard attempt < maxRetryAttempts, let cloudError = error as? CKError else {
            return nil
        }

        switch cloudError.code {
        case .networkUnavailable, .networkFailure, .serverResponseLost:
            return 0.75 * pow(2, Double(attempt))
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return retryAfter(for: cloudError) ?? (1.0 * pow(2, Double(attempt)))
        default:
            return nil
        }
    }

    nonisolated private static func retryAfter(for error: CKError) -> TimeInterval? {
        (error.userInfo[CKErrorRetryAfterKey] as? NSNumber)?.doubleValue
    }

    private func mapCloudError(_ error: Error) -> Error {
        guard let error = error as? CKError else {
            return error
        }

        switch error.code {
        case .networkUnavailable, .networkFailure, .serverResponseLost:
            return LibraryRemoteServiceError.networkUnavailable
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return LibraryRemoteServiceError.serviceUnavailable(retryAfter: Self.retryAfter(for: error))
        case .badContainer:
            return LibraryRemoteServiceError.invalidContainerConfiguration
        case .missingEntitlement:
            return LibraryRemoteServiceError.missingEntitlement
        case .notAuthenticated:
            return LibraryRemoteServiceError.noCloudAccount
        case .accountTemporarilyUnavailable:
            return LibraryRemoteServiceError.accountTemporarilyUnavailable
        case .permissionFailure:
            return LibraryRemoteServiceError.permissionDenied
        case .unknownItem:
            return LibraryRemoteServiceError.repositoryNotFound
        default:
            return LibraryRemoteServiceError.unknown(error.localizedDescription)
        }
    }

    nonisolated private static func makeRepositoryDescriptor(from record: CKRecord) throws -> RepositoryDescriptor {
        RepositoryDescriptor(
            id: record.recordID.recordName,
            name: try requireStringField(RepositoryField.name, in: record),
            ownerProfileID: try requireStringField(RepositoryField.ownerProfileID, in: record),
            accessAccount: try requireStringField(RepositoryField.accessAccount, in: record)
        )
    }

    nonisolated private static func selectOwnedRepository(
        from records: [CKRecord],
        preferredOwnerProfileID: String
    ) -> CKRecord {
        let preferredRecords = records.filter { record in
            (record[RepositoryField.ownerProfileID] as? String) == preferredOwnerProfileID
        }

        let candidates = preferredRecords.isEmpty ? records : preferredRecords
        return candidates.max { left, right in
            repositoryUpdatedAt(left) < repositoryUpdatedAt(right)
        } ?? records[0]
    }

    nonisolated private static func makeRemoteBookSnapshot(
        from record: CKRecord,
        fallbackCoverData: Data? = nil
    ) throws -> RemoteBookSnapshot {
        let payloadJSONString = try requireStringField(BookField.payload, in: record)
        let payload = try decodePayload(payloadJSONString)
        let createdAt = try requireDateField(BookField.createdAt, in: record)
        let updatedAt = try requireDateField(BookField.updatedAt, in: record)
        let coverAssetID = record[BookField.coverAssetID] as? String

        let bookID = Self.extractBookID(from: record.recordID.recordName)
        let book = Book(
            id: bookID,
            payload: payload,
            coverAssetID: coverAssetID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        let coverData = fallbackCoverData ?? loadAssetData(from: record[BookField.coverAsset] as? CKAsset)
        return RemoteBookSnapshot(book: book, coverData: coverData)
    }

    nonisolated private static func requireStringField(_ key: String, in record: CKRecord) throws -> String {
        guard let value = record[key] as? String, !value.trimmed.isEmpty else {
            throw LibraryRemoteServiceError.invalidCloudRecord
        }

        return value
    }

    nonisolated private static func requireDateField(_ key: String, in record: CKRecord) throws -> Date {
        guard let value = record[key] as? Date else {
            throw LibraryRemoteServiceError.invalidCloudRecord
        }

        return value
    }

    nonisolated private static func encodePayload(_ payload: BookPayload) throws -> String {
        let data = try JSONEncoder().encode(payload)

        guard let string = String(data: data, encoding: .utf8) else {
            throw LibraryRemoteServiceError.invalidCloudRecord
        }

        return string
    }

    nonisolated private static func decodePayload(_ string: String) throws -> BookPayload {
        guard let data = string.data(using: .utf8) else {
            throw LibraryRemoteServiceError.invalidCloudRecord
        }

        return try JSONDecoder().decode(BookPayload.self, from: data)
    }

    nonisolated private static func copyWritableFields(from source: CKRecord, to destination: CKRecord) {
        for key in source.allKeys() {
            destination[key] = source[key]
        }
    }

    nonisolated private static func extractBookID(from recordName: String) -> String {
        guard let separatorIndex = recordName.firstIndex(of: "|") else {
            return recordName
        }

        return String(recordName[recordName.index(after: separatorIndex)...])
    }

    nonisolated private static func bookRecordName(repositoryID: String, bookID: String) -> String {
        "\(repositoryID)|\(bookID)"
    }

    nonisolated private static func loadAssetData(from asset: CKAsset?) -> Data? {
        guard let url = asset?.fileURL else {
            return nil
        }

        return try? Data(contentsOf: url)
    }

    nonisolated private static func generateCredentials() -> RepositoryCredentials {
        RepositoryCredentials(
            account: "HL\(Self.makeRandomCode(length: 8))",
            password: Self.makeRandomPassword()
        )
    }

    nonisolated private static func makeRandomPassword() -> String {
        [
            makeRandomCode(length: 4),
            makeRandomCode(length: 4),
            makeRandomCode(length: 4)
        ]
        .joined(separator: "-")
    }

    nonisolated private static func makeRandomCode(length: Int) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }

    nonisolated private static func makeRepositoryID() -> String {
        "repo.\(UUID().uuidString)"
    }

    nonisolated private static func makeSalt() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    nonisolated private static func makePasswordHash(password: String, salt: String) -> String {
        let data = Data("\(salt):\(password)".utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func makeCoverAssetID(from data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "cover-\(hex)"
    }

    nonisolated private static func repositoryUpdatedAt(_ record: CKRecord) -> Date {
        if let updatedAt = record[RepositoryField.updatedAt] as? Date {
            return updatedAt
        }

        return record.modificationDate ?? .distantPast
    }
}

nonisolated private struct TemporaryAssetFile: Sendable {
    let url: URL

    init(data: Data, fileExtension: String) {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)

        try? data.write(to: url, options: [.atomic])
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: url)
    }
}
