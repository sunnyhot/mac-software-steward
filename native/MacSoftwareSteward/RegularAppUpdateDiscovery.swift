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
                actions: actions(for: .sparkle),
                diagnostic: "Info.plist 声明了 Sparkle appcast。"
            )
        }

        if let vendorCapability = vendorCapability(plist: plist, bundleID: bundleID, version: version) {
            return vendorCapability
        }
        if containsUpdaterHint(plist) {
            return AppUpdateCapability(
                detector: .unknownUpdater,
                confidence: .medium,
                feedURLString: "",
                installedVersion: version,
                summary: "检测到内置更新相关配置",
                actions: actions(for: .unknownUpdater),
                diagnostic: "Info.plist 中存在 update/appcast 相关键。"
            )
        }

        return .none
    }

    private static func vendorCapability(
        plist: [String: Any],
        bundleID: String,
        version: String
    ) -> AppUpdateCapability? {
        if bundleID == "com.google.chrome" || bundleID.hasPrefix("com.google.chrome.") {
            return vendorCapability(
                .chromeKeystone,
                version: version,
                confidence: .high,
                summary: "可通过 Chrome Keystone 检查更新",
                evidence: ["bundle identifier \(bundleID)"]
            )
        }
        if let evidence = chromeKeystoneEvidence(in: plist) {
            return vendorCapability(
                .chromeKeystone,
                version: version,
                confidence: .medium,
                summary: "检测到 Chrome Keystone 更新元数据",
                evidence: evidence
            )
        }

        if bundleID.hasPrefix("com.adobe.") {
            return vendorCapability(
                .adobeUpdater,
                version: version,
                confidence: .high,
                summary: "可通过 Adobe 更新器检查",
                evidence: ["bundle identifier \(bundleID)"]
            )
        }
        if let evidence = adobeUpdaterEvidence(in: plist) {
            return vendorCapability(
                .adobeUpdater,
                version: version,
                confidence: .medium,
                summary: "检测到 Adobe 更新器元数据",
                evidence: evidence
            )
        }

        if bundleID.hasPrefix("com.jetbrains.") {
            return vendorCapability(
                .jetBrainsToolbox,
                version: version,
                confidence: .high,
                summary: "可通过 JetBrains Toolbox 或应用内更新检查",
                evidence: ["bundle identifier \(bundleID)"]
            )
        }
        if let evidence = jetBrainsEvidence(in: plist) {
            return vendorCapability(
                .jetBrainsToolbox,
                version: version,
                confidence: .medium,
                summary: "检测到 JetBrains Toolbox 更新元数据",
                evidence: evidence
            )
        }

        if bundleID.hasPrefix("com.microsoft.") {
            return vendorCapability(
                .microsoftAutoUpdate,
                version: version,
                confidence: .high,
                summary: "可通过 Microsoft AutoUpdate 检查",
                evidence: ["bundle identifier \(bundleID)"]
            )
        }
        if let evidence = microsoftAutoUpdateEvidence(in: plist) {
            return vendorCapability(
                .microsoftAutoUpdate,
                version: version,
                confidence: .medium,
                summary: "检测到 Microsoft AutoUpdate 元数据",
                evidence: evidence
            )
        }

        return nil
    }

    private static func vendorCapability(
        _ detector: AppUpdateDetectorKind,
        version: String,
        confidence: DetectionConfidence,
        summary: String,
        evidence: [String]
    ) -> AppUpdateCapability {
        AppUpdateCapability(
            detector: detector,
            confidence: confidence,
            feedURLString: "",
            installedVersion: version,
            summary: summary,
            actions: actions(for: detector),
            diagnostic: "\(detector.title) 识别证据：\(evidence.joined(separator: "、"))。"
        )
    }

    private static func actions(for detector: AppUpdateDetectorKind) -> [AppUpdateAction] {
        switch detector {
        case .adobeUpdater, .jetBrainsToolbox, .microsoftAutoUpdate:
            return [
                AppUpdateAction(kind: .openUpdater, title: "打开更新器", systemImage: "arrow.down.app"),
                AppUpdateAction(kind: .openApp, title: "打开应用", systemImage: "play.circle"),
                AppUpdateAction(kind: .revealInFinder, title: "Finder", systemImage: "arrow.up.forward.app")
            ]
        case .sparkle, .chromeKeystone, .unknownUpdater:
            return [
                AppUpdateAction(kind: .openApp, title: "打开应用", systemImage: "play.circle"),
                AppUpdateAction(kind: .revealInFinder, title: "Finder", systemImage: "arrow.up.forward.app")
            ]
        case .none:
            return []
        }
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

    private static func chromeKeystoneEvidence(in plist: [String: Any]) -> [String]? {
        let evidence = plist.compactMap { key, value -> String? in
            let lowerKey = key.lowercased()
            let lowerValue = string(value).lowercased()
            if lowerKey.hasPrefix("ks") || lowerKey.contains("keystone") {
                return key
            }
            if lowerValue.contains("keystone") || lowerValue.contains("tools.google.com/service/update") {
                return key
            }
            return nil
        }
        return nonEmptyEvidence(evidence)
    }

    private static func adobeUpdaterEvidence(in plist: [String: Any]) -> [String]? {
        let evidence = plist.compactMap { key, value -> String? in
            let lowerKey = key.lowercased()
            let lowerValue = string(value).lowercased()
            if lowerKey.contains("adobe") && lowerKey.contains("update") {
                return key
            }
            if lowerValue.contains("adobe updater")
                || lowerValue.contains("creative cloud")
                || lowerValue.contains("aam") {
                return key
            }
            return nil
        }
        return nonEmptyEvidence(evidence)
    }

    private static func jetBrainsEvidence(in plist: [String: Any]) -> [String]? {
        let evidence = plist.compactMap { key, value -> String? in
            let lowerKey = key.lowercased()
            let lowerValue = string(value).lowercased()
            if lowerKey.contains("jetbrains") || lowerValue.contains("jetbrains toolbox") {
                return key
            }
            return nil
        }
        return nonEmptyEvidence(evidence)
    }

    private static func microsoftAutoUpdateEvidence(in plist: [String: Any]) -> [String]? {
        let evidence = plist.compactMap { key, value -> String? in
            let lowerKey = key.lowercased()
            let lowerValue = string(value).lowercased()
            if lowerKey.hasPrefix("mau") || lowerKey.contains("microsoftautoupdate") {
                return key
            }
            if lowerValue.contains("microsoft autoupdate") || lowerValue.contains("microsoft auto update") {
                return key
            }
            return nil
        }
        return nonEmptyEvidence(evidence)
    }

    private static func nonEmptyEvidence(_ evidence: [String]) -> [String]? {
        let uniqueEvidence = Array(Set(evidence)).sorted()
        return uniqueEvidence.isEmpty ? nil : uniqueEvidence
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
