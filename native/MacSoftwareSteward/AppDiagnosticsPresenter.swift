import Foundation

struct AppDiagnosticDetailItem: Hashable {
    var title: String
    var value: String
    var symbol: String
}

struct AppDiagnosticRow: Identifiable, Equatable {
    var id: String { appID }
    var appID: String
    var appName: String
    var detectorTitle: String
    var stateTitle: String
    var reasonTitle: String
    var summary: String
    var diagnostic: String
    var feedURLString: String
    var actionHint: String
    var detailItems: [AppDiagnosticDetailItem]
    var severity: InboxSeverity
}

enum AppDiagnosticsPresenter {
    static func rows(from apps: [AppItem]) -> [AppDiagnosticRow] {
        apps.compactMap(row)
    }

    static func row(from app: AppItem) -> AppDiagnosticRow? {
        let capability = app.updateCapability
        let summary = trimmed(capability.summary)
        let diagnostic = trimmed(capability.diagnostic)
        let feedURLString = trimmed(capability.feedURLString)

        guard shouldShowDiagnostics(
            app: app,
            capability: capability,
            summary: summary,
            diagnostic: diagnostic,
            feedURLString: feedURLString
        ) else {
            return nil
        }

        return AppDiagnosticRow(
            appID: app.id,
            appName: app.name,
            detectorTitle: capability.detector.title,
            stateTitle: stateTitle(for: app.updateState),
            reasonTitle: reasonTitle(app: app, diagnostic: diagnostic),
            summary: displaySummary(summary, detector: capability.detector),
            diagnostic: diagnostic.isEmpty ? "暂无诊断细节。" : diagnostic,
            feedURLString: feedURLString,
            actionHint: actionHint(app: app, capability: capability, diagnostic: diagnostic),
            detailItems: detailItems(app: app, capability: capability, feedURLString: feedURLString),
            severity: severity(for: app)
        )
    }

    private static func shouldShowDiagnostics(
        app: AppItem,
        capability: AppUpdateCapability,
        summary: String,
        diagnostic: String,
        feedURLString: String
    ) -> Bool {
        if capability.detector != .none { return true }
        if !summary.isEmpty || !diagnostic.isEmpty || !feedURLString.isEmpty { return true }
        if app.updateState == "outdated" { return true }
        if app.updateState == "checkable" { return true }
        if app.managedBy == "manual",
           app.updateState == "unknown",
           app.source != "Apple",
           !app.path.hasPrefix("/System/") {
            return true
        }
        return false
    }

    private static func displaySummary(_ summary: String, detector: AppUpdateDetectorKind) -> String {
        if !summary.isEmpty { return summary }
        if detector == .none { return "未发现可执行更新器信息。" }
        return "\(detector.title) 暂无概要。"
    }

    private static func stateTitle(for state: String) -> String {
        switch state {
        case "outdated":
            return "可更新"
        case "checkable":
            return "可检查"
        case "current":
            return "已是最新"
        case "unknown":
            return "未知"
        case "":
            return "未判定"
        default:
            return state
        }
    }

    private static func severity(for app: AppItem) -> InboxSeverity {
        if isUpdateSourceIssue(app.updateCapability.diagnostic) {
            return .warning
        }
        if app.updateState == "outdated" {
            return .warning
        }
        return .info
    }

    private static func reasonTitle(app: AppItem, diagnostic: String) -> String {
        if isUpdateSourceIssue(diagnostic) {
            return "更新源异常"
        }
        if app.updateState == "outdated", !trimmed(app.availableVersion).isEmpty {
            return "发现新版本"
        }
        if app.updateState == "checkable" || app.updateState == "unknown" || trimmed(app.availableVersion).isEmpty {
            return "无法确认版本"
        }
        return "可手动检查"
    }

    private static func actionHint(
        app: AppItem,
        capability: AppUpdateCapability,
        diagnostic: String
    ) -> String {
        if isUpdateSourceIssue(diagnostic) {
            return "检查网络或更新源状态；必要时打开应用内更新器或在 Finder 中定位后手动处理。"
        }
        if app.updateState == "outdated" {
            return "已有可用版本信息；普通 App 不会静默替换，请打开应用或更新器完成升级。"
        }
        if capability.detector == .none {
            return "未发现可用更新源；可打开 Finder 定位应用，进入应用菜单手动确认版本。"
        }
        if capability.actions.contains(where: { $0.kind == .openUpdater }) {
            return "打开更新器或应用，使用厂商提供的更新流程确认版本。"
        }
        return "打开应用，使用应用内更新入口确认版本。"
    }

    private static func detailItems(
        app: AppItem,
        capability: AppUpdateCapability,
        feedURLString: String
    ) -> [AppDiagnosticDetailItem] {
        var items: [AppDiagnosticDetailItem] = [
            AppDiagnosticDetailItem(title: "管理方式", value: app.managedBy.isEmpty ? "未知" : app.managedBy, symbol: "tag"),
            AppDiagnosticDetailItem(title: "识别器", value: capability.detector.title, symbol: "scope"),
            AppDiagnosticDetailItem(title: "置信度", value: confidenceTitle(capability.confidence), symbol: "gauge.with.dots.needle.50percent")
        ]

        let installedVersion = trimmed(capability.installedVersion).isEmpty ? trimmed(app.version) : trimmed(capability.installedVersion)
        items.append(AppDiagnosticDetailItem(title: "安装版本", value: installedVersion.isEmpty ? "未知" : installedVersion, symbol: "number"))

        let availableVersion = trimmed(app.availableVersion)
        if !availableVersion.isEmpty {
            items.append(AppDiagnosticDetailItem(title: "可用版本", value: availableVersion, symbol: "arrow.up.circle"))
        } else {
            items.append(AppDiagnosticDetailItem(title: "可用版本", value: "无法确认", symbol: "questionmark.circle"))
        }

        if !feedURLString.isEmpty {
            items.append(AppDiagnosticDetailItem(title: "Appcast Feed", value: feedURLString, symbol: "link"))
        }
        if !app.source.isEmpty {
            items.append(AppDiagnosticDetailItem(title: "来源", value: app.source, symbol: "shippingbox"))
        }
        return items
    }

    private static func confidenceTitle(_ confidence: DetectionConfidence) -> String {
        switch confidence {
        case .none:
            return "无"
        case .low:
            return "低"
        case .medium:
            return "中"
        case .high:
            return "高"
        }
    }

    private static func isUpdateSourceIssue(_ diagnostic: String) -> Bool {
        let text = diagnostic.lowercased()
        return text.contains("http 状态码")
            || text.contains("无效")
            || text.contains("检查失败")
            || text.contains("未找到可用版本")
            || text.contains("parse")
            || text.contains("解析")
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
