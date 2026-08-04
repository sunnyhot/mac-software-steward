import Darwin
import Foundation

struct DailyInspectionConfig {
    var enabled: Bool
    var hour: Int
    var minute: Int
    var includeGreedy: Bool
    var runBrewUpdate: Bool
    var installedHelperPath: String
    var health: DailyInspectionHealth
    var launchAgentPath: String
    var logPath: String

    var isOperational: Bool {
        enabled && health == .healthy
    }
}

struct DailyInspectionRuntimeStatus: Equatable {
    var isLoaded: Bool
    var lastExitCode: Int32?
}

enum DailyInspectionHealth: Equatable {
    case disabled
    case healthy
    case needsRepair(String)

    var title: String {
        switch self {
        case .disabled:
            return "未启用"
        case .healthy:
            return "配置正常"
        case .needsRepair:
            return "需要修复"
        }
    }

    var detail: String {
        switch self {
        case .disabled:
            return "每日巡检当前未启用。"
        case .healthy:
            return "后台程序与当前应用版本一致。"
        case .needsRepair(let reason):
            return reason
        }
    }
}

enum DailyInspectionScheduler {
    static let label = "local.codex.MacSoftwareSteward.daily"

    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacSoftwareSteward", isDirectory: true)
    }

    static var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    static var launchAgentURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(label).plist")
    }

    static var logURL: URL {
        supportDirectory.appendingPathComponent("daily-inspection.log")
    }

    static func helperPath(in bundleURL: URL = Bundle.main.bundleURL) -> String {
        bundleURL
            .appendingPathComponent("Contents/MacOS/MacSoftwareStewardAgent")
            .path
    }

    /// 开发构建从仓库启动时，优先沿用 /Applications 中的正式版本，避免把每日任务
    /// 绑定到会被下一次构建清空的临时目录。
    static func preferredHelperPath(in bundleURL: URL = Bundle.main.bundleURL) -> String {
        let bundledHelper = helperPath(in: bundleURL)
        let applicationsHelper = "/Applications/MacSoftwareSteward.app/Contents/MacOS/MacSoftwareStewardAgent"
        let bundleIsInstalled = bundleURL.standardizedFileURL.path.hasPrefix("/Applications/")
        if !bundleIsInstalled, FileManager.default.isExecutableFile(atPath: applicationsHelper) {
            return applicationsHelper
        }
        return bundledHelper
    }

    static func currentConfig(expectedHelperPath: String = preferredHelperPath()) -> DailyInspectionConfig {
        let plistExists = FileManager.default.fileExists(atPath: launchAgentURL.path)
        let data = try? Data(contentsOf: launchAgentURL)
        return config(
            plistData: data,
            plistExists: plistExists,
            expectedHelperPath: expectedHelperPath
        )
    }

    static func config(
        plistData: Data?,
        plistExists: Bool,
        expectedHelperPath: String,
        isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)
    ) -> DailyInspectionConfig {
        var hour = 9
        var minute = 0
        var arguments: [String] = []

        if let data = plistData,
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            if let calendar = plist["StartCalendarInterval"] as? [String: Any] {
                hour = calendar["Hour"] as? Int ?? hour
                minute = calendar["Minute"] as? Int ?? minute
            }
            arguments = plist["ProgramArguments"] as? [String] ?? []
        }

        let installedHelperPath = arguments.first ?? ""
        let health: DailyInspectionHealth
        if !plistExists {
            health = .disabled
        } else if installedHelperPath.isEmpty {
            health = .needsRepair("巡检配置不完整，未找到后台程序路径。")
        } else if !isExecutable(installedHelperPath) {
            health = .needsRepair("原后台程序已不存在，需要切换到当前应用版本。")
        } else if standardizedPath(installedHelperPath) != standardizedPath(expectedHelperPath) {
            health = .needsRepair("后台程序仍指向旧版应用，需要更新为当前版本。")
        } else {
            health = .healthy
        }

        return DailyInspectionConfig(
            enabled: plistExists,
            hour: hour,
            minute: minute,
            includeGreedy: arguments.contains("--greedy"),
            runBrewUpdate: arguments.contains("--brew-update"),
            installedHelperPath: installedHelperPath,
            health: health,
            launchAgentPath: launchAgentURL.path,
            logPath: logURL.path
        )
    }

    /// 修复应用移动、升级或 LaunchAgent 未加载导致的巡检失效。
    /// 保留用户已经保存的时间和高级选项，只替换为当前 bundle 内的 helper。
    @discardableResult
    static func repairIfNeeded(currentHelperPath: String = preferredHelperPath()) async throws -> Bool {
        let config = currentConfig(expectedHelperPath: currentHelperPath)
        guard config.enabled else { return false }

        let loaded = await CommandRunner.run(
            "/bin/launchctl",
            arguments: ["print", "\(launchDomain)/\(label)"],
            timeout: 10
        ).ok
        guard config.health != .healthy || !loaded else { return false }

        try await install(
            hour: config.hour,
            minute: config.minute,
            includeGreedy: config.includeGreedy,
            runBrewUpdate: config.runBrewUpdate,
            helperPath: currentHelperPath
        )
        return true
    }

    static func runtimeStatus() async -> DailyInspectionRuntimeStatus {
        let result = await CommandRunner.run(
            "/bin/launchctl",
            arguments: ["print", "\(launchDomain)/\(label)"],
            timeout: 10
        )
        return parseRuntimeStatus(output: result.stdout, isLoaded: result.ok)
    }

    static func parseRuntimeStatus(output: String, isLoaded: Bool) -> DailyInspectionRuntimeStatus {
        let pattern = #"last exit code\s*=\s*(-?\d+)"#
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        let match = try? NSRegularExpression(pattern: pattern).firstMatch(in: output, range: range)
        let code: Int32?
        if let match,
           let valueRange = Range(match.range(at: 1), in: output) {
            code = Int32(output[valueRange])
        } else {
            code = nil
        }
        return DailyInspectionRuntimeStatus(isLoaded: isLoaded, lastExitCode: code)
    }

    static func install(
        hour: Int,
        minute: Int,
        includeGreedy: Bool,
        runBrewUpdate: Bool,
        helperPath: String
    ) async throws {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw StewardError.message("巡检时间无效。")
        }
        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            throw StewardError.message("未找到后台巡检 helper，请先重新构建原生应用。")
        }

        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }

        var arguments = [
            helperPath,
            "daily-check",
            "--auto-upgrade"
        ]
        if includeGreedy {
            arguments.append("--greedy")
        }
        if runBrewUpdate {
            arguments.append("--brew-update")
        }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": arguments,
            "StartCalendarInterval": [
                "Hour": hour,
                "Minute": minute
            ],
            "RunAtLoad": false,
            "StandardOutPath": logURL.path,
            "StandardErrorPath": logURL.path,
            "EnvironmentVariables": [
                "PATH": CommandRunner.defaultPath,
                "LC_ALL": "en_US.UTF-8",
                "LANG": "en_US.UTF-8"
            ]
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: launchAgentURL, options: .atomic)

        _ = await CommandRunner.run("/bin/launchctl", arguments: ["bootout", launchDomain, launchAgentURL.path], timeout: 10)
        let result = await CommandRunner.run("/bin/launchctl", arguments: ["bootstrap", launchDomain, launchAgentURL.path], timeout: 10)
        guard result.ok else {
            throw StewardError.message(result.stderr.isEmpty ? "启用每日巡检失败。" : result.stderr)
        }
    }

    static func uninstall() async throws {
        _ = await CommandRunner.run("/bin/launchctl", arguments: ["bootout", launchDomain, launchAgentURL.path], timeout: 10)
        if FileManager.default.fileExists(atPath: launchAgentURL.path) {
            try FileManager.default.removeItem(at: launchAgentURL)
        }
    }

    static func recentLog(maxBytes: Int = 60_000) -> String {
        guard let handle = try? FileHandle(forReadingFrom: logURL) else {
            return ""
        }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let offset = fileSize > UInt64(maxBytes) ? fileSize - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static var launchDomain: String {
        "gui/\(getuid())"
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
