// BrowserApp/BrowserApp/Browser/BrowserView.swift

import SwiftUI
import WebKit

struct BrowserView: View {
    @StateObject private var viewModel = BrowserViewModel()
    @EnvironmentObject var adBlocker: AdBlocker
    @EnvironmentObject var downloadManager: DownloadManager

    var body: some View {
        VStack(spacing: 0) {
            AddressBarView(
                urlString: $viewModel.urlString,
                onSubmit: { viewModel.loadURL() }
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            if viewModel.isLoading {
                ProgressView(value: viewModel.estimatedProgress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .frame(height: 2)
            }

            ZStack {
                WebViewContainer(viewModel: viewModel, adBlocker: adBlocker)
                    .ignoresSafeArea(.container, edges: .bottom)

                if viewModel.showVideoOverlay {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            VideoOverlayButton(
                                videoCount: viewModel.detectedVideos.count,
                                onTap: {
                                    viewModel.showDownloadSheet = true
                                },
                                onLongPress: {
                                    viewModel.showDownloadSheet = true
                                }
                            )
                            .padding(.trailing, 16)
                            .padding(.bottom, 16)
                        }
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $viewModel.showDownloadSheet) {
            DownloadSheet(
                videos: viewModel.detectedVideos,
                subtitles: viewModel.detectedSubtitles,
                downloadManager: downloadManager,
                onShowAllVideos: {
                    viewModel.showDownloadSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        viewModel.showVideoListSheet = true
                    }
                },
                onShowAllSubtitles: {
                    viewModel.showDownloadSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        viewModel.showSubtitleListSheet = true
                    }
                }
            )
        }
        .sheet(isPresented: $viewModel.showVideoListSheet) {
            VideoListSheet(
                videos: viewModel.detectedVideos,
                downloadManager: downloadManager
            )
        }
        .sheet(isPresented: $viewModel.showSubtitleListSheet) {
            NavigationView {
                List(viewModel.detectedSubtitles) { subtitle in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(subtitle.fileName)
                            .font(.body)
                        Text(subtitle.format)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Indir") {
                            downloadManager.download(url: subtitle.url, fileName: subtitle.fileName)
                        }
                        .tint(.blue)
                    }
                }
                .navigationTitle("Altyazilar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Kapat") {
                            viewModel.showSubtitleListSheet = false
                        }
                    }
                }
            }
        }
    }
}

struct WebViewContainer: UIViewRepresentable {
    @ObservedObject var viewModel: BrowserViewModel
    let adBlocker: AdBlocker

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let contentController = config.userContentController
        contentController.add(viewModel, name: "videoFound")

        if let jsURL = Bundle.main.url(forResource: "inject", withExtension: "js"),
           let jsSource = try? String(contentsOf: jsURL, encoding: .utf8) {
            let userScript = WKUserScript(source: jsSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
            contentController.addUserScript(userScript)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = viewModel
        webView.uiDelegate = viewModel
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .interactive

        context.coordinator.webView = webView
        webView.addObserver(context.coordinator, forKeyPath: "estimatedProgress", options: .new, context: nil)

        viewModel.setWebView(webView)
        adBlocker.applyRules(to: webView)

        if let url = URL(string: viewModel.homepageURL) {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.removeObserver(coordinator, forKeyPath: "estimatedProgress")
    }

    class Coordinator: NSObject {
        let viewModel: BrowserViewModel
        weak var webView: WKWebView?

        init(viewModel: BrowserViewModel) {
            self.viewModel = viewModel
        }

        override func observeValue(
            forKeyPath keyPath: String?,
            of object: Any?,
            change: [NSKeyValueChangeKey: Any]?,
            context: UnsafeMutableRawPointer?
        ) {
            if keyPath == "estimatedProgress",
               let webView = object as? WKWebView {
                DispatchQueue.main.async {
                    self.viewModel.estimatedProgress = webView.estimatedProgress
                }
            }
        }
    }
}
