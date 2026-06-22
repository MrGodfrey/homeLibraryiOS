import Foundation
import XCTest

final class CLICommandTests: XCTestCase {
    func testCLICommandSmokeAndSafetyGates() throws {
        let workDirectory = temporaryDirectory()

        let doctor = try runCLI(["doctor", "--remote", "memory"], in: workDirectory)
        XCTAssertEqual(doctor.status, 0)
        let doctorJSON = try doctor.jsonObject()
        XCTAssertEqual(doctorJSON["ok"] as? Bool, true)
        let doctorCodesign = try XCTUnwrap(doctorJSON["codesign"] as? [String: Any])
        XCTAssertNotNil(doctorCodesign["hasCloudKitEntitlement"] as? Bool)
        let doctorProvisioning = try XCTUnwrap(doctorJSON["provisioningProfiles"] as? [String: Any])
        XCTAssertEqual(
            doctorProvisioning["targetContainerIdentifier"] as? String,
            "iCloud.yu.homeLibrary"
        )
        XCTAssertNotNil(doctorProvisioning["installedProfileReady"] as? Bool)
        XCTAssertNotNil(doctorJSON["warnings"] as? [String])
        XCTAssertTrue(doctor.stderr.isEmpty)

        let realModeDoctor = try runCLI(["doctor"], in: workDirectory)
        XCTAssertEqual(realModeDoctor.status, 0)
        let realModeDoctorJSON = try realModeDoctor.jsonObject()
        XCTAssertEqual(realModeDoctorJSON["ok"] as? Bool, false)
        XCTAssertEqual(realModeDoctorJSON["accountStatus"] as? String, "notCheckedMissingEntitlements")
        let realModeWarnings = try XCTUnwrap(realModeDoctorJSON["warnings"] as? [String])
        XCTAssertTrue(realModeWarnings.contains { $0.contains("missing required entitlements") })

        let repos = try runCLI(["repos", "--remote", "memory"], in: workDirectory)
        XCTAssertEqual(repos.status, 0)
        let repositories = try XCTUnwrap(try repos.jsonValue("repositories") as? [[String: Any]])
        XCTAssertEqual(repositories.first?["id"] as? String, "memory")

        let defaultExport = try runCLI(["export-ai-workspace", "--remote", "memory", "--repo", "memory"], in: workDirectory)
        XCTAssertEqual(defaultExport.status, 0)
        XCTAssertTrue(defaultExport.stderr.contains("Exporting AI workspace"))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: workDirectory
                    .appendingPathComponent(".derived/AIWorkflow/AIWorkspace.zip")
                    .path
            )
        )

        let workspaceURL = workDirectory.appendingPathComponent("CommandWorkspace", isDirectory: true)
        let export = try runCLI([
            "export-ai-workspace",
            "--remote", "memory",
            "--repo", "memory",
            "--output", workspaceURL.path
        ], in: workDirectory)
        XCTAssertEqual(export.status, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceURL.appendingPathComponent("LibrarySnapshot.json").path))

        let invalidPatchURL = workDirectory.appendingPathComponent("invalid.homelibpatch")
        try writeJSON(makeCreatePatchJSON(repositoryID: "memory", locationID: "missing-location"), to: invalidPatchURL)
        let validationURL = workDirectory.appendingPathComponent("validation.json")
        let invalidValidation = try runCLI([
            "validate-patch",
            invalidPatchURL.path,
            "--snapshot", workspaceURL.appendingPathComponent("LibrarySnapshot.json").path,
            "--result", validationURL.path
        ], in: workDirectory)
        XCTAssertEqual(invalidValidation.status, 1)
        XCTAssertEqual(try invalidValidation.jsonValue("ok") as? Bool, false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: validationURL.path))

        let validPatchURL = workDirectory.appendingPathComponent("valid.homelibpatch")
        try writeJSON(makeCreatePatchJSON(repositoryID: "memory", locationID: "location.chengdu"), to: validPatchURL)
        let reviewDecisionURL = workDirectory.appendingPathComponent("ReviewDecision.json")
        let autoReview = try runCLI([
            "review-patch",
            validPatchURL.path,
            "--snapshot", workspaceURL.appendingPathComponent("LibrarySnapshot.json").path,
            "--result", reviewDecisionURL.path,
            "--auto-approve-test-only",
            "--remote", "memory"
        ], in: workDirectory)
        XCTAssertEqual(autoReview.status, 0)
        XCTAssertEqual(try autoReview.jsonValue("approved") as? Bool, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: reviewDecisionURL.path))

        let snapshotURL = workDirectory.appendingPathComponent("delete-snapshot.json")
        try writeJSON(makeDeleteSnapshotJSON(repositoryID: "memory-delete"), to: snapshotURL)
        let deletePatchURL = workDirectory.appendingPathComponent("delete.homelibpatch")
        try writeJSON(makeDeletePatchJSON(repositoryID: "memory-delete"), to: deletePatchURL)
        let applyResultURL = workDirectory.appendingPathComponent("apply-result.json")
        let applyWithoutReview = try runCLI([
            "apply-patch",
            deletePatchURL.path,
            "--remote", "memory",
            "--snapshot", snapshotURL.path,
            "--result", applyResultURL.path
        ], in: workDirectory)
        XCTAssertEqual(applyWithoutReview.status, 0)
        XCTAssertEqual(try applyWithoutReview.jsonValue("skippedCount") as? Int, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: applyResultURL.path))

        let liveResultURL = workDirectory.appendingPathComponent("memory-live-result.json")
        let memoryLive = try runCLI([
            "run-live-test",
            "--remote", "memory",
            "--result", liveResultURL.path
        ], in: workDirectory)
        XCTAssertEqual(memoryLive.status, 0)
        XCTAssertEqual(try memoryLive.jsonValue("ok") as? Bool, true)
        XCTAssertEqual(try memoryLive.jsonValue("cleanupOK") as? Bool, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveResultURL.path))

        let gatedLive = try runCLI(["run-live-test"], in: workDirectory)
        XCTAssertEqual(gatedLive.status, 2)
        XCTAssertTrue(gatedLive.stdout.contains("HOME_LIBRARY_CLOUDKIT_LIVE_TESTS=1"))
    }

    private func runCLI(_ arguments: [String], in workingDirectory: URL) throws -> CommandResult {
        let executableURL = packageRoot()
            .appendingPathComponent(".build/debug/home-library-cloudkit")
        XCTAssertTrue(FileManager.default.fileExists(atPath: executableURL.path), "Expected SwiftPM to build \(executableURL.path) before CLI command tests run.")

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = ProcessInfo.processInfo.environment.filter {
            $0.key != "HOME_LIBRARY_CLOUDKIT_LIVE_TESTS"
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return CommandResult(
            status: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("home-library-cli-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeJSON(_ value: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: [.atomic])
    }

    private func makeCreatePatchJSON(repositoryID: String, locationID: String) -> [String: Any] {
        [
            "schemaVersion": 1,
            "source": "cli-command-test",
            "createdAt": "2026-06-22T12:00:00.000Z",
            "targetRepository": [
                "id": repositoryID,
                "databaseScope": "private",
                "zoneID": repositoryID
            ],
            "baseSnapshot": [
                "id": "snapshot.cli",
                "createdAt": "2026-06-22T12:00:00.000Z"
            ],
            "operations": [
                [
                    "op": "createBook",
                    "clientOperationID": "op-create-invalid",
                    "confidence": 0.95,
                    "fields": [
                        "title": "Invalid Location Book",
                        "author": "Codex",
                        "publisher": "OpenAI",
                        "year": "2026",
                        "isbn": "9780131177055",
                        "locationID": locationID
                    ],
                    "evidence": [],
                    "warnings": []
                ]
            ],
            "notes": []
        ]
    }

    private func makeDeleteSnapshotJSON(repositoryID: String) -> [String: Any] {
        [
            "schemaVersion": 1,
            "snapshotID": "snapshot.delete",
            "createdAt": "2026-06-22T12:00:00.000Z",
            "repository": [
                "id": repositoryID,
                "name": "AIWorkflowTest-Delete",
                "role": "owner",
                "databaseScope": "private",
                "zoneName": repositoryID,
                "zoneOwnerName": "__defaultOwner__",
                "shareStatus": "notShared"
            ],
            "locations": [
                [
                    "id": "location.chengdu",
                    "name": "成都",
                    "sortOrder": 0,
                    "isVisible": true
                ]
            ],
            "books": [
                [
                    "id": "book-delete",
                    "title": "Delete Candidate",
                    "author": "Codex",
                    "translator": "",
                    "publisher": "OpenAI",
                    "year": "2026",
                    "isbn": "9780131177055",
                    "locationID": "location.chengdu",
                    "coverAssetID": NSNull(),
                    "hasCover": false,
                    "updatedAt": "2026-06-22T12:00:00.000Z",
                    "recordChangeTag": "tag-delete"
                ]
            ]
        ]
    }

    private func makeDeletePatchJSON(repositoryID: String) -> [String: Any] {
        [
            "schemaVersion": 1,
            "source": "cli-command-test",
            "createdAt": "2026-06-22T12:01:00.000Z",
            "targetRepository": [
                "id": repositoryID,
                "databaseScope": "private",
                "zoneID": repositoryID
            ],
            "operations": [
                [
                    "op": "deleteBook",
                    "clientOperationID": "op-delete-no-review",
                    "id": "book-delete",
                    "expectedUpdatedAt": "2026-06-22T12:00:00.000Z",
                    "expectedRecordChangeTag": "tag-delete",
                    "reason": "command test",
                    "evidence": [],
                    "warnings": []
                ]
            ],
            "notes": []
        ]
    }
}

private struct CommandResult {
    var status: Int32
    var stdout: String
    var stderr: String

    func jsonValue(_ key: String) throws -> Any? {
        try jsonObject()[key]
    }

    func jsonObject() throws -> [String: Any] {
        let data = Data(stdout.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }
}
