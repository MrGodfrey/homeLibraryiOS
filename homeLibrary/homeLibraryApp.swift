//
//  homeLibraryApp.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import CloudKit
import SwiftUI

@main
struct homeLibraryApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = LibraryStore(configuration: .live())
    @State private var didStartAutomation = false

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .onReceive(NotificationCenter.default.publisher(for: AppDelegate.didAcceptCloudShare)) { notification in
                    guard let metadata = notification.object as? CKShare.Metadata else {
                        return
                    }

                    Task {
                        await store.acceptShareMetadata(metadata)
                    }
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
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    static let didAcceptCloudShare = Notification.Name("homeLibrary.didAcceptCloudShare")

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        NotificationCenter.default.post(name: Self.didAcceptCloudShare, object: cloudKitShareMetadata)
    }
}
