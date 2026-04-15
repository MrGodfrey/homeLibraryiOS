#!/usr/bin/env swift

import Darwin
import Foundation

struct ScriptError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

struct SimulatorList: Decodable {
    let devices: [String: [SimulatorDevice]]
}

struct SimulatorDevice: Decodable {
    let name: String
    let udid: String
    let state: String
    let isAvailable: Bool
}

struct AutomationResult: Decodable {
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
    let completedAt: String?
}

struct StageDescriptor {
    let command: String
    let resultFile: String
    let timeout: TimeInterval
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

let scriptURL = URL(fileURLWithPath: #filePath)
let repoRootURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let repoRootPath = repoRootURL.path
let projectPath = repoRootURL.appendingPathComponent("homeLibrary.xcodeproj").path
let derivedDataPath = repoRootURL.appendingPathComponent(".derived/dual-sim-cloudkit").path
let appPath = URL(fileURLWithPath: derivedDataPath)
    .appendingPathComponent("Build/Products/Debug-iphonesimulator/homeLibrary.app").path
let bundleID = "yu.homeLibrary"

let environment = ProcessInfo.processInfo.environment
let ownerSimulatorName = environment["HOME_LIBRARY_DUAL_SIM_OWNER_NAME"] ?? "iPhone 17"
let memberSimulatorName = environment["HOME_LIBRARY_DUAL_SIM_MEMBER_NAME"] ?? "testPhone2"

let runID = ISO8601DateFormatter.compactRunID.string(from: Date()) + "-" + UUID().uuidString.prefix(6)
let repositoryName = "Dual Sim \(runID)"
let initialTitle = "双机创建 \(runID)"
let updatedTitle = "双机更新 \(runID)"
let ownerNamespace = "dual-sim-owner-\(runID)"
let memberNamespace = "dual-sim-member-\(runID)"

let ownerPrepareStage = StageDescriptor(command: "owner-prepare", resultFile: "owner-prepare-\(runID).json", timeout: 90)
let memberJoinStage = StageDescriptor(command: "member-join-create-update", resultFile: "member-join-\(runID).json", timeout: 150)
let ownerVerifyUpdateStage = StageDescriptor(command: "owner-verify-update", resultFile: "owner-verify-update-\(runID).json", timeout: 120)
let memberDeleteStage = StageDescriptor(command: "member-delete", resultFile: "member-delete-\(runID).json", timeout: 90)
let ownerVerifyDeleteStage = StageDescriptor(command: "owner-verify-delete", resultFile: "owner-verify-delete-\(runID).json", timeout: 120)
let ownerCleanupStage = StageDescriptor(command: "owner-cleanup", resultFile: "owner-cleanup-\(runID).json", timeout: 120)
let memberCleanupStage = StageDescriptor(command: "member-verify-cleanup", resultFile: "member-cleanup-\(runID).json", timeout: 150)

let stageFiles = [
    ownerPrepareStage.resultFile,
    memberJoinStage.resultFile,
    ownerVerifyUpdateStage.resultFile,
    memberDeleteStage.resultFile,
    ownerVerifyDeleteStage.resultFile,
    ownerCleanupStage.resultFile,
    memberCleanupStage.resultFile
]

func runCommand(
    _ executable: String,
    _ arguments: [String],
    environment overrides: [String: String] = [:],
    currentDirectory: URL? = nil
) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory

    var mergedEnvironment = ProcessInfo.processInfo.environment
    overrides.forEach { key, value in
        mergedEnvironment[key] = value
    }
    process.environment = mergedEnvironment

    let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("dual-sim-command-\(UUID().uuidString).log")
    FileManager.default.createFile(atPath: logURL.path, contents: nil)
    let logHandle = try FileHandle(forWritingTo: logURL)
    process.standardOutput = logHandle
    process.standardError = logHandle

    try process.run()
    process.waitUntilExit()
    try? logHandle.close()

    let combined = ((try? String(contentsOf: logURL, encoding: .utf8)) ?? "").trimmed
    try? FileManager.default.removeItem(at: logURL)

    guard process.terminationStatus == 0 else {
        throw ScriptError(message: combined.isEmpty ? "\(executable) 执行失败。" : combined)
    }

    return combined
}

func printStage(_ title: String) {
    print("[dual-sim] \(title)")
    fflush(stdout)
}

func loadBootedSimulator(named name: String) throws -> SimulatorDevice {
    let output = try runCommand("/usr/bin/xcrun", ["simctl", "list", "devices", "--json"])
    let data = Data(output.utf8)
    let simulators = try JSONDecoder().decode(SimulatorList.self, from: data)

    guard let simulator = simulators.devices.values
        .flatMap({ $0 })
        .first(where: { $0.name == name && $0.isAvailable && $0.state == "Booted" }) else {
        throw ScriptError(message: "没有找到 booted 模拟器 `\(name)`。请确认它已经启动并登录对应的 iCloud 账号。")
    }

    return simulator
}

func buildApp() throws {
    printStage("构建 Debug 模拟器包")
    _ = try runCommand(
        "/usr/bin/xcodebuild",
        [
            "-project", projectPath,
            "-scheme", "homeLibrary",
            "-configuration", "Debug",
            "-destination", "generic/platform=iOS Simulator",
            "-derivedDataPath", derivedDataPath,
            "-quiet",
            "build"
        ],
        currentDirectory: repoRootURL
    )

    guard FileManager.default.fileExists(atPath: appPath) else {
        throw ScriptError(message: "没有找到构建产物：\(appPath)")
    }
}

func installApp(on simulator: SimulatorDevice) throws {
    printStage("安装到 \(simulator.name)")
    _ = try runCommand("/usr/bin/xcrun", ["simctl", "install", simulator.udid, appPath])
}

func appDataContainer(for simulator: SimulatorDevice) throws -> URL {
    let output = try runCommand("/usr/bin/xcrun", ["simctl", "get_app_container", simulator.udid, bundleID, "data"])
    return URL(fileURLWithPath: output.trimmed, isDirectory: true)
}

func terminateApp(on simulator: SimulatorDevice) {
    _ = try? runCommand("/usr/bin/xcrun", ["simctl", "terminate", simulator.udid, bundleID])
}

func removeItemIfExists(_ url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else {
        return
    }

    try? FileManager.default.removeItem(at: url)
}

func automationEnvironment(
    namespace: String,
    stage: StageDescriptor,
    extras: [String: String]
) -> [String: String] {
    var values = [
        "HOME_LIBRARY_REMOTE_DRIVER": "cloudkit",
        "HOME_LIBRARY_CLOUDKIT_LIVE_TESTS": "1",
        "HOME_LIBRARY_DEBUG_CLOUDKIT": "1",
        "HOME_LIBRARY_CLOUDKIT_AUTOMATION_ALLOW_PUBLIC_SHARE": "1",
        "HOME_LIBRARY_STORAGE_NAMESPACE": namespace,
        "HOME_LIBRARY_SESSION_NAMESPACE": namespace,
        "HOME_LIBRARY_CLOUDKIT_AUTOMATION_COMMAND": stage.command,
        "HOME_LIBRARY_CLOUDKIT_AUTOMATION_RESULT_FILE": stage.resultFile
    ]

    extras.forEach { key, value in
        values[key] = value
    }

    return values
}

func launchAutomation(
    on simulator: SimulatorDevice,
    dataContainer: URL,
    stage: StageDescriptor,
    childEnvironment: [String: String]
) throws -> AutomationResult {
    let resultURL = dataContainer.appendingPathComponent("Documents/\(stage.resultFile)")
    try? FileManager.default.createDirectory(at: resultURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    removeItemIfExists(resultURL)
    terminateApp(on: simulator)

    var prefixedEnvironment: [String: String] = [:]
    childEnvironment.forEach { key, value in
        prefixedEnvironment["SIMCTL_CHILD_\(key)"] = value
    }

    printStage("在 \(simulator.name) 执行 \(stage.command)")
    _ = try runCommand(
        "/usr/bin/xcrun",
        ["simctl", "launch", "--terminate-running-process", simulator.udid, bundleID],
        environment: prefixedEnvironment
    )

    let result = try waitForResult(at: resultURL, timeout: stage.timeout)
    terminateApp(on: simulator)

    guard result.success else {
        throw ScriptError(message: "\(simulator.name) 的 \(stage.command) 失败：\(result.message)")
    }

    return result
}

func waitForResult(at url: URL, timeout: TimeInterval) throws -> AutomationResult {
    let deadline = Date().addingTimeInterval(timeout)
    let decoder = JSONDecoder()

    while Date() < deadline {
        if let data = try? Data(contentsOf: url),
           let result = try? decoder.decode(AutomationResult.self, from: data) {
            return result
        }

        Thread.sleep(forTimeInterval: 1)
    }

    throw ScriptError(message: "等待 automation 结果超时：\(url.path)")
}

func cleanupLocalNamespace(dataContainer: URL, namespace: String, resultFiles: [String]) {
    let baseDirectory = dataContainer.appendingPathComponent("Library/Application Support/homeLibrary/\(namespace)")
    removeItemIfExists(baseDirectory)

    let documentsDirectory = dataContainer.appendingPathComponent("Documents", isDirectory: true)
    resultFiles.forEach { filename in
        removeItemIfExists(documentsDirectory.appendingPathComponent(filename))
    }
}

func require<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
        throw ScriptError(message: message)
    }

    return value
}

var ownerDataContainer: URL?
var memberDataContainer: URL?
var ownerZoneName: String?
var memberBookID: String?

do {
    let ownerSimulator = try loadBootedSimulator(named: ownerSimulatorName)
    let memberSimulator = try loadBootedSimulator(named: memberSimulatorName)

    try buildApp()
    try installApp(on: ownerSimulator)
    try installApp(on: memberSimulator)

    let resolvedOwnerContainer = try appDataContainer(for: ownerSimulator)
    let resolvedMemberContainer = try appDataContainer(for: memberSimulator)
    ownerDataContainer = resolvedOwnerContainer
    memberDataContainer = resolvedMemberContainer

    let ownerPrepare = try launchAutomation(
        on: ownerSimulator,
        dataContainer: resolvedOwnerContainer,
        stage: ownerPrepareStage,
        childEnvironment: automationEnvironment(
            namespace: ownerNamespace,
            stage: ownerPrepareStage,
            extras: [
                "HOME_LIBRARY_PREFERRED_REPOSITORY_NAME": repositoryName,
                "HOME_LIBRARY_CLOUDKIT_AUTOMATION_REPOSITORY_NAME": repositoryName
            ]
        )
    )

    let shareURL = try require(ownerPrepare.shareURL, "owner 没有返回 share URL。")
    let zoneName = try require(ownerPrepare.zoneName, "owner 没有返回 zoneName。")
    ownerZoneName = zoneName

    let memberJoin = try launchAutomation(
        on: memberSimulator,
        dataContainer: resolvedMemberContainer,
        stage: memberJoinStage,
        childEnvironment: automationEnvironment(
            namespace: memberNamespace,
            stage: memberJoinStage,
            extras: [
                "HOME_LIBRARY_CLOUDKIT_AUTOMATION_REPOSITORY_NAME": repositoryName,
                "HOME_LIBRARY_CLOUDKIT_AUTOMATION_ZONE_NAME": zoneName,
                "HOME_LIBRARY_CLOUDKIT_AUTOMATION_SHARE_URL": shareURL,
                "HOME_LIBRARY_CLOUDKIT_AUTOMATION_INITIAL_TITLE": initialTitle,
                "HOME_LIBRARY_CLOUDKIT_AUTOMATION_UPDATED_TITLE": updatedTitle
            ]
        )
    )

    let bookID = try require(memberJoin.bookID, "member 没有返回 bookID。")
    memberBookID = bookID

    _ = try launchAutomation(
        on: ownerSimulator,
        dataContainer: resolvedOwnerContainer,
        stage: ownerVerifyUpdateStage,
        childEnvironment: automationEnvironment(
            namespace: ownerNamespace,
            stage: ownerVerifyUpdateStage,
            extras: [
                "HOME_LIBRARY_PREFERRED_REPOSITORY_NAME": repositoryName,
                "HOME_LIBRARY_CLOUDKIT_AUTOMATION_REPOSITORY_NAME": repositoryName,
                "HOME_LIBRARY_CLOUDKIT_AUTOMATION_ZONE_NAME": zoneName,
                "HOME_LIBRARY_CLOUDKIT_AUTOMATION_UPDATED_TITLE": updatedTitle,
                "HOME_LIBRARY_CLOUDKIT_AUTOMATION_BOOK_ID": bookID
            ]
        )
    )

    _ = try launchAutomation(
        on: memberSimulator,
        dataContainer: resolvedMemberContainer,
        stage: memberDeleteStage,
        childEnvironment: automationEnvironment(
            namespace: memberNamespace,
            stage: memberDeleteStage,
            extras: [
                "HOME_LIBRARY_CLOUDKIT_AUTOMATION_REPOSITORY_NAME": repositoryName,
                "HOME_LIBRARY_CLOUDKIT_AUTOMATION_ZONE_NAME": zoneName,
                "HOME_LIBRARY_CLOUDKIT_AUTOMATION_BOOK_ID": bookID
            ]
        )
    )

    _ = try launchAutomation(
        on: ownerSimulator,
        dataContainer: resolvedOwnerContainer,
        stage: ownerVerifyDeleteStage,
        childEnvironment: automationEnvironment(
            namespace: ownerNamespace,
            stage: ownerVerifyDeleteStage,
            extras: [
                "HOME_LIBRARY_PREFERRED_REPOSITORY_NAME": repositoryName,
                "HOME_LIBRARY_CLOUDKIT_AUTOMATION_REPOSITORY_NAME": repositoryName,
                "HOME_LIBRARY_CLOUDKIT_AUTOMATION_ZONE_NAME": zoneName,
                "HOME_LIBRARY_CLOUDKIT_AUTOMATION_BOOK_ID": bookID
            ]
        )
    )

    _ = try launchAutomation(
        on: ownerSimulator,
        dataContainer: resolvedOwnerContainer,
        stage: ownerCleanupStage,
        childEnvironment: automationEnvironment(
            namespace: ownerNamespace,
            stage: ownerCleanupStage,
            extras: [
                "HOME_LIBRARY_PREFERRED_REPOSITORY_NAME": repositoryName,
                "HOME_LIBRARY_CLOUDKIT_AUTOMATION_REPOSITORY_NAME": repositoryName,
                "HOME_LIBRARY_CLOUDKIT_AUTOMATION_ZONE_NAME": zoneName,
                "HOME_LIBRARY_CLOUDKIT_AUTOMATION_BOOK_ID": bookID
            ]
        )
    )

    _ = try launchAutomation(
        on: memberSimulator,
        dataContainer: resolvedMemberContainer,
        stage: memberCleanupStage,
        childEnvironment: automationEnvironment(
            namespace: memberNamespace,
            stage: memberCleanupStage,
            extras: [
                "HOME_LIBRARY_CLOUDKIT_AUTOMATION_REPOSITORY_NAME": repositoryName,
                "HOME_LIBRARY_CLOUDKIT_AUTOMATION_ZONE_NAME": zoneName,
                "HOME_LIBRARY_CLOUDKIT_AUTOMATION_BOOK_ID": bookID
            ]
        )
    )

    cleanupLocalNamespace(dataContainer: resolvedOwnerContainer, namespace: ownerNamespace, resultFiles: stageFiles)
    cleanupLocalNamespace(dataContainer: resolvedMemberContainer, namespace: memberNamespace, resultFiles: stageFiles)

    print("[dual-sim] 完成：\(ownerSimulator.name) 创建并共享仓库，\(memberSimulator.name) 接受共享后通过新增/读取/修改/删除验证，最终 owner 删除测试仓库且 member 侧确认共享已消失。")
    exit(0)
} catch {
    if let ownerSimulator = try? loadBootedSimulator(named: ownerSimulatorName),
       let resolvedOwnerContainer = ownerDataContainer,
       let zoneName = ownerZoneName {
        _ = try? launchAutomation(
            on: ownerSimulator,
            dataContainer: resolvedOwnerContainer,
            stage: ownerCleanupStage,
            childEnvironment: automationEnvironment(
                namespace: ownerNamespace,
                stage: ownerCleanupStage,
                extras: [
                    "HOME_LIBRARY_PREFERRED_REPOSITORY_NAME": repositoryName,
                    "HOME_LIBRARY_CLOUDKIT_AUTOMATION_REPOSITORY_NAME": repositoryName,
                    "HOME_LIBRARY_CLOUDKIT_AUTOMATION_ZONE_NAME": zoneName,
                    "HOME_LIBRARY_CLOUDKIT_AUTOMATION_BOOK_ID": memberBookID ?? ""
                ]
            )
        )
    }

    if let memberSimulator = try? loadBootedSimulator(named: memberSimulatorName),
       let resolvedMemberContainer = memberDataContainer,
       let zoneName = ownerZoneName {
        _ = try? launchAutomation(
            on: memberSimulator,
            dataContainer: resolvedMemberContainer,
            stage: memberCleanupStage,
            childEnvironment: automationEnvironment(
                namespace: memberNamespace,
                stage: memberCleanupStage,
                extras: [
                    "HOME_LIBRARY_CLOUDKIT_AUTOMATION_REPOSITORY_NAME": repositoryName,
                    "HOME_LIBRARY_CLOUDKIT_AUTOMATION_ZONE_NAME": zoneName,
                    "HOME_LIBRARY_CLOUDKIT_AUTOMATION_BOOK_ID": memberBookID ?? ""
                ]
            )
        )
    }

    if let resolvedOwnerContainer = ownerDataContainer {
        cleanupLocalNamespace(dataContainer: resolvedOwnerContainer, namespace: ownerNamespace, resultFiles: stageFiles)
    }

    if let resolvedMemberContainer = memberDataContainer {
        cleanupLocalNamespace(dataContainer: resolvedMemberContainer, namespace: memberNamespace, resultFiles: stageFiles)
    }

    let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    fputs("[dual-sim] 失败：\(message)\n", stderr)
    exit(1)
}

extension ISO8601DateFormatter {
    static let compactRunID: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
