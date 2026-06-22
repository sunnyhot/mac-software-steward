import Foundation

enum ManualAppReplacementArchiveKind: Equatable {
    case zip
    case dmg
}

enum ManualAppReplacementError: LocalizedError, Equatable {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message):
            return message
        }
    }
}

enum ManualAppReplacementInstaller {
    static func archiveKind(for fileURL: URL) -> ManualAppReplacementArchiveKind? {
        switch fileURL.pathExtension.lowercased() {
        case "zip":
            return .zip
        case "dmg":
            return .dmg
        default:
            return nil
        }
    }

    static func findApp(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let url as URL in enumerator where url.pathExtension == "app" {
            return url
        }
        return nil
    }

    static func validateReplacement(existingAppURL: URL, newAppURL: URL) throws {
        guard existingAppURL.pathExtension == "app", newAppURL.pathExtension == "app" else {
            throw ManualAppReplacementError.message("直接替换只支持 .app 应用包。")
        }

        let existingBundleID = Bundle(url: existingAppURL)?.bundleIdentifier ?? ""
        let newBundleID = Bundle(url: newAppURL)?.bundleIdentifier ?? ""
        if !existingBundleID.isEmpty,
           !newBundleID.isEmpty,
           existingBundleID != newBundleID {
            throw ManualAppReplacementError.message("下载包的应用标识不一致，已停止替换。")
        }
    }

    static func replace(existingAppURL: URL, with newAppURL: URL) throws {
        let fileManager = FileManager.default
        let parent = existingAppURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: existingAppURL.path) else {
            throw ManualAppReplacementError.message("原应用不存在：\(existingAppURL.path)")
        }
        guard fileManager.isWritableFile(atPath: parent.path) else {
            throw ManualAppReplacementError.message("目标目录不可写：\(parent.path)")
        }

        let backupURL = parent.appendingPathComponent(
            ".\(existingAppURL.deletingPathExtension().lastPathComponent).backup-\(UUID().uuidString).app",
            isDirectory: true
        )

        try fileManager.moveItem(at: existingAppURL, to: backupURL)
        do {
            try fileManager.copyItem(at: newAppURL, to: existingAppURL)
            try? fileManager.removeItem(at: backupURL)
        } catch {
            try? fileManager.removeItem(at: existingAppURL)
            try? fileManager.moveItem(at: backupURL, to: existingAppURL)
            throw error
        }
    }

    static func mountPoint(fromHdiutilOutput output: String) -> URL? {
        output
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let tabParts = line.split(separator: "\t", omittingEmptySubsequences: true)
                if let last = tabParts.last, last.hasPrefix("/Volumes/") {
                    return String(last)
                }
                guard let range = line.range(of: "/Volumes/") else { return nil }
                return String(line[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .first
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
}
