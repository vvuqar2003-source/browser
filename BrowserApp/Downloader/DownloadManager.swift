// BrowserApp/BrowserApp/Downloader/DownloadManager.swift

import Foundation
import UIKit
import UserNotifications

class DownloadManager: NSObject, ObservableObject {
    @Published var activeDownloads: [DownloadTask] = []
    @Published var downloadHistory: [DownloadRecord] = []
    @Published var downloadProgress: [UUID: Double] = [:]

    private var foregroundSession: URLSession!
    private var backgroundSession: URLSession!
    private var backgroundCompletionHandler: (() -> Void)?
    private let maxConcurrent = 3
    private var pendingQueue: [DownloadTask] = []
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
    }

    struct DownloadRecord: Identifiable, Codable {
        let id: UUID
        let fileName: String
        let date: Date
        let fileSize: String
        let url: String
    }

    override init() {
        super.init()

        let fgConfig = URLSessionConfiguration.default
        foregroundSession = URLSession(configuration: fgConfig, delegate: self, delegateQueue: .main)

        let bgConfig = URLSessionConfiguration.background(withIdentifier: "com.browserapp.downloads")
        bgConfig.isDiscretionary = false
        bgConfig.sessionSendsLaunchEvents = true
        backgroundSession = URLSession(configuration: bgConfig, delegate: self, delegateQueue: .main)

        loadHistory()
    }

    func handleBackgroundEvents(identifier: String, completionHandler: @escaping () -> Void) {
        backgroundCompletionHandler = completionHandler
    }

    func download(url: URL, fileName: String) {
        let isHLS = url.pathExtension.lowercased() == "m3u8"

        if isHLS {
            let hlsDownloader = HLSDownloader()
            let task = DownloadTask(url: url, fileName: fileName, isHLS: true)
            activeDownloads.append(task)

            hlsDownloader.download(m3u8URL: url) { [weak self] result in
                DispatchQueue.main.async {
                    self?.activeDownloads.removeAll { $0.url == url }
                    switch result {
                    case .success(let fileURL):
                        self?.saveToFiles(sourceURL: fileURL, fileName: fileName)
                        self?.addRecord(fileName: fileName, url: url.absoluteString, fileSize: "N/A")
                    case .failure(let error):
                        print("HLS download failed: \(error)")
                    }
                }
            }
            return
        }

        let task = DownloadTask(url: url, fileName: fileName, isHLS: false)
        var mutableTask = task

        let session = isBackgroundDownload ? backgroundSession : foregroundSession
        let downloadTask = session?.downloadTask(with: url)
        mutableTask.task = downloadTask
        activeDownloads.append(mutableTask)
        downloadTask?.resume()
    }

    func cancelDownload(id: UUID) {
        if let index = activeDownloads.firstIndex(where: { $0.id == id }) {
            activeDownloads[index].task?.cancel()
            activeDownloads.remove(at: index)
        }
    }

    func clearHistory() {
        downloadHistory.removeAll()
        saveHistory()
    }

    private func saveToFiles(sourceURL: URL, fileName: String) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documentsPath.appendingPathComponent(fileName)

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)

            UISaveVideoAtPathToSavedPhotosAlbum(destinationURL.path, nil, nil, nil)
        } catch {
            print("File save error: \(error)")
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
            sendNotification(title: "İndirme Tamamlandı", body: "\(fileName) indirildi.")
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
}

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let index = activeDownloads.firstIndex(where: { $0.task?.taskIdentifier == downloadTask.taskIdentifier }) else { return }

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
        guard let index = activeDownloads.firstIndex(where: { $0.task?.taskIdentifier == downloadTask.taskIdentifier }) else { return }

        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        activeDownloads[index].progress = progress
        downloadProgress[activeDownloads[index].id] = progress
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
