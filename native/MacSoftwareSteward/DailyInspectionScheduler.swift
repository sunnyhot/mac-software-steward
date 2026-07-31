import Darwin
import Foundation

struct DailyInspectionConfig {
    var enabled: Bool
    var hour: Int
    var minute: Int
    var launchAgentPath: String
    var logPath: String
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

    static func currentConfig() -> DailyInspectionConfig {
        var hour = 9
        var minute = 0

        if let data = try? Data(contentsOf: launchAgentURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let calendar = plist["StartCalendarInterval"] as? [String: Any] {
            hour = calendar["Hour"] as? Int ?? hour
            minute = calendar["Minute"] as? Int ?? minute
        }

        return DailyInspectionConfig(
            enabled: FileManager.default.fileExists(atPath: launchAgentURL.path),
            hour: hour,
            minute: minute,
            launchAgentPath: launchAgentURL.path,
            logPath: logURL.path
        )
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
}
