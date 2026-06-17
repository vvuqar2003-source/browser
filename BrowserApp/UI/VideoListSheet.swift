// BrowserApp/BrowserApp/UI/VideoListSheet.swift

import SwiftUI

struct VideoListSheet: View {
    let videos: [DetectedVideo]
    let downloadManager: DownloadManager

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List(videos) { video in
                VStack(alignment: .leading, spacing: 6) {
                    Text(video.fileName)
                        .font(.body)
                        .lineLimit(2)

                    HStack(spacing: 8) {
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

                        Spacer()

                        Text(video.timestamp, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(video.url.absoluteString)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
                .swipeActions(edge: .trailing) {
                    Button("İndir") {
                        downloadManager.download(url: video.url, fileName: video.fileName)
                    }
                    .tint(.blue)
                }
            }
            .navigationTitle("Tüm Videolar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        let urls = videos.map { $0.url.absoluteString }.joined(separator: "\n")
                        UIPasteboard.general.string = urls
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Kapat") {
                        dismiss()
                    }
                }
            }
        }
    }
}
