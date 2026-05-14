import AppKit
import Foundation

@MainActor
final class AppUpdateModel: ObservableObject {
    @Published var automaticChecksEnabled: Bool {
        didSet {
            UserDefaults.standard.set(automaticChecksEnabled, forKey: Self.automaticChecksKey)
            if automaticChecksEnabled {
                startPeriodicCheck()
            } else {
                stopPeriodicCheck()
            }
        }
    }
    @Published var automaticDownloadsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(automaticDownloadsEnabled, forKey: Self.automaticDownloadsKey)
        }
    }
    @Published var isChecking = false
    @Published var isInstalling = false
    @Published var status = "尚未检查更新。"
    @Published var latestVersion = ""
    @Published var releaseURL = ""
    @Published var releaseNotes = ""
    @Published var updateAvailable = false
    /// 是否显示应用更新弹框
    @Published var showUpdateDialog = false
    @Published var progress = ""
    /// 下载进度百分比（0.0 ~ 1.0），nil 表示未在下载或无法获取
    @Published var downloadFraction: Double? = nil
    /// 已下载字节数（人类可读，如 "1.2 MB"）
    @Published var downloadedSizeText: String? = nil
    /// 下载速度（人类可读，如 "3.5 MB/s"）
    @Published var downloadSpeedText: String? = nil

    private var latestRelease: GitHubRelease?
    private let session: URLSession
    private var periodicTask: Task<Void, Never>?
    private var lastCheckTime: Date?
    /// 用于跟踪下载进度
    private var downloadStartTime: Date?
    private var lastDownloadedBytes: Int64 = 0
    private var lastDownloadSpeedTime: Date?

    private static let automaticChecksKey = "AppUpdateAutomaticChecksEnabled"
    private static let automaticDownloadsKey = "AppUpdateAutomaticDownloadsEnabled"
    private static let checkInterval: TimeInterval = 4 * 3600

    init(session: URLSession = .shared) {
        self.session = session
        self.automaticChecksEnabled = UserDefaults.standard.object(forKey: Self.automaticChecksKey) as? Bool ?? true
        self.automaticDownloadsEnabled = UserDefaults.standard.object(forKey: Self.automaticDownloadsKey) as? Bool ?? true
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var repositoryName: String {
        "\(owner)/\(repo)"
    }

    func autoCheckIfNeeded() async {
        guard automaticChecksEnabled else { return }
        await checkForUpdates(automatic: true)
        if updateAvailable, automaticDownloadsEnabled {
            showUpdateDialog = false
            await downloadInstallAndRestart()
        }
        startPeriodicCheck()
    }

    func checkForUpdates(automatic: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        progress = ""
        if !automatic {
            status = "正在检查 GitHub Release..."
        }

        do {
            let release = try await fetchLatestRelease()
            latestRelease = release
            latestVersion = release.versionString
            releaseURL = release.htmlURL
            releaseNotes = release.body ?? ""
            updateAvailable = compareVersions(release.versionString, currentVersion) == .orderedDescending
            lastCheckTime = Date()
            status = updateAvailable
                ? "发现新版本 \(release.versionString)。"
                : "当前已是最新版本 \(currentVersion)。"
            if updateAvailable {
                showUpdateDialog = true
            }
        } catch {
            if !automatic {
                status = "检查更新失败：\(error.localizedDescription)"
            }
        }

        isChecking = false

        if automatic, updateAvailable, automaticDownloadsEnabled {
            showUpdateDialog = false
            await downloadInstallAndRestart()
        }
    }

    private func startPeriodicCheck() {
        guard periodicTask == nil else { return }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.checkInterval))
                guard !Task.isCancelled, let self else { return }
                guard self.automaticChecksEnabled else { return }
                await self.checkForUpdates(automatic: true)
            }
        }
    }

    private func stopPeriodicCheck() {
        periodicTask?.cancel()
        periodicTask = nil
    }

    func downloadInstallAndRestart() async {
        guard !isInstalling else { return }
        guard let release = latestRelease else {
            status = "请先检查更新。"
            return
        }
        guard let asset = release.asset(named: assetName) ?? release.firstZipAsset else {
            status = "Release 中没有找到 \(assetName) 或 .zip 安装包。"
            return
        }

        isInstalling = true
        downloadFraction = 0
        downloadedSizeText = nil
        downloadSpeedText = nil
        downloadStartTime = Date()
        lastDownloadedBytes = 0
        lastDownloadSpeedTime = Date()
        progress = "正在下载 \(asset.name)..."

        do {
            let downloaded = try await download(asset: asset)
            downloadFraction = nil
            progress = "正在解压安装包..."
            let extractedApp = try await extractApp(from: downloaded)
            progress = "正在准备重启并安装..."
            let destination = try scheduleInstallAndRestart(newAppURL: extractedApp)
            status = "安装脚本已启动，将安装到 \(destination.path) 并重启。"
        } catch {
            status = "安装更新失败：\(error.localizedDescription)"
            progress = ""
            isInstalling = false
            downloadFraction = nil
            downloadedSizeText = nil
            downloadSpeedText = nil
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            throw AppUpdateError.message("GitHub Release URL 无效。")
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacSoftwareSteward/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return try await fetchLatestReleaseByRedirect()
        }
        do {
            return try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            return try await fetchLatestReleaseByRedirect()
        }
    }

    private func fetchLatestReleaseByRedirect() async throws -> GitHubRelease {
        guard let url = URL(string: "https://github.com/\(owner)/\(repo)/releases/latest") else {
            throw AppUpdateError.message("GitHub Release URL 无效。")
        }

        let (_, response) = try await session.data(from: url)
        guard let finalURL = response.url?.absoluteString,
              let tag = finalURL.components(separatedBy: "/releases/tag/").last,
              !tag.isEmpty,
              tag != finalURL else {
            throw AppUpdateError.message("无法解析 GitHub 最新版本。请稍后再试。")
        }

        let downloadURL = "https://github.com/\(owner)/\(repo)/releases/download/\(tag)/\(assetName)"
        return GitHubRelease(
            tagName: tag,
            name: tag,
            htmlURL: "https://github.com/\(owner)/\(repo)/releases/tag/\(tag)",
            body: "GitHub API 暂不可用，已通过 Release 重定向检测到最新版本。",
            draft: false,
            prerelease: false,
            assets: [
                GitHubRelease.Asset(
                    name: assetName,
                    browserDownloadURL: downloadURL,
                    size: 0
                )
            ]
        )
    }

    private func download(asset: GitHubRelease.Asset) async throws -> URL {
        guard let url = URL(string: asset.browserDownloadURL) else {
            throw AppUpdateError.message("Release asset 下载地址无效。")
        }
        let workDirectory = try makeWorkDirectory()
        let destination = workDirectory.appendingPathComponent(asset.name)

        // 使用 delegate-based URLSession 获取下载进度
        let delegate = DownloadProgressDelegate { [weak self] bytesWritten, totalWritten, totalExpected in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if totalExpected > 0 {
                    self.downloadFraction = Double(totalWritten) / Double(totalExpected)
                }
                self.downloadedSizeText = ByteCountFormatter.string(fromByteCount: totalWritten, countStyle: .file)
                // 计算下载速度（每秒采样一次避免抖动）
                let now = Date()
                if let lastTime = self.lastDownloadSpeedTime,
                   now.timeIntervalSince(lastTime) >= 1.0 {
                    let bytesDelta = totalWritten - self.lastDownloadedBytes
                    let timeDelta = now.timeIntervalSince(lastTime)
                    if timeDelta > 0 {
                        let bytesPerSecond = Double(bytesDelta) / timeDelta
                        self.downloadSpeedText = ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
                    }
                    self.lastDownloadedBytes = totalWritten
                    self.lastDownloadSpeedTime = now
                }
            }
        }
        let downloadSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { downloadSession.finishTasksAndInvalidate() }

        let (temporaryURL, response) = try await downloadSession.download(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppUpdateError.message("下载安装包失败。")
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func extractApp(from zipURL: URL) async throws -> URL {
        let extractDirectory = zipURL.deletingLastPathComponent().appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
        let result = await CommandRunner.run("/usr/bin/ditto", arguments: ["-x", "-k", zipURL.path, extractDirectory.path], timeout: 120)
        guard result.ok else {
            throw AppUpdateError.message(result.stderr.isEmpty ? "解压安装包失败。" : result.stderr)
        }
        guard let app = findApp(in: extractDirectory) else {
            throw AppUpdateError.message("安装包中没有找到 \(appBundleName)。")
        }
        return app
    }

    private func scheduleInstallAndRestart(newAppURL: URL) throws -> URL {
        let currentAppURL = Bundle.main.bundleURL
        guard currentAppURL.pathExtension == "app" else {
            throw AppUpdateError.message("当前不是从 .app bundle 启动，无法自动安装。")
        }

        let destinationAppURL = try installDestination(for: currentAppURL)
        let destinationParent = destinationAppURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        guard FileManager.default.isWritableFile(atPath: destinationParent.path) else {
            throw AppUpdateError.message("目标安装目录不可写：\(destinationParent.path)")
        }

        let scriptURL = newAppURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("install-update.zsh")
        let logURL = DailyInspectionScheduler.supportDirectory.appendingPathComponent("self-update.log")
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = """
        #!/bin/zsh
        set -euo pipefail
        APP_PID="$1"
        DEST_APP="$2"
        NEW_APP="$3"
        WORK_DIR="$4"
        LOG_PATH="$5"
        {
          echo "[system] $(date -u +%FT%TZ) installing update"
          for i in {1..80}; do
            /bin/kill -0 "$APP_PID" 2>/dev/null || break
            /bin/sleep 0.25
          done
          /bin/mkdir -p "$(/usr/bin/dirname "$DEST_APP")"
          /bin/rm -rf "$DEST_APP"
          /usr/bin/ditto "$NEW_APP" "$DEST_APP"
          /usr/bin/xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true
          /usr/bin/open -n "$DEST_APP"
          rm -rf "$WORK_DIR"
          echo "[system] update installed to $DEST_APP"
        } >> "$LOG_PATH" 2>&1
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            scriptURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            destinationAppURL.path,
            newAppURL.path,
            scriptURL.deletingLastPathComponent().path,
            logURL.path
        ]
        try process.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
        return destinationAppURL
    }

    private func installDestination(for currentAppURL: URL) throws -> URL {
        let currentParent = currentAppURL.deletingLastPathComponent()
        if !isTranslocated(currentAppURL),
           FileManager.default.isWritableFile(atPath: currentParent.path) {
            return currentAppURL
        }

        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if FileManager.default.isWritableFile(atPath: systemApplications.path) {
            return systemApplications.appendingPathComponent(appBundleName)
        }

        let userApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: userApplications, withIntermediateDirectories: true)
        guard FileManager.default.isWritableFile(atPath: userApplications.path) else {
            throw AppUpdateError.message("无法写入 ~/Applications，请手动移动应用后再更新。")
        }
        return userApplications.appendingPathComponent(appBundleName)
    }

    private func isTranslocated(_ appURL: URL) -> Bool {
        appURL.path.contains("/AppTranslocation/")
    }

    private func makeWorkDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSoftwareStewardUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func findApp(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var fallback: URL?
        for case let url as URL in enumerator {
            guard url.pathExtension == "app" else { continue }
            if url.lastPathComponent == appBundleName {
                return url
            }
            fallback = fallback ?? url
        }
        return fallback
    }

    private var owner: String {
        Bundle.main.object(forInfoDictionaryKey: "GitHubReleaseOwner") as? String ?? "sunnyhot"
    }

    private var repo: String {
        Bundle.main.object(forInfoDictionaryKey: "GitHubReleaseRepo") as? String ?? "mac-software-steward"
    }

    private var assetName: String {
        Bundle.main.object(forInfoDictionaryKey: "GitHubReleaseAssetName") as? String ?? "MacSoftwareSteward.zip"
    }

    private var appBundleName: String {
        Bundle.main.object(forInfoDictionaryKey: "GitHubReleaseAppBundleName") as? String ?? "MacSoftwareSteward.app"
    }
}

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        var name: String
        var browserDownloadURL: String
        var size: Int

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
        }
    }

    var tagName: String
    var name: String?
    var htmlURL: String
    var body: String?
    var draft: Bool
    var prerelease: Bool
    var assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case body
        case draft
        case prerelease
        case assets
    }

    var versionString: String {
        tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    func asset(named assetName: String) -> Asset? {
        assets.first { $0.name == assetName }
    }

    var firstZipAsset: Asset? {
        assets.first { $0.name.lowercased().hasSuffix(".zip") }
    }
}

private enum AppUpdateError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
    let left = versionParts(lhs)
    let right = versionParts(rhs)
    let count = max(left.count, right.count)
    for index in 0..<count {
        let a = index < left.count ? left[index] : 0
        let b = index < right.count ? right[index] : 0
        if a > b { return .orderedDescending }
        if a < b { return .orderedAscending }
    }
    return .orderedSame
}

private func versionParts(_ version: String) -> [Int] {
    version
        .split { !$0.isNumber }
        .map { Int($0) ?? 0 }
}

/// URLSession 下载进度委托
private final class DownloadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let onProgress: (Int64, Int64, Int64) -> Void

    init(onProgress: @escaping (Int64, Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        // 错误由 async/await 处理，此处无需额外处理
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        // 上传进度，不处理
    }
}

// URLSessionDownloadDelegate 的进度回调在 extension 中实现
extension DownloadProgressDelegate: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // 文件移动由调用方处理
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)
    }
}
