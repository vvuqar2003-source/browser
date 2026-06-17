// BrowserApp/BrowserApp/App/BrowserAppApp.swift

import SwiftUI

@main
struct BrowserAppApp: App {
    @StateObject private var downloadManager = DownloadManager()
    @StateObject private var adBlocker = AdBlocker()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(downloadManager)
                .environmentObject(adBlocker)
                .onAppear {
                    adBlocker.loadRules()
                }
        }
    }
}
