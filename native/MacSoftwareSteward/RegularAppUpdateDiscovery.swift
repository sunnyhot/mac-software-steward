import Foundation

enum RegularAppUpdateDiscovery {
    static func discover(appPath: String) -> AppUpdateCapability {
        let plistURL = URL(fileURLWithPath: appPath)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")

        guard
            let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            return .none
        }

        return discover(plist: plist)
    }

    static func discover(plist: [String: Any]) -> AppUpdateCapability {
        let bundleID = string(plist["CFBundleIdentifier"]).lowercased()
        let version = string(plist["CFBundleShortVersionString"])

        if let feedURL = sparkleFeedURL(from: plist) {
            return AppUpdateCapability(
                detector: .sparkle,
                confidence: .high,
                feedURLString: feedURL,
                installedVersion: version,
                summary: "可通过 Sparkle 检查更新",
                diagnostic: "Info.plist 声明了 Sparkle appcast。"
            )
        }

        if bundleID == "com.google.chrome" || bundleID.hasPrefix("com.google.chrome.") {
            return vendorCapability(.chromeKeystone, version: version, summary: "可通过 Chrome 内置更新器检查")
        }
        if bundleID.hasPrefix("com.adobe.") {
            return vendorCapability(.adobeUpdater, version: version, summary: "可通过 Adobe 更新器检查")
        }
        if bundleID.hasPrefix("com.jetbrains.") {
            return vendorCapability(.jetBrainsToolbox, version: version, summary: "可通过 JetBrains Toolbox 或应用内更新检查")
        }
        if bundleID.hasPrefix("com.microsoft.") {
            return vendorCapability(.microsoftAutoUpdate, version: version, summary: "可通过 Microsoft AutoUpdate 检查")
        }
        if containsUpdaterHint(plist) {
            return AppUpdateCapability(
                detector: .unknownUpdater,
                confidence: .medium,
                feedURLString: "",
                installedVersion: version,
                summary: "检测到内置更新相关配置",
                diagnostic: "Info.plist 中存在 update/appcast 相关键。"
            )
        }

        return .none
    }

    private static func vendorCapability(
        _ detector: AppUpdateDetectorKind,
        version: String,
        summary: String
    ) -> AppUpdateCapability {
        AppUpdateCapability(
            detector: detector,
            confidence: .high,
            feedURLString: "",
            installedVersion: version,
            summary: summary,
            diagnostic: "根据 bundle identifier 识别为 \(detector.title) 更新家族。"
        )
    }

    private static func sparkleFeedURL(from plist: [String: Any]) -> String? {
        for key in ["SUFeedURL", "SUFeedURLForSparkle", "SUAppcastURL"] {
            let value = string(plist[key]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("http://") || value.hasPrefix("https://") {
                return value
            }
        }
        return nil
    }

    private static func containsUpdaterHint(_ plist: [String: Any]) -> Bool {
        plist.contains { key, value in
            let lowerKey = key.lowercased()
            guard lowerKey.contains("update") || lowerKey.contains("appcast") else {
                return false
            }
            return !string(value).isEmpty
        }
    }

    private static func string(_ value: Any?) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return ""
        }
    }
}
