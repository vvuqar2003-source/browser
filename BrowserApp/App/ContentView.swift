import SwiftUI

struct ContentView: View {
    @StateObject private var tabManager = TabManager()

    var body: some View {
        TabView {
            BrowserContainerView(tabManager: tabManager)
                .tabItem {
                    Label("Tarayıcı", systemImage: "globe")
                }
                .tag(0)

            DownloadsListView()
                .tabItem {
                    Label("İndirmeler", systemImage: "arrow.down.to.line")
                }
                .tag(1)

            NavigationView {
                SettingsView()
                    .navigationTitle("Ayarlar")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("Ayarlar", systemImage: "gear")
            }
            .tag(2)
        }
        .tint(.blue)
    }
}
