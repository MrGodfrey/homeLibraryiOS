//
//  homeLibraryApp.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import CloudKit
import Combine
import SwiftUI

@main
struct homeLibraryApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = LibraryStore(configuration: .live())
    @StateObject private var cloudShareDeliveryCenter = CloudShareDeliveryCenter.shared
    @State private var didStartAutomation = false

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .task(id: cloudShareDeliveryCenter.deliverySequence) {
                    await consumePendingCloudShares()
                }
                .task {
                    guard !didStartAutomation else {
                        return
                    }

                    didStartAutomation = true
                    await CloudKitDualSimulatorAutomation.runIfNeeded(store: store)
                }
        }
    }

    @MainActor
    private func consumePendingCloudShares() async {
        for metadata in cloudShareDeliveryCenter.drainPendingMetadata() {
            await store.acceptShareMetadata(metadata)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = CloudShareSceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        deliver(cloudKitShareMetadata)
    }

    private func deliver(_ metadata: CKShare.Metadata) {
        Task { @MainActor in
            CloudShareDeliveryCenter.shared.enqueue(metadata)
        }
    }
}

final class CloudShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else {
            return
        }

        deliver(metadata)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        deliver(cloudKitShareMetadata)
    }

    private func deliver(_ metadata: CKShare.Metadata) {
        Task { @MainActor in
            CloudShareDeliveryCenter.shared.enqueue(metadata)
        }
    }
}

@MainActor
final class CloudShareDeliveryCenter: ObservableObject {
    static let shared = CloudShareDeliveryCenter()

    @Published private(set) var deliverySequence = 0

    private var pendingMetadata: [CKShare.Metadata] = []
    private var pendingKeys: Set<String> = []

    private init() {}

    func enqueue(_ metadata: CKShare.Metadata) {
        let key = Self.makeKey(for: metadata)
        guard pendingKeys.insert(key).inserted else {
            return
        }

        pendingMetadata.append(metadata)
        deliverySequence &+= 1
    }

    func drainPendingMetadata() -> [CKShare.Metadata] {
        defer {
            pendingMetadata.removeAll()
            pendingKeys.removeAll()
        }
        return pendingMetadata
    }

    private nonisolated static func makeKey(for metadata: CKShare.Metadata) -> String {
        let recordID = metadata.share.recordID
        return "\(recordID.zoneID.ownerName):\(recordID.zoneID.zoneName):\(recordID.recordName)"
    }
}
