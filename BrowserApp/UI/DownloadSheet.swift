// BrowserApp/BrowserApp/UI/DownloadSheet.swift

import SwiftUI

struct DownloadSheet: View {
    let videos: [DetectedVideo]
    let subtitles: [DetectedSubtitle]
    let downloadManager: DownloadManager
    let onShowAllVideos: () -> Void
    let onShowAllSubtitles: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if videos.isEmpty && subtitles.isEmpty {
                    Section {
                        Text("Bu sayfada video veya altyazı bulunamadı.")
                            .foregroundColor(.secondary)
                    }
                }

                if !videos.isEmpty {
                    Section(header: Text("Videolar (\(videos.count))")) {
                        ForEach(videos.prefix(5)) { video in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(video.fileName)
                                    .font(.body)
                                    .lineLimit(1)

                                HStack {
                                    Text(video.format)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.2))
                                        .cornerRadius(4)

                                    if let size = video.estimatedSize {
                                        Text(size)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("İndir") {
                                    downloadManager.download(url: video.url, fileName: video.fileName)
                                    dismiss()
                                }
                                .tint(.blue)
                            }
                        }

                        if videos.count > 5 {
                            Button {
                                onShowAllVideos()
                            } label: {
                                HStack {
                                    Text("Sayfadaki Tüm Videoları Göster")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                            }
                        }
                    }
                }

                if !subtitles.isEmpty {
                    Section(header: Text("Altyazılar (\(subtitles.count))")) {
                        ForEach(subtitles.prefix(3)) { subtitle in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(subtitle.fileName)
                                    .font(.body)
                                    .lineLimit(1)

                                Text(subtitle.format)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("İndir") {
                                    downloadManager.download(url: subtitle.url, fileName: subtitle.fileName)
                                    dismiss()
                                }
                                .tint(.blue)
                            }
                        }

                        if subtitles.count > 3 {
                            Button {
                                onShowAllSubtitles()
                            } label: {
                                HStack {
                                    Text("Sayfadaki Tüm Altyazıları Göster")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("İndirme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Kapat") {
                        dismiss()
                    }
                }
            }
        }
    }
}
