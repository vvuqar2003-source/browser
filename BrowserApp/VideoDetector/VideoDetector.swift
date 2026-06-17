// BrowserApp/BrowserApp/VideoDetector/VideoDetector.swift

import Foundation
import WebKit

class VideoDetector {
    static let videoExtensions: Set<String> = ["mp4", "m3u8", "mkv", "webm", "ts", "mov"]
    static let subtitleExtensions: Set<String> = ["vtt", "srt"]

    static func isVideoURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return videoExtensions.contains(ext)
    }

    static func isSubtitleURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return subtitleExtensions.contains(ext)
    }

    static func injectScript(into contentController: WKUserContentController, handler: BrowserViewModel) {
        guard let jsURL = Bundle.main.url(forResource: "inject", withExtension: "js"),
              let jsSource = try? String(contentsOf: jsURL, encoding: .utf8) else {
            return
        }

        let userScript = WKUserScript(
            source: jsSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        contentController.addUserScript(userScript)
        contentController.add(handler, name: "videoFound")
    }
}
