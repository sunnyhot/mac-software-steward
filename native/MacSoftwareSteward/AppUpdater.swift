import AppKit
import Foundation

@MainActor
final class AppUpdateModel: ObservableObject {
    @Published var automaticChecksEnabled: Bool {
        didSet {
            UserDefaults.standard.set(automaticChecksEnabled, forKey: Self.automaticChecksKey)
        }
    }
    @Published var isChecking = false
    @Published var isInstalling = false
    @Published var status = "尚未检查更新。"
    @Published var latestVersion = ""
    @Published var releaseURL = ""
    @Published var releaseNotes = ""
    @Published var updateAvailable = false
    @Published var progress = ""

    private var latestRelease: GitHubRelease?
    private let session: URLSession

    private static let automaticChecksKey = "AppUpdateAutomaticChecksEnabled"

    init(session: URLSession = .shared) {
        self.session = session
        self.automaticChecksEnabled = UserDefaults.standard.object(forKey: Self.automaticChecksKey) as? Bool ?? true
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
            status = updateAvailable
                ? "发现新版本 \(release.versionString)。"
                : "当前已是最新版本 \(currentVersion)。"
        } catch {
            if !automatic {
                status = "检查更新失败：\(error.localizedDescription)"
            }
        }

        isChecking = false
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
        progress = "正在下载 \(asset.name)..."

        do {
            let downloaded = try await download(asset: asset)
            progress = "正在解压安装包..."
            let extractedApp = try await extractApp(from: downloaded)
            progress = "正在准备重启并安装..."
            try scheduleInstallAndRestart(newAppURL: extractedApp)
            status = "安装脚本已启动，应用即将重启。"
        } catch {
            status = "安装更新失败：\(error.localizedDescription)"
            progress = ""
            isInstalling = false
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
            throw AppUpdateError.message("无法读取 GitHub Release。请确认仓库 \(repositoryName) 可访问。")
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func download(asset: GitHubRelease.Asset) async throws -> URL {
        guard let url = URL(string: asset.browserDownloadURL) else {
            throw AppUpdateError.message("Release asset 下载地址无效。")
        }
        let workDirectory = try makeWorkDirectory()
        let destination = workDirectory.appendingPathComponent(asset.name)
        let (temporaryURL, response) = try await session.download(from: url)
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

    private func scheduleInstallAndRestart(newAppURL: URL) throws {
        let currentAppURL = Bundle.main.bundleURL
        guard currentAppURL.pathExtension == "app" else {
            throw AppUpdateError.message("当前不是从 .app bundle 启动，无法自动安装。")
        }
        let parentDirectory = currentAppURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parentDirectory.path) else {
            throw AppUpdateError.message("应用所在目录不可写，无法自动替换：\(parentDirectory.path)")
        }

        let scriptURL = newAppURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("install-update.zsh")
        let logURL = DailyInspectionScheduler.supportDirectory.appendingPathComponent("self-update.log")
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = """
        #!/bin/zsh
        set -euo pipefail
        APP_PATH="$1"
        NEW_APP="$2"
        WORK_DIR="$3"
        LOG_PATH="$4"
        {
          echo "[system] $(date -u +%FT%TZ) installing update"
          sleep 1.5
          rm -rf "$APP_PATH"
          /usr/bin/ditto "$NEW_APP" "$APP_PATH"
          /usr/bin/xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true
          /usr/bin/open -n "$APP_PATH"
          rm -rf "$WORK_DIR"
          echo "[system] update installed"
        } >> "$LOG_PATH" 2>&1
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            scriptURL.path,
            currentAppURL.path,
            newAppURL.path,
            scriptURL.deletingLastPathComponent().path,
            logURL.path
        ]
        try process.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
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
