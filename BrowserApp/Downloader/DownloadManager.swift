import Foundation
import UIKit
import UserNotifications

class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published var activeDownloads: [DownloadTask] = []
    @Published var downloadHistory: [DownloadRecord] = []
    @Published var downloadProgress: [UUID: Double] = [:]
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

    private var isBackgroundDownload: Bool {
        UserDefaults.standard.bool(forKey: "backgroundDownload")
    }

    struct DownloadTask: Identifiable {
        let id = UUID()
        let url: URL
        let fileName: String
        var task: URLSessionDownloadTask?
        var progress: Double = 0
        var isHLS: Bool
        var isBackground: Bool
        var error: String?
    }

    struct DownloadRecord: Identifiable, Codable {
        let id: UUID
        let fileName: String
        let date: Date
        let fileSize: String
        let url: String
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

    func download(url: URL, fileName: String, headers: [String: String]? = nil) {
        downloadError = nil
        let isHLS = url.pathExtension.lowercased() == "m3u8"
        let useBackground = isBackgroundDownload

        if isHLS {
            let hlsDownloader = HLSDownloader()
            hlsDownloaders[url] = hlsDownloader

            let task = DownloadTask(url: url, fileName: fileName, task: nil, isHLS: true, isBackground: useBackground)
            activeDownloads.append(task)

            hlsDownloader.download(m3u8URL: url) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.hlsDownloaders.removeValue(forKey: url)
                    self.activeDownloads.removeAll { $0.url == url }
                    switch result {
                    case .success(let fileURL):
                        self.saveToFiles(sourceURL: fileURL, fileName: fileName)
                        self.addRecord(fileName: fileName, url: url.absoluteString, fileSize: "N/A")
                    case .failure(let error):
                        self.downloadError = "HLS hatasi: \(error.localizedDescription)"
                        print("HLS download failed: \(error)")
                    }
                }
            }
            return
        }

        let session: URLSession = useBackground ? backgroundSession : foregroundSession
        var request = URLRequest(url: url)
        headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let downloadTask = session.downloadTask(with: request)

        let task = DownloadTask(url: url, fileName: fileName, task: downloadTask, isHLS: false, isBackground: useBackground)
        activeDownloads.append(task)
        downloadTask.resume()
    }

    func cancelDownload(id: UUID) {
        if let index = activeDownloads.firstIndex(where: { $0.id == id }) {
            let task = activeDownloads[index]
            if task.isHLS {
                hlsDownloaders[task.url]?.cancel()
                hlsDownloaders.removeValue(forKey: task.url)
            } else {
                task.task?.cancel()
            }
            activeDownloads.remove(at: index)
            downloadProgress.removeValue(forKey: id)
        }
    }

    func clearHistory() {
        downloadHistory.removeAll()
        saveHistory()
    }

    func clearCache() {
        let tempDir = FileManager.default.temporaryDirectory
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        do {
            let tempFiles = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            for file in tempFiles {
                try FileManager.default.removeItem(at: file)
            }
            let docFiles = try FileManager.default.contentsOfDirectory(at: documentsDir, includingPropertiesForKeys: nil)
            for file in docFiles where file.lastPathComponent.hasPrefix(".tmp_") {
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            print("Cache clear error: \(error)")
        }
    }

    func updateCellularAccess(_ enabled: Bool) {
        cellularDownloadEnabled = enabled
        foregroundSession.configuration.allowsCellularAccess = enabled
        backgroundSession.configuration.allowsCellularAccess = enabled
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
            print("File save error: \(error)")
            downloadError = "Kayit hatasi: \(error.localizedDescription)"
        }
    }

    private func addRecord(fileName: String, url: String, fileSize: String) {
        let record = DownloadRecord(
            id: UUID(),
            fileName: fileName,
            date: Date(),
            fileSize: fileSize,
            url: url
        )
        downloadHistory.insert(record, at: 0)
        saveHistory()

        if isBackgroundDownload {
            sendNotification(title: "Indirme Tamamlandi", body: "\(fileName) indirildi.")
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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

    private func findTaskIndex(for downloadTask: URLSessionDownloadTask, in session: URLSession) -> Int? {
        let isBG = session.configuration.identifier != nil
        return activeDownloads.firstIndex(where: {
            $0.task?.taskIdentifier == downloadTask.taskIdentifier && $0.isBackground == isBG
        })
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let index = findTaskIndex(for: downloadTask, in: session) else { return }

        let task = activeDownloads[index]
        let fileName = task.fileName

        saveToFiles(sourceURL: location, fileName: fileName)
        addRecord(fileName: fileName, url: task.url.absoluteString, fileSize: "N/A")

        activeDownloads.remove(at: index)
        downloadProgress.removeValue(forKey: task.id)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let index = findTaskIndex(for: downloadTask, in: session) else { return }

        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        activeDownloads[index].progress = progress
        downloadProgress[activeDownloads[index].id] = progress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let index = findTaskIndex(for: downloadTask, in: session) else { return }

        if let error = error {
            let taskId = activeDownloads[index].id
            activeDownloads[index].error = error.localizedDescription
            downloadError = "Indirme hatasi: \(error.localizedDescription)"
            print("Download failed: \(error.localizedDescription)")
            activeDownloads.remove(at: index)
            downloadProgress.removeValue(forKey: taskId)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
