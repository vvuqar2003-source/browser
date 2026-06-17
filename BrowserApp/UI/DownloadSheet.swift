import SwiftUI

struct DownloadSheet: View {
    let videos: [DetectedVideo]
    let subtitles: [DetectedSubtitle]
    let viewModel: BrowserViewModel
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

                if !videos.isEmpty || !subtitles.isEmpty {
                    Section {
                        Button(action: downloadAll) {
                            HStack {
                                Image(systemName: "arrow.down.to.line")
                                Text("Tümünü İndir (\(videos.count + subtitles.count))")
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

                if !videos.isEmpty {
                    Section(header: Text("Videolar (\(videos.count))")) {
                        ForEach(videos.prefix(5)) { video in
                            Button {
                                viewModel.downloadVideo(video, with: downloadManager)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(video.fileName)
                                        .font(.body)
                                        .lineLimit(1)
                                        .foregroundColor(.primary)

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

                                        Spacer()

                                        Image(systemName: "arrow.down.circle")
                                            .foregroundColor(.blue)
                                            .font(.caption)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("İndir") {
                                    viewModel.downloadVideo(video, with: downloadManager)
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
                            Button {
                                viewModel.downloadSubtitle(subtitle, with: downloadManager)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(subtitle.fileName)
                                        .font(.body)
                                        .lineLimit(1)
                                        .foregroundColor(.primary)

                                    HStack {
                                        Text(subtitle.format)
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        Spacer()

                                        Image(systemName: "arrow.down.circle")
                                            .foregroundColor(.blue)
                                            .font(.caption)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("İndir") {
                                    viewModel.downloadSubtitle(subtitle, with: downloadManager)
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

    private func downloadAll() {
        for video in videos {
            viewModel.downloadVideo(video, with: downloadManager)
        }
        for subtitle in subtitles {
            viewModel.downloadSubtitle(subtitle, with: downloadManager)
        }
        dismiss()
    }
}
