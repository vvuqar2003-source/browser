// BrowserApp/BrowserApp/App/ContentView.swift

import SwiftUI

struct ContentView: View {
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            BrowserView()
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gear")
                        }
                    }
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
