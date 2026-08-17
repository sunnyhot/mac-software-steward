import CryptoKit
import Foundation

/// 在 `brew upgrade --cask` 之前，通过国内 GitHub 镜像预下载 cask 文件到 brew 缓存目录。
///
/// brew 发现缓存已存在同名文件时会跳过下载，直接安装——从而绕过 GitHub Releases
/// 在国内直连慢的问题。所有失败均静默跳过，不影响原有 brew 下载流程。
///
/// 缓存文件名规则（已验证）：`SHA256(downloadURL)` (完整 hex) + `--` + URL basename，
/// 存放在 `~/Library/Caches/Homebrew/downloads/`。
enum CaskMirrorPrefetcher {
    /// cask 下载信息：原始 URL + 声明的 sha256。
    struct CaskDownloadInfo: Equatable {
        var url: URL
        var sha256: String
    }

    /// GitHub 镜像前缀。ghproxy 会代理 GitHub Releases 的下载请求。
    private static let mirrorPrefix = "https://mirror.ghproxy.com/"

    /// brew 下载缓存目录。
    static let brewDownloadCacheURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("Homebrew", isDirectory: true)
            .appendingPathComponent("downloads", isDirectory: true)
    }()

    // MARK: - URL 解析

    /// 从 `brew info --cask --json=v2` 的输出中提取 cask 的下载 URL 和 sha256。
    static func resolveDownloadInfo(from infoJSON: String, caskName: String) -> CaskDownloadInfo? {
        guard let data = infoJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casks = root["casks"] as? [[String: Any]] else { return nil }
        let selected = casks.first { ($0["token"] as? String) == caskName } ?? casks.first
        guard let urlString = selected?["url"] as? String,
              let url = URL(string: urlString) else { return nil }
        let sha256 = (selected?["sha256"] as? String) ?? ""
        return CaskDownloadInfo(url: url, sha256: sha256)
    }

    /// 仅 GitHub Releases 下载 URL 走镜像（这是国内最慢的来源）。
    /// 非 GitHub URL（如厂商直连）不走镜像——镜像不一定支持，且不一定慢。
    /// 例外：warp.dev 的 /download/brew?version= 端点已失效（404），改写为其直链稳定端点。
    static func mirrorURL(for url: URL) -> URL? {
        if let warpMirror = warpDirectURL(for: url) { return warpMirror }
        guard let host = url.host?.lowercased(), host == "github.com" else { return nil }
        guard url.path.lowercased().contains("/releases/download/") else { return nil }
        // mirror.ghproxy.com/https://github.com/owner/repo/releases/download/...
        return URL(string: mirrorPrefix + url.absoluteString)
    }

    /// warp.dev 直链改写：https://app.warp.dev/download/brew?version=vX → https://releases.warp.dev/stable/vX/Warp.dmg
    /// 仅当 URL 与预期格式完全匹配时改写；内容仍受 cask 声明的 sha256 校验兜底。
    private static func warpDirectURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(), host == "app.warp.dev" else { return nil }
        guard url.path.lowercased() == "/download/brew" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let version = components.queryItems?.first(where: { $0.name == "version" })?.value,
              !version.isEmpty else { return nil }
        return URL(string: "https://releases.warp.dev/stable/\(version)/Warp.dmg")
    }

    /// 计算 brew 缓存文件名：`SHA256(url)` + `--` + URL basename。
    static func cacheFileName(for url: URL) -> String? {
        let urlString = url.absoluteString
        let hash = SHA256.hash(data: Data(urlString.utf8))
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        let basename = url.lastPathComponent
        guard !basename.isEmpty else { return nil }
        return "\(hex)--\(basename)"
    }

    // MARK: - 预下载

    /// 预下载 cask 文件到 brew 缓存目录。
    ///
    /// - Returns: `true` 表示缓存已就绪（brew 会跳过下载）；`false` 表示跳过（任何失败均静默跳过）。
    static func prefetch(
        info: CaskDownloadInfo,
        onProgress: ((Double) -> Void)? = nil
    ) async -> Bool {
        guard let mirror = mirrorURL(for: info.url),
              let cacheName = cacheFileName(for: info.url) else { return false }

        let cacheURL = brewDownloadCacheURL.appendingPathComponent(cacheName)

        // 缓存已存在则跳过（brew 也会跳过）。
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            return true
        }

        // 确保缓存目录存在。
        try? FileManager.default.createDirectory(at: brewDownloadCacheURL, withIntermediateDirectories: true)

        // 下载到临时文件。
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSoftwareStewardPrefetch-\(UUID().uuidString)-\(info.url.lastPathComponent)")

        do {
            let downloaded = try await downloadFile(
                from: mirror,
                to: tempURL,
                expectedByteCount: nil,
                onProgress: onProgress
            )

            // SHA256 校验：不匹配则删除，绝不放入 brew 缓存。
            if !info.sha256.isEmpty {
                let actualSHA = sha256Hex(of: downloaded)
                guard actualSHA == info.sha256 else { return false }
            }

            // 移到 brew 缓存（原子移动）。
            try? FileManager.default.removeItem(at: cacheURL) // 清理可能的残留
            try FileManager.default.moveItem(at: downloaded, to: cacheURL)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }
    }

    // MARK: - 下载

    /// 用 URLSession 下载文件，支持进度回调。
    private static func downloadFile(
        from url: URL,
        to destination: URL,
        expectedByteCount: Int64?,
        onProgress: ((Double) -> Void)?
    ) async throws -> URL {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600

        let delegate = PrefetchDownloadDelegate(
            destination: destination,
            onProgress: onProgress
        )
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.setValue("MacSoftwareSteward", forHTTPHeaderField: "User-Agent")

        let task = session.downloadTask(with: request)
        return try await delegate.waitForDownload(task)
    }

    // MARK: - 校验

    /// 计算文件的 SHA256 hex。
    static func sha256Hex(of url: URL) -> String {
        guard let fileData = try? Data(contentsOf: url) else { return "" }
        let hash = SHA256.hash(data: fileData)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Download Delegate

private final class PrefetchDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let onProgress: ((Double) -> Void)?
    private var continuation: CheckedContinuation<URL, Error>?

    init(destination: URL, onProgress: ((Double) -> Void)?) {
        self.destination = destination
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

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress?(fraction)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume(returning: destination)
        } catch {
            continuation?.resume(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
        }
    }
}
