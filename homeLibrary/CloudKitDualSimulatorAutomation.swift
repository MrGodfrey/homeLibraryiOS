//
//  CloudKitDualSimulatorAutomation.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/15.
//

import CloudKit
import Foundation

@MainActor
enum CloudKitDualSimulatorAutomation {
    private enum EnvironmentKey {
        static let command = "HOME_LIBRARY_CLOUDKIT_AUTOMATION_COMMAND"
        static let resultFile = "HOME_LIBRARY_CLOUDKIT_AUTOMATION_RESULT_FILE"
        static let repositoryName = "HOME_LIBRARY_CLOUDKIT_AUTOMATION_REPOSITORY_NAME"
        static let zoneName = "HOME_LIBRARY_CLOUDKIT_AUTOMATION_ZONE_NAME"
        static let shareURL = "HOME_LIBRARY_CLOUDKIT_AUTOMATION_SHARE_URL"
        static let initialTitle = "HOME_LIBRARY_CLOUDKIT_AUTOMATION_INITIAL_TITLE"
        static let updatedTitle = "HOME_LIBRARY_CLOUDKIT_AUTOMATION_UPDATED_TITLE"
        static let bookID = "HOME_LIBRARY_CLOUDKIT_AUTOMATION_BOOK_ID"
    }

    private enum Command: String {
        case ownerPrepare = "owner-prepare"
        case memberJoinCreateUpdate = "member-join-create-update"
        case ownerVerifyUpdate = "owner-verify-update"
        case memberDelete = "member-delete"
        case ownerVerifyDelete = "owner-verify-delete"
        case ownerCleanup = "owner-cleanup"
        case memberVerifyCleanup = "member-verify-cleanup"
    }

    private struct ResultPayload: Codable {
        let command: String
        let success: Bool
        let message: String
        let repositoryID: String?
        let repositoryName: String?
        let zoneName: String?
        let shareURL: String?
        let bookID: String?
        let bookTitle: String?
        let bookCount: Int?
        let observedBookTitles: [String]
        let completedAt: Date
    }

    private enum AutomationError: LocalizedError {
        case invalidCommand(String)
        case missingEnvironment(String)
        case preconditionFailed(String)
        case timedOut(String)

        var errorDescription: String? {
            switch self {
            case .invalidCommand(let value):
                return "不支持的双模拟器测试命令：\(value)"
            case .missingEnvironment(let key):
                return "缺少测试环境变量：\(key)"
            case .preconditionFailed(let message):
                return message
            case .timedOut(let description):
                return "等待超时：\(description)"
            }
        }
    }

    static func runIfNeeded(
        store: LibraryStore,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async {
        let environment = LibraryEnvironment.resolved(environment)
        guard let rawCommand = environment[EnvironmentKey.command]?.nilIfEmpty else {
            return
        }

        store.alertMessage = nil

        let payload: ResultPayload

        do {
            guard let command = Command(rawValue: rawCommand) else {
                throw AutomationError.invalidCommand(rawCommand)
            }

            guard let service = store.cloudKitService else {
                throw AutomationError.preconditionFailed("双模拟器 live test 只能在 CloudKit 驱动下运行。")
            }

            payload = try await run(command: command, store: store, service: service, environment: environment)
        } catch {
            payload = ResultPayload(
                command: rawCommand,
                success: false,
                message: LibraryStore.userFacingMessage(for: error),
                repositoryID: nil,
                repositoryName: environment[EnvironmentKey.repositoryName]?.nilIfEmpty,
                zoneName: environment[EnvironmentKey.zoneName]?.nilIfEmpty,
                shareURL: nil,
                bookID: environment[EnvironmentKey.bookID]?.nilIfEmpty,
                bookTitle: nil,
                bookCount: nil,
                observedBookTitles: [],
                completedAt: .now
            )
        }

        try? write(payload, environment: environment)
    }

    private static func run(
        command: Command,
        store: LibraryStore,
        service: CloudKitLibraryService,
        environment: [String: String]
    ) async throws -> ResultPayload {
        switch command {
        case .ownerPrepare:
            return try await runOwnerPrepare(store: store, service: service, environment: environment)
        case .memberJoinCreateUpdate:
            return try await runMemberJoinCreateUpdate(store: store, service: service, environment: environment)
        case .ownerVerifyUpdate:
            return try await runOwnerVerifyUpdate(service: service, environment: environment)
        case .memberDelete:
            return try await runMemberDelete(store: store, service: service, environment: environment)
        case .ownerVerifyDelete:
            return try await runOwnerVerifyDelete(service: service, environment: environment)
        case .ownerCleanup:
            return try await runOwnerCleanup(service: service, environment: environment)
        case .memberVerifyCleanup:
            return try await runMemberVerifyCleanup(service: service, environment: environment)
        }
    }

    private static func runOwnerPrepare(
        store: LibraryStore,
        service: CloudKitLibraryService,
        environment: [String: String]
    ) async throws -> ResultPayload {
        let repositoryName = try requiredValue(for: EnvironmentKey.repositoryName, in: environment)

        await store.loadBooks(force: true)

        guard await store.createOwnedRepository() else {
            throw AutomationError.preconditionFailed(store.alertMessage ?? "创建 owner 测试仓库失败。")
        }

        guard let repository = store.currentRepository else {
            throw AutomationError.preconditionFailed("owner 测试仓库创建后没有选中当前仓库。")
        }

        guard repository.name == repositoryName else {
            throw AutomationError.preconditionFailed("owner 测试仓库名字不符合预期：\(repository.name)")
        }

        let shareURL = try await service.shareURL(for: repository)

        return ResultPayload(
            command: Command.ownerPrepare.rawValue,
            success: true,
            message: "已创建 owner 测试仓库并生成共享链接。",
            repositoryID: repository.id,
            repositoryName: repository.name,
            zoneName: repository.zoneName,
            shareURL: shareURL.absoluteString,
            bookID: nil,
            bookTitle: nil,
            bookCount: store.books.count,
            observedBookTitles: store.books.map(\.title),
            completedAt: .now
        )
    }

    private static func runMemberJoinCreateUpdate(
        store: LibraryStore,
        service: CloudKitLibraryService,
        environment: [String: String]
    ) async throws -> ResultPayload {
        let repositoryName = try requiredValue(for: EnvironmentKey.repositoryName, in: environment)
        let shareURL = try requiredURL(for: EnvironmentKey.shareURL, in: environment)
        let initialTitle = try requiredValue(for: EnvironmentKey.initialTitle, in: environment)
        let updatedTitle = try requiredValue(for: EnvironmentKey.updatedTitle, in: environment)
        let zoneName = environment[EnvironmentKey.zoneName]?.nilIfEmpty

        let metadata = try await waitForShareMetadata(service: service, shareURL: shareURL)
        await store.acceptShareMetadata(metadata)

        let repository = try await waitForRepository(
            service: service,
            repositoryName: repositoryName,
            zoneName: zoneName,
            role: .member,
            scope: .shared,
            description: "member 侧发现共享仓库"
        )

        await store.switchRepository(to: repository)

        let locationID = store.defaultLocationID
        let createDraft = BookDraft(
            title: initialTitle,
            author: "Dual Sim Runner",
            publisher: "OpenAI",
            year: "2026",
            locationID: locationID,
            coverData: nil
        )

        guard await store.saveBook(draft: createDraft, editing: nil) else {
            throw AutomationError.preconditionFailed(store.alertMessage ?? "member 创建书籍失败。")
        }

        let createdBook = try await poll(description: "member 侧读取新建书籍") {
            await store.loadBooks(force: true)
            return store.books.first(where: { $0.title == initialTitle })
        }

        let updateDraft = BookDraft(
            title: updatedTitle,
            author: createdBook.author,
            publisher: createdBook.publisher,
            year: createdBook.year,
            locationID: createdBook.locationID,
            customFields: createdBook.customFields,
            coverData: nil,
            keepsExistingCoverReference: createdBook.coverAssetID != nil
        )

        guard await store.saveBook(draft: updateDraft, editing: createdBook) else {
            throw AutomationError.preconditionFailed(store.alertMessage ?? "member 修改书籍失败。")
        }

        let updatedBook = try await poll(description: "member 侧读取修改后的书籍") {
            await store.loadBooks(force: true)
            return store.books.first(where: { $0.id == createdBook.id && $0.title == updatedTitle })
        }

        return ResultPayload(
            command: Command.memberJoinCreateUpdate.rawValue,
            success: true,
            message: "member 已接受共享并完成新增、读取、修改。",
            repositoryID: repository.id,
            repositoryName: repository.name,
            zoneName: repository.zoneName,
            shareURL: nil,
            bookID: updatedBook.id,
            bookTitle: updatedBook.title,
            bookCount: store.books.count,
            observedBookTitles: store.books.map(\.title),
            completedAt: .now
        )
    }

    private static func runOwnerVerifyUpdate(
        service: CloudKitLibraryService,
        environment: [String: String]
    ) async throws -> ResultPayload {
        let repositoryName = try requiredValue(for: EnvironmentKey.repositoryName, in: environment)
        let expectedTitle = try requiredValue(for: EnvironmentKey.updatedTitle, in: environment)
        let expectedBookID = try requiredValue(for: EnvironmentKey.bookID, in: environment)
        let zoneName = environment[EnvironmentKey.zoneName]?.nilIfEmpty

        let repository = try await waitForRepository(
            service: service,
            repositoryName: repositoryName,
            zoneName: zoneName,
            role: .owner,
            scope: .private,
            description: "owner 侧定位测试仓库"
        )

        let snapshot: RemoteRepositorySnapshot = try await poll(description: "owner 侧看到 member 修改后的书籍") {
            let snapshot = try await service.refreshRepository(repository)
            guard snapshot.books.contains(where: { $0.book.id == expectedBookID && $0.book.title == expectedTitle }) else {
                return nil
            }

            return snapshot
        }

        return ResultPayload(
            command: Command.ownerVerifyUpdate.rawValue,
            success: true,
            message: "owner 已验证 member 的新增/修改同步可见。",
            repositoryID: snapshot.repository.id,
            repositoryName: snapshot.repository.name,
            zoneName: snapshot.repository.zoneName,
            shareURL: nil,
            bookID: expectedBookID,
            bookTitle: expectedTitle,
            bookCount: snapshot.books.count,
            observedBookTitles: snapshot.books.map { $0.book.title },
            completedAt: .now
        )
    }

    private static func runMemberDelete(
        store: LibraryStore,
        service: CloudKitLibraryService,
        environment: [String: String]
    ) async throws -> ResultPayload {
        let repositoryName = try requiredValue(for: EnvironmentKey.repositoryName, in: environment)
        let bookID = try requiredValue(for: EnvironmentKey.bookID, in: environment)
        let zoneName = environment[EnvironmentKey.zoneName]?.nilIfEmpty

        let repository = try await waitForRepository(
            service: service,
            repositoryName: repositoryName,
            zoneName: zoneName,
            role: .member,
            scope: .shared,
            description: "member 侧定位共享仓库"
        )

        await store.switchRepository(to: repository)

        let book = try await poll(description: "member 侧定位待删除书籍") {
            await store.loadBooks(force: true)
            return store.books.first(where: { $0.id == bookID })
        }

        guard await store.deleteBook(book) else {
            throw AutomationError.preconditionFailed(store.alertMessage ?? "member 删除书籍失败。")
        }

        _ = try await poll(description: "member 侧确认删除完成") {
            await store.loadBooks(force: true)
            return store.books.contains(where: { $0.id == bookID }) ? nil : true
        }

        return ResultPayload(
            command: Command.memberDelete.rawValue,
            success: true,
            message: "member 已完成删除并确认本地读取为空。",
            repositoryID: repository.id,
            repositoryName: repository.name,
            zoneName: repository.zoneName,
            shareURL: nil,
            bookID: bookID,
            bookTitle: nil,
            bookCount: store.books.count,
            observedBookTitles: store.books.map(\.title),
            completedAt: .now
        )
    }

    private static func runOwnerVerifyDelete(
        service: CloudKitLibraryService,
        environment: [String: String]
    ) async throws -> ResultPayload {
        let repositoryName = try requiredValue(for: EnvironmentKey.repositoryName, in: environment)
        let expectedBookID = try requiredValue(for: EnvironmentKey.bookID, in: environment)
        let zoneName = environment[EnvironmentKey.zoneName]?.nilIfEmpty

        let repository = try await waitForRepository(
            service: service,
            repositoryName: repositoryName,
            zoneName: zoneName,
            role: .owner,
            scope: .private,
            description: "owner 侧定位测试仓库"
        )

        let snapshot: RemoteRepositorySnapshot = try await poll(description: "owner 侧确认删除同步") {
            let snapshot = try await service.refreshRepository(repository)
            guard snapshot.books.contains(where: { $0.book.id == expectedBookID }) else {
                return snapshot
            }

            return nil
        }

        return ResultPayload(
            command: Command.ownerVerifyDelete.rawValue,
            success: true,
            message: "owner 已验证 member 的删除同步可见。",
            repositoryID: snapshot.repository.id,
            repositoryName: snapshot.repository.name,
            zoneName: snapshot.repository.zoneName,
            shareURL: nil,
            bookID: expectedBookID,
            bookTitle: nil,
            bookCount: snapshot.books.count,
            observedBookTitles: snapshot.books.map { $0.book.title },
            completedAt: .now
        )
    }

    private static func runOwnerCleanup(
        service: CloudKitLibraryService,
        environment: [String: String]
    ) async throws -> ResultPayload {
        let repositoryName = try requiredValue(for: EnvironmentKey.repositoryName, in: environment)
        let zoneName = environment[EnvironmentKey.zoneName]?.nilIfEmpty

        guard let repository = try await findRepository(
            service: service,
            repositoryName: repositoryName,
            zoneName: zoneName,
            role: .owner,
            scope: .private
        ) else {
            return ResultPayload(
                command: Command.ownerCleanup.rawValue,
                success: true,
                message: "owner 测试仓库已经不存在，无需再次清理。",
                repositoryID: nil,
                repositoryName: repositoryName,
                zoneName: zoneName,
                shareURL: nil,
                bookID: environment[EnvironmentKey.bookID]?.nilIfEmpty,
                bookTitle: nil,
                bookCount: nil,
                observedBookTitles: [],
                completedAt: .now
            )
        }

        try await service.deleteRepository(repository)

        _ = try await poll(description: "owner 侧确认测试仓库已删除") {
            let remaining = try await service.listRepositories()
            return remaining.contains(where: {
                matches(
                    $0,
                    repositoryName: repositoryName,
                    zoneName: zoneName,
                    role: .owner,
                    scope: .private
                )
            }) ? nil : true
        }

        return ResultPayload(
            command: Command.ownerCleanup.rawValue,
            success: true,
            message: "owner 测试仓库已删除。",
            repositoryID: repository.id,
            repositoryName: repository.name,
            zoneName: repository.zoneName,
            shareURL: nil,
            bookID: environment[EnvironmentKey.bookID]?.nilIfEmpty,
            bookTitle: nil,
            bookCount: nil,
            observedBookTitles: [],
            completedAt: .now
        )
    }

    private static func runMemberVerifyCleanup(
        service: CloudKitLibraryService,
        environment: [String: String]
    ) async throws -> ResultPayload {
        let repositoryName = try requiredValue(for: EnvironmentKey.repositoryName, in: environment)
        let zoneName = environment[EnvironmentKey.zoneName]?.nilIfEmpty

        _ = try await poll(description: "member 侧确认共享仓库已移除", timeout: 90) {
            let repositories = try await service.listRepositories()
            return repositories.contains(where: {
                matches(
                    $0,
                    repositoryName: repositoryName,
                    zoneName: zoneName,
                    role: .member,
                    scope: .shared
                )
            }) ? nil : true
        }

        return ResultPayload(
            command: Command.memberVerifyCleanup.rawValue,
            success: true,
            message: "member 侧已确认共享仓库不再可见。",
            repositoryID: nil,
            repositoryName: repositoryName,
            zoneName: zoneName,
            shareURL: nil,
            bookID: environment[EnvironmentKey.bookID]?.nilIfEmpty,
            bookTitle: nil,
            bookCount: nil,
            observedBookTitles: [],
            completedAt: .now
        )
    }

    private static func findRepository(
        service: CloudKitLibraryService,
        repositoryName: String,
        zoneName: String?,
        role: RepositoryRole,
        scope: CloudDatabaseScope
    ) async throws -> LibraryRepositoryReference? {
        let repositories = try await service.listRepositories()
        return repositories.first {
            matches($0, repositoryName: repositoryName, zoneName: zoneName, role: role, scope: scope)
        }
    }

    private static func waitForRepository(
        service: CloudKitLibraryService,
        repositoryName: String,
        zoneName: String?,
        role: RepositoryRole,
        scope: CloudDatabaseScope,
        description: String,
        timeout: TimeInterval = 60
    ) async throws -> LibraryRepositoryReference {
        try await poll(description: description, timeout: timeout) {
            try await findRepository(
                service: service,
                repositoryName: repositoryName,
                zoneName: zoneName,
                role: role,
                scope: scope
            )
        }
    }

    private static func waitForShareMetadata(
        service: CloudKitLibraryService,
        shareURL: URL,
        timeout: TimeInterval = 90,
        interval: TimeInterval = 3
    ) async throws -> CKShare.Metadata {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?

        while Date() < deadline {
            do {
                return try await service.shareMetadata(for: shareURL)
            } catch {
                lastError = error
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }

        throw lastError ?? AutomationError.timedOut("等待共享 metadata 就绪")
    }

    private static func matches(
        _ repository: LibraryRepositoryReference,
        repositoryName: String,
        zoneName: String?,
        role: RepositoryRole,
        scope: CloudDatabaseScope
    ) -> Bool {
        guard repository.role == role, repository.databaseScope == scope else {
            return false
        }

        if let zoneName {
            return repository.zoneName == zoneName
        }

        return repository.name == repositoryName
    }

    private static func poll<T>(
        description: String,
        timeout: TimeInterval = 60,
        interval: TimeInterval = 1,
        operation: @escaping @MainActor () async throws -> T?
    ) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)

        while true {
            if let value = try await operation() {
                return value
            }

            guard Date() < deadline else {
                throw AutomationError.timedOut(description)
            }

            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    private static func requiredValue(for key: String, in environment: [String: String]) throws -> String {
        guard let value = environment[key]?.nilIfEmpty else {
            throw AutomationError.missingEnvironment(key)
        }

        return value
    }

    private static func requiredURL(for key: String, in environment: [String: String]) throws -> URL {
        let rawValue = try requiredValue(for: key, in: environment)
        guard let url = URL(string: rawValue) else {
            throw AutomationError.preconditionFailed("环境变量 \(key) 不是合法 URL：\(rawValue)")
        }

        return url
    }

    private static func write(_ payload: ResultPayload, environment: [String: String]) throws {
        let filename = environment[EnvironmentKey.resultFile]?.nilIfEmpty ?? "cloudkit-dual-sim-result.json"
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ??
            FileManager.default.temporaryDirectory
        let url = documentsDirectory.appendingPathComponent(filename)
        let data = try LibraryJSONCodec.makeEncoder().encode(payload)
        try data.write(to: url, options: .atomic)
    }
}
