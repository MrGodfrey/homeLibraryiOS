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
        if let metadata = options.cloudKitShareMetadata {
            deliver(metadata)
        }

        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
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

@MainActor
final class CloudShareDeliveryCenter: ObservableObject {
    static let shared = CloudShareDeliveryCenter()

    @Published private(set) var deliverySequence = 0

    private var pendingMetadata: [CKShare.Metadata] = []

    private init() {}

    func enqueue(_ metadata: CKShare.Metadata) {
        pendingMetadata.append(metadata)
        deliverySequence &+= 1
    }

    func drainPendingMetadata() -> [CKShare.Metadata] {
        defer { pendingMetadata.removeAll() }
        return pendingMetadata
    }
}
