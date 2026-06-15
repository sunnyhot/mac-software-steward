import Foundation

struct AppDiagnosticRow: Identifiable, Equatable {
    var id: String { appID }
    var appID: String
    var appName: String
    var detectorTitle: String
    var stateTitle: String
    var summary: String
    var diagnostic: String
    var feedURLString: String
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
            summary: displaySummary(summary, detector: capability.detector),
            diagnostic: diagnostic.isEmpty ? "暂无诊断细节。" : diagnostic,
            feedURLString: feedURLString,
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
        if app.updateState == "outdated" {
            return .warning
        }
        return .info
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
