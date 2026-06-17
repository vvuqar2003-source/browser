import SwiftUI
import WebKit
import Combine

struct DetectedVideo: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let pageTitle: String
    let timestamp: Date
    var fileName: String
    var format: String
    var estimatedSize: String?
    var streamType: String // "hls", "direct"
    var sourcePageURL: String? // iframe/embed URL where video was found
    var sourceOrigin: String?

    static func == (lhs: DetectedVideo, rhs: DetectedVideo) -> Bool {
        lhs.url == rhs.url
    }
}

struct DetectedSubtitle: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let pageTitle: String
    var fileName: String
    var format: String
    var sourcePageURL: String?
    var sourceOrigin: String?

    static func == (lhs: DetectedSubtitle, rhs: DetectedSubtitle) -> Bool {
        lhs.url == rhs.url
    }
}

class BrowserViewModel: NSObject, ObservableObject {
    @Published var urlString: String = ""
    @Published var pageTitle: String = ""
    @Published var isLoading: Bool = false
    @Published var estimatedProgress: Double = 0.0
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var detectedVideos: [DetectedVideo] = []
    @Published var detectedSubtitles: [DetectedSubtitle] = []
    @Published var showDownloadSheet: Bool = false
    @Published var showVideoListSheet: Bool = false
    @Published var showSubtitleListSheet: Bool = false
    @Published var currentVideoURL: String = ""
    @Published var detectedCount: Int = 0

    private var seenVideoURLs = Set<String>()
    private var seenSubtitleURLs = Set<String>()
    private var webView: WKWebView?
    private var cancellables = Set<AnyCancellable>()

    let homepageURL = "https://www.google.com"

    func setWebView(_ webView: WKWebView) {
        self.webView = webView
    }

    func loadURL() {
        guard let webView = webView else { return }

        var finalURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        if finalURLString.isEmpty {
            finalURLString = homepageURL
        }

        if !finalURLString.hasPrefix("http://") && !finalURLString.hasPrefix("https://") {
            if finalURLString.contains(".") && !finalURLString.contains(" ") {
                finalURLString = "https://" + finalURLString
            } else {
                let query = finalURLString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? finalURLString
                finalURLString = "https://www.google.com/search?q=\(query)"
            }
        }

        if let url = URL(string: finalURLString) {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        webView?.reload()
    }

    func goHome() {
        urlString = homepageURL
        loadURL()
    }

    func scanAndShowDownloadSheet() {
        webView?.evaluateJavaScript("manualScan()") { [weak self] _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.showDownloadSheet = true
            }
        }
    }

    func downloadVideo(_ video: DetectedVideo, with downloadManager: DownloadManager) {
        guard let webView = webView else { return }

        let isHLS = video.streamType == "hls"

        if isHLS {
            // HLS needs segment-by-segment download, use headers approach
            getDownloadHeaders(for: video.url, refererOverride: video.sourcePageURL) { headers in
                downloadManager.downloadHLS(url: video.url, fileName: video.fileName, headers: headers)
            }
            return
        }

        // Build request with correct Referer (iframe/embed URL, not main page)
        var request = URLRequest(url: video.url)
        if let referer = video.sourcePageURL {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        if let origin = video.sourceOrigin {
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }

        webView.startDownload(using: request) { download in
            DispatchQueue.main.async {
                downloadManager.handleWKDownload(download, fileName: video.fileName, url: video.url)
            }
        }
    }

    func downloadSubtitle(_ subtitle: DetectedSubtitle, with downloadManager: DownloadManager) {
        guard let webView = webView else { return }

        var request = URLRequest(url: subtitle.url)
        if let referer = subtitle.sourcePageURL {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        if let origin = subtitle.sourceOrigin {
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }

        webView.startDownload(using: request) { download in
            DispatchQueue.main.async {
                downloadManager.handleWKDownload(download, fileName: subtitle.fileName, url: subtitle.url)
            }
        }
    }

    private func getDownloadHeaders(for url: URL, refererOverride: String? = nil, completion: @escaping ([String: String]?) -> Void) {
        guard let webView = webView else {
            completion(nil)
            return
        }

        let pageURL = webView.url?.absoluteString

        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            var headers: [String: String] = [:]

            let relevantCookies = cookies.filter { cookie in
                guard let host = url.host else { return false }
                let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                return host.hasSuffix(domain)
            }

            if !relevantCookies.isEmpty {
                headers["Cookie"] = relevantCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            }

            if let referer = refererOverride ?? pageURL {
                headers["Referer"] = referer
            }

            webView.evaluateJavaScript("navigator.userAgent") { result, _ in
                if let ua = result as? String {
                    headers["User-Agent"] = ua
                }
                DispatchQueue.main.async {
                    completion(headers.isEmpty ? nil : headers)
                }
            }
        }
    }

    func addVideo(url: URL, pageTitle: String, streamType: String? = nil, sourcePageURL: String? = nil, sourceOrigin: String? = nil) {
        let urlString = url.absoluteString
        guard !seenVideoURLs.contains(urlString) else { return }
        seenVideoURLs.insert(urlString)

        let ext = url.pathExtension.lowercased()
        let isHLS = streamType == "hls" || ext == "m3u8"
        let format: String
        if isHLS {
            format = "HLS (M3U8)"
        } else {
            switch ext {
            case "mp4": format = "MP4"
            case "mkv": format = "MKV"
            case "webm": format = "WebM"
            case "ts": format = "MPEG-TS"
            case "mov": format = "MOV"
            default: format = ext.isEmpty ? "Video" : ext.uppercased()
            }
        }

        let baseName: String
        if url.lastPathComponent.isEmpty || url.lastPathComponent == "/" {
            baseName = "video_\(detectedVideos.count + 1)"
        } else {
            baseName = url.lastPathComponent
        }
        let fileName = isHLS && !baseName.hasSuffix(".mp4") ? baseName + ".mp4" : baseName

        let video = DetectedVideo(
            url: url,
            pageTitle: pageTitle,
            timestamp: Date(),
            fileName: fileName,
            format: format,
            estimatedSize: nil,
            streamType: isHLS ? "hls" : "direct",
            sourcePageURL: sourcePageURL,
            sourceOrigin: sourceOrigin
        )

        DispatchQueue.main.async {
            self.detectedVideos.append(video)
            self.detectedCount = self.detectedVideos.count + self.detectedSubtitles.count
        }
    }

    func addSubtitle(url: URL, pageTitle: String, sourcePageURL: String? = nil, sourceOrigin: String? = nil) {
        let urlString = url.absoluteString
        guard !seenSubtitleURLs.contains(urlString) else { return }
        seenSubtitleURLs.insert(urlString)

        let ext = url.pathExtension.lowercased()
        let format = ext == "srt" ? "SRT" : "VTT"
        let fileName = url.lastPathComponent.isEmpty ? "subtitle_\(detectedSubtitles.count + 1).\(ext)" : url.lastPathComponent

        let subtitle = DetectedSubtitle(
            url: url,
            pageTitle: pageTitle,
            fileName: fileName,
            format: format,
            sourcePageURL: sourcePageURL,
            sourceOrigin: sourceOrigin
        )

        DispatchQueue.main.async {
            self.detectedSubtitles.append(subtitle)
            self.detectedCount = self.detectedVideos.count + self.detectedSubtitles.count
        }
    }

    func clearDetected() {
        detectedVideos.removeAll()
        detectedSubtitles.removeAll()
        seenVideoURLs.removeAll()
        seenSubtitleURLs.removeAll()
        detectedCount = 0
    }
}

extension BrowserViewModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.isLoading = true
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.isLoading = false
            self.urlString = webView.url?.absoluteString ?? ""
            self.pageTitle = webView.title ?? ""
            self.canGoBack = webView.canGoBack
            self.canGoForward = webView.canGoForward
            self.clearDetected()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        DispatchQueue.main.async {
            self.isLoading = false
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.urlString = webView.url?.absoluteString ?? ""
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url, url.scheme == "http" {
            let secureURL = URL(string: url.absoluteString.replacingOccurrences(of: "http://", with: "https://")) ?? url
            webView.load(URLRequest(url: secureURL))
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

extension BrowserViewModel: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "videoFound",
              let body = message.body as? [String: String],
              let urlString = body["url"],
              let url = URL(string: urlString) else { return }

        let pageTitle = body["pageTitle"] ?? self.pageTitle
        let type = body["type"] ?? "video"
        let streamType = body["streamType"]
        let pageURL = body["pageURL"]
        let origin = body["origin"]

        if type == "subtitle" {
            addSubtitle(url: url, pageTitle: pageTitle, sourcePageURL: pageURL, sourceOrigin: origin)
        } else {
            addVideo(url: url, pageTitle: pageTitle, streamType: streamType, sourcePageURL: pageURL, sourceOrigin: origin)
        }
    }
}

extension BrowserViewModel: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
