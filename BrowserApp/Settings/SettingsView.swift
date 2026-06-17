// BrowserApp/BrowserApp/Settings/SettingsView.swift

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var adBlocker: AdBlocker
    @EnvironmentObject var downloadManager: DownloadManager
    @AppStorage("backgroundDownload") private var backgroundDownload = false
    @State private var showClearHistoryAlert = false

    var body: some View {
        List {
            Section(header: Text("İndirme")) {
                Toggle("Arka Planda İndir", isOn: $backgroundDownload)
                    .tint(.blue)

                if backgroundDownload {
                    Text("Uygulama arka planda olsa bile indirmeler devam eder.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("Reklam Engelleyici")) {
                Toggle("Reklam Engelleyici", isOn: $adBlocker.isEnabled)
                    .tint(.green)

                HStack {
                    Text("Engellenen Reklam Sayısı")
                    Spacer()
                    Text("\(adBlocker.blockedCount)")
                        .foregroundColor(.secondary)
                }

                Button {
                    adBlocker.updateRules()
                } label: {
                    HStack {
                        Text("Filtre Listelerini Güncelle")
                        Spacer()
                        if adBlocker.isLoading {
                            ProgressView()
                        }
                    }
                }
                .disabled(adBlocker.isLoading)

                if let lastUpdate = adBlocker.lastUpdate {
                    Text("Son güncelleme: \(lastUpdate, style: .relative) önce")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("İndirme Geçmişi")) {
                if downloadManager.downloadHistory.isEmpty {
                    Text("İndirme geçmişi boş")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(downloadManager.downloadHistory) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.fileName)
                                .font(.body)
                            HStack {
                                Text(record.date, style: .date)
                                Text(record.date, style: .time)
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }

                Button(role: .destructive) {
                    showClearHistoryAlert = true
                } label: {
                    Text("Tüm İndirme Geçmişini Temizle")
                }
                .disabled(downloadManager.downloadHistory.isEmpty)
            }
        }
        .alert("İndirme Geçmişini Temizle", isPresented: $showClearHistoryAlert) {
            Button("İptal", role: .cancel) {}
            Button("Temizle", role: .destructive) {
                downloadManager.clearHistory()
            }
        } message: {
            Text("Tüm indirme geçmişi silinecek. Bu işlem geri alınamaz.")
        }
    }
}
