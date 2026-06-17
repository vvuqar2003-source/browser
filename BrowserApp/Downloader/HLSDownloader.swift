import Foundation
import AVFoundation

class HLSDownloader {
    private var downloadSession: URLSession?
    private var activeTasks: [URLSessionDataTask] = []
    private var completion: ((Result<URL, Error>) -> Void)?
    private var headers: [String: String]?

    enum HLSError: Error, LocalizedError {
        case invalidPlaylist
        case noSegmentsFound
        case mergeFailed
        case fetchFailed
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .invalidPlaylist: return "Geçersiz HLS playlist"
            case .noSegmentsFound: return "HLS segmenti bulunamadı"
            case .mergeFailed: return "Segment birleştirme hatası"
            case .fetchFailed: return "Playlist indirilemedi"
            case .httpError(let code): return "HTTP hatası: \(code)"
            }
        }
    }

    func download(m3u8URL: URL, headers: [String: String]? = nil, completion: @escaping (Result<URL, Error>) -> Void) {
        self.completion = completion
        self.headers = headers

        var request = URLRequest(url: m3u8URL)
        headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                DispatchQueue.main.async { completion(.failure(HLSError.invalidPlaylist)) }
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                DispatchQueue.main.async { completion(.failure(HLSError.httpError(httpResponse.statusCode))) }
                return
            }

            guard let data = data, error == nil else {
                DispatchQueue.main.async { completion(.failure(error ?? HLSError.invalidPlaylist)) }
                return
            }

            let content = String(data: data, encoding: .utf8) ?? ""

            self.parseM3U8(content: content, baseURL: m3u8URL) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let segments):
                    guard !segments.isEmpty else {
                        DispatchQueue.main.async { completion(.failure(HLSError.noSegmentsFound)) }
                        return
                    }
                    self.downloadSegments(segments)
                case .failure(let error):
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }.resume()
    }

    private func parseM3U8(content: String, baseURL: URL, completion: @escaping (Result<[URL], Error>) -> Void) {
        var segments: [URL] = []
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if let segmentURL = URL(string: trimmed, relativeTo: baseURL) {
                segments.append(segmentURL)
            } else if let segmentURL = URL(string: trimmed) {
                segments.append(segmentURL)
            }
        }

        // If no segments found, look for variant playlist
        if segments.isEmpty {
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#EXT-X-STREAM-INF") {
                    if index + 1 < lines.count {
                        let nextLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
                        if !nextLine.isEmpty && !nextLine.hasPrefix("#") {
                            if let variantURL = URL(string: nextLine, relativeTo: baseURL) {
                                fetchVariantPlaylist(url: variantURL, completion: completion)
                                return
                            }
                        }
                    }
                }
            }
        }

        completion(.success(segments))
    }

    private func fetchVariantPlaylist(url: URL, completion: @escaping (Result<[URL], Error>) -> Void) {
        var request = URLRequest(url: url)
        headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async { completion(.failure(error ?? HLSError.fetchFailed)) }
                return
            }

            let content = String(data: data, encoding: .utf8) ?? ""
            var segments: [URL] = []
            let lines = content.components(separatedBy: .newlines)

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    if let segURL = URL(string: trimmed, relativeTo: url) {
                        segments.append(segURL)
                    }
                }
            }

            DispatchQueue.main.async { completion(.success(segments)) }
        }.resume()
    }

    private func downloadSegments(_ segmentURLs: [URL]) {
        let group = DispatchGroup()
        var collectedData: [Int: Data] = [:]
        let lock = NSLock()
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        self.downloadSession = session

        for (index, segmentURL) in segmentURLs.enumerated() {
            group.enter()

            var request = URLRequest(url: segmentURL)
            headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

            let task = session.dataTask(with: request) { data, response, error in
                defer { group.leave() }

                // Check HTTP status
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    return
                }

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

            if collectedData.count < segmentURLs.count / 2 {
                self.completion?(.failure(HLSError.fetchFailed))
                return
            }

            let sortedData = collectedData.sorted { $0.key < $1.key }.map { $0.value }
            self.mergeSegments(sortedData)
        }
    }

    private func mergeSegments(_ segmentDataArray: [Data]) {
        let tempDir = FileManager.default.temporaryDirectory
        let tsURL = tempDir.appendingPathComponent(UUID().uuidString + ".ts")

        FileManager.default.createFile(atPath: tsURL.path, contents: nil)
        guard let fileHandle = try? FileHandle(forWritingTo: tsURL) else {
            completion?(.failure(HLSError.mergeFailed))
            return
        }

        for data in segmentDataArray {
            fileHandle.write(data)
        }
        fileHandle.closeFile()

        convertToMP4(inputURL: tsURL)
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

        exportSession.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                try? FileManager.default.removeItem(at: inputURL)

                switch exportSession.status {
                case .completed:
                    self?.completion?(.success(outputURL))
                case .failed:
                    self?.completion?(.failure(exportSession.error ?? HLSError.mergeFailed))
                case .cancelled:
                    self?.completion?(.failure(HLSError.mergeFailed))
                default:
                    break
                }
            }
        }
    }

    func cancel() {
        activeTasks.forEach { $0.cancel() }
        activeTasks.removeAll()
        downloadSession?.invalidateAndCancel()
        downloadSession = nil
    }
}
