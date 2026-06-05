import Foundation

struct HomebrewDownloadSnapshot: Equatable {
    var fileURL: URL
    var byteCount: Int64
    var expectedByteCount: Int64?
    var updatedAt: Date
    var speedBytesPerSecond: Double?

    var downloadFraction: Double? {
        guard let expectedByteCount, expectedByteCount > 0 else { return nil }
        return min(max(Double(byteCount) / Double(expectedByteCount), 0), 1)
    }

    var downloadSizeText: String {
        let downloaded = HomebrewDownloadMonitor.formatBytes(byteCount)
        guard let expectedByteCount, expectedByteCount > byteCount else { return downloaded }
        return "\(downloaded) / \(HomebrewDownloadMonitor.formatBytes(expectedByteCount))"
    }

    var downloadSpeedText: String? {
        guard let speedBytesPerSecond else { return nil }
        guard speedBytesPerSecond > 0 else { return "等待网络" }
        return "\(HomebrewDownloadMonitor.formatBytes(Int64(speedBytesPerSecond)))/s"
    }

    var downloadTimeRemainingText: String? {
        guard let expectedByteCount,
              let speedBytesPerSecond,
              speedBytesPerSecond > 0,
              expectedByteCount > byteCount else { return nil }
        let seconds = Double(expectedByteCount - byteCount) / speedBytesPerSecond
        return "剩余 \(HomebrewDownloadMonitor.formatDuration(seconds))"
    }

    var detailText: String {
        if let speedBytesPerSecond, speedBytesPerSecond <= 0 {
            return "正在下载，等待网络响应"
        }
        return "正在下载（Homebrew 缓存）"
    }
}

enum HomebrewDownloadMonitor {
    static func downloadsDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let cache = environment["HOMEBREW_CACHE"], !cache.isEmpty {
            return URL(fileURLWithPath: cache, isDirectory: true).appendingPathComponent("downloads", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Homebrew/downloads", isDirectory: true)
    }

    static func snapshot(
        packageName: String,
        in directory: URL = downloadsDirectory(),
        previous: HomebrewDownloadSnapshot?,
        now: Date = Date(),
        expectedByteCountHint: Int64? = nil,
        fileManager: FileManager = .default
    ) throws -> HomebrewDownloadSnapshot? {
        let candidates = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.lastPathComponent.hasSuffix(".incomplete") }
        .filter { matches(fileName: $0.lastPathComponent, packageName: packageName) }

        guard !candidates.isEmpty else { return nil }
        let selected = candidates.first { $0 == previous?.fileURL } ?? newestFile(in: candidates)
        let byteCount = fileSize(of: selected, fileManager: fileManager)
        let expectedByteCount = expectedSize(
            forIncompleteFile: selected,
            byteCount: byteCount,
            hint: expectedByteCountHint,
            fileManager: fileManager
        )
        let speed = speedBytesPerSecond(for: selected, byteCount: byteCount, previous: previous, now: now)

        return HomebrewDownloadSnapshot(
            fileURL: selected,
            byteCount: byteCount,
            expectedByteCount: expectedByteCount,
            updatedAt: now,
            speedBytesPerSecond: speed
        )
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func formatDuration(_ seconds: Double) -> String {
        let rounded = max(Int(seconds.rounded(.up)), 1)
        if rounded < 60 { return "\(rounded) 秒" }

        let minutes = Int(ceil(Double(rounded) / 60.0))
        if minutes < 60 { return "\(minutes) 分钟" }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours < 24 {
            return remainingMinutes == 0 ? "\(hours) 小时" : "\(hours) 小时 \(remainingMinutes) 分钟"
        }

        let days = hours / 24
        let remainingHours = hours % 24
        return remainingHours == 0 ? "\(days) 天" : "\(days) 天 \(remainingHours) 小时"
    }

    static func canApplySnapshot(toPhase phaseText: String) -> Bool {
        ["", "执行命令", "准备下载", "下载中", "安装中"].contains(phaseText)
    }

    private static func newestFile(in urls: [URL]) -> URL {
        urls.max { lhs, rhs in
            modificationDate(of: lhs) < modificationDate(of: rhs)
        } ?? urls[0]
    }

    private static func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func fileSize(of url: URL, fileManager: FileManager) -> Int64 {
        guard let size = try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber else { return 0 }
        return size.int64Value
    }

    private static func expectedSize(forIncompleteFile url: URL, byteCount: Int64, hint: Int64?, fileManager: FileManager) -> Int64? {
        let incompleteSuffix = ".incomplete"
        guard url.path.hasSuffix(incompleteSuffix) else { return nil }
        let completePath = String(url.path.dropLast(incompleteSuffix.count))
        let completeSize = fileSize(of: URL(fileURLWithPath: completePath), fileManager: fileManager)
        if completeSize > byteCount { return completeSize }
        if let hint, hint > byteCount { return hint }
        return nil
    }

    private static func speedBytesPerSecond(
        for url: URL,
        byteCount: Int64,
        previous: HomebrewDownloadSnapshot?,
        now: Date
    ) -> Double? {
        guard let previous, previous.fileURL == url else { return nil }
        let interval = now.timeIntervalSince(previous.updatedAt)
        guard interval > 0 else { return nil }
        return max(Double(byteCount - previous.byteCount) / interval, 0)
    }

    private static func matches(fileName: String, packageName: String) -> Bool {
        let normalizedFileName = normalized(fileName)
        let normalizedPackageName = normalized(packageName)
        guard !normalizedPackageName.isEmpty else { return false }
        if normalizedFileName.contains(normalizedPackageName) { return true }

        let parts = normalizedPackageName.split(separator: "-").filter { $0.count > 1 }
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { normalizedFileName.contains($0) }
    }

    private static func normalized(_ text: String) -> String {
        let scalars = text.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        return String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
    }
}
