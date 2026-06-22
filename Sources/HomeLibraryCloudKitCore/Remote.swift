import CloudKit
import Foundation

public protocol LibraryRemote {
    func accountStatus() async throws -> CKAccountStatus
    func listRepositories() async throws -> [LibraryRepositoryReference]
    func createOwnedRepository(preferredName: String) async throws -> LibraryRepositoryReference
    func refreshRepository(_ repository: LibraryRepositoryReference) async throws -> RemoteRepositorySnapshot
    func saveLocations(_ locations: [LibraryLocation], in repository: LibraryRepositoryReference) async throws -> [LibraryLocation]
    func upsertBook(_ book: Book, coverData: Data?, in repository: LibraryRepositoryReference) async throws -> RemoteBookSnapshot
    func deleteBook(id: String, in repository: LibraryRepositoryReference) async throws
    func deleteRepository(_ repository: LibraryRepositoryReference) async throws
}

public actor InMemoryLibraryRemote: LibraryRemote {
    private struct StoredRepository: Sendable {
        var repository: LibraryRepositoryReference
        var locations: [LibraryLocation]
        var snapshotsByBookID: [String: RemoteBookSnapshot]
    }

    private var repositoriesByID: [String: StoredRepository] = [:]
    private var tagCounter = 0

    public init() {}

    public func seedRepository(
        _ repository: LibraryRepositoryReference,
        locations: [LibraryLocation] = LibraryLocation.defaultLocations(),
        books: [RemoteBookSnapshot] = []
    ) {
        repositoriesByID[repository.id] = StoredRepository(
            repository: repository,
            locations: locations,
            snapshotsByBookID: Dictionary(uniqueKeysWithValues: books.map { ($0.book.id, $0) })
        )
    }

    public func accountStatus() async throws -> CKAccountStatus {
        .available
    }

    public func listRepositories() async throws -> [LibraryRepositoryReference] {
        repositoriesByID.values
            .map(\.repository)
            .sorted { left, right in
                if left.role != right.role {
                    return left.role == .owner
                }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
    }

    public func createOwnedRepository(preferredName: String) async throws -> LibraryRepositoryReference {
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

    public func refreshRepository(_ repository: LibraryRepositoryReference) async throws -> RemoteRepositorySnapshot {
        guard let stored = repositoriesByID[repository.id] else {
            throw CLIError("repository not found: \(repository.id)")
        }

        return RemoteRepositorySnapshot(
            repository: stored.repository,
            locations: stored.locations.sorted { $0.sortOrder < $1.sortOrder },
            books: stored.snapshotsByBookID.values.sorted { left, right in
                if left.book.updatedAt != right.book.updatedAt {
                    return left.book.updatedAt > right.book.updatedAt
                }
                return left.book.createdAt > right.book.createdAt
            },
            changeTokenData: Data("memory-\(tagCounter)".utf8)
        )
    }

    public func saveLocations(_ locations: [LibraryLocation], in repository: LibraryRepositoryReference) async throws -> [LibraryLocation] {
        guard var stored = repositoriesByID[repository.id] else {
            throw CLIError("repository not found: \(repository.id)")
        }

        let normalized = locations
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .map { index, location in
                LibraryLocation(id: location.id, name: location.name, sortOrder: index, isVisible: location.isVisible)
            }

        stored.locations = normalized
        repositoriesByID[repository.id] = stored
        return normalized
    }

    public func upsertBook(_ book: Book, coverData: Data?, in repository: LibraryRepositoryReference) async throws -> RemoteBookSnapshot {
        guard var stored = repositoriesByID[repository.id] else {
            throw CLIError("repository not found: \(repository.id)")
        }

        let existingSnapshot = stored.snapshotsByBookID[book.id]
        let storedCoverAssetID = coverData.map(HomeLibraryHash.coverAssetID(for:)) ?? book.coverAssetID
        let storedCoverData: Data?

        if let coverData {
            storedCoverData = coverData
        } else if storedCoverAssetID == existingSnapshot?.book.coverAssetID {
            storedCoverData = existingSnapshot?.coverData
        } else {
            storedCoverData = nil
        }

        tagCounter += 1
        var storedBook = book
        storedBook.coverAssetID = storedCoverAssetID
        let snapshot = RemoteBookSnapshot(
            book: storedBook,
            coverData: storedCoverData,
            recordChangeTag: "memory-tag-\(tagCounter)"
        )
        stored.snapshotsByBookID[book.id] = snapshot
        repositoriesByID[repository.id] = stored
        return snapshot
    }

    public func deleteBook(id: String, in repository: LibraryRepositoryReference) async throws {
        guard var stored = repositoriesByID[repository.id] else {
            throw CLIError("repository not found: \(repository.id)")
        }
        tagCounter += 1
        stored.snapshotsByBookID[id] = nil
        repositoriesByID[repository.id] = stored
    }

    public func deleteRepository(_ repository: LibraryRepositoryReference) async throws {
        repositoriesByID[repository.id] = nil
    }
}

public final class CloudKitLibraryRemote: LibraryRemote {
    private enum RecordType {
        static let repository = "LibraryRepository"
        static let book = "LibraryBook"
        static let location = "LibraryLocation"
    }

    private enum RepositoryField {
        static let name = "name"
        static let schemaVersion = "schemaVersion"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
    }

    private enum LocationField {
        static let name = "name"
        static let sortOrder = "sortOrder"
        static let isVisible = "isVisible"
    }

    private enum BookField {
        static let title = "title"
        static let author = "author"
        static let locationID = "locationID"
        static let payload = "payload"
        static let coverAssetID = "coverAssetID"
        static let coverAsset = "coverAsset"
        static let schemaVersion = "schemaVersion"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
    }

    private enum RecordName {
        static let repository = "repository"
        static func location(_ id: String) -> String { "location.\(id)" }
        static func book(_ id: String) -> String { "book.\(id)" }
    }

    private struct ZoneRecordChanges {
        var records: [CKRecord]
        var deletedRecordIDs: [CKRecord.ID]
        var changeTokenData: Data?
        var isFullRefresh: Bool
    }

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let sharedDatabase: CKDatabase
    private let liveTestZonePrefix: String
    private var hasValidatedCloudAccount = false
    private let snapshotCacheLock = NSLock()
    private var snapshotsByZoneKey: [String: RemoteRepositorySnapshot] = [:]

    public init(containerIdentifier: String? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let containerIdentifier = containerIdentifier?.nilIfEmpty {
            container = CKContainer(identifier: containerIdentifier)
        } else {
            container = CKContainer.default()
        }
        privateDatabase = container.privateCloudDatabase
        sharedDatabase = container.sharedCloudDatabase
        liveTestZonePrefix = environment["HOME_LIBRARY_CLOUDKIT_LIVE_TESTS"] == "1" ? "library.live-test." : "library."
    }

    public func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    public func listRepositories() async throws -> [LibraryRepositoryReference] {
        try await ensureCloudAccountAvailable()
        let owned = try await fetchRepositories(in: privateDatabase, scope: .private, role: .owner)
        let shared = try await fetchRepositories(in: sharedDatabase, scope: .shared, role: .member)
        return (owned + shared).sorted { left, right in
            if left.role != right.role {
                return left.role == .owner
            }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    public func createOwnedRepository(preferredName: String) async throws -> LibraryRepositoryReference {
        try await ensureCloudAccountAvailable()
        let zoneID = CKRecordZone.ID(zoneName: "\(liveTestZonePrefix)\(UUID().uuidString)", ownerName: CKCurrentUserDefaultName)
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await privateDatabase.modifyRecordZones(saving: [zone], deleting: [])

        let now = Date()
        let repositoryRecord = CKRecord(recordType: RecordType.repository, recordID: CKRecord.ID(recordName: RecordName.repository, zoneID: zoneID))
        repositoryRecord[RepositoryField.name] = preferredName as CKRecordValue
        repositoryRecord[RepositoryField.schemaVersion] = Int64(LibraryImportPackage.currentSchemaVersion) as CKRecordValue
        repositoryRecord[RepositoryField.createdAt] = now as CKRecordValue
        repositoryRecord[RepositoryField.updatedAt] = now as CKRecordValue

        let locationRecords = LibraryLocation.defaultLocations().map { makeLocationRecord(for: $0, zoneID: zoneID) }
        _ = try await saveRecords([repositoryRecord] + locationRecords, deleting: [], in: privateDatabase, zoneID: zoneID)

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

    public func refreshRepository(_ repository: LibraryRepositoryReference) async throws -> RemoteRepositorySnapshot {
        try await ensureCloudAccountAvailable()
        let database = database(for: repository.databaseScope)
        let zoneID = repository.zoneID
        let zone = try await fetchZone(zoneID: zoneID, in: database)
        let previousSnapshot = cachedSnapshot(for: repository)
        let changes = try await fetchZoneRecordChanges(inZoneWith: zoneID, database: database, since: previousSnapshot?.changeTokenData)

        var repositoryRecord = changes.records.first {
            $0.recordType == RecordType.repository && $0.recordID.recordName == RecordName.repository
        }

        if repositoryRecord == nil && changes.isFullRefresh {
            repositoryRecord = try await fetchRecord(recordID: CKRecord.ID(recordName: RecordName.repository, zoneID: zoneID), in: database)
        }

        let updatedRepository: LibraryRepositoryReference
        if let repositoryRecord {
            updatedRepository = try makeRepositoryReference(from: repositoryRecord, role: repository.role, scope: repository.databaseScope, zone: zone)
        } else if let previousSnapshot, !changes.isFullRefresh {
            updatedRepository = previousSnapshot.repository
        } else {
            updatedRepository = repository
        }

        let baseSnapshot = changes.isFullRefresh ? nil : previousSnapshot
        let snapshot = RemoteRepositorySnapshot(
            repository: updatedRepository,
            locations: try mergeLocations(baseSnapshot: baseSnapshot, changes: changes),
            books: try mergeBooks(baseSnapshot: baseSnapshot, changes: changes),
            changeTokenData: changes.changeTokenData
        )
        cacheSnapshot(snapshot)
        return snapshot
    }

    public func saveLocations(_ locations: [LibraryLocation], in repository: LibraryRepositoryReference) async throws -> [LibraryLocation] {
        try await ensureCloudAccountAvailable()
        let database = database(for: repository.databaseScope)
        let zoneID = repository.zoneID
        let normalized = locations
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .map { index, location in
                LibraryLocation(id: location.id, name: location.name, sortOrder: index, isVisible: location.isVisible)
            }
        let existingLocationRecords = try await fetchRecords(recordType: RecordType.location, inZoneWith: zoneID, database: database)
        let existingIDs = Set(existingLocationRecords.map(\.recordID.recordName))
        let recordsToSave = normalized.map { makeLocationRecord(for: $0, zoneID: zoneID) }
        let desiredRecordIDs = Set(recordsToSave.map(\.recordID.recordName))
        let recordIDsToDelete = existingIDs.subtracting(desiredRecordIDs).map { CKRecord.ID(recordName: $0, zoneID: zoneID) }

        _ = try await saveRecords(recordsToSave, deleting: recordIDsToDelete, in: database, zoneID: zoneID)
        return normalized
    }

    public func upsertBook(_ book: Book, coverData: Data?, in repository: LibraryRepositoryReference) async throws -> RemoteBookSnapshot {
        try await ensureCloudAccountAvailable()
        let database = database(for: repository.databaseScope)
        let zoneID = repository.zoneID
        let recordID = CKRecord.ID(recordName: RecordName.book(book.id), zoneID: zoneID)
        let record = try await fetchRecordIfPresent(recordID: recordID, in: database) ?? CKRecord(recordType: RecordType.book, recordID: recordID)

        let payloadJSON = try Self.encodePayload(book.payload)
        let storedCoverAssetID = coverData.map(HomeLibraryHash.coverAssetID(for:)) ?? book.coverAssetID

        record[BookField.title] = book.title as CKRecordValue
        record[BookField.author] = book.author as CKRecordValue
        record[BookField.locationID] = book.locationID as CKRecordValue
        record[BookField.payload] = payloadJSON as CKRecordValue
        record[BookField.coverAssetID] = storedCoverAssetID as CKRecordValue?
        record[BookField.schemaVersion] = Int64(book.payload.schemaVersion) as CKRecordValue
        record[BookField.createdAt] = book.createdAt as CKRecordValue
        record[BookField.updatedAt] = book.updatedAt as CKRecordValue

        let temporaryAssetFile = coverData.map { TemporaryAssetFile(data: $0, fileExtension: "bin") }
        defer { temporaryAssetFile?.cleanup() }

        if let temporaryAssetFile {
            record[BookField.coverAsset] = CKAsset(fileURL: temporaryAssetFile.url)
        } else if storedCoverAssetID == nil {
            record[BookField.coverAsset] = nil
        }

        let savedRecord = try await saveRecord(record, in: database, zoneID: zoneID)
        return try Self.makeRemoteBookSnapshot(from: savedRecord, fallbackCoverData: coverData)
    }

    public func deleteBook(id: String, in repository: LibraryRepositoryReference) async throws {
        try await ensureCloudAccountAvailable()
        let database = database(for: repository.databaseScope)
        let zoneID = repository.zoneID
        let recordID = CKRecord.ID(recordName: RecordName.book(id), zoneID: zoneID)
        _ = try await saveRecords([], deleting: [recordID], in: database, zoneID: zoneID)
    }

    public func deleteRepository(_ repository: LibraryRepositoryReference) async throws {
        try await ensureCloudAccountAvailable()
        switch repository.databaseScope {
        case .private:
            guard repository.isOwner else {
                throw CLIError("only owned private repositories can be deleted by this CLI")
            }
            _ = try await privateDatabase.modifyRecordZones(saving: [], deleting: [repository.zoneID])
        case .shared:
            guard let shareRecordName = repository.shareRecordName?.nilIfEmpty else {
                throw CLIError("shared repository does not expose a share record")
            }
            let shareRecordID = CKRecord.ID(recordName: shareRecordName, zoneID: repository.zoneID)
            _ = try await saveRecords([], deleting: [shareRecordID], in: sharedDatabase, zoneID: repository.zoneID)
        }
    }

    private func fetchRepositories(in database: CKDatabase, scope: CloudDatabaseScope, role: RepositoryRole) async throws -> [LibraryRepositoryReference] {
        let zoneIDs = try await fetchZoneIDs(in: database)
        let zonesByID = try await fetchZones(zoneIDs: zoneIDs, in: database)
        var repositories: [LibraryRepositoryReference] = []

        for zoneID in zoneIDs {
            let repositoryRecordID = CKRecord.ID(recordName: RecordName.repository, zoneID: zoneID)
            guard let record = try await fetchRecordIfPresent(recordID: repositoryRecordID, in: database),
                  let zone = zonesByID[zoneID] else {
                continue
            }
            repositories.append(try makeRepositoryReference(from: record, role: role, scope: scope, zone: zone))
        }

        return repositories
    }

    private func fetchZoneIDs(in database: CKDatabase) async throws -> [CKRecordZone.ID] {
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
    }

    private func fetchZones(zoneIDs: [CKRecordZone.ID], in database: CKDatabase) async throws -> [CKRecordZone.ID: CKRecordZone] {
        guard !zoneIDs.isEmpty else {
            return [:]
        }

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
    }

    private func fetchZone(zoneID: CKRecordZone.ID, in database: CKDatabase) async throws -> CKRecordZone {
        let zones = try await fetchZones(zoneIDs: [zoneID], in: database)
        guard let zone = zones[zoneID] else {
            throw CLIError("repository zone not found: \(zoneID.zoneName)")
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
                throw CLIError("no available iCloud account")
            default:
                throw CLIError("CloudKit account is not available: \(status)")
            }
        } catch {
            throw mapCloudError(error)
        }
    }

    private func fetchRecord(recordID: CKRecord.ID, in database: CKDatabase) async throws -> CKRecord {
        if let record = try await fetchRecordIfPresent(recordID: recordID, in: database) {
            return record
        }
        throw CLIError("record not found: \(recordID.recordName)")
    }

    private func fetchRecordIfPresent(recordID: CKRecord.ID, in database: CKDatabase) async throws -> CKRecord? {
        do {
            let records = try await database.records(for: [recordID])
            guard let recordResult = records[recordID] else {
                return nil
            }
            switch recordResult {
            case .success(let record):
                return record
            case .failure(let error):
                if let ckError = error as? CKError,
                   ckError.code == .unknownItem || ckError.code == .zoneNotFound {
                    return nil
                }
                throw mapCloudError(error)
            }
        } catch {
            throw mapCloudError(error)
        }
    }

    private func fetchRecords(recordType: String, inZoneWith zoneID: CKRecordZone.ID, database: CKDatabase) async throws -> [CKRecord] {
        try await fetchZoneRecordChanges(inZoneWith: zoneID, database: database, since: nil)
            .records
            .filter { $0.recordType == recordType }
    }

    private func fetchZoneRecordChanges(inZoneWith zoneID: CKRecordZone.ID, database: CKDatabase, since changeTokenData: Data?) async throws -> ZoneRecordChanges {
        let startingChangeToken = Self.decodeChangeToken(from: changeTokenData)
        let isFullRefresh = startingChangeToken == nil

        do {
            var recordsByID: [CKRecord.ID: CKRecord] = [:]
            var deletedRecordIDs: [CKRecord.ID] = []
            var changeToken = startingChangeToken
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
                    deletedRecordIDs.append(deletion.recordID)
                }
                changeToken = changes.changeToken
                moreComing = changes.moreComing
            } while moreComing

            return ZoneRecordChanges(
                records: Array(recordsByID.values),
                deletedRecordIDs: deletedRecordIDs,
                changeTokenData: Self.encodeChangeToken(changeToken),
                isFullRefresh: isFullRefresh
            )
        } catch let error as CKError where error.code == .changeTokenExpired && changeTokenData != nil {
            return try await fetchZoneRecordChanges(inZoneWith: zoneID, database: database, since: nil)
        } catch {
            throw mapCloudError(error)
        }
    }

    private func saveRecord(_ record: CKRecord, in database: CKDatabase, zoneID: CKRecordZone.ID) async throws -> CKRecord {
        let result = try await saveRecords([record], deleting: [], in: database, zoneID: zoneID, savePolicy: .ifServerRecordUnchanged)
        guard let recordResult = result.saveResults[record.recordID] else {
            throw CLIError("CloudKit did not return save result")
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
        deleting recordIDs: [CKRecord.ID],
        in database: CKDatabase,
        zoneID: CKRecordZone.ID,
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy = .changedKeys
    ) async throws -> (saveResults: [CKRecord.ID: Result<CKRecord, Error>], deleteResults: [CKRecord.ID: Result<Void, Error>]) {
        do {
            return try await database.modifyRecords(saving: records, deleting: recordIDs, savePolicy: savePolicy, atomically: true)
        } catch {
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

    private func cachedSnapshot(for repository: LibraryRepositoryReference) -> RemoteRepositorySnapshot? {
        snapshotCacheLock.lock()
        defer { snapshotCacheLock.unlock() }
        return snapshotsByZoneKey[zoneCacheKey(for: repository)]
    }

    private func cacheSnapshot(_ snapshot: RemoteRepositorySnapshot) {
        snapshotCacheLock.lock()
        snapshotsByZoneKey[zoneCacheKey(for: snapshot.repository)] = snapshot
        snapshotCacheLock.unlock()
    }

    private func zoneCacheKey(for repository: LibraryRepositoryReference) -> String {
        "\(repository.databaseScope.rawValue)|\(repository.zoneOwnerName)|\(repository.zoneName)"
    }

    private func mergeLocations(
        baseSnapshot: RemoteRepositorySnapshot?,
        changes: ZoneRecordChanges
    ) throws -> [LibraryLocation] {
        var locationsByID = baseSnapshot?.locationsByID ?? [:]
        for record in changes.records where record.recordType == RecordType.location {
            let location = try Self.makeLocation(from: record)
            locationsByID[location.id] = location
        }
        for recordID in changes.deletedRecordIDs where recordID.recordName.hasPrefix("location.") {
            let id = Self.idFromPrefixedRecordName(recordID.recordName, prefix: "location.")
            locationsByID[id] = nil
        }
        return locationsByID.values.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func mergeBooks(
        baseSnapshot: RemoteRepositorySnapshot?,
        changes: ZoneRecordChanges
    ) throws -> [RemoteBookSnapshot] {
        var booksByID = baseSnapshot?.booksByID ?? [:]
        for record in changes.records where record.recordType == RecordType.book {
            let snapshot = try Self.makeRemoteBookSnapshot(from: record)
            booksByID[snapshot.book.id] = snapshot
        }
        for recordID in changes.deletedRecordIDs where recordID.recordName.hasPrefix("book.") {
            let id = Self.idFromPrefixedRecordName(recordID.recordName, prefix: "book.")
            booksByID[id] = nil
        }
        return booksByID.values.sorted { left, right in
            if left.book.updatedAt != right.book.updatedAt {
                return left.book.updatedAt > right.book.updatedAt
            }
            return left.book.createdAt > right.book.createdAt
        }
    }

    private func makeLocationRecord(for location: LibraryLocation, zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: RecordType.location, recordID: CKRecord.ID(recordName: RecordName.location(location.id), zoneID: zoneID))
        record[LocationField.name] = location.name as CKRecordValue
        record[LocationField.sortOrder] = Int64(location.sortOrder) as CKRecordValue
        record[LocationField.isVisible] = location.isVisible as CKRecordValue
        return record
    }

    private func makeRepositoryReference(from record: CKRecord, role: RepositoryRole, scope: CloudDatabaseScope, zone: CKRecordZone) throws -> LibraryRepositoryReference {
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

    private func mapCloudError(_ error: Error) -> Error {
        guard let error = error as? CKError else {
            return error
        }

        switch error.code {
        case .networkUnavailable, .networkFailure, .serverResponseLost:
            return CLIError("CloudKit network is unavailable: \(error.localizedDescription)", category: .retryableCloudKit)
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return CLIError("CloudKit service is temporarily unavailable: \(error.localizedDescription)", category: .retryableCloudKit)
        case .badContainer:
            return CLIError("invalid CloudKit container configuration")
        case .missingEntitlement:
            return CLIError("missing CloudKit entitlement")
        case .notAuthenticated:
            return CLIError("no available iCloud account")
        case .accountTemporarilyUnavailable:
            return CLIError("iCloud account is temporarily unavailable", category: .retryableCloudKit)
        case .permissionFailure:
            return CLIError("permission denied by CloudKit")
        case .unknownItem, .zoneNotFound:
            return CLIError("repository or record not found")
        case .serverRecordChanged:
            return CLIError("CloudKit conflict: server record changed", category: .cloudKitConflict)
        default:
            return CLIError(error.localizedDescription)
        }
    }

    private static func makeLocation(from record: CKRecord) throws -> LibraryLocation {
        LibraryLocation(
            id: idFromPrefixedRecordName(record.recordID.recordName, prefix: "location."),
            name: try requireStringField(LocationField.name, in: record),
            sortOrder: Int(try requireInt64Field(LocationField.sortOrder, in: record)),
            isVisible: (record[LocationField.isVisible] as? NSNumber)?.boolValue ?? true
        )
    }

    private static func makeRemoteBookSnapshot(from record: CKRecord, fallbackCoverData: Data? = nil) throws -> RemoteBookSnapshot {
        let payloadJSONString = try requireStringField(BookField.payload, in: record)
        let payload = try decodePayload(payloadJSONString)
        let createdAt = try requireDateField(BookField.createdAt, in: record)
        let updatedAt = try requireDateField(BookField.updatedAt, in: record)
        let coverAssetID = record[BookField.coverAssetID] as? String
        let bookID = idFromPrefixedRecordName(record.recordID.recordName, prefix: "book.")
        let book = Book(id: bookID, payload: payload, coverAssetID: coverAssetID, createdAt: createdAt, updatedAt: updatedAt)
        let coverData = fallbackCoverData ?? loadAssetData(from: record[BookField.coverAsset] as? CKAsset)
        return RemoteBookSnapshot(book: book, coverData: coverData, recordChangeTag: record.recordChangeTag)
    }

    static func idFromPrefixedRecordName(_ recordName: String, prefix: String) -> String {
        guard recordName.hasPrefix(prefix) else {
            return recordName
        }
        return String(recordName.dropFirst(prefix.count))
    }

    private static func requireStringField(_ key: String, in record: CKRecord) throws -> String {
        guard let value = record[key] as? String, !value.trimmed.isEmpty else {
            throw CLIError("invalid CloudKit record: missing \(key)")
        }
        return value
    }

    private static func requireInt64Field(_ key: String, in record: CKRecord) throws -> Int64 {
        guard let value = record[key] as? NSNumber else {
            throw CLIError("invalid CloudKit record: missing \(key)")
        }
        return value.int64Value
    }

    private static func requireDateField(_ key: String, in record: CKRecord) throws -> Date {
        guard let value = record[key] as? Date else {
            throw CLIError("invalid CloudKit record: missing \(key)")
        }
        return value
    }

    private static func encodePayload(_ payload: BookPayload) throws -> String {
        let data = try JSONEncoder().encode(payload)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CLIError("failed to encode CloudKit book payload")
        }
        return string
    }

    private static func decodePayload(_ string: String) throws -> BookPayload {
        guard let data = string.data(using: .utf8) else {
            throw CLIError("failed to decode CloudKit book payload")
        }
        return try JSONDecoder().decode(BookPayload.self, from: data)
    }

    private static func encodeChangeToken(_ token: CKServerChangeToken?) -> Data? {
        guard let token else {
            return nil
        }
        return try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    private static func decodeChangeToken(from data: Data?) -> CKServerChangeToken? {
        guard let data else {
            return nil
        }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private static func loadAssetData(from asset: CKAsset?) -> Data? {
        guard let url = asset?.fileURL else {
            return nil
        }
        return try? Data(contentsOf: url)
    }
}

private final class TemporaryAssetFile {
    let url: URL

    init(data: Data, fileExtension: String) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("home-library-cloudkit-assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try? data.write(to: url, options: [.atomic])
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: url)
    }
}
