import AppKit
import Foundation
import CryptoKit

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
    @Published var releaseAssetName = ""
    @Published var releaseAssetSizeText = ""
    @Published var releasePublishedAtText = ""
    @Published var updateAvailable = false
    /// 是否显示应用更新弹框
    @Published var showUpdateDialog = false
    @Published var progress = ""
    /// 下载进度百分比（0.0 ~ 1.0），nil 表示未在下载或无法获取
    @Published var downloadFraction: Double? = nil
    /// 已下载字节数（人类可读，如 "1.2 MB"）
    @Published var downloadedSizeText: String? = nil
    /// 下载总大小（人类可读，如 "3.1 MB"）
    @Published var totalDownloadSizeText: String? = nil
    /// 下载速度（人类可读，如 "3.5 MB/s"）
    @Published var downloadSpeedText: String? = nil
    /// 最近一次下载/安装失败的用户可读错误信息；nil 表示无失败
    @Published var updateErrorMessage: String? = nil
    /// 失败版本记忆：当某个 (version, sha256) 校验/安装失败后记下，命中则跳过自动下载以打破循环。
    /// 手动触发更新不受此限制。出现新版本时自动失效。
    @Published var failedUpdateMemory: AppUpdateFailureMemory? {
        didSet {
            if let memory = failedUpdateMemory {
                if let data = try? JSONEncoder().encode(memory) {
                    UserDefaults.standard.set(data, forKey: Self.failedUpdateMemoryKey)
                }
            } else {
                UserDefaults.standard.removeObject(forKey: Self.failedUpdateMemoryKey)
            }
        }
    }

    private var latestRelease: GitHubRelease?
    private let session: URLSession
    private let downloadStrategiesProvider: () async -> [DownloadAccelerationStrategy]
    private let acceleratedDownloadRunner: AcceleratedDownloader.Runner?
    private var periodicTask: Task<Void, Never>?
    private var lastCheckTime: Date?

    private static let automaticChecksKey = "AppUpdateAutomaticChecksEnabled"
    private static let automaticDownloadsKey = "AppUpdateAutomaticDownloadsEnabled"
    /// 失败版本记忆持久化 key（存储 JSON 编码的 AppUpdateFailureMemory）
    private static let failedUpdateMemoryKey = "AppUpdateFailedMemory"
    private static let checkInterval: TimeInterval = 4 * 3600

    /// 静态 manifest 下载地址（latest.json）
    private var manifestURL: String {
        "https://github.com/\(owner)/\(repo)/releases/latest/download/latest.json"
    }

    init(
        session: URLSession = .shared,
        downloadStrategiesProvider: @escaping () async -> [DownloadAccelerationStrategy] = DownloadAccelerationPolicy.defaultStrategies,
        acceleratedDownloadRunner: AcceleratedDownloader.Runner? = nil
    ) {
        self.session = session
        self.downloadStrategiesProvider = downloadStrategiesProvider
        self.acceleratedDownloadRunner = acceleratedDownloadRunner
        self.automaticChecksEnabled = UserDefaults.standard.object(forKey: Self.automaticChecksKey) as? Bool ?? true
        self.automaticDownloadsEnabled = UserDefaults.standard.object(forKey: Self.automaticDownloadsKey) as? Bool ?? true
        if let data = UserDefaults.standard.data(forKey: Self.failedUpdateMemoryKey),
           let memory = try? JSONDecoder().decode(AppUpdateFailureMemory.self, from: data) {
            self.failedUpdateMemory = memory
        }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Mac 软件管家"
    }

    var downloadStatusText: String {
        if let fraction = downloadFraction {
            let percent = "\(Int(fraction * 100))%"
            let downloaded = downloadedSizeText ?? ""
            let total = totalDownloadSizeText ?? releaseAssetSizeText
            if !downloaded.isEmpty, !total.isEmpty {
                return "正在下载... \(percent)  \(downloaded) / \(total)"
            }
            return "正在下载... \(percent)"
        }
        if let downloaded = downloadedSizeText {
            let total = totalDownloadSizeText ?? releaseAssetSizeText
            if !total.isEmpty {
                return "正在下载... \(downloaded) / \(total)"
            }
            return "正在下载... \(downloaded)"
        }
        return progress.isEmpty ? "正在准备..." : progress
    }

    func autoCheckIfNeeded() async {
        guard automaticChecksEnabled else { return }
        await checkForUpdates(automatic: true)
        startPeriodicCheck()
    }

    func checkForUpdates(automatic: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        progress = ""
        updateErrorMessage = nil
        if !automatic {
            status = "正在检查更新..."
        }

        do {
            let release = try await fetchLatestRelease()
            latestRelease = release
            latestVersion = release.versionString
            releaseURL = release.htmlURL
            releaseNotes = release.body ?? ""
            let displayAsset = release.asset(named: assetName) ?? release.firstZipAsset
            releaseAssetName = displayAsset?.name ?? assetName
            releaseAssetSizeText = Self.fileSizeText(displayAsset?.size ?? 0)
            releasePublishedAtText = Self.displayDateTime(from: release.publishedAt)
            updateAvailable = compareVersions(release.versionString, currentVersion) == .orderedDescending
            lastCheckTime = Date()
            // 失败记忆失效：当前 release 与记忆中的 (version, sha256) 不一致（新版本或同版本已重新打包），
            // 说明那是一个新的、尚未失败过的产物，清除记忆以恢复自动下载。
            if let memory = failedUpdateMemory,
               !memory.shouldSkipAutoDownload(version: release.versionString, sha256: displayAsset?.expectedSHA256 ?? "") {
                failedUpdateMemory = nil
            }
            status = updateAvailable
                ? "发现新版本 \(release.versionString)。"
                : "当前已是最新版本 \(currentVersion)。"
            if updateAvailable {
                if HomebrewSelfInstallDetector.isManaged() {
                    // 2026-09-02:brew 管理——只提示,不弹安装弹窗、不自动下载覆盖。
                    status = "发现新版本 \(release.versionString)。本应用由 Homebrew 管理，请运行 brew upgrade 更新。"
                } else {
                    showUpdateDialog = true
                }
            }
        } catch {
            if !automatic {
                status = "检查更新失败：\(error.localizedDescription)"
            }
        }

        isChecking = false

        if automatic, updateAvailable, automaticDownloadsEnabled, !HomebrewSelfInstallDetector.isManaged() {
            // 命中失败版本记忆则跳过自动下载，打破坏 release 导致的无限重下循环。
            // 手动点击"检查更新/下载并重启"不受此限制（manual 路径不会进入这里）。
            if let memory = failedUpdateMemory,
               let asset = latestRelease?.asset(named: assetName) ?? latestRelease?.firstZipAsset,
               memory.shouldSkipAutoDownload(version: latestVersion, sha256: asset.expectedSHA256) {
                status = "版本 \(latestVersion) 自动更新已暂停：上次安装失败，可手动重试。"
                return
            }
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
        if HomebrewSelfInstallDetector.isManaged() {
            // 2026-09-02:brew 管理兜底——任何入口触发的自更新都不覆盖安装。
            status = "本应用由 Homebrew 管理，请运行 brew upgrade 更新；应用内覆盖安装已停用。"
            updateErrorMessage = nil
            return
        }
        guard let release = latestRelease else {
            status = "请先检查更新。"
            return
        }
        guard let asset = release.asset(named: assetName) ?? release.firstZipAsset else {
            status = "Release 中没有找到 \(assetName) 或 .zip 安装包。"
            return
        }

        isInstalling = true
        updateErrorMessage = nil
        downloadFraction = nil
        downloadedSizeText = nil
        totalDownloadSizeText = releaseAssetSizeText.isEmpty ? nil : releaseAssetSizeText
        downloadSpeedText = nil
        progress = "正在连接下载 \(asset.name)..."

        do {
            let downloaded = try await download(asset: asset)
            downloadFraction = nil
            progress = "正在校验安装包..."
            try AppUpdateSecurity.verifySHA256(fileURL: downloaded, expectedSHA256: asset.expectedSHA256)
            progress = "正在解压安装包..."
            let extractedApp = try await extractApp(from: downloaded)
            progress = "正在准备重启并安装..."
            let destination = try scheduleInstallAndRestart(newAppURL: extractedApp)
            updateErrorMessage = nil
            status = "安装脚本已启动，将安装到 \(destination.path) 并重启。"
        } catch {
            let friendlyMessage = Self.friendlyUpdateErrorMessage(from: error)
            updateErrorMessage = friendlyMessage
            status = "安装更新失败：\(friendlyMessage)"
            progress = ""
            isInstalling = false
            downloadFraction = nil
            downloadedSizeText = nil
            totalDownloadSizeText = nil
            downloadSpeedText = nil
            // 记录失败版本记忆：命中同一 (version, sha256) 的后续自动检查将跳过下载，
            // 避免坏 release（如校验和与实际资产不符）触发无限重下。手动更新不受影响。
            failedUpdateMemory = AppUpdateFailureMemory(
                version: release.versionString,
                sha256: asset.expectedSHA256,
                failedAt: Date()
            )
            // 自动下载失败时打开更新弹窗让用户看到失败原因
            showUpdateDialog = true
        }
    }

    // MARK: - 静态 manifest 获取

    /// 从 latest.json 静态 manifest 读取最新版本信息。
    /// 不再调用 GitHub REST API，不受 API 速率限制。

    private static func fileSizeText(_ bytes: Int) -> String {
        guard bytes > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private static func displayDateTime(from isoString: String?) -> String {
        guard let isoString, !isoString.isEmpty else { return "" }
        let fractionalParser = ISO8601DateFormatter()
        fractionalParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fractionalParser.date(from: isoString) ?? {
            let parser = ISO8601DateFormatter()
            parser.formatOptions = [.withInternetDateTime]
            return parser.date(from: isoString)
        }()
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// 将底层错误转换为用户可理解的更新失败描述
    private static func friendlyUpdateErrorMessage(from error: Error) -> String {
        let nsError = error as NSError
        let domain = nsError.domain
        let code = nsError.code
        let description = error.localizedDescription

        // 网络相关错误
        if domain == NSURLErrorDomain {
            switch code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorTimedOut:
                return "网络连接失败，请检查网络后重试。"
            case NSURLErrorCancelled:
                return "下载已被取消。"
            default:
                break
            }
        }

        // AppUpdateError.message 已是用户友好的
        if let updateError = error as? AppUpdateError {
            return updateError.localizedDescription
        }

        // 兜底：截断过长的技术信息
        if description.count > 100 {
            return String(description.prefix(100)) + "…"
        }
        return description
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        guard let url = URL(string: manifestURL) else {
            throw AppUpdateError.message("Manifest URL 无效。")
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // 禁用缓存，确保每次拿到最新 manifest
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AppUpdateError.message("获取 latest.json 失败（HTTP \(statusCode)）。")
        }

        let manifest = try JSONDecoder().decode(LatestManifest.self, from: data)

        // 转换为 GitHubRelease 以保持下游逻辑不变
        return GitHubRelease(
            tagName: manifest.tag,
            name: manifest.tag,
            htmlURL: manifest.htmlURL,
            body: manifest.notes,
            draft: false,
            prerelease: false,
            assets: [
                GitHubRelease.Asset(
                    name: manifest.asset,
                    browserDownloadURL: manifest.downloadURL,
                    size: manifest.size ?? 0,
                    expectedSHA256: manifest.sha256
                )
            ],
            publishedAt: manifest.publishedAt
        )
    }

    private func download(asset: GitHubRelease.Asset) async throws -> URL {
        try await downloadReleaseAssetForSelfUpdate(
            assetName: asset.name,
            downloadURLString: asset.browserDownloadURL,
            size: asset.size
        )
    }

    func downloadReleaseAssetForSelfUpdate(
        assetName: String,
        downloadURLString: String,
        size: Int
    ) async throws -> URL {
        let request = try AppUpdateDownloadPresenter.request(
            assetName: assetName,
            downloadURLString: downloadURLString,
            size: size
        )
        let workDirectory = try makeWorkDirectory()
        let destination = workDirectory.appendingPathComponent(assetName)
        let strategies = await downloadStrategiesProvider()
        let downloadedFile = try await AcceleratedDownloader.download(
            request,
            strategies: strategies,
            runner: acceleratedDownloadRunner,
            onProgress: { [weak self] downloadProgress in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let presentation = AppUpdateDownloadPresenter.presentation(
                        for: downloadProgress,
                        assetName: assetName
                    )
                    self.progress = presentation.progressText
                    self.downloadFraction = presentation.fraction
                    self.downloadedSizeText = presentation.downloadedSizeText
                    self.totalDownloadSizeText = presentation.totalDownloadSizeText
                    self.downloadSpeedText = presentation.downloadSpeedText
                }
            },
            onStatus: { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.progress = status
                }
            }
        )

        guard FileManager.default.fileExists(atPath: downloadedFile.path) else {
            throw AppUpdateError.message("下载文件保存失败：临时文件不存在。")
        }
        try FileManager.default.moveItem(at: downloadedFile, to: destination)
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
        let logURL = selfUpdateSupportDirectory.appendingPathComponent("self-update.log")
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SelfUpdateInstallScript.content.write(to: scriptURL, atomically: true, encoding: .utf8)
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

    private var selfUpdateSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacSoftwareSteward", isDirectory: true)
    }
}

// MARK: - 静态 Manifest 模型

/// latest.json 的数据结构，由 Release workflow 自动生成。
/// 包含：version, tag, asset, sha256, notes, download_url, html_url, size, published_at
private struct LatestManifest: Decodable {
    var version: String
    var tag: String
    var asset: String
    var sha256: String
    var notes: String
    var downloadURL: String
    var htmlURL: String
    var size: Int?
    var publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case version, tag, asset, sha256, notes, size
        case downloadURL = "download_url"
        case htmlURL = "html_url"
        case publishedAt = "published_at"
    }
}

// MARK: - GitHub Release 模型（保留，供内部使用）

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        var name: String
        var browserDownloadURL: String
        var size: Int
        var expectedSHA256: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
            case expectedSHA256 = "sha256"
        }
    }

    var tagName: String
    var name: String?
    var htmlURL: String
    var body: String?
    var draft: Bool
    var prerelease: Bool
    var assets: [Asset]
    var publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case body
        case draft
        case prerelease
        case assets
        case publishedAt = "published_at"
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
