import SwiftUI
import WebKit

// MARK: - Browser Container (manages tabs)

struct BrowserContainerView: View {
    @ObservedObject var tabManager: TabManager
    @EnvironmentObject var adBlocker: AdBlocker
    @EnvironmentObject var downloadManager: DownloadManager

    var body: some View {
        ZStack {
            // Render active tab's browser
            if let tab = tabManager.activeTab {
                SingleBrowserView(viewModel: tab.viewModel, tabManager: tabManager)
                    .id(tab.id)
            }

            // Tab grid overlay
            if tabManager.showTabGrid {
                TabGridView(tabManager: tabManager)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: tabManager.showTabGrid)
    }
}

// MARK: - Single Browser View

struct SingleBrowserView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var tabManager: TabManager
    @EnvironmentObject var adBlocker: AdBlocker
    @EnvironmentObject var downloadManager: DownloadManager

    var body: some View {
        VStack(spacing: 0) {
            // Address bar
            AddressBarView(
                urlString: $viewModel.urlString,
                onSubmit: { viewModel.loadURL() }
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            // Progress bar
            if viewModel.isLoading {
                ProgressView(value: viewModel.estimatedProgress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .frame(height: 2)
            }

            // Web content
            ZStack {
                WebViewContainer(viewModel: viewModel, adBlocker: adBlocker)
                    .ignoresSafeArea(.container, edges: .bottom)

                // Video overlay button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        if viewModel.detectedCount > 0 {
                            VideoOverlayButton(
                                videoCount: viewModel.detectedCount,
                                onTap: {
                                    viewModel.scanAndShowDownloadSheet()
                                }
                            )
                            .padding(.trailing, 16)
                            .padding(.bottom, 60)
                        }
                    }
                }
            }

            // Bottom toolbar
            BottomToolbar(viewModel: viewModel, tabManager: tabManager)
        }
        .sheet(isPresented: $viewModel.showDownloadSheet) {
            DownloadSheet(
                videos: viewModel.detectedVideos,
                subtitles: viewModel.detectedSubtitles,
                viewModel: viewModel,
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
                viewModel: viewModel,
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
                            viewModel.downloadSubtitle(subtitle, with: downloadManager)
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

// MARK: - Bottom Toolbar

struct BottomToolbar: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var tabManager: TabManager

    var body: some View {
        HStack {
            Button { viewModel.goBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
            }
            .disabled(!viewModel.canGoBack)

            Spacer()

            Button { viewModel.goForward() } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
            }
            .disabled(!viewModel.canGoForward)

            Spacer()

            Button { viewModel.reload() } label: {
                Image(systemName: viewModel.isLoading ? "xmark" : "arrow.clockwise")
                    .font(.title3)
            }

            Spacer()

            // Tab count button
            Button {
                withAnimation {
                    tabManager.showTabGrid.toggle()
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary, lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                    Text("\(tabManager.tabs.count)")
                        .font(.caption)
                        .fontWeight(.bold)
                }
            }

            Spacer()

            Menu {
                Button {
                    tabManager.addNewTab()
                } label: {
                    Label("Yeni Sekme", systemImage: "plus")
                }
                Button {
                    viewModel.goHome()
                } label: {
                    Label("Ana Sayfa", systemImage: "house")
                }
                Button {
                    if let url = URL(string: viewModel.urlString) {
                        UIPasteboard.general.url = url
                    }
                } label: {
                    Label("URL Kopyala", systemImage: "doc.on.doc")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .overlay(
            Divider(), alignment: .top
        )
    }
}

// MARK: - Tab Grid

struct TabGridView: View {
    @ObservedObject var tabManager: TabManager

    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Sekmeler")
                    .font(.headline)
                Spacer()
                Button {
                    tabManager.addNewTab()
                    tabManager.showTabGrid = false
                } label: {
                    Image(systemName: "plus")
                        .font(.title3)
                }
                Button("Bitti") {
                    tabManager.showTabGrid = false
                }
                .padding(.leading, 12)
            }
            .padding()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(tabManager.tabs) { tab in
                        TabCard(
                            tab: tab,
                            isActive: tab.id == tabManager.activeTabId,
                            onTap: { tabManager.switchTo(tab.id) },
                            onClose: { tabManager.closeTab(tab.id) }
                        )
                    }
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct TabCard: View {
    let tab: Tab
    let isActive: Bool
    let onTap: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tab.viewModel.pageTitle.isEmpty ? "Yeni Sekme" : tab.viewModel.pageTitle)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Text(tab.viewModel.urlString.isEmpty ? "google.com" : tab.viewModel.urlString)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .background(isActive ? Color.blue.opacity(0.1) : Color(.systemBackground))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.blue : Color(.systemGray4), lineWidth: isActive ? 2 : 1)
        )
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - WebView Container

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
