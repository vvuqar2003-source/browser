import SwiftUI

struct DownloadsListView: View {
    @EnvironmentObject var downloadManager: DownloadManager
    @State private var shareURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        NavigationView {
            List {
                if !downloadManager.activeDownloads.isEmpty {
                    Section(header: Text("Aktif İndirmeler")) {
                        ForEach(downloadManager.activeDownloads) { task in
                            ActiveDownloadRow(task: task, downloadManager: downloadManager)
                        }
                    }
                }

                if !downloadManager.downloadHistory.isEmpty {
                    Section(header: Text("İndirme Geçmişi")) {
                        ForEach(downloadManager.downloadHistory) { record in
                            DownloadHistoryRow(record: record) { url in
                                shareURL = url
                                showShareSheet = true
                            }
                        }

                        Button(role: .destructive) {
                            downloadManager.clearHistory()
                        } label: {
                            Text("Tüm Geçmişi Temizle")
                        }
                    }
                }

                if downloadManager.activeDownloads.isEmpty && downloadManager.downloadHistory.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "arrow.down.to.line")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("Hiç indirme yok")
                                .foregroundColor(.secondary)
                            Text("Bir videoyu indirmek için tarayıcıya gidin\nve indirme butonuna basın.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    }
                }

                if let error = downloadManager.downloadError {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("İndirmeler")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showShareSheet) {
                if let url = shareURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Active Download Row

struct ActiveDownloadRow: View {
    let task: DownloadManager.DownloadTask
    let downloadManager: DownloadManager

    var progress: DownloadManager.DownloadProgress? {
        downloadManager.downloadProgress[task.id]
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.fileName)
                        .font(.body)
                        .lineLimit(1)
                    Text(task.isHLS ? "HLS Stream" : task.url.host ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    downloadManager.cancelDownload(id: task.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                }
            }

            // Progress bar
            ProgressView(value: progress?.fraction ?? task.progress)
                .tint(task.error != nil ? .red : .blue)

            // Stats row
            HStack {
                // Percentage
                Text("\(Int((progress?.fraction ?? task.progress) * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                // Downloaded / Total
                if let p = progress, p.totalBytesWritten > 0 {
                    Text("• \(p.downloadedText) / \(p.totalText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Speed
                if let p = progress, !p.speedText.isEmpty {
                    Text(p.speedText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
            }

            // Error
            if let error = task.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }

            // Status
            if task.error == nil {
                HStack {
                    Text(task.statusText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Download History Row

struct DownloadHistoryRow: View {
    let record: DownloadManager.DownloadRecord
    let onShare: (URL) -> Void

    var body: some View {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(record.fileName)
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)

        Button {
            if fileExists {
                onShare(fileURL)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        // Status icon
                        Image(systemName: record.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(record.success ? .green : .red)

                        Text(record.fileName)
                            .font(.body)
                            .lineLimit(1)
                            .foregroundColor(.primary)
                    }

                    HStack(spacing: 6) {
                        Text(record.date, style: .date)
                        Text(record.date, style: .time)

                        Text("•")

                        Text(record.fileSize)
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                if record.success && fileExists {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.blue)
                        .font(.body)
                } else if record.success && !fileExists {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
            }
        }
        .disabled(!fileExists || !record.success)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
