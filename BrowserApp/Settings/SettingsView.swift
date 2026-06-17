import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var adBlocker: AdBlocker
    @EnvironmentObject var downloadManager: DownloadManager
    @AppStorage("backgroundDownload") private var backgroundDownload = false
    @AppStorage("maxConcurrentDownloads") private var maxConcurrentDownloads = 3
    @State private var showClearHistoryAlert = false
    @State private var showClearCacheAlert = false
    @State private var showResetAlert = false

    var body: some View {
        List {
            downloadSection
            storageSection
            adBlockSection
            historySection
            aboutSection
        }
        .alert("İndirme Geçmişini Temizle", isPresented: $showClearHistoryAlert) {
            Button("İptal", role: .cancel) {}
            Button("Temizle", role: .destructive) {
                downloadManager.clearHistory()
            }
        } message: {
            Text("Tüm indirme geçmişi silinecek. Bu işlem geri alınamaz.")
        }
        .alert("Önbelleği Temizle", isPresented: $showClearCacheAlert) {
            Button("İptal", role: .cancel) {}
            Button("Temizle", role: .destructive) {
                downloadManager.clearCache()
            }
        } message: {
            Text("Geçici indirme dosyaları temizlenecek.")
        }
        .alert("Ayarları Sıfırla", isPresented: $showResetAlert) {
            Button("İptal", role: .cancel) {}
            Button("Sıfırla", role: .destructive) {
                resetSettings()
            }
        } message: {
            Text("Tüm ayarlar varsayılan değerlerine dönecek.")
        }
    }

    private var downloadSection: some View {
        Section(header: Text("İndirme")) {
            Toggle("Arka Planda İndir", isOn: $backgroundDownload)
                .tint(.blue)

            if backgroundDownload {
                Text("Uygulama arka planda olsa bile indirmeler devam eder.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Toggle("Hücresel Veri ile İndir", isOn: Binding(
                get: { downloadManager.cellularDownloadEnabled },
                set: { downloadManager.updateCellularAccess($0) }
            ))
            .tint(.blue)

            Toggle("Videoları Otomatik İndir", isOn: $downloadManager.autoDownloadVideos)
                .tint(.blue)

            Toggle("Fotoğraflara Kaydet", isOn: $downloadManager.saveToPhotos)
                .tint(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text("Maksimum Eş Zamanlı İndirme: \(maxConcurrentDownloads)")
                    .font(.subheadline)
                Stepper("", value: $maxConcurrentDownloads, in: 1...5)
                    .labelsHidden()
            }
        }
    }

    private var storageSection: some View {
        Section(header: Text("Depolama")) {
            HStack {
                Text("İndirilen Dosyalar")
                Spacer()
                Text(downloadedFilesSize())
                    .foregroundColor(.secondary)
            }

            Button(role: .destructive) {
                showClearCacheAlert = true
            } label: {
                HStack {
                    Text("Önbelleği Temizle")
                    Spacer()
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
        }
    }

    private var adBlockSection: some View {
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
    }

    private var historySection: some View {
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

    private var aboutSection: some View {
        Section(header: Text("Hakkında")) {
            HStack {
                Text("Uygulama Adı")
                Spacer()
                Text("BrowserApp")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Sürüm")
                Spacer()
                Text("1.0")
                    .foregroundColor(.secondary)
            }

            Button(role: .destructive) {
                showResetAlert = true
            } label: {
                HStack {
                    Text("Ayarları Sıfırla")
                    Spacer()
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundColor(.red)
                }
            }
        }
    }

    private func downloadedFilesSize() -> String {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: documentsPath,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return "0 MB" }

        let totalSize = files.reduce(0) { sum, file in
            let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
            return sum + (attrs?[.size] as? Int64 ?? 0)
        }

        let mb = Double(totalSize) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }

    private func resetSettings() {
        backgroundDownload = false
        maxConcurrentDownloads = 3
        downloadManager.updateCellularAccess(true)
        downloadManager.autoDownloadVideos = false
        downloadManager.saveToPhotos = false
        adBlocker.isEnabled = false
    }
}
