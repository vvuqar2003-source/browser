// BrowserApp/BrowserApp/Downloader/HLSDownloader.swift

import Foundation
import AVFoundation

class HLSDownloader {
    private var downloadSession: URLSession?
    private var activeTasks: [URLSessionDataTask] = []
    private var segmentData: [URL: Data] = [:]
    private var completion: ((Result<URL, Error>) -> Void)?
    private var allSegments: [URL] = []
    private var downloadedCount = 0
    private var outputURL: URL?

    enum HLSError: Error {
        case invalidPlaylist
        case noSegmentsFound
        case mergeFailed
    }

    func download(m3u8URL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        self.completion = completion

        URLSession.shared.dataTask(with: m3u8URL) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else {
                completion(.failure(error ?? HLSError.invalidPlaylist))
                return
            }

            do {
                let content = String(data: data, encoding: .utf8) ?? ""
                let segments = try self.parseM3U8(content: content, baseURL: m3u8URL)

                guard !segments.isEmpty else {
                    completion(.failure(HLSError.noSegmentsFound))
                    return
                }

                self.allSegments = segments
                self.downloadSegments()
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func parseM3U8(content: String, baseURL: URL) throws -> [URL] {
        var segments: [URL] = []
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                if trimmed.hasPrefix("#EXT-X-STREAM-INF") {
                    continue
                }
                continue
            }

            if let segmentURL = URL(string: trimmed, relativeTo: baseURL) {
                segments.append(segmentURL)
            } else if let segmentURL = URL(string: trimmed) {
                segments.append(segmentURL)
            }
        }

        if segments.isEmpty {
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#EXT-X-STREAM-INF") {
                    if let nextLine = lines.first(where: { !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
                       let variantURL = URL(string: nextLine.trimmingCharacters(in: .whitespaces), relativeTo: baseURL) {
                        return try parseVariantPlaylist(url: variantURL)
                    }
                }
            }
        }

        return segments
    }

    private func parseVariantPlaylist(url: URL) throws -> [URL] {
        let semaphore = DispatchSemaphore(value: 0)
        var segments: [URL] = []
        var fetchError: Error?

        URLSession.shared.dataTask(with: url) { data, response, error in
            defer { semaphore.signal() }
            guard let data = data, error == nil else {
                fetchError = error
                return
            }

            let content = String(data: data, encoding: .utf8) ?? ""
            let lines = content.components(separatedBy: .newlines)

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    if let segURL = URL(string: trimmed, relativeTo: url) {
                        segments.append(segURL)
                    }
                }
            }
        }.resume()

        semaphore.wait()

        if let error = fetchError {
            throw error
        }

        return segments
    }

    private func downloadSegments() {
        let config = URLSessionConfiguration.default
        downloadSession = URLSession(configuration: config, delegate: nil, delegateQueue: .main)

        let group = DispatchGroup()
        var collectedData: [Int: Data] = [:]
        let lock = NSLock()

        for (index, segmentURL) in allSegments.enumerated() {
            group.enter()

            let task = downloadSession!.dataTask(with: segmentURL) { data, response, error in
                defer { group.leave() }

                if let data = data {
                    lock.lock()
                    collectedData[index] = data
                    lock.unlock()
                }
            }
            activeTasks.append(task)
            task.resume()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }

            let sortedData = collectedData.sorted { $0.key < $1.key }.map { $0.value }
            self.mergeSegments(sortedData)
        }
    }

    private func mergeSegments(_ segmentDataArray: [Data]) {
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent(UUID().uuidString + ".mp4")
        self.outputURL = outputURL

        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        guard let fileHandle = try? FileHandle(forWritingTo: outputURL) else {
            completion?(.failure(HLSError.mergeFailed))
            return
        }

        for data in segmentDataArray {
            fileHandle.write(data)
        }
        fileHandle.closeFile()

        convertToMP4(inputURL: outputURL)
    }

    private func convertToMP4(inputURL: URL) {
        let asset = AVURLAsset(url: inputURL)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            try? FileManager.default.removeItem(at: inputURL)
            completion?(.failure(HLSError.mergeFailed))
            return
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                try? FileManager.default.removeItem(at: inputURL)

                switch exportSession.status {
                case .completed:
                    self.completion?(.success(outputURL))
                case .failed:
                    self.completion?(.failure(exportSession.error ?? HLSError.mergeFailed))
                case .cancelled:
                    self.completion?(.failure(HLSError.mergeFailed))
                default:
                    break
                }
            }
        }
    }

    func cancel() {
        activeTasks.forEach { $0.cancel() }
        activeTasks.removeAll()
        if let outputURL = outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
    }
}
