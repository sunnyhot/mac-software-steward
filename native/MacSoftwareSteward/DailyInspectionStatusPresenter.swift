import Foundation

enum DailyInspectionStatusTone: Equatable {
    case normal
    case warning
}

struct DailyInspectionStatusPresentation: Equatable {
    var title: String
    var detail: String
    var symbol: String
    var tone: DailyInspectionStatusTone
}

/// 合并 launchd 的当前运行状态与持久化巡检报告。
/// 重新 bootstrap 会清空 launchctl 的 lastExitCode，因此仅靠 runtime 会把
/// “今天已经成功运行”误显示成“等待首次巡检”。
enum DailyInspectionStatusPresenter {
    static func make(
        health: DailyInspectionHealth,
        runtime: DailyInspectionRuntimeStatus,
        latestReport: InspectionReportRecord?,
        automaticUpgradeEnabled: Bool,
        hour: Int,
        minute: Int
    ) -> DailyInspectionStatusPresentation {
        let schedule = String(format: "%02d:%02d", hour, minute)
        let mode = automaticUpgradeEnabled ? "自动处理" : "仅提醒"

        if case .needsRepair = health {
            return DailyInspectionStatusPresentation(
                title: health.title,
                detail: "\(health.detail) 计划时间：每天 \(schedule)。",
                symbol: "exclamationmark.triangle.fill",
                tone: .warning
            )
        }

        if health == .disabled {
            return DailyInspectionStatusPresentation(
                title: health.title,
                detail: health.detail,
                symbol: "minus.circle",
                tone: .normal
            )
        }

        if let code = runtime.lastExitCode, code != 0 {
            return DailyInspectionStatusPresentation(
                title: "最近巡检失败",
                detail: "最近一次退出码为 \(code) · 每天 \(schedule) · 当前\(mode)",
                symbol: "exclamationmark.circle.fill",
                tone: .warning
            )
        }

        if let latestReport {
            let finishedAt = latestReport.finishedAt.formatted(date: .abbreviated, time: .shortened)
            if latestReport.status == .failed {
                return DailyInspectionStatusPresentation(
                    title: "最近巡检失败",
                    detail: "\(finishedAt) · \(latestReport.failures.count) 项失败 · 每天 \(schedule) · 当前\(mode)",
                    symbol: "exclamationmark.circle.fill",
                    tone: .warning
                )
            }
            return DailyInspectionStatusPresentation(
                title: "运行正常 · \(mode)",
                detail: "最近完成 \(finishedAt) · 发现 \(latestReport.scanSummary.actionable) 项 · 每天 \(schedule)",
                symbol: "checkmark.circle.fill",
                tone: .normal
            )
        }

        if runtime.lastExitCode == 0 {
            return DailyInspectionStatusPresentation(
                title: "运行正常 · \(mode)",
                detail: "最近一次巡检已完成 · 每天 \(schedule)",
                symbol: "checkmark.circle.fill",
                tone: .normal
            )
        }

        return DailyInspectionStatusPresentation(
            title: "等待巡检 · \(mode)",
            detail: automaticUpgradeEnabled
                ? "每天 \(schedule) 扫描，并自动处理符合条件的项目。"
                : "每天 \(schedule) 扫描；当前只提醒，不会自动升级。",
            symbol: "clock.circle",
            tone: .normal
        )
    }
}
