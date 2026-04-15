//
//  LibrarySync.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import CloudKit
import CryptoKit
import Foundation
import OSLog
import UIKit

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

nonisolated struct RemoteBookSnapshot: Sendable {
    let book: Book
    let coverData: Data?
}

protocol LibraryRemoteSyncing {
    func listRepositories() async throws -> [LibraryRepositoryReference]
    func createOwnedRepository(preferredName: String) async throws -> LibraryRepositoryReference
    func refreshRepository(_ repository: LibraryRepositoryReference) async throws -> RemoteRepositorySnapshot
    func saveLocations(_ locations: [LibraryLocation], in repository: LibraryRepositoryReference) async throws -> [LibraryLocation]
    func upsertBook(_ book: Book, coverData: Data?, in repository: LibraryRepositoryReference) async throws -> RemoteBookSnapshot
    func deleteBook(id: String, deletedAt: Date, in repository: LibraryRepositoryReference) async throws
    func clearRepository(_ repository: LibraryRepositoryReference, resetLocations: [LibraryLocation]) async throws
    func exportRepository(_ repository: LibraryRepositoryReference) async throws -> LibraryImportPackage
    func deleteRepository(_ repository: LibraryRepositoryReference) async throws
}

protocol LibraryShareMetadataAccepting {
    func acceptShare(metadata: CKShare.Metadata) async throws
}

protocol LibraryShareLinkAccepting {
    func acceptShare(from url: URL) async throws -> CKShare.Metadata
}

enum LibraryRemoteServiceError: LocalizedError {
    case repositoryNotFound
    case shareNotAvailable
    case noCloudAccount
    case permissionDenied
    case invalidCloudRecord
    case networkUnavailable
    case serviceUnavailable(retryAfter: TimeInterval?)
    case accountTemporarilyUnavailable
    case invalidContainerConfiguration
    case missingEntitlement
    case missingQueryableIndex(field: String?)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .repositoryNotFound:
            return "没有找到对应的家庭书库。"
        case .shareNotAvailable:
            return "当前书库还没有可用的共享。"
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
        case .missingQueryableIndex(let field):
            if let field, !field.isEmpty {
                return "CloudKit schema 缺少 QUERYABLE 索引：\(field)。请在 CloudKit Dashboard 的 Schema 里为该字段添加 QUERYABLE。"
            }

            return "CloudKit schema 缺少 QUERYABLE 索引。请在 CloudKit Dashboard 的 Schema 里为相关字段添加 QUERYABLE。"
        case .unknown(let message):
            return message
        }
    }
}

actor InMemoryLibraryRemoteService: LibraryRemoteSyncing {
    private struct StoredRepository: Sendable {
        var repository: LibraryRepositoryReference
        var locations: [LibraryLocation]
        var snapshotsByBookID: [String: RemoteBookSnapshot]
    }

    private var repositoriesByID: [String: StoredRepository] = [:]

    func listRepositories() async throws -> [LibraryRepositoryReference] {
        repositoriesByID.values
            .map(\.repository)
            .sorted { left, right in
                if left.role != right.role {
                    return left.role == .owner
                }

                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
    }

    func createOwnedRepository(preferredName: String) async throws -> LibraryRepositoryReference {
        let repository = LibraryRepositoryReference(
            id: "repo.\(UUID().uuidString)",
            name: preferredName,
            role: .owner,
            databaseScope: .private,
            zoneName: "memory.\(UUID().uuidString)",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: nil,
            shareStatus: .notShared
        )

        repositoriesByID[repository.id] = StoredRepository(
            repository: repository,
            locations: LibraryLocation.defaultLocations(),
            snapshotsByBookID: [:]
        )

        return repository
    }

    func refreshRepository(_ repository: LibraryRepositoryReference) async throws -> RemoteRepositorySnapshot {
        guard let storedRepository = repositoriesByID[repository.id] else {
            throw LibraryRemoteServiceError.repositoryNotFound
        }

        return RemoteRepositorySnapshot(
            repository: storedRepository.repository,
            locations: storedRepository.locations.sorted(by: { $0.sortOrder < $1.sortOrder }),
            books: storedRepository.snapshotsByBookID.values.sorted { left, right in
                if left.book.updatedAt != right.book.updatedAt {
                    return left.book.updatedAt > right.book.updatedAt
                }

                return left.book.createdAt > right.book.createdAt
            }
        )
    }

    func saveLocations(_ locations: [LibraryLocation], in repository: LibraryRepositoryReference) async throws -> [LibraryLocation] {
        guard var storedRepository = repositoriesByID[repository.id] else {
            throw LibraryRemoteServiceError.repositoryNotFound
        }

        let normalizedLocations = locations
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .enumerated()
            .map { index, location in
                LibraryLocation(id: location.id, name: location.name, sortOrder: index, isVisible: location.isVisible)
            }

        storedRepository.locations = normalizedLocations
        repositoriesByID[repository.id] = storedRepository
        return normalizedLocations
    }

    func upsertBook(_ book: Book, coverData: Data?, in repository: LibraryRepositoryReference) async throws -> RemoteBookSnapshot {
        guard var storedRepository = repositoriesByID[repository.id] else {
            throw LibraryRemoteServiceError.repositoryNotFound
        }

        let existingSnapshot = storedRepository.snapshotsByBookID[book.id]
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
        storedRepository.snapshotsByBookID[book.id] = snapshot
        repositoriesByID[repository.id] = storedRepository
        return snapshot
    }

    func deleteBook(id: String, deletedAt: Date, in repository: LibraryRepositoryReference) async throws {
        guard var storedRepository = repositoriesByID[repository.id] else {
            throw LibraryRemoteServiceError.repositoryNotFound
        }

        _ = deletedAt
        storedRepository.snapshotsByBookID[id] = nil
        repositoriesByID[repository.id] = storedRepository
    }

    func clearRepository(_ repository: LibraryRepositoryReference, resetLocations: [LibraryLocation]) async throws {
        guard var storedRepository = repositoriesByID[repository.id] else {
            throw LibraryRemoteServiceError.repositoryNotFound
        }

        storedRepository.snapshotsByBookID = [:]
        storedRepository.locations = resetLocations
        repositoriesByID[repository.id] = storedRepository
    }

    func exportRepository(_ repository: LibraryRepositoryReference) async throws -> LibraryImportPackage {
        guard let storedRepository = repositoriesByID[repository.id] else {
            throw LibraryRemoteServiceError.repositoryNotFound
        }

        let locationsByID = Dictionary(uniqueKeysWithValues: storedRepository.locations.map { ($0.id, $0) })
        let books = storedRepository.snapshotsByBookID.values
            .map { LibraryImportBook(book: $0.book, coverData: $0.coverData, locationsByID: locationsByID) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        return LibraryImportPackage(
            schemaVersion: LibraryImportPackage.currentSchemaVersion,
            source: "memory",
            exportedAt: .now,
            locations: storedRepository.locations.map(LibraryImportLocation.init(location:)),
            books: books
        )
    }

    func deleteRepository(_ repository: LibraryRepositoryReference) async throws {
        repositoriesByID[repository.id] = nil
    }

    nonisolated private static func makeCoverAssetID(from data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "cover-\(hex)"
    }
}

final class CloudKitLibraryService: NSObject, LibraryRemoteSyncing {
    private enum RecordType {
        nonisolated static let repository = "LibraryRepository"
        nonisolated static let book = "LibraryBook"
        nonisolated static let location = "LibraryLocation"
    }

    private enum RepositoryField {
        nonisolated static let name = "name"
        nonisolated static let schemaVersion = "schemaVersion"
        nonisolated static let createdAt = "createdAt"
        nonisolated static let updatedAt = "updatedAt"
    }

    private enum LocationField {
        nonisolated static let name = "name"
        nonisolated static let sortOrder = "sortOrder"
        nonisolated static let isVisible = "isVisible"
    }

    private enum BookField {
        nonisolated static let title = "title"
        nonisolated static let author = "author"
        nonisolated static let locationID = "locationID"
        nonisolated static let payload = "payload"
        nonisolated static let coverAssetID = "coverAssetID"
        nonisolated static let coverAsset = "coverAsset"
        nonisolated static let schemaVersion = "schemaVersion"
        nonisolated static let createdAt = "createdAt"
        nonisolated static let updatedAt = "updatedAt"
    }

    private enum RecordName {
        nonisolated static let repository = "repository"
        nonisolated static func location(_ id: String) -> String { "location.\(id)" }
        nonisolated static func book(_ id: String) -> String { "book.\(id)" }
    }

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let sharedDatabase: CKDatabase
    private let liveTestZonePrefix: String
    private let sharePublicPermission: CKShare.ParticipantPermission
    private let logger = Logger(subsystem: "yu.homeLibrary", category: "CloudKit")
    private var hasValidatedCloudAccount = false

    init(
        containerIdentifier: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        let environment = LibraryEnvironment.resolved(environment)

        if let containerIdentifier, !containerIdentifier.isEmpty {
            container = CKContainer(identifier: containerIdentifier)
        } else {
            container = CKContainer.default()
        }

        privateDatabase = container.privateCloudDatabase
        sharedDatabase = container.sharedCloudDatabase
        liveTestZonePrefix = environment["HOME_LIBRARY_CLOUDKIT_LIVE_TESTS"] == "1" ? "library.live-test." : "library."
        sharePublicPermission = environment["HOME_LIBRARY_CLOUDKIT_AUTOMATION_ALLOW_PUBLIC_SHARE"] == "1" ? .readWrite : .none
        super.init()
    }

    func listRepositories() async throws -> [LibraryRepositoryReference] {
        try await ensureCloudAccountAvailable()

        let ownedRepositories = try await fetchRepositories(in: privateDatabase, scope: .private, role: .owner)
        let sharedRepositories = try await fetchRepositories(in: sharedDatabase, scope: .shared, role: .member)

        return (ownedRepositories + sharedRepositories).sorted { left, right in
            if left.role != right.role {
                return left.role == .owner
            }

            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    func createOwnedRepository(preferredName: String) async throws -> LibraryRepositoryReference {
        try await ensureCloudAccountAvailable()

        let zoneID = CKRecordZone.ID(zoneName: makeZoneName(), ownerName: CKCurrentUserDefaultName)
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await privateDatabase.modifyRecordZones(saving: [zone], deleting: [])

        let now = Date()
        let repositoryRecord = CKRecord(recordType: RecordType.repository, recordID: CKRecord.ID(recordName: RecordName.repository, zoneID: zoneID))
        repositoryRecord[RepositoryField.name] = preferredName as CKRecordValue
        repositoryRecord[RepositoryField.schemaVersion] = Int64(LibraryImportPackage.currentSchemaVersion) as CKRecordValue
        repositoryRecord[RepositoryField.createdAt] = now as CKRecordValue
        repositoryRecord[RepositoryField.updatedAt] = now as CKRecordValue

        let locationRecords = LibraryLocation.defaultLocations().map { makeLocationRecord(for: $0, zoneID: zoneID) }
        _ = try await saveRecords([repositoryRecord] + locationRecords, in: privateDatabase, operationName: "createOwnedRepository", zoneID: zoneID)

        return LibraryRepositoryReference(
            id: zoneID.zoneName,
            name: preferredName,
            role: .owner,
            databaseScope: .private,
            zoneName: zoneID.zoneName,
            zoneOwnerName: zoneID.ownerName,
            shareRecordName: nil,
            shareStatus: .notShared
        )
    }

    func refreshRepository(_ repository: LibraryRepositoryReference) async throws -> RemoteRepositorySnapshot {
        try await ensureCloudAccountAvailable()
        let database = database(for: repository.databaseScope)
        let zoneID = repository.zoneID

        let repositoryRecord = try await fetchRecord(
            recordID: CKRecord.ID(recordName: RecordName.repository, zoneID: zoneID),
            in: database,
            operationName: "refreshRepository.repository"
        )
        let zone = try await fetchZone(zoneID: zoneID, in: database)
        let updatedRepository = try makeRepositoryReference(from: repositoryRecord, role: repository.role, scope: repository.databaseScope, zone: zone)
        let locationRecords = try await fetchRecords(recordType: RecordType.location, inZoneWith: zoneID, database: database, operationName: "refreshRepository.locations")
        let bookRecords = try await fetchRecords(recordType: RecordType.book, inZoneWith: zoneID, database: database, operationName: "refreshRepository.books")

        let locations = try locationRecords.map(Self.makeLocation).sorted { $0.sortOrder < $1.sortOrder }
        let books = try bookRecords.map { try Self.makeRemoteBookSnapshot(from: $0) }
            .sorted { left, right in
                if left.book.updatedAt != right.book.updatedAt {
                    return left.book.updatedAt > right.book.updatedAt
                }

                return left.book.createdAt > right.book.createdAt
            }

        return RemoteRepositorySnapshot(repository: updatedRepository, locations: locations, books: books)
    }

    func saveLocations(_ locations: [LibraryLocation], in repository: LibraryRepositoryReference) async throws -> [LibraryLocation] {
        try await ensureCloudAccountAvailable()
        let database = database(for: repository.databaseScope)
        let zoneID = repository.zoneID
        let normalizedLocations = locations
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .enumerated()
            .map { index, location in
                LibraryLocation(id: location.id, name: location.name, sortOrder: index, isVisible: location.isVisible)
            }

        let existingLocationRecords = try await fetchRecords(recordType: RecordType.location, inZoneWith: zoneID, database: database, operationName: "saveLocations.fetch")
        let existingIDs = Set(existingLocationRecords.map(\.recordID.recordName))
        let recordsToSave = normalizedLocations.map { makeLocationRecord(for: $0, zoneID: zoneID) }
        let desiredRecordIDs = Set(recordsToSave.map(\.recordID.recordName))
        let recordIDsToDelete = existingIDs.subtracting(desiredRecordIDs).map { CKRecord.ID(recordName: $0, zoneID: zoneID) }

        _ = try await saveRecords(recordsToSave, deleting: recordIDsToDelete, in: database, operationName: "saveLocations.modify", zoneID: zoneID)
        return normalizedLocations
    }

    func upsertBook(_ book: Book, coverData: Data?, in repository: LibraryRepositoryReference) async throws -> RemoteBookSnapshot {
        try await ensureCloudAccountAvailable()
        let database = database(for: repository.databaseScope)
        let zoneID = repository.zoneID
        let recordID = CKRecord.ID(recordName: RecordName.book(book.id), zoneID: zoneID)
        let record = try await fetchRecordIfPresent(recordID: recordID, in: database, operationName: "upsertBook.fetch") ?? CKRecord(recordType: RecordType.book, recordID: recordID)

        let payloadJSON = try Self.encodePayload(book.payload)
        let storedCoverAssetID = coverData.map(Self.makeCoverAssetID(from:)) ?? book.coverAssetID

        record[BookField.title] = book.title as CKRecordValue
        record[BookField.author] = book.author as CKRecordValue
        record[BookField.locationID] = book.locationID as CKRecordValue
        record[BookField.payload] = payloadJSON as CKRecordValue
        record[BookField.coverAssetID] = storedCoverAssetID as CKRecordValue?
        record[BookField.schemaVersion] = Int64(book.payload.schemaVersion) as CKRecordValue
        record[BookField.createdAt] = book.createdAt as CKRecordValue
        record[BookField.updatedAt] = book.updatedAt as CKRecordValue

        let temporaryAssetFile = coverData.map { TemporaryAssetFile(data: $0, fileExtension: "bin") }
        defer {
            temporaryAssetFile?.cleanup()
        }

        if let temporaryAssetFile {
            record[BookField.coverAsset] = CKAsset(fileURL: temporaryAssetFile.url)
        } else if storedCoverAssetID == nil {
            record[BookField.coverAsset] = nil
        }

        let savedRecord = try await saveRecord(record, in: database, operationName: "upsertBook.modify", zoneID: zoneID)
        return try Self.makeRemoteBookSnapshot(from: savedRecord, fallbackCoverData: coverData)
    }

    func deleteBook(id: String, deletedAt: Date, in repository: LibraryRepositoryReference) async throws {
        try await ensureCloudAccountAvailable()
        _ = deletedAt

        let database = database(for: repository.databaseScope)
        let zoneID = repository.zoneID
        let recordID = CKRecord.ID(recordName: RecordName.book(id), zoneID: zoneID)
        _ = try await saveRecords([], deleting: [recordID], in: database, operationName: "deleteBook", zoneID: zoneID)
    }

    func clearRepository(_ repository: LibraryRepositoryReference, resetLocations: [LibraryLocation]) async throws {
        try await ensureCloudAccountAvailable()
        let database = database(for: repository.databaseScope)
        let zoneID = repository.zoneID

        let bookRecords = try await fetchRecords(recordType: RecordType.book, inZoneWith: zoneID, database: database, operationName: "clearRepository.books")
        let locationRecords = try await fetchRecords(recordType: RecordType.location, inZoneWith: zoneID, database: database, operationName: "clearRepository.locations")
        let resetLocationRecordNames = Set(resetLocations.map { RecordName.location($0.id) })
        let recordIDsToDelete =
            bookRecords.map(\.recordID) +
            locationRecords
                .map(\.recordID)
                .filter { !resetLocationRecordNames.contains($0.recordName) }

        let repositoryRecord = try await fetchRecord(
            recordID: CKRecord.ID(recordName: RecordName.repository, zoneID: zoneID),
            in: database,
            operationName: "clearRepository.repository"
        )
        repositoryRecord[RepositoryField.updatedAt] = Date() as CKRecordValue
        let locationRecordsToSave = resetLocations.map { makeLocationRecord(for: $0, zoneID: zoneID) }
        _ = try await saveRecords([repositoryRecord] + locationRecordsToSave, deleting: recordIDsToDelete, in: database, operationName: "clearRepository.modify", zoneID: zoneID)
    }

    func exportRepository(_ repository: LibraryRepositoryReference) async throws -> LibraryImportPackage {
        let snapshot = try await refreshRepository(repository)
        let locationsByID = Dictionary(uniqueKeysWithValues: snapshot.locations.map { ($0.id, $0) })

        return LibraryImportPackage(
            schemaVersion: LibraryImportPackage.currentSchemaVersion,
            source: repository.name,
            exportedAt: .now,
            locations: snapshot.locations.map(LibraryImportLocation.init(location:)),
            books: snapshot.books.map { LibraryImportBook(book: $0.book, coverData: $0.coverData, locationsByID: locationsByID) }
        )
    }

    func deleteRepository(_ repository: LibraryRepositoryReference) async throws {
        try await ensureCloudAccountAvailable()

        switch repository.databaseScope {
        case .private:
            guard repository.isOwner else {
                throw LibraryRemoteServiceError.permissionDenied
            }

            let zoneID = repository.zoneID
            _ = try await privateDatabase.modifyRecordZones(saving: [], deleting: [zoneID])
        case .shared:
            guard let shareRecordName = repository.shareRecordName?.trimmed.nilIfEmpty else {
                throw LibraryRemoteServiceError.shareNotAvailable
            }

            let shareRecordID = CKRecord.ID(recordName: shareRecordName, zoneID: repository.zoneID)
            _ = try await saveRecords(
                [],
                deleting: [shareRecordID],
                in: sharedDatabase,
                operationName: "deleteRepository.leaveShare",
                zoneID: repository.zoneID
            )
        }
    }

    func acceptShare(metadata: CKShare.Metadata) async throws {
        try await ensureCloudAccountAvailable()
        _ = try await container.accept([metadata])
    }

    func shareMetadata(for url: URL) async throws -> CKShare.Metadata {
        try await ensureCloudAccountAvailable()
        return try await container.shareMetadata(for: url)
    }

    func shareURL(for repository: LibraryRepositoryReference) async throws -> URL {
        guard repository.isOwner else {
            throw LibraryRemoteServiceError.permissionDenied
        }

        try await ensureCloudAccountAvailable()
        let share = try await fetchOrCreateZoneShare(for: repository)
        guard let url = share.url else {
            throw LibraryRemoteServiceError.shareNotAvailable
        }

        return url
    }

    @MainActor
    func makeSharingController(for repository: LibraryRepositoryReference) async throws -> UICloudSharingController {
        guard repository.isOwner else {
            throw LibraryRemoteServiceError.permissionDenied
        }

        try await ensureCloudAccountAvailable()
        let share = try await fetchOrCreateZoneShare(for: repository)
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        return controller
    }

    private func fetchOrCreateZoneShare(for repository: LibraryRepositoryReference) async throws -> CKShare {
        let zone = try await fetchZone(zoneID: repository.zoneID, in: privateDatabase)

        if let shareReference = zone.share,
           let existingShare = try await fetchRecordIfPresent(recordID: shareReference.recordID, in: privateDatabase, operationName: "fetchOrCreateZoneShare.fetchShare") as? CKShare {
            if existingShare.publicPermission != sharePublicPermission {
                existingShare.publicPermission = sharePublicPermission
                guard let savedShare = try await saveRecord(existingShare, in: privateDatabase, operationName: "fetchOrCreateZoneShare.updateShare", zoneID: repository.zoneID) as? CKShare else {
                    throw LibraryRemoteServiceError.invalidCloudRecord
                }

                return savedShare
            }

            return existingShare
        }

        let share = CKShare(recordZoneID: repository.zoneID)
        share[CKShare.SystemFieldKey.title] = repository.name as CKRecordValue
        share.publicPermission = sharePublicPermission

        guard let savedShare = try await saveRecord(share, in: privateDatabase, operationName: "fetchOrCreateZoneShare.createShare", zoneID: repository.zoneID) as? CKShare else {
            throw LibraryRemoteServiceError.invalidCloudRecord
        }

        return savedShare
    }

    private func fetchRepositories(
        in database: CKDatabase,
        scope: CloudDatabaseScope,
        role: RepositoryRole
    ) async throws -> [LibraryRepositoryReference] {
        let zoneIDs = try await fetchZoneIDs(in: database)
        let zonesByID = try await fetchZones(zoneIDs: zoneIDs, in: database)
        var repositories: [LibraryRepositoryReference] = []

        for zoneID in zoneIDs {
            let repositoryRecordID = CKRecord.ID(recordName: RecordName.repository, zoneID: zoneID)
            guard let record = try await fetchRecordIfPresent(
                recordID: repositoryRecordID,
                in: database,
                operationName: "fetchRepositories.shared.record"
            ) else {
                continue
            }

            guard let zone = zonesByID[zoneID] else {
                continue
            }

            repositories.append(try makeRepositoryReference(from: record, role: role, scope: scope, zone: zone))
        }

        return repositories.sorted { left, right in
            if left.role != right.role {
                return left.role == .owner
            }

            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    private func fetchZoneIDs(in database: CKDatabase) async throws -> [CKRecordZone.ID] {
        logCloudKit("fetchZoneIDs", scope: database.databaseScope, zoneID: nil, detail: "scan database changes")

        do {
            var changeToken: CKServerChangeToken?
            var zoneIDs: Set<CKRecordZone.ID> = []
            var moreComing = false

            repeat {
                let changes = try await database.databaseChanges(since: changeToken)
                zoneIDs.formUnion(changes.modifications.map(\.zoneID))
                changeToken = changes.changeToken
                moreComing = changes.moreComing
            } while moreComing

            return zoneIDs.sorted { left, right in
                if left.zoneName != right.zoneName {
                    return left.zoneName < right.zoneName
                }

                return left.ownerName < right.ownerName
            }
        } catch {
            logCloudKit("fetchZoneIDs.failed", scope: database.databaseScope, zoneID: nil, detail: "\(error)")
            throw mapCloudError(error)
        }
    }

    private func fetchZones(zoneIDs: [CKRecordZone.ID], in database: CKDatabase) async throws -> [CKRecordZone.ID: CKRecordZone] {
        guard !zoneIDs.isEmpty else {
            return [:]
        }

        logCloudKit("fetchZones", scope: database.databaseScope, zoneID: nil, detail: "count=\(zoneIDs.count)")

        do {
            let result = try await database.recordZones(for: zoneIDs)
            var zones: [CKRecordZone.ID: CKRecordZone] = [:]

            for zoneID in zoneIDs {
                guard let value = result[zoneID] else {
                    continue
                }

                switch value {
                case .success(let zone):
                    zones[zoneID] = zone
                case .failure(let error):
                    throw mapCloudError(error)
                }
            }

            return zones
        } catch {
            logCloudKit("fetchZones.failed", scope: database.databaseScope, zoneID: nil, detail: "\(error)")
            throw mapCloudError(error)
        }
    }

    private func fetchZone(zoneID: CKRecordZone.ID, in database: CKDatabase) async throws -> CKRecordZone {
        let zones = try await fetchZones(zoneIDs: [zoneID], in: database)
        guard let zone = zones[zoneID] else {
            throw LibraryRemoteServiceError.repositoryNotFound
        }
        return zone
    }

    private func ensureCloudAccountAvailable() async throws {
        if hasValidatedCloudAccount {
            return
        }

        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                hasValidatedCloudAccount = true
            case .noAccount:
                throw LibraryRemoteServiceError.noCloudAccount
            default:
                throw LibraryRemoteServiceError.unknown("当前 CloudKit 不可用，请稍后再试。")
            }
        } catch {
            throw mapCloudError(error)
        }
    }

    private func fetchRecord(
        recordID: CKRecord.ID,
        in database: CKDatabase,
        operationName: String
    ) async throws -> CKRecord {
        if let record = try await fetchRecordIfPresent(recordID: recordID, in: database, operationName: operationName) {
            return record
        }

        throw LibraryRemoteServiceError.repositoryNotFound
    }

    private func fetchRecordIfPresent(
        recordID: CKRecord.ID,
        in database: CKDatabase,
        operationName: String
    ) async throws -> CKRecord? {
        logCloudKit(operationName, scope: database.databaseScope, zoneID: recordID.zoneID, detail: "fetch \(recordID.recordName)")

        do {
            let records = try await database.records(for: [recordID])
            guard let recordResult = records[recordID] else {
                return nil
            }

            switch recordResult {
            case .success(let record):
                return record
            case .failure(let error):
                let mappedError = mapCloudError(error)
                if case LibraryRemoteServiceError.repositoryNotFound = mappedError {
                    return nil
                }

                throw mappedError
            }
        } catch {
            logCloudKit("\(operationName).failed", scope: database.databaseScope, zoneID: recordID.zoneID, detail: "\(error)")
            throw mapCloudError(error)
        }
    }

    private func fetchRecords(
        recordType: String,
        inZoneWith zoneID: CKRecordZone.ID,
        database: CKDatabase,
        operationName: String
    ) async throws -> [CKRecord] {
        let records = try await fetchAllZoneRecords(
            inZoneWith: zoneID,
            database: database,
            operationName: operationName
        )
        return records.filter { $0.recordType == recordType }
    }

    private func fetchAllZoneRecords(
        inZoneWith zoneID: CKRecordZone.ID,
        database: CKDatabase,
        operationName: String
    ) async throws -> [CKRecord] {
        logCloudKit(operationName, scope: database.databaseScope, zoneID: zoneID, detail: "scan zone records")

        do {
            var recordsByID: [CKRecord.ID: CKRecord] = [:]
            var changeToken: CKServerChangeToken?
            var moreComing = false

            repeat {
                let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: changeToken)
                for (recordID, result) in changes.modificationResultsByID {
                    switch result {
                    case .success(let modification):
                        recordsByID[recordID] = modification.record
                    case .failure(let error):
                        throw mapCloudError(error)
                    }
                }
                for deletion in changes.deletions {
                    recordsByID[deletion.recordID] = nil
                }
                changeToken = changes.changeToken
                moreComing = changes.moreComing
            } while moreComing

            return Array(recordsByID.values)
        } catch {
            logCloudKit("\(operationName).failed", scope: database.databaseScope, zoneID: zoneID, detail: "\(error)")
            throw mapCloudError(error)
        }
    }

    private func saveRecord(
        _ record: CKRecord,
        in database: CKDatabase,
        operationName: String,
        zoneID: CKRecordZone.ID
    ) async throws -> CKRecord {
        let result = try await saveRecords([record], deleting: [], in: database, operationName: operationName, zoneID: zoneID)
        guard let recordResult = result.saveResults[record.recordID] else {
            throw LibraryRemoteServiceError.invalidCloudRecord
        }

        switch recordResult {
        case .success(let savedRecord):
            return savedRecord
        case .failure(let error):
            throw mapCloudError(error)
        }
    }

    private func saveRecords(
        _ records: [CKRecord],
        deleting recordIDs: [CKRecord.ID] = [],
        in database: CKDatabase,
        operationName: String,
        zoneID: CKRecordZone.ID
    ) async throws -> (saveResults: [CKRecord.ID: Result<CKRecord, Error>], deleteResults: [CKRecord.ID: Result<Void, Error>]) {
        logCloudKit(operationName, scope: database.databaseScope, zoneID: zoneID, detail: "save=\(records.count) delete=\(recordIDs.count)")

        do {
            return try await database.modifyRecords(saving: records, deleting: recordIDs, savePolicy: .changedKeys, atomically: true)
        } catch let error as CKError where error.code == .serverRecordChanged {
            guard let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord,
                  let conflictingRecord = records.first(where: { $0.recordID == serverRecord.recordID }) else {
                throw mapCloudError(error)
            }

            Self.copyWritableFields(from: conflictingRecord, to: serverRecord)
            return try await database.modifyRecords(saving: [serverRecord], deleting: recordIDs, savePolicy: .changedKeys, atomically: true)
        } catch {
            logCloudKit("\(operationName).failed", scope: database.databaseScope, zoneID: zoneID, detail: "\(error)")
            throw mapCloudError(error)
        }
    }

    private func database(for scope: CloudDatabaseScope) -> CKDatabase {
        switch scope {
        case .private:
            return privateDatabase
        case .shared:
            return sharedDatabase
        }
    }

    private func makeZoneName() -> String {
        "\(liveTestZonePrefix)\(UUID().uuidString)"
    }

    private func makeLocationRecord(for location: LibraryLocation, zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: RecordType.location, recordID: CKRecord.ID(recordName: RecordName.location(location.id), zoneID: zoneID))
        record[LocationField.name] = location.name as CKRecordValue
        record[LocationField.sortOrder] = Int64(location.sortOrder) as CKRecordValue
        record[LocationField.isVisible] = location.isVisible as CKRecordValue
        return record
    }

    private func makeRepositoryReference(
        from record: CKRecord,
        role: RepositoryRole,
        scope: CloudDatabaseScope,
        zone: CKRecordZone
    ) throws -> LibraryRepositoryReference {
        LibraryRepositoryReference(
            id: record.recordID.zoneID.zoneName,
            name: try Self.requireStringField(RepositoryField.name, in: record),
            role: role,
            databaseScope: scope,
            zoneName: record.recordID.zoneID.zoneName,
            zoneOwnerName: record.recordID.zoneID.ownerName,
            shareRecordName: zone.share?.recordID.recordName,
            shareStatus: zone.share == nil ? .notShared : .shared
        )
    }

    private func logCloudKit(_ operation: String, scope: CKDatabase.Scope, zoneID: CKRecordZone.ID?, detail: String) {
        #if DEBUG
        logger.notice("[\(operation)] scope=\(String(describing: scope), privacy: .public) zone=\(zoneID?.zoneName ?? "-", privacy: .public) detail=\(detail, privacy: .public)")
        #else
        let environment = LibraryEnvironment.resolved(ProcessInfo.processInfo.environment)
        if environment["HOME_LIBRARY_DEBUG_CLOUDKIT"] == "1" ||
            environment["HOME_LIBRARY_CLOUDKIT_LIVE_TESTS"] == "1" {
            logger.notice("[\(operation)] scope=\(String(describing: scope), privacy: .public) zone=\(zoneID?.zoneName ?? "-", privacy: .public) detail=\(detail, privacy: .public)")
        }
        #endif
    }

    private func mapCloudError(_ error: Error) -> Error {
        guard let error = error as? CKError else {
            return error
        }

        if let missingQueryableField = Self.extractMissingQueryableField(from: error.localizedDescription) {
            return LibraryRemoteServiceError.missingQueryableIndex(field: missingQueryableField)
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
        case .unknownItem, .zoneNotFound:
            return LibraryRemoteServiceError.repositoryNotFound
        default:
            return LibraryRemoteServiceError.unknown(error.localizedDescription)
        }
    }

    nonisolated private static func retryAfter(for error: CKError) -> TimeInterval? {
        (error.userInfo[CKErrorRetryAfterKey] as? NSNumber)?.doubleValue
    }

    nonisolated private static func extractMissingQueryableField(from message: String) -> String? {
        let marker = "Field "
        let suffix = " is not marked queryable"

        guard let markerRange = message.range(of: marker),
              let suffixRange = message.range(of: suffix),
              markerRange.upperBound <= suffixRange.lowerBound else {
            return nil
        }

        return String(message[markerRange.upperBound..<suffixRange.lowerBound]).trimmed.nilIfEmpty
    }

    nonisolated private static func makeLocation(from record: CKRecord) throws -> LibraryLocation {
        LibraryLocation(
            id: record.recordID.recordName.replacingOccurrences(of: "location.", with: ""),
            name: try requireStringField(LocationField.name, in: record),
            sortOrder: Int(try requireInt64Field(LocationField.sortOrder, in: record)),
            isVisible: (record[LocationField.isVisible] as? NSNumber)?.boolValue ?? true
        )
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

        let bookID = record.recordID.recordName.replacingOccurrences(of: "book.", with: "")
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

    nonisolated private static func requireInt64Field(_ key: String, in record: CKRecord) throws -> Int64 {
        guard let value = record[key] as? NSNumber else {
            throw LibraryRemoteServiceError.invalidCloudRecord
        }

        return value.int64Value
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

    nonisolated private static func loadAssetData(from asset: CKAsset?) -> Data? {
        guard let url = asset?.fileURL else {
            return nil
        }

        return try? Data(contentsOf: url)
    }

    nonisolated private static func makeCoverAssetID(from data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "cover-\(hex)"
    }
}

extension CloudKitLibraryService: LibraryShareMetadataAccepting, LibraryShareLinkAccepting {
    func acceptShare(from url: URL) async throws -> CKShare.Metadata {
        let metadata = try await shareMetadata(for: url)
        try await acceptShare(metadata: metadata)
        return metadata
    }
}

private extension Dictionary where Key == CKRecordZone.ID, Value == CKRecordZone {
    func record(for zoneID: CKRecordZone.ID) throws -> CKRecordZone {
        guard let zone = self[zoneID] else {
            throw LibraryRemoteServiceError.repositoryNotFound
        }
        return zone
    }
}

private extension LibraryRepositoryReference {
    var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwnerName)
    }
}

private final class TemporaryAssetFile {
    let url: URL

    init(data: Data, fileExtension: String) {
        let directoryURL = FileManager.default.temporaryDirectory
        url = directoryURL.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExtension)
        try? data.write(to: url, options: [.atomic])
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: url)
    }
}
