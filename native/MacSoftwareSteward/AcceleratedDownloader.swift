import Foundation

struct AcceleratedDownloadRequest: Hashable {
    var url: URL
    var destinationFileName: String
    var expectedByteCount: Int64?
    var operationName: String
}

struct AcceleratedDownloadProgress: Hashable {
    var byteCount: Int64
    var expectedByteCount: Int64?
    var speedBytesPerSecond: Double?
    var statusText: String
}

struct AcceleratedDownloadAttempt: Hashable {
    var index: Int
    var strategy: DownloadAccelerationStrategy
    var request: AcceleratedDownloadRequest
}

enum AcceleratedDownloadError: LocalizedError, Equatable {
    case retryable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .retryable(let message), .failed(let message):
            return message
        }
    }
}

enum AcceleratedDownloader {
    typealias Runner = (
        AcceleratedDownloadAttempt,
        @escaping (AcceleratedDownloadProgress) -> Void
    ) async throws -> URL

    static func download(
        _ request: AcceleratedDownloadRequest,
        strategies: [DownloadAccelerationStrategy],
        config: DownloadAccelerationConfig = .production,
        runner: Runner? = nil,
        onProgress: @escaping (AcceleratedDownloadProgress) -> Void = { _ in },
        onStatus: @escaping (String) -> Void = { _ in }
    ) async throws -> URL {
        let effectiveStrategies = strategies.isEmpty
            ? [DownloadAccelerationStrategy(kind: .direct, proxyURLString: nil)]
            : strategies
        let run = runner ?? urlSessionRunner
        var attemptIndex = 0
        var lastError: Error?

        while attemptIndex < min(config.maxAttempts, effectiveStrategies.count) {
            let strategy = effectiveStrategies[attemptIndex]
            let attempt = AcceleratedDownloadAttempt(index: attemptIndex, strategy: strategy, request: request)
            onStatus("正在使用\(strategy.title)下载（第 \(attemptIndex + 1)/\(min(config.maxAttempts, effectiveStrategies.count)) 次）")

            do {
                return try await run(attempt, onProgress)
            } catch AcceleratedDownloadError.retryable(let message) {
                lastError = AcceleratedDownloadError.retryable(message)
                switch DownloadAccelerationPolicy.retryDecision(
                    attemptIndex: attemptIndex,
                    strategyCount: effectiveStrategies.count,
                    maxAttempts: config.maxAttempts
                ) {
                case .retry(let next):
                    onStatus("\(message)，正在自动切换加速方式重试")
                    attemptIndex = next
                    continue
                case .stop:
                    throw AcceleratedDownloadError.failed(message)
                }
            } catch {
                lastError = error
                throw error
            }
        }

        throw lastError ?? AcceleratedDownloadError.failed("下载失败。")
    }

    private static func urlSessionRunner(
        attempt: AcceleratedDownloadAttempt,
        onProgress: @escaping (AcceleratedDownloadProgress) -> Void
    ) async throws -> URL {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        if !attempt.strategy.connectionProxyDictionary.isEmpty {
            configuration.connectionProxyDictionary = attempt.strategy.connectionProxyDictionary
        }

        let safeFileName = URL(fileURLWithPath: attempt.request.destinationFileName).lastPathComponent
        let stableTempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSoftwareStewardDownload-\(UUID().uuidString)-\(safeFileName)")
        let delegate = AcceleratedURLSessionDelegate(
            stableSaveURL: stableTempURL,
            expectedByteCount: attempt.request.expectedByteCount,
            onProgress: onProgress
        )
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: attempt.request.url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.setValue("MacSoftwareSteward", forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)
        let downloaded = try await delegate.waitForDownload(task)
        if let http = task.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AcceleratedDownloadError.retryable("下载服务返回 HTTP \(http.statusCode)")
        }
        return downloaded
    }
}

private final class AcceleratedURLSessionDelegate: NSObject, URLSessionDownloadDelegate {
    private let stableSaveURL: URL
    private let expectedByteCount: Int64?
    private let onProgress: (AcceleratedDownloadProgress) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var savedFileURL: URL?
    private var savedFileError: Error?
    private var lastBytes: Int64 = 0
    private var lastDate = Date()

    init(
        stableSaveURL: URL,
        expectedByteCount: Int64?,
        onProgress: @escaping (AcceleratedDownloadProgress) -> Void
    ) {
        self.stableSaveURL = stableSaveURL
        self.expectedByteCount = expectedByteCount
        self.onProgress = onProgress
    }

    func waitForDownload(_ task: URLSessionDownloadTask) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            if FileManager.default.fileExists(atPath: stableSaveURL.path) {
                try FileManager.default.removeItem(at: stableSaveURL)
            }
            try FileManager.default.moveItem(at: location, to: stableSaveURL)
            savedFileURL = stableSaveURL
        } catch {
            savedFileError = error
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let now = Date()
        let interval = now.timeIntervalSince(lastDate)
        let speed = interval > 0 ? Double(totalBytesWritten - lastBytes) / interval : nil
        lastDate = now
        lastBytes = totalBytesWritten
        onProgress(AcceleratedDownloadProgress(
            byteCount: totalBytesWritten,
            expectedByteCount: totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedByteCount,
            speedBytesPerSecond: speed,
            statusText: "正在下载"
        ))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let continuation else { return }
        self.continuation = nil

        if let error {
            continuation.resume(throwing: error)
        } else if let savedFileError {
            continuation.resume(throwing: savedFileError)
        } else if let savedFileURL {
            continuation.resume(returning: savedFileURL)
        } else {
            continuation.resume(throwing: AcceleratedDownloadError.failed("下载文件保存失败：未收到完成文件。"))
        }
    }
}
