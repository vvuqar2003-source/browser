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
                            VStack(spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(task.fileName)
                                            .font(.body)
                                            .lineLimit(1)
                                        Text(task.isHLS ? "HLS" : task.url.lastPathComponent)
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

                                ProgressView(value: downloadManager.downloadProgress[task.id] ?? 0)
                                    .tint(.blue)

                                HStack {
                                    Text("\(Int((downloadManager.downloadProgress[task.id] ?? 0) * 100))%")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    if let error = task.error {
                                        Text(error)
                                            .font(.caption)
                                            .foregroundColor(.red)
                                            .lineLimit(1)
                                    } else {
                                        Text(task.isHLS ? "Birleştiriliyor..." : "İndiriliyor")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if !downloadManager.downloadHistory.isEmpty {
                    Section(header: Text("İndirme Geçmişi")) {
                        ForEach(downloadManager.downloadHistory) { record in
                            Button {
                                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                                let fileURL = documentsPath.appendingPathComponent(record.fileName)
                                if FileManager.default.fileExists(atPath: fileURL.path) {
                                    shareURL = fileURL
                                    showShareSheet = true
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.fileName)
                                            .font(.body)
                                            .lineLimit(1)
                                            .foregroundColor(.primary)
                                        HStack {
                                            Text(record.date, style: .date)
                                            Text(record.date, style: .time)
                                            if !record.fileSize.isEmpty {
                                                Text("• \(record.fileSize)")
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                                    let fileURL = documentsPath.appendingPathComponent(record.fileName)
                                    if FileManager.default.fileExists(atPath: fileURL.path) {
                                        Image(systemName: "square.and.arrow.up")
                                            .foregroundColor(.blue)
                                            .font(.caption)
                                    } else {
                                        Image(systemName: "exclamationmark.triangle")
                                            .foregroundColor(.orange)
                                            .font(.caption)
                                    }
                                }
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

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
