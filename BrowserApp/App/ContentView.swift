import SwiftUI

struct ContentView: View {
    @State private var showSettings = false
    @State private var showDownloads = false

    var body: some View {
        NavigationView {
            BrowserView()
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button {
                            showDownloads = true
                        } label: {
                            Image(systemName: "arrow.down.to.line")
                        }

                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gear")
                        }
                    }
                }
                .sheet(isPresented: $showDownloads) {
                    DownloadsListView()
                }
                .sheet(isPresented: $showSettings) {
                    NavigationView {
                        SettingsView()
                            .navigationTitle("Ayarlar")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button("Kapat") {
                                        showSettings = false
                                    }
                                }
                            }
                    }
                }
        }
        .navigationViewStyle(.stack)
    }
}
