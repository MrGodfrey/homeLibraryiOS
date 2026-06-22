import CloudKit
import Foundation
import HomeLibraryCloudKitCore
import AppKit

@main
struct HomeLibraryCloudKitCLI {
    static func main() async {
        do {
            let cli = CLI(arguments: Array(CommandLine.arguments.dropFirst()))
            let exitCode = try await cli.run()
            Foundation.exit(exitCode)
        } catch let error as CLIError {
            writeError(error.message)
            printJSON(ErrorOutput(ok: false, error: error.message))
            Foundation.exit(error.exitCode)
        } catch {
            writeError("\(error)")
            printJSON(ErrorOutput(ok: false, error: "\(error)"))
            Foundation.exit(1)
        }
    }
}

private struct CLI {
    var arguments: [String]

    func run() async throws -> Int32 {
        guard let command = arguments.first else {
            throw CLIError("missing command", exitCode: 2)
        }
        let options = Options(Array(arguments.dropFirst()))

        switch command {
        case "doctor":
            try await doctor(options: options)
            return 0
        case "repos":
            try await repos(options: options)
            return 0
        case "export-ai-workspace":
            try await exportAIWorkspace(options: options)
            return 0
        case "validate-patch":
            let result = try await validatePatch(options: options)
            return result.ok ? 0 : 1
        case "review-patch":
            try await reviewPatch(options: options)
            return 0
        case "apply-patch":
            let result = try await applyPatch(options: options)
            return result.ok ? 0 : 1
        case "run-live-test":
            let result = try await runLiveTest(options: options)
            return result.ok ? 0 : 1
        default:
            throw CLIError("unknown command: \(command)", exitCode: 2)
        }
    }

    private func doctor(options: Options) async throws {
        let containerID = options.value("container") ??
            ProcessInfo.processInfo.environment["HOME_LIBRARY_CLOUDKIT_CONTAINER"] ??
            HomeLibraryCloudKitConstants.defaultContainerIdentifier
        let expectedCloudKitEnvironment = expectedCloudKitEnvironment()
        let derivedIgnored = isIgnored(".derived")
        let markdownTestIgnored = isIgnored("markdownNote/test")
        let entitlements = codesignEntitlementsSummary(
            expectedContainerID: containerID,
            expectedCloudKitEnvironment: expectedCloudKitEnvironment
        )
        let provisioning = provisioningProfileDiagnostics(
            codesign: entitlements,
            containerID: containerID
        )
        let shouldCheckCloudKit = options.remoteMode == .memory ||
            (entitlements.hasCloudKitEntitlement && entitlements.hasContainerIdentifier)
        let accountStatus: String
        let accountAvailable: Bool
        if shouldCheckCloudKit {
            let remote = makeRemote(options: options, containerID: containerID)
            let status = try await remote.accountStatus()
            accountStatus = "\(status)"
            accountAvailable = status == .available
        } else {
            accountStatus = "notCheckedMissingEntitlements"
            accountAvailable = false
        }
        let warnings = doctorWarnings(
            options: options,
            accountAvailable: accountAvailable,
            skippedCloudKitAccountCheck: !shouldCheckCloudKit,
            codesign: entitlements,
            provisioning: provisioning
        )
        let ok = options.remoteMode == .memory ? accountAvailable : (
            accountAvailable &&
            entitlements.hasCloudKitEntitlement &&
            entitlements.hasContainerIdentifier &&
            entitlements.hasExpectedCloudKitEnvironment &&
            provisioning.installedProfileReady
        )

        printJSON(DoctorOutput(
            ok: ok,
            bundleID: HomeLibraryCloudKitConstants.defaultBundleIdentifier,
            containerID: containerID,
            environment: expectedCloudKitEnvironment,
            accountStatus: "\(accountStatus)",
            canAccessPrivateDatabase: ok,
            canAccessSharedDatabase: ok,
            derivedIgnored: derivedIgnored,
            markdownNoteTestIgnored: markdownTestIgnored,
            codesign: entitlements,
            provisioningProfiles: provisioning,
            warnings: warnings
        ))
    }

    private func repos(options: Options) async throws {
        let remote = try await configuredRemote(options: options)
        let repositories = try await remote.listRepositories()
        var summaries: [RepositorySummary] = []
        for repository in repositories {
            let snapshot = try? await remote.refreshRepository(repository)
            summaries.append(RepositorySummary(
                id: repository.id,
                name: repository.name,
                role: repository.role,
                databaseScope: repository.databaseScope,
                zoneID: repository.zoneName,
                canWrite: repository.canWrite,
                bookCount: snapshot?.books.count ?? 0,
                locationCount: snapshot?.locations.count ?? 0
            ))
        }
        printJSON(ReposOutput(repositories: summaries))
    }

    private func exportAIWorkspace(options: Options) async throws {
        let output = URL(fileURLWithPath: options.value("output") ?? ".derived/AIWorkflow/AIWorkspace.zip")
        let snapshot = try await loadSnapshot(options: options)
        writeError("Exporting AI workspace for \(snapshot.repository.id)")
        let result = try AIWorkspaceExporter.export(snapshot: snapshot, to: output)
        printJSON(result)
    }

    @discardableResult
    private func validatePatch(options: Options) async throws -> PatchValidationResult {
        guard let patchPath = options.positional.first else {
            throw CLIError("validate-patch requires a .homelibpatch path", exitCode: 2)
        }
        let patchURL = URL(fileURLWithPath: patchPath)
        let patchData = try Data(contentsOf: patchURL)
        let patch = try HomeLibraryJSONCodec.makeDecoder().decode(LibraryAIPatch.self, from: patchData)
        let snapshot = try await loadSnapshot(options: options, targetRepositoryID: patch.targetRepository.id)
        let result = LibraryAIPatchValidator.validate(patch: patch, patchData: patchData, snapshot: snapshot)
        if let resultPath = options.value("result") {
            try FileSystem.writeJSON(result, to: URL(fileURLWithPath: resultPath))
        }
        printJSON(result)
        return result
    }

    private func reviewPatch(options: Options) async throws {
        guard let patchPath = options.positional.first else {
            throw CLIError("review-patch requires a .homelibpatch path", exitCode: 2)
        }
        let resultURL = URL(fileURLWithPath: options.value("result") ?? ".derived/AIWorkflow/ReviewDecision.json")
        let patchURL = URL(fileURLWithPath: patchPath)
        let patchData = try Data(contentsOf: patchURL)
        let patch = try HomeLibraryJSONCodec.makeDecoder().decode(LibraryAIPatch.self, from: patchData)
        let snapshot = try await loadSnapshot(options: options, targetRepositoryID: patch.targetRepository.id)
        let validation = LibraryAIPatchValidator.validate(patch: patch, patchData: patchData, snapshot: snapshot)

        if options.has("auto-approve-test-only") {
            guard canAutoApproveTestOnly(options: options, patch: patch) else {
                throw CLIError("--auto-approve-test-only only works with --remote memory or AIWorkflowTest-* under HOME_LIBRARY_CLOUDKIT_LIVE_TESTS=1")
            }
            let decision = ReviewDecision(
                approved: true,
                approvedAt: .now,
                patchDigest: validation.patchDigest,
                approvedOperationIDs: patch.operations.map(\.clientOperationID),
                includeLowConfidence: true
            )
            try FileSystem.writeJSON(decision, to: resultURL)
            printJSON(ReviewAutoOutput(ok: true, reviewDecision: resultURL.path, approved: true))
            return
        }

        let server = PatchReviewServer(
            patch: patch,
            patchData: patchData,
            validation: validation,
            resultURL: resultURL,
            timeoutSeconds: TimeInterval(options.value("timeout").flatMap(Double.init) ?? 300)
        )
        let result = try await server.run()
        printJSON(result)
    }

    @discardableResult
    private func applyPatch(options: Options) async throws -> PatchApplyResult {
        guard let patchPath = options.positional.first else {
            throw CLIError("apply-patch requires a .homelibpatch path", exitCode: 2)
        }
        let patchURL = URL(fileURLWithPath: patchPath)
        let patchData = try Data(contentsOf: patchURL)
        let patch = try HomeLibraryJSONCodec.makeDecoder().decode(LibraryAIPatch.self, from: patchData)
        let remote = try await configuredRemote(options: options, targetRepositoryID: patch.targetRepository.id)
        let repository = try await findRepository(id: patch.targetRepository.id, remote: remote)
        let reviewDecision = try options.value("review-decision").map { try FileSystem.readJSON(ReviewDecision.self, from: URL(fileURLWithPath: $0)) }
        let result = try await LibraryAIPatchApplier.apply(
            patch: patch,
            patchData: patchData,
            reviewDecision: reviewDecision,
            remote: remote,
            repository: repository
        )
        if let resultPath = options.value("result") {
            try FileSystem.writeJSON(result, to: URL(fileURLWithPath: resultPath))
        }
        printJSON(result)
        return result
    }

    private func loadSnapshot(options: Options, targetRepositoryID: String? = nil) async throws -> RemoteRepositorySnapshot {
        if let snapshotPath = options.value("snapshot") {
            let workspaceSnapshot = try FileSystem.readJSON(AIWorkspaceSnapshot.self, from: URL(fileURLWithPath: snapshotPath))
            return workspaceSnapshot.makeRemoteSnapshot()
        }

        let remote = try await configuredRemote(options: options, targetRepositoryID: targetRepositoryID)
        let repositoryID = targetRepositoryID ?? options.value("repo")
        guard let repositoryID else {
            throw CLIError("--repo is required unless --snapshot is provided", exitCode: 2)
        }
        let repository = try await findRepository(id: repositoryID, remote: remote)
        return try await remote.refreshRepository(repository)
    }

    private func configuredRemote(options: Options, targetRepositoryID: String? = nil) async throws -> LibraryRemote {
        if options.remoteMode == .memory {
            return try await makeMemoryFixtureRepository(options: options, targetRepositoryID: targetRepositoryID)
        }
        return makeRemote(options: options, containerID: options.value("container"))
    }

    private func makeRemote(options: Options, containerID: String?) -> LibraryRemote {
        if options.remoteMode == .memory {
            return InMemoryLibraryRemote()
        }
        let resolvedContainer = containerID ??
            ProcessInfo.processInfo.environment["HOME_LIBRARY_CLOUDKIT_CONTAINER"] ??
            HomeLibraryCloudKitConstants.defaultContainerIdentifier
        return CloudKitLibraryRemote(containerIdentifier: resolvedContainer)
    }

    private func makeMemoryFixtureRepository(options: Options, targetRepositoryID: String?) async throws -> InMemoryLibraryRemote {
        let remote = InMemoryLibraryRemote()
        if let snapshotPath = options.value("snapshot") {
            let workspaceSnapshot = try FileSystem.readJSON(AIWorkspaceSnapshot.self, from: URL(fileURLWithPath: snapshotPath))
            let snapshot = workspaceSnapshot.makeRemoteSnapshot()
            await remote.seedRepository(snapshot.repository, locations: snapshot.locations, books: snapshot.books)
            return remote
        }
        let id = targetRepositoryID ?? options.value("repo") ?? "memory"
        let repository = LibraryRepositoryReference(
            id: id,
            name: id.hasPrefix("AIWorkflowTest") ? id : "AIWorkflowTest-Memory",
            role: .owner,
            databaseScope: .private,
            zoneName: id,
            zoneOwnerName: CKCurrentUserDefaultName
        )
        await remote.seedRepository(repository)
        return remote
    }

    private func findRepository(id: String, remote: LibraryRemote) async throws -> LibraryRepositoryReference {
        let repositories = try await remote.listRepositories()
        guard let repository = repositories.first(where: { $0.id == id || $0.zoneName == id }) else {
            throw CLIError("repository not found: \(id)")
        }
        return repository
    }

    private func canAutoApproveTestOnly(options: Options, patch: LibraryAIPatch) -> Bool {
        if options.remoteMode == .memory {
            return true
        }
        let environment = ProcessInfo.processInfo.environment
        return environment["HOME_LIBRARY_CLOUDKIT_LIVE_TESTS"] == "1" &&
            patch.targetRepository.id.hasPrefix(environment["HOME_LIBRARY_TEST_REPOSITORY_PREFIX"] ?? "AIWorkflowTest")
    }

    private func runLiveTest(options: Options) async throws -> LiveTestOutput {
        let environment = ProcessInfo.processInfo.environment
        if options.remoteMode != .memory,
           environment["HOME_LIBRARY_CLOUDKIT_LIVE_TESTS"] != "1" {
            throw CLIError("run-live-test requires HOME_LIBRARY_CLOUDKIT_LIVE_TESTS=1 unless --remote memory is used", exitCode: 2)
        }

        let remote = try await configuredRemote(options: options)
        let accountStatus = try await remote.accountStatus()
        guard accountStatus == .available else {
            throw CLIError("CloudKit account status is not available: \(accountStatus)")
        }

        let prefix = environment["HOME_LIBRARY_TEST_REPOSITORY_PREFIX"]?.nilIfEmpty ?? "AIWorkflowTest"
        let repositoryName = "\(prefix)-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6))"
        let repository = try await remote.createOwnedRepository(preferredName: repositoryName)
        var steps: [LiveTestStep] = [
            LiveTestStep(name: "doctor", ok: true, detail: "accountStatus=\(accountStatus)"),
            LiveTestStep(name: "createTestRepository", ok: true, detail: repository.id)
        ]
        var cleanupOK = false

        do {
            let locations = LibraryLocation.defaultLocations() + [
                LibraryLocation(id: "location.aiworkflow", name: "AI Workflow", sortOrder: 2)
            ]
            let savedLocations = try await remote.saveLocations(locations, in: repository)
            steps.append(LiveTestStep(name: "saveLocations", ok: savedLocations.contains(where: { $0.id == "location.aiworkflow" }), detail: "\(savedLocations.count) locations"))
            let locationSnapshot = try await waitForLocation("location.aiworkflow", remote: remote, repository: repository)
            steps.append(LiveTestStep(
                name: "verifySavedLocation",
                ok: locationSnapshot.locations.contains(where: { $0.id == "location.aiworkflow" }),
                detail: "\(locationSnapshot.locations.count) refreshed locations"
            ))

            let createPatch = LibraryAIPatch(
                source: "home-library-cloudkit-live-test",
                createdAt: .now,
                targetRepository: AITargetRepository(id: repository.id, name: repository.name, databaseScope: repository.databaseScope, zoneID: repository.zoneName),
                operations: [
                    .createBook(CreateBookOperation(
                        clientOperationID: "live-create-book",
                        confidence: 0.99,
                        fields: PatchBookFields(
                            title: "AI Workflow Live Test",
                            author: "Codex",
                            publisher: "",
                            year: "",
                            isbn: "9780131177055",
                            locationID: "location.aiworkflow"
                        ),
                        cover: makeTestCoverPayload(name: "create", color: .systemBlue),
                        evidence: [PatchEvidence(sourceName: "live-test", url: "https://example.com/home-library-cloudkit-live-test", matchedFields: ["title"])]
                    ))
                ]
            )
            let createResult = try await validateAndApply(createPatch, remote: remote, repository: repository, reviewDecision: nil)
            steps.append(LiveTestStep(name: "applyCreateBookWithCover", ok: createResult.appliedCount == 1, detail: applySummary(createResult)))

            var snapshot = try await remote.refreshRepository(repository)
            guard let created = snapshot.books.first else {
                throw CLIError("live test create did not produce a book")
            }
            steps.append(LiveTestStep(
                name: "refreshCover",
                ok: created.book.coverAssetID != nil && created.coverData != nil,
                detail: "coverAssetID=\(created.book.coverAssetID ?? "nil") changeToken=\(snapshot.changeTokenData == nil ? "nil" : "present")"
            ))

            let updatePatch = LibraryAIPatch(
                source: "home-library-cloudkit-live-test",
                createdAt: .now,
                targetRepository: AITargetRepository(id: repository.id, name: repository.name, databaseScope: repository.databaseScope, zoneID: repository.zoneName),
                operations: [
                    .updateBook(UpdateBookOperation(
                        clientOperationID: "live-update-fields",
                        id: created.book.id,
                        expectedUpdatedAt: created.book.updatedAt,
                        expectedRecordChangeTag: created.recordChangeTag,
                        confidence: 0.99,
                        fields: [
                            "publisher": PatchFieldUpdate(mode: .fillIfEmpty, value: "OpenAI Press"),
                            "year": PatchFieldUpdate(mode: .fillIfEmpty, value: "2026")
                        ]
                    ))
                ]
            )
            let updateResult = try await validateAndApply(updatePatch, remote: remote, repository: repository, reviewDecision: nil)
            steps.append(LiveTestStep(name: "applyUpdateFields", ok: updateResult.appliedCount == 1, detail: applySummary(updateResult)))

            snapshot = try await remote.refreshRepository(repository)
            guard let updated = snapshot.books.first else {
                throw CLIError("live test update lost test book")
            }

            if options.remoteMode != .memory,
               let simulatorName = environment["HOME_LIBRARY_TEST_SIMULATOR_NAME"]?.nilIfEmpty {
                let simulatorResult = try verifySimulatorVisibility(
                    simulatorName: simulatorName,
                    repository: repository,
                    expectedBookTitle: updated.book.title,
                    expectedBookID: updated.book.id,
                    environment: environment
                )
                steps.append(LiveTestStep(
                    name: "verifySimulatorVisibility",
                    ok: simulatorResult.success,
                    detail: "simulator=\(simulatorName) bookID=\(simulatorResult.bookID ?? "nil") observed=\(simulatorResult.observedBookTitles.joined(separator: ","))"
                ))
            }

            let replaceCoverPatch = LibraryAIPatch(
                source: "home-library-cloudkit-live-test",
                createdAt: .now,
                targetRepository: AITargetRepository(id: repository.id, name: repository.name, databaseScope: repository.databaseScope, zoneID: repository.zoneName),
                operations: [
                    .updateBookCover(UpdateBookCoverOperation(
                        clientOperationID: "live-replace-cover",
                        id: updated.book.id,
                        expectedUpdatedAt: updated.book.updatedAt,
                        expectedRecordChangeTag: updated.recordChangeTag,
                        confidence: 0.99,
                        expectedCurrentCoverAssetID: updated.book.coverAssetID,
                        cover: makeTestCoverPayload(name: "replace", color: .systemGreen)
                    ))
                ]
            )
            let replaceDecision = makeDecision(for: replaceCoverPatch)
            let replaceResult = try await validateAndApply(replaceCoverPatch, remote: remote, repository: repository, reviewDecision: replaceDecision)
            steps.append(LiveTestStep(name: "applyReplaceCover", ok: replaceResult.appliedCount == 1, detail: applySummary(replaceResult)))

            snapshot = try await remote.refreshRepository(repository)
            guard let coverReplaced = snapshot.books.first else {
                throw CLIError("live test cover replace lost test book")
            }

            let stalePatch = LibraryAIPatch(
                source: "home-library-cloudkit-live-test",
                createdAt: .now,
                targetRepository: AITargetRepository(id: repository.id, name: repository.name, databaseScope: repository.databaseScope, zoneID: repository.zoneName),
                operations: [
                    .updateBook(UpdateBookOperation(
                        clientOperationID: "live-stale-conflict",
                        id: coverReplaced.book.id,
                        expectedUpdatedAt: coverReplaced.book.updatedAt,
                        expectedRecordChangeTag: coverReplaced.recordChangeTag,
                        confidence: 0.99,
                        fields: ["year": PatchFieldUpdate(mode: .replaceIfCurrentValue, expectedValue: "2026", value: "2027")]
                    ))
                ]
            )
            var externallyChangedBook = coverReplaced.book
            externallyChangedBook.author = "Codex External Change"
            externallyChangedBook.updatedAt = Date()
            _ = try await remote.upsertBook(externallyChangedBook, coverData: nil, in: repository)
            let conflictResult = try await validateAndApply(stalePatch, remote: remote, repository: repository, reviewDecision: makeDecision(for: stalePatch))
            steps.append(LiveTestStep(name: "stalePatchConflict", ok: conflictResult.conflictCount == 1, detail: applySummary(conflictResult)))

            snapshot = try await remote.refreshRepository(repository)
            guard let changed = snapshot.books.first else {
                throw CLIError("live test conflict path lost test book")
            }

            let removeCoverPatch = LibraryAIPatch(
                source: "home-library-cloudkit-live-test",
                createdAt: .now,
                targetRepository: AITargetRepository(id: repository.id, name: repository.name, databaseScope: repository.databaseScope, zoneID: repository.zoneName),
                operations: [
                    .removeBookCover(RemoveBookCoverOperation(
                        clientOperationID: "live-remove-cover",
                        id: changed.book.id,
                        expectedUpdatedAt: changed.book.updatedAt,
                        expectedRecordChangeTag: changed.recordChangeTag,
                        expectedCurrentCoverAssetID: changed.book.coverAssetID ?? "",
                        reason: "live test cleanup"
                    ))
                ]
            )
            let removeResult = try await validateAndApply(removeCoverPatch, remote: remote, repository: repository, reviewDecision: makeDecision(for: removeCoverPatch))
            steps.append(LiveTestStep(name: "applyRemoveCover", ok: removeResult.appliedCount == 1, detail: applySummary(removeResult)))

            snapshot = try await remote.refreshRepository(repository)
            guard let noCover = snapshot.books.first else {
                throw CLIError("live test remove cover lost test book")
            }

            let workspaceURL = FileSystem.defaultWorkflowDirectory().appendingPathComponent("LiveWorkspace-\(repository.id)", isDirectory: true)
            let workspace = try AIWorkspaceExporter.export(snapshot: snapshot, to: workspaceURL)
            steps.append(LiveTestStep(name: "exportAIWorkspace", ok: workspace.ok, detail: workspace.path))

            let deletePatch = LibraryAIPatch(
                source: "home-library-cloudkit-live-test",
                createdAt: .now,
                targetRepository: AITargetRepository(id: repository.id, name: repository.name, databaseScope: repository.databaseScope, zoneID: repository.zoneName),
                operations: [
                    .deleteBook(DeleteBookOperation(
                        clientOperationID: "live-delete-book",
                        id: noCover.book.id,
                        expectedUpdatedAt: noCover.book.updatedAt,
                        expectedRecordChangeTag: noCover.recordChangeTag,
                        reason: "live test cleanup"
                    ))
                ]
            )
            let deleteResult = try await validateAndApply(deletePatch, remote: remote, repository: repository, reviewDecision: makeDecision(for: deletePatch))
            steps.append(LiveTestStep(name: "applyDeleteBook", ok: deleteResult.appliedCount == 1, detail: applySummary(deleteResult)))

            let finalSnapshot = try await remote.refreshRepository(repository)
            steps.append(LiveTestStep(name: "verifyDelete", ok: finalSnapshot.books.isEmpty, detail: "bookCount=\(finalSnapshot.books.count)"))

            try await remote.deleteRepository(repository)
            cleanupOK = true
            steps.append(LiveTestStep(name: "cleanupRepository", ok: true, detail: repository.id))

            let ok = steps.allSatisfy(\.ok)
            let output = LiveTestOutput(ok: ok, repositoryID: repository.id, steps: steps, cleanupOK: cleanupOK)
            if let resultPath = options.value("result") {
                try FileSystem.writeJSON(output, to: URL(fileURLWithPath: resultPath))
            }
            printJSON(output)
            return output
        } catch {
            do {
                try await remote.deleteRepository(repository)
                cleanupOK = true
                steps.append(LiveTestStep(name: "cleanupRepository", ok: true, detail: "cleaned after error: \(error)"))
            } catch {
                steps.append(LiveTestStep(name: "cleanupRepository", ok: false, detail: "cleanup failed after error: \(error)"))
            }
            let output = LiveTestOutput(ok: false, repositoryID: repository.id, steps: steps, cleanupOK: cleanupOK)
            if let resultPath = options.value("result") {
                try? FileSystem.writeJSON(output, to: URL(fileURLWithPath: resultPath))
            }
            printJSON(output)
            throw error
        }
    }

    private func validateAndApply(
        _ patch: LibraryAIPatch,
        remote: LibraryRemote,
        repository: LibraryRepositoryReference,
        reviewDecision: ReviewDecision?
    ) async throws -> PatchApplyResult {
        let patchData = try HomeLibraryJSONCodec.makeEncoder(prettyPrinted: false).encode(patch)
        let snapshot = try await remote.refreshRepository(repository)
        let validation = LibraryAIPatchValidator.validate(patch: patch, patchData: patchData, snapshot: snapshot)
        guard validation.errors.isEmpty else {
            throw CLIError("live test validation failed: \(validation.errors.joined(separator: "; "))")
        }
        return try await LibraryAIPatchApplier.apply(
            patch: patch,
            patchData: patchData,
            reviewDecision: reviewDecision,
            remote: remote,
            repository: repository
        )
    }

    private func waitForLocation(
        _ locationID: String,
        remote: LibraryRemote,
        repository: LibraryRepositoryReference,
        timeoutSeconds: TimeInterval = 12
    ) async throws -> RemoteRepositorySnapshot {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var lastSnapshot = try await remote.refreshRepository(repository)
        while !lastSnapshot.locations.contains(where: { $0.id == locationID }) && Date() < deadline {
            try await Task.sleep(nanoseconds: 700_000_000)
            lastSnapshot = try await remote.refreshRepository(repository)
        }
        return lastSnapshot
    }

    private func verifySimulatorVisibility(
        simulatorName: String,
        repository: LibraryRepositoryReference,
        expectedBookTitle: String,
        expectedBookID: String,
        environment: [String: String]
    ) throws -> SimulatorAutomationResult {
        let repoRoot = repositoryRoot(environment: environment)
        let projectPath = repoRoot.appendingPathComponent("homeLibrary.xcodeproj").path
        guard FileManager.default.fileExists(atPath: projectPath) else {
            throw CLIError("HOME_LIBRARY_REPO_ROOT does not contain homeLibrary.xcodeproj: \(repoRoot.path)")
        }

        let derivedDataURL = repoRoot.appendingPathComponent(".derived/AIWorkflow/cli-sim-cloudkit", isDirectory: true)
        let productsURL = derivedDataURL.appendingPathComponent("Build/Products/Debug-iphonesimulator", isDirectory: true)
        let bundleID = "yu.homeLibrary"
        let simulator = try loadBootedSimulator(named: simulatorName)

        _ = try runProcess(
            "/usr/bin/xcodebuild",
            [
                "-project", projectPath,
                "-scheme", "homeLibrary",
                "-configuration", "Debug",
                "-destination", "generic/platform=iOS Simulator",
                "-derivedDataPath", derivedDataURL.path,
                "-quiet",
                "build"
            ],
            currentDirectory: repoRoot
        )

        let appURL = try builtSimulatorAppURL(in: productsURL, bundleID: bundleID)

        _ = try runProcess("/usr/bin/xcrun", ["simctl", "install", simulator.udid, appURL.path])
        let dataContainerOutput = try runProcess(
            "/usr/bin/xcrun",
            ["simctl", "get_app_container", simulator.udid, bundleID, "data"]
        )
        let dataContainerURL = URL(fileURLWithPath: dataContainerOutput.trimmed, isDirectory: true)
        let resultFile = "cli-sim-\(UUID().uuidString).json"
        let resultURL = dataContainerURL.appendingPathComponent("Documents/\(resultFile)")
        try FileManager.default.createDirectory(
            at: resultURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: resultURL)
        _ = try? runProcess("/usr/bin/xcrun", ["simctl", "terminate", simulator.udid, bundleID])

        let namespace = "cli-sim-\(UUID().uuidString)"
        var automationEnvironment = [
            "HOME_LIBRARY_REMOTE_DRIVER": "cloudkit",
            "HOME_LIBRARY_CLOUDKIT_LIVE_TESTS": "1",
            "HOME_LIBRARY_DEBUG_CLOUDKIT": "1",
            "HOME_LIBRARY_STORAGE_NAMESPACE": namespace,
            "HOME_LIBRARY_SESSION_NAMESPACE": namespace,
            "HOME_LIBRARY_CLOUDKIT_AUTOMATION_COMMAND": "verify-repository-book",
            "HOME_LIBRARY_CLOUDKIT_AUTOMATION_RESULT_FILE": resultFile,
            "HOME_LIBRARY_CLOUDKIT_AUTOMATION_REPOSITORY_NAME": repository.name,
            "HOME_LIBRARY_CLOUDKIT_AUTOMATION_ZONE_NAME": repository.zoneName,
            "HOME_LIBRARY_CLOUDKIT_AUTOMATION_INITIAL_TITLE": expectedBookTitle,
            "HOME_LIBRARY_CLOUDKIT_AUTOMATION_BOOK_ID": expectedBookID
        ]
        for key in ["HOME_LIBRARY_CLOUDKIT_CONTAINER", "HOME_LIBRARY_CLOUDKIT_ENVIRONMENT"] {
            if let value = environment[key]?.nilIfEmpty {
                automationEnvironment[key] = value
            }
        }

        var launchEnvironment: [String: String] = [:]
        for (key, value) in automationEnvironment {
            launchEnvironment["SIMCTL_CHILD_\(key)"] = value
        }

        _ = try runProcess(
            "/usr/bin/xcrun",
            ["simctl", "launch", "--terminate-running-process", simulator.udid, bundleID],
            environment: launchEnvironment
        )

        let result = try waitForSimulatorAutomationResult(at: resultURL, timeout: 180)
        _ = try? runProcess("/usr/bin/xcrun", ["simctl", "terminate", simulator.udid, bundleID])

        guard result.success else {
            throw CLIError("simulator visibility check failed: \(result.message)")
        }

        return result
    }

    private func repositoryRoot(environment: [String: String]) -> URL {
        if let path = environment["HOME_LIBRARY_REPO_ROOT"]?.nilIfEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    private func loadBootedSimulator(named name: String) throws -> SimulatorDevice {
        let output = try runProcess("/usr/bin/xcrun", ["simctl", "list", "devices", "--json"])
        guard let data = output.data(using: .utf8),
              let list = try? JSONDecoder().decode(SimulatorList.self, from: data),
              let simulator = list.devices.values
                .flatMap({ $0 })
                .first(where: { $0.name == name && $0.isAvailable && $0.state == "Booted" }) else {
            throw CLIError("HOME_LIBRARY_TEST_SIMULATOR_NAME=\(name) is not a booted simulator. Boot it and sign in to the same iCloud account before running this verification.")
        }

        return simulator
    }

    private func builtSimulatorAppURL(in productsURL: URL, bundleID: String) throws -> URL {
        let apps = (try? FileManager.default.contentsOfDirectory(
            at: productsURL,
            includingPropertiesForKeys: nil
        ))?.filter { $0.pathExtension == "app" } ?? []

        for appURL in apps {
            let infoPlistURL = appURL.appendingPathComponent("Info.plist")
            guard let data = try? Data(contentsOf: infoPlistURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                  let dictionary = plist as? [String: Any],
                  dictionary["CFBundleIdentifier"] as? String == bundleID else {
                continue
            }

            return appURL
        }

        throw CLIError("iOS simulator build did not produce an app with bundle id \(bundleID) under \(productsURL.path)")
    }

    private func waitForSimulatorAutomationResult(
        at url: URL,
        timeout: TimeInterval
    ) throws -> SimulatorAutomationResult {
        let deadline = Date().addingTimeInterval(timeout)
        let decoder = JSONDecoder()

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let result = try? decoder.decode(SimulatorAutomationResult.self, from: data) {
                return result
            }

            Thread.sleep(forTimeInterval: 1)
        }

        throw CLIError("timed out waiting for simulator automation result at \(url.path)")
    }

    private func runProcess(
        _ executable: String,
        _ arguments: [String],
        environment overrides: [String: String] = [:],
        currentDirectory: URL? = nil
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        if !overrides.isEmpty {
            var merged = ProcessInfo.processInfo.environment
            overrides.forEach { key, value in
                merged[key] = value
            }
            process.environment = merged
        }

        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("home-library-cloudkit-process-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        process.standardOutput = logHandle
        process.standardError = logHandle

        try process.run()
        process.waitUntilExit()
        try? logHandle.close()

        let output = ((try? String(contentsOf: logURL, encoding: .utf8)) ?? "").trimmed
        try? FileManager.default.removeItem(at: logURL)

        guard process.terminationStatus == 0 else {
            throw CLIError(output.isEmpty ? "\(executable) failed with exit \(process.terminationStatus)" : output)
        }

        return output
    }

    private func applySummary(_ result: PatchApplyResult) -> String {
        let operationDetails = result.operations.map {
            "\($0.clientOperationID):\($0.status.rawValue):\($0.message)"
        }.joined(separator: " | ")
        return "applied=\(result.appliedCount) skipped=\(result.skippedCount) conflicts=\(result.conflictCount) failed=\(result.failedCount) retryable=\(result.retryableFailedCount) \(operationDetails)"
    }

    private func makeDecision(for patch: LibraryAIPatch) -> ReviewDecision {
        let data = (try? HomeLibraryJSONCodec.makeEncoder(prettyPrinted: false).encode(patch)) ?? Data()
        return ReviewDecision(
            approved: true,
            approvedAt: .now,
            patchDigest: HomeLibraryHash.digestString(for: data),
            approvedOperationIDs: patch.operations.map(\.clientOperationID),
            includeLowConfidence: true
        )
    }

    private func makeTestCoverPayload(name: String, color: NSColor) -> PatchCoverPayload {
        let size = NSSize(width: 180, height: 270)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        color.setFill()
        NSBezierPath(rect: NSRect(x: 24, y: 24, width: 132, height: 222)).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation ?? Data())
        let data = bitmap?.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) ?? Data()
        return PatchCoverPayload(
            originalPixelSize: LibraryCoverImageSize(width: Int(size.width), height: Int(size.height)),
            compressedPixelSize: LibraryCoverImageSize(width: Int(size.width), height: Int(size.height)),
            compressedByteSize: data.count,
            sourceURL: "https://example.com/\(name)-cover.jpg",
            data: data.base64EncodedString()
        )
    }

    private func isIgnored(_ path: String) -> Bool {
        guard let gitignore = try? String(contentsOfFile: ".gitignore", encoding: .utf8) else {
            return false
        }
        return gitignore
            .components(separatedBy: .newlines)
            .map(\.trimmed)
            .contains(path)
    }

    private func codesignEntitlementsSummary(
        expectedContainerID: String,
        expectedCloudKitEnvironment: String
    ) -> CodesignDiagnostics {
        let executable = CommandLine.arguments.first ?? ""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-d", "--entitlements", ":-", executable]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let entitlements = parsePropertyList(data)
            let services = stringListEntitlement("com.apple.developer.icloud-services", in: entitlements)
            let containers = stringListEntitlement("com.apple.developer.icloud-container-identifiers", in: entitlements)
            let developmentContainers = stringListEntitlement("com.apple.developer.icloud-container-development-container-identifiers", in: entitlements)
            let environments = stringListEntitlement("com.apple.developer.icloud-container-environment", in: entitlements)
            let applicationIdentifier = (entitlements["application-identifier"] as? String) ??
                (entitlements["com.apple.application-identifier"] as? String)
            let teamIdentifier = entitlements["com.apple.developer.team-identifier"] as? String
            return CodesignDiagnostics(
                checkedExecutable: executable,
                applicationIdentifier: applicationIdentifier,
                teamIdentifier: teamIdentifier,
                iCloudServices: services,
                iCloudContainerIdentifiers: containers,
                iCloudDevelopmentContainerIdentifiers: developmentContainers,
                iCloudContainerEnvironments: environments,
                expectedICloudContainerEnvironment: expectedCloudKitEnvironment,
                hasCloudKitEntitlement: services.contains("CloudKit") || services.contains("*"),
                hasContainerIdentifier: containers.contains(expectedContainerID),
                hasExpectedCloudKitEnvironment: environments.contains(expectedCloudKitEnvironment),
                readable: process.terminationStatus == 0
            )
        } catch {
            return CodesignDiagnostics(
                checkedExecutable: executable,
                applicationIdentifier: nil,
                teamIdentifier: nil,
                iCloudServices: [],
                iCloudContainerIdentifiers: [],
                iCloudDevelopmentContainerIdentifiers: [],
                iCloudContainerEnvironments: [],
                expectedICloudContainerEnvironment: expectedCloudKitEnvironment,
                hasCloudKitEntitlement: false,
                hasContainerIdentifier: false,
                hasExpectedCloudKitEnvironment: false,
                readable: false
            )
        }
    }

    private func expectedCloudKitEnvironment() -> String {
        let rawValue = ProcessInfo.processInfo.environment["HOME_LIBRARY_CLOUDKIT_ENVIRONMENT"]?.nilIfEmpty ?? "production"
        return rawValue.caseInsensitiveCompare("development") == .orderedSame ? "Development" : "Production"
    }

    private func provisioningProfileDiagnostics(
        codesign: CodesignDiagnostics,
        containerID: String
    ) -> ProvisioningProfileDiagnostics {
        let targetApplicationIdentifier = codesign.applicationIdentifier ??
            "\(HomeLibraryCloudKitConstants.defaultTeamIdentifier).\(HomeLibraryCloudKitConstants.defaultBundleIdentifier)"
        let directories = provisioningProfileDirectories()
        var totalProfiles = 0
        var decodeErrors = 0
        var appIDMatches = 0
        var containerMatches = 0
        var macOSMatches = 0
        var readyMatches = 0
        var platformCounts: [String: Int] = [:]

        for directory in directories {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator where ["mobileprovision", "provisionprofile"].contains(url.pathExtension) {
                totalProfiles += 1
                guard let profile = readProvisioningProfile(url) else {
                    decodeErrors += 1
                    continue
                }
                let appIDMatch = profile.applicationIdentifier == targetApplicationIdentifier
                let containerMatch = profile.iCloudContainerIdentifiers.contains(containerID)
                let macOSMatch = profile.platforms.contains { platform in
                    platform == "OSX" || platform == "macOS"
                }

                for platform in profile.platforms {
                    platformCounts[platform, default: 0] += 1
                }
                if appIDMatch { appIDMatches += 1 }
                if containerMatch { containerMatches += 1 }
                if macOSMatch { macOSMatches += 1 }
                if appIDMatch && containerMatch && macOSMatch {
                    readyMatches += 1
                }
            }
        }

        return ProvisioningProfileDiagnostics(
            targetApplicationIdentifier: targetApplicationIdentifier,
            targetContainerIdentifier: containerID,
            searchedProfileDirectories: directories.map(profileDirectoryLabel),
            profileCount: totalProfiles,
            decodeErrorCount: decodeErrors,
            matchingApplicationIdentifierCount: appIDMatches,
            matchingContainerCount: containerMatches,
            matchingMacOSPlatformCount: macOSMatches,
            matchingReadyProfileCount: readyMatches,
            installedProfileReady: readyMatches > 0,
            platformCounts: platformCounts
        )
    }

    private func provisioningProfileDirectories() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/MobileDevice/Provisioning Profiles", isDirectory: true),
            home.appendingPathComponent("Library/Developer/Xcode/UserData/Provisioning Profiles", isDirectory: true)
        ]
    }

    private func profileDirectoryLabel(_ url: URL) -> String {
        let path = url.path
        if path.contains("/Library/MobileDevice/Provisioning Profiles") {
            return "~/Library/MobileDevice/Provisioning Profiles"
        }
        if path.contains("/Library/Developer/Xcode/UserData/Provisioning Profiles") {
            return "~/Library/Developer/Xcode/UserData/Provisioning Profiles"
        }
        return url.lastPathComponent
    }

    private func readProvisioningProfile(_ url: URL) -> ProvisioningProfile? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["cms", "-D", "-i", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return nil
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let plist = parsePropertyList(data)
            let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
            return ProvisioningProfile(
                applicationIdentifier: (entitlements["application-identifier"] as? String) ??
                    (entitlements["com.apple.application-identifier"] as? String),
                iCloudContainerIdentifiers: entitlements["com.apple.developer.icloud-container-identifiers"] as? [String] ?? [],
                platforms: plist["Platform"] as? [String] ?? []
            )
        } catch {
            return nil
        }
    }

    private func parsePropertyList(_ data: Data) -> [String: Any] {
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    private func stringListEntitlement(_ key: String, in entitlements: [String: Any]) -> [String] {
        if let values = entitlements[key] as? [String] {
            return values
        }
        if let value = entitlements[key] as? String {
            return [value]
        }
        return []
    }

    private func doctorWarnings(
        options: Options,
        accountAvailable: Bool,
        skippedCloudKitAccountCheck: Bool,
        codesign: CodesignDiagnostics,
        provisioning: ProvisioningProfileDiagnostics
    ) -> [String] {
        var warnings: [String] = []
        if skippedCloudKitAccountCheck && options.remoteMode != .memory {
            warnings.append("CloudKit account status was not checked because the executable is missing required entitlements")
        } else if !accountAvailable && options.remoteMode != .memory {
            warnings.append("CloudKit account status is not available")
        }
        if !codesign.hasCloudKitEntitlement {
            warnings.append("current executable does not expose a CloudKit entitlement")
        }
        if !codesign.hasContainerIdentifier {
            warnings.append("current executable does not expose the expected iCloud container entitlement")
        }
        if !codesign.hasExpectedCloudKitEnvironment {
            warnings.append("current executable is not signed for CloudKit \(codesign.expectedICloudContainerEnvironment)")
        }
        if codesign.expectedICloudContainerEnvironment == "Production",
           !codesign.iCloudDevelopmentContainerIdentifiers.isEmpty {
            warnings.append("current executable still exposes CloudKit development container identifiers")
        }
        if !provisioning.installedProfileReady {
            warnings.append("no installed macOS provisioning profile matches the CLI application identifier and iCloud container")
        }
        return warnings
    }
}

private enum RemoteMode {
    case cloudkit
    case memory
}

private struct ErrorOutput: Encodable {
    var ok: Bool
    var error: String
}

private struct DoctorOutput: Encodable {
    var ok: Bool
    var bundleID: String
    var containerID: String
    var environment: String
    var accountStatus: String
    var canAccessPrivateDatabase: Bool
    var canAccessSharedDatabase: Bool
    var derivedIgnored: Bool
    var markdownNoteTestIgnored: Bool
    var codesign: CodesignDiagnostics
    var provisioningProfiles: ProvisioningProfileDiagnostics
    var warnings: [String]
}

private struct CodesignDiagnostics: Encodable {
    var checkedExecutable: String
    var applicationIdentifier: String?
    var teamIdentifier: String?
    var iCloudServices: [String]
    var iCloudContainerIdentifiers: [String]
    var iCloudDevelopmentContainerIdentifiers: [String]
    var iCloudContainerEnvironments: [String]
    var expectedICloudContainerEnvironment: String
    var hasCloudKitEntitlement: Bool
    var hasContainerIdentifier: Bool
    var hasExpectedCloudKitEnvironment: Bool
    var readable: Bool
}

private struct ProvisioningProfileDiagnostics: Encodable {
    var targetApplicationIdentifier: String
    var targetContainerIdentifier: String
    var searchedProfileDirectories: [String]
    var profileCount: Int
    var decodeErrorCount: Int
    var matchingApplicationIdentifierCount: Int
    var matchingContainerCount: Int
    var matchingMacOSPlatformCount: Int
    var matchingReadyProfileCount: Int
    var installedProfileReady: Bool
    var platformCounts: [String: Int]
}

private struct ProvisioningProfile {
    var applicationIdentifier: String?
    var iCloudContainerIdentifiers: [String]
    var platforms: [String]
}

private struct ReposOutput: Encodable {
    var repositories: [RepositorySummary]
}

private struct ReviewAutoOutput: Encodable {
    var ok: Bool
    var reviewDecision: String
    var approved: Bool
}

private struct LiveTestOutput: Encodable {
    var ok: Bool
    var repositoryID: String
    var steps: [LiveTestStep]
    var cleanupOK: Bool
}

private struct LiveTestStep: Encodable {
    var name: String
    var ok: Bool
    var detail: String
}

private struct SimulatorList: Decodable {
    var devices: [String: [SimulatorDevice]]
}

private struct SimulatorDevice: Decodable {
    var name: String
    var udid: String
    var state: String
    var isAvailable: Bool
}

private struct SimulatorAutomationResult: Decodable {
    var command: String
    var success: Bool
    var message: String
    var repositoryID: String?
    var repositoryName: String?
    var zoneName: String?
    var shareURL: String?
    var bookID: String?
    var bookTitle: String?
    var bookCount: Int?
    var observedBookTitles: [String]
    var completedAt: String?
}

private struct Options {
    var positional: [String] = []
    private var values: [String: String] = [:]
    private var flags: Set<String> = []

    init(_ rawArguments: [String]) {
        var index = 0
        while index < rawArguments.count {
            let argument = rawArguments[index]
            if argument.hasPrefix("--") {
                let key = String(argument.dropFirst(2))
                if index + 1 < rawArguments.count, !rawArguments[index + 1].hasPrefix("--") {
                    values[key] = rawArguments[index + 1]
                    index += 2
                } else {
                    flags.insert(key)
                    index += 1
                }
            } else {
                positional.append(argument)
                index += 1
            }
        }
    }

    func value(_ key: String) -> String? {
        values[key]
    }

    func has(_ key: String) -> Bool {
        flags.contains(key)
    }

    var remoteMode: RemoteMode {
        values["remote"] == "memory" ? .memory : .cloudkit
    }
}

private extension AIWorkspaceSnapshot {
    func makeRemoteSnapshot() -> RemoteRepositorySnapshot {
        RemoteRepositorySnapshot(
            repository: repository,
            locations: locations,
            books: books.map { workspaceBook in
                RemoteBookSnapshot(
                    book: Book(
                        id: workspaceBook.id,
                        title: workspaceBook.title,
                        author: workspaceBook.author,
                        publisher: workspaceBook.publisher,
                        year: workspaceBook.year,
                        locationID: workspaceBook.locationID,
                        customFields: makeCustomFields(workspaceBook),
                        coverAssetID: workspaceBook.coverAssetID,
                        createdAt: createdAt,
                        updatedAt: workspaceBook.updatedAt
                    ),
                    coverData: nil,
                    recordChangeTag: workspaceBook.recordChangeTag
                )
            }
        )
    }

    private func makeCustomFields(_ book: AIWorkspaceBook) -> [String: String] {
        var fields: [String: String] = [:]
        if !book.isbn.trimmed.isEmpty {
            fields[BookInfoFieldKey.isbn] = book.isbn.trimmed
        }
        if !book.translator.trimmed.isEmpty {
            fields[BookInfoFieldKey.translator] = book.translator.trimmed
        }
        return fields
    }
}

private func printJSON<T: Encodable>(_ value: T) {
    do {
        let data = try HomeLibraryJSONCodec.makeEncoder().encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
        print(#"{"ok":false,"error":"failed to encode JSON"}"#)
    }
}

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
}
