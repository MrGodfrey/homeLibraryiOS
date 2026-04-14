//
//  homeLibraryApp.swift
//  homeLibrary
//
//  Created by Codex on 2026/4/14.
//

import SwiftUI

@main
struct homeLibraryApp: App {
    @StateObject private var store = LibraryStore(configuration: .live())

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}
