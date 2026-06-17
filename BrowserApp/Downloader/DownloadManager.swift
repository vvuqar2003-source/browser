import Foundation
import UIKit
import WebKit
import UserNotifications

class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published var activeDownloads: [DownloadTask] = []
    @Published var downloadHistory: [DownloadRecord] = []
    @Published var downloadProgress: [UUID: DownloadProgressInfo] = [:]
    @Published var downloadError: String?

    @Published var cellularDownloadEnabled: Bool {
        didSet { UserDefaults.standard.set(cellularDownloadEnabled, forKey: "cellularDownload") }
    }
    @Published var autoDownloadVideos: Bool {
        didSet { UserDefaults.standard.set(autoDownloadVideos, forKey: "autoDownloadVideos") }
    }
    @Published var saveToPhotos: Bool {
        didSet { UserDefaults.standard.set(saveToPhotos, forKey: "saveToPhotos") }
    }

    private var foregroundSession: URLSession!
    private var backgroundSession: URLSession!
    private var backgroundCompletionHandler: (() -> Void)?
    private var hlsDownloaders: [URL: HLSDownloader] = [:]

    // WKDownload tracking
    private var wkDownloads: [UUID: WKDownload] = [:]
    private var wkDownloadTaskIds: [ObjectIdentifier: UUID] = [:]
    private var wkDownloadFileNames: [ObjectIdentifier: String] = [:]
    private var progressObservations: [UUID: NSKeyValueObservation] = [:]
    private var downloadStartTimes: [UUID: Date] = [:]

    // URLSession tracking
    private var urlSessionStartTimes: [Int: Date] = [:]

    private var isBackgroundDownload: Bool {
        UserDefaults.standard.bool(forKey: "backgroundDownload")
    }

    struct DownloadProgressInfo {
        var fraction: Double = 0
        var totalBytesWritten: Int64 = 0
        var totalBytesExpected: Int64 = 0
        var speed: Double = 0

        var downloadedText: String { formatBytes(totalBytesWritten) }
        var totalText: String { totalBytesExpected > 0 ? formatBytes(totalBytesExpected) : "?" }

        var speedText: String {
            if speed <= 0 { return "" }
            if speed >= 1_048_576 { return String(format: "%.1f MB/s", speed / 1_048_576) }
            if speed >= 1024 { return String(format: "%.0f KB/s", speed / 1024) }
            return String(format: "%.0f B/s", speed)
        }

        private func formatBytes(_ bytes: Int64) -> String {
            let mb = Double(bytes) / 1_048_576
            if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
            if mb >= 1 { return String(format: "%.1f MB", mb) }
            return String(format: "%.0f KB", Double(bytes) / 1024)
        }
    }

    struct DownloadTask: Identifiable {
        let id = UUID()
        let url: URL
        let fileName: String
        var urlSessionTask: URLSessionDownloadTask?
        var progress: Double = 0
        var isHLS: Bool
        var isBackground: Bool
        var error: String?
        var statusText: String = "Başlatılıyor..."
    }

    struct DownloadRecord: Identifiable, Codable {
        let id: UUID
        let fileName: String
        let date: Date
        let fileSize: String
        let url: String
        var success: Bool = true
    }

    override init() {
        self.cellularDownloadEnabled = UserDefaults.standard.bool(forKey: "cellularDownload")
        self.autoDownloadVideos = UserDefaults.standard.bool(forKey: "autoDownloadVideos")
        self.saveToPhotos = UserDefaults.standard.bool(forKey: "saveToPhotos")

        super.init()

        let fgConfig = URLSessionConfiguration.default
        fgConfig.allowsCellularAccess = cellularDownloadEnabled
        foregroundSession = URLSession(configuration: fgConfig, delegate: self, delegateQueue: .main)

        let bgConfig = URLSessionConfiguration.background(withIdentifier: "com.browserapp.downloads")
        bgConfig.isDiscretionary = false
        bgConfig.sessionSendsLaunchEvents = true
        bgConfig.allowsCellularAccess = cellularDownloadEnabled
        backgroundSession = URLSession(configuration: bgConfig, delegate: self, delegateQueue: .main)

        loadHistory()
    }

    func handleBackgroundEvents(identifier: String, completionHandler: @escaping () -> Void) {
        backgroundCompletionHandler = completionHandler
        if backgroundSession == nil || backgroundSession.configuration.identifier != identifier {
            let config = URLSessionConfiguration.background(withIdentifier: identifier)
            backgroundSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        }
    }

    // MARK: - WKDownload (primary method - uses browser cookies automatically)

    func handleWKDownload(_ download: WKDownload, fileName: String, url: URL) {
        var task = DownloadTask(url: url, fileName: fileName, urlSessionTask: nil, isHLS: false, isBackground: false)
        task.statusText = "Bağlanıyor..."
        activeDownloads.append(task)

        let taskId = task.id
        let objId = ObjectIdentifier(download)
        wkDownloads[taskId] = download
        wkDownloadTaskIds[objId] = taskId
        wkDownloadFileNames[objId] = fileName
        downloadStartTimes[taskId] = Date()
        download.delegate = self

        // Observe progress
        let observation = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            DispatchQueue.main.async {
                guard let self = self,
                      let index = self.activeDownloads.firstIndex(where: { $0.id == taskId }) else { return }

                let fraction = progress.fractionCompleted
                let written = progress.completedUnitCount
                let total = progress.totalUnitCount

                self.activeDownloads[index].progress = fraction

                var speed: Double = 0
                if let startTime = self.downloadStartTimes[taskId] {
                    let elapsed = Date().timeIntervalSince(startTime)
                    if elapsed > 0.5 { speed = Double(written) / elapsed }
                }

                var info = DownloadProgressInfo()
                info.fraction = fraction
                info.totalBytesWritten = written
                info.totalBytesExpected = total
                info.speed = speed
                self.downloadProgress[taskId] = info

                if written > 0 {
                    self.activeDownloads[index].statusText = "\(info.downloadedText) / \(info.totalText)"
                }
            }
        }
        progressObservations[taskId] = observation
    }

    // MARK: - HLS Download

    func downloadHLS(url: URL, fileName: String, headers: [String: String]? = nil) {
        downloadError = nil
        let hlsDownloader = HLSDownloader()
        hlsDownloaders[url] = hlsDownloader

        var task = DownloadTask(url: url, fileName: fileName, urlSessionTask: nil, isHLS: true, isBackground: false)
        task.statusText = "HLS segmentleri indiriliyor..."
        activeDownloads.append(task)

        hlsDownloader.download(m3u8URL: url, headers: headers) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.hlsDownloaders.removeValue(forKey: url)
                self.activeDownloads.removeAll { $0.url == url }
                switch result {
                case .success(let fileURL):
                    let size = self.fileSizeString(fileURL)
                    self.saveToFiles(sourceURL: fileURL, fileName: fileName)
                    self.addRecord(fileName: fileName, url: url.absoluteString, fileSize: size, success: true)
                case .failure(let error):
                    self.downloadError = "HLS hatası: \(error.localizedDescription)"
                    self.addRecord(fileName: fileName, url: url.absoluteString, fileSize: "Hata", success: false)
                }
            }
        }
    }

    // MARK: - URLSession fallback (for background downloads)

    func download(url: URL, fileName: String, headers: [String: String]? = nil) {
        downloadError = nil
        let session: URLSession = isBackgroundDownload ? backgroundSession : foregroundSession
        var request = URLRequest(url: url)
        headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let downloadTask = session.downloadTask(with: request)

        var task = DownloadTask(url: url, fileName: fileName, urlSessionTask: downloadTask, isHLS: false, isBackground: isBackgroundDownload)
        task.statusText = "İndiriliyor..."
        activeDownloads.append(task)
        urlSessionStartTimes[downloadTask.taskIdentifier] = Date()
        downloadTask.resume()
    }

    // MARK: - Cancel

    func cancelDownload(id: UUID) {
        guard let index = activeDownloads.firstIndex(where: { $0.id == id }) else { return }
        let task = activeDownloads[index]

        if task.isHLS {
            hlsDownloaders[task.url]?.cancel()
            hlsDownloaders.removeValue(forKey: task.url)
        } else if let wkDownload = wkDownloads[id] {
            wkDownload.cancel { _ in }
            cleanupWKDownload(id)
        } else {
            if let taskId = task.urlSessionTask?.taskIdentifier {
                urlSessionStartTimes.removeValue(forKey: taskId)
            }
            task.urlSessionTask?.cancel()
        }

        activeDownloads.remove(at: index)
        downloadProgress.removeValue(forKey: id)
        downloadStartTimes.removeValue(forKey: id)
    }

    // MARK: - History & Files

    func clearHistory() {
        downloadHistory.removeAll()
        saveHistory()
    }

    func clearCache() {
        let tempDir = FileManager.default.temporaryDirectory
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            let tempFiles = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            for file in tempFiles { try? FileManager.default.removeItem(at: file) }
            let docFiles = try FileManager.default.contentsOfDirectory(at: documentsDir, includingPropertiesForKeys: nil)
            for file in docFiles where file.lastPathComponent.hasPrefix(".tmp_") {
                try? FileManager.default.removeItem(at: file)
            }
        } catch {}
    }

    func updateCellularAccess(_ enabled: Bool) {
        cellularDownloadEnabled = enabled
    }

    private func saveToFiles(sourceURL: URL, fileName: String) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documentsPath.appendingPathComponent(fileName)
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            downloadError = "Kayıt hatası: \(error.localizedDescription)"
        }
    }

    func fileSizeString(_ url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return "?" }
        let mb = Double(size) / 1_048_576
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return String(format: "%.0f KB", Double(size) / 1024)
    }

    private func addRecord(fileName: String, url: String, fileSize: String, success: Bool) {
        let record = DownloadRecord(id: UUID(), fileName: fileName, date: Date(), fileSize: fileSize, url: url, success: success)
        downloadHistory.insert(record, at: 0)
        saveHistory()
        if success {
            sendNotification(title: "İndirme Tamamlandı", body: "\(fileName) — \(fileSize)")
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "downloadHistory"),
           let records = try? JSONDecoder().decode([DownloadRecord].self, from: data) {
            downloadHistory = records
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(downloadHistory) {
            UserDefaults.standard.set(data, forKey: "downloadHistory")
        }
    }

    private func cleanupWKDownload(_ taskId: UUID) {
        if let download = wkDownloads[taskId] {
            let objId = ObjectIdentifier(download)
            wkDownloadTaskIds.removeValue(forKey: objId)
            wkDownloadFileNames.removeValue(forKey: objId)
        }
        wkDownloads.removeValue(forKey: taskId)
        progressObservations.removeValue(forKey: taskId)
        downloadStartTimes.removeValue(forKey: taskId)
    }

    private func findURLSessionTaskIndex(for downloadTask: URLSessionDownloadTask, in session: URLSession) -> Int? {
        let isBG = session.configuration.identifier != nil
        return activeDownloads.firstIndex(where: {
            $0.urlSessionTask?.taskIdentifier == downloadTask.taskIdentifier && $0.isBackground == isBG
        })
    }
}

// MARK: - WKDownloadDelegate

extension DownloadManager: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let objId = ObjectIdentifier(download)
        let taskId = wkDownloadTaskIds[objId]

        // Check HTTP status & content type
        if let httpResponse = response as? HTTPURLResponse {
            let status = httpResponse.statusCode
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""

            if status < 200 || status >= 300 {
                let msg = "Sunucu hatası: HTTP \(status)"
                failWKDownload(taskId: taskId, message: msg)
                completionHandler(nil)
                return
            }

            if contentType.contains("text/html") {
                let msg = "Sunucu video yerine HTML sayfası döndürdü (muhtemelen giriş gerekli)"
                failWKDownload(taskId: taskId, message: msg)
                completionHandler(nil)
                return
            }
        }

        let fileName = wkDownloadFileNames[objId] ?? suggestedFilename
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documentsPath.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: destinationURL)

        // Update status
        if let taskId = taskId, let index = activeDownloads.firstIndex(where: { $0.id == taskId }) {
            activeDownloads[index].statusText = "İndiriliyor..."
        }

        completionHandler(destinationURL)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let objId = ObjectIdentifier(download)
        guard let taskId = wkDownloadTaskIds[objId],
              let index = activeDownloads.firstIndex(where: { $0.id == taskId }) else { return }

        let task = activeDownloads[index]
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(task.fileName)
        let size = fileSizeString(fileURL)

        addRecord(fileName: task.fileName, url: task.url.absoluteString, fileSize: size, success: true)

        activeDownloads.remove(at: index)
        downloadProgress.removeValue(forKey: taskId)
        cleanupWKDownload(taskId)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let objId = ObjectIdentifier(download)
        guard let taskId = wkDownloadTaskIds[objId] else { return }
        failWKDownload(taskId: taskId, message: error.localizedDescription)
    }

    private func failWKDownload(taskId: UUID?, message: String) {
        guard let taskId = taskId,
              let index = activeDownloads.firstIndex(where: { $0.id == taskId }) else { return }
        activeDownloads[index].error = message
        downloadError = message
        addRecord(fileName: activeDownloads[index].fileName, url: activeDownloads[index].url.absoluteString, fileSize: "Hata", success: false)
        activeDownloads.remove(at: index)
        downloadProgress.removeValue(forKey: taskId)
        cleanupWKDownload(taskId)
    }
}

// MARK: - URLSessionDownloadDelegate (fallback)

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let index = findURLSessionTaskIndex(for: downloadTask, in: session) else { return }
        let task = activeDownloads[index]

        if let httpResponse = downloadTask.response as? HTTPURLResponse {
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 || contentType.contains("text/html") {
                let msg = contentType.contains("text/html") ? "Sunucu HTML döndürdü" : "HTTP \(httpResponse.statusCode)"
                activeDownloads[index].error = msg
                downloadError = msg
                addRecord(fileName: task.fileName, url: task.url.absoluteString, fileSize: "Hata", success: false)
                activeDownloads.remove(at: index)
                downloadProgress.removeValue(forKey: task.id)
                return
            }
        }

        let size = fileSizeString(location)
        saveToFiles(sourceURL: location, fileName: task.fileName)
        addRecord(fileName: task.fileName, url: task.url.absoluteString, fileSize: size, success: true)
        activeDownloads.remove(at: index)
        downloadProgress.removeValue(forKey: task.id)
        urlSessionStartTimes.removeValue(forKey: downloadTask.taskIdentifier)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let index = findURLSessionTaskIndex(for: downloadTask, in: session) else { return }

        let fraction = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        var speed: Double = 0
        if let startTime = urlSessionStartTimes[downloadTask.taskIdentifier] {
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > 0.5 { speed = Double(totalBytesWritten) / elapsed }
        }

        let taskId = activeDownloads[index].id
        activeDownloads[index].progress = fraction

        var info = DownloadProgressInfo()
        info.fraction = fraction
        info.totalBytesWritten = totalBytesWritten
        info.totalBytesExpected = totalBytesExpectedToWrite
        info.speed = speed
        downloadProgress[taskId] = info
        activeDownloads[index].statusText = "\(info.downloadedText) / \(info.totalText)"
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let index = findURLSessionTaskIndex(for: downloadTask, in: session) else { return }
        if let error = error {
            if (error as NSError).code == NSURLErrorCancelled { return }
            let taskId = activeDownloads[index].id
            activeDownloads[index].error = error.localizedDescription
            downloadError = error.localizedDescription
            addRecord(fileName: activeDownloads[index].fileName, url: activeDownloads[index].url.absoluteString, fileSize: "Hata", success: false)
            activeDownloads.remove(at: index)
            downloadProgress.removeValue(forKey: taskId)
            urlSessionStartTimes.removeValue(forKey: downloadTask.taskIdentifier)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
