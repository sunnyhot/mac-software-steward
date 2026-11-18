import Foundation

@main
struct DailyInspectionStatusPresenterTest {
    static func main() {
        let runtime = DailyInspectionRuntimeStatus(isLoaded: true, lastExitCode: nil)
        let success = report(status: .succeeded, failures: 0)
        let automatic = DailyInspectionStatusPresenter.make(
            health: .healthy,
            runtime: runtime,
            latestReport: success,
            automaticUpgradeEnabled: true,
            hour: 11,
            minute: 0
        )
        precondition(automatic.title == "运行正常 · 自动处理")
        precondition(automatic.detail.contains("11:00"))
        precondition(automatic.detail.contains("26"))
        precondition(automatic.tone == .normal)

        let reminder = DailyInspectionStatusPresenter.make(
            health: .healthy,
            runtime: runtime,
            latestReport: success,
            automaticUpgradeEnabled: false,
            hour: 9,
            minute: 30
        )
        precondition(reminder.title == "运行正常 · 仅提醒")
        precondition(reminder.detail.contains("09:30"))

        let failed = DailyInspectionStatusPresenter.make(
            health: .healthy,
            runtime: runtime,
            latestReport: report(status: .failed, failures: 2),
            automaticUpgradeEnabled: true,
            hour: 11,
            minute: 0
        )
        precondition(failed.title == "最近巡检失败")
        precondition(failed.detail.contains("2 项失败"))
        precondition(failed.tone == .warning)

        let runtimeFailure = DailyInspectionStatusPresenter.make(
            health: .healthy,
            runtime: DailyInspectionRuntimeStatus(isLoaded: true, lastExitCode: 7),
            latestReport: success,
            automaticUpgradeEnabled: true,
            hour: 11,
            minute: 0
        )
        precondition(runtimeFailure.title == "最近巡检失败")
        precondition(runtimeFailure.detail.contains("7"))
        precondition(runtimeFailure.tone == .warning)

        let waiting = DailyInspectionStatusPresenter.make(
            health: .healthy,
            runtime: runtime,
            latestReport: nil,
            automaticUpgradeEnabled: false,
            hour: 11,
            minute: 0
        )
        precondition(waiting.title == "等待巡检 · 仅提醒")
        precondition(waiting.detail.contains("不会自动升级"))

        let repair = DailyInspectionStatusPresenter.make(
            health: .needsRepair("LaunchAgent 尚未加载。"),
            runtime: DailyInspectionRuntimeStatus(isLoaded: false, lastExitCode: nil),
            latestReport: success,
            automaticUpgradeEnabled: true,
            hour: 11,
            minute: 0
        )
        precondition(repair.title == "需要修复")
        precondition(repair.tone == .warning)

        let disabled = DailyInspectionStatusPresenter.make(
            health: .disabled,
            runtime: DailyInspectionRuntimeStatus(isLoaded: false, lastExitCode: nil),
            latestReport: success,
            automaticUpgradeEnabled: false,
            hour: 9,
            minute: 0
        )
        precondition(disabled.title == "未启用")
        precondition(disabled.tone == .normal)
    }

    private static func report(status: InspectionReportStatus, failures: Int) -> InspectionReportRecord {
        InspectionReportRecord(
            id: UUID(),
            trigger: .dailyAgent,
            startedAt: Date(timeIntervalSince1970: 100),
            finishedAt: Date(timeIntervalSince1970: 128),
            status: status,
            scanSummary: InspectionScanSummary(
                applications: 400,
                brewFormulae: 80,
                brewCasks: 18,
                masApps: 3,
                outdated: 30,
                actionable: 26
            ),
            automaticUpgrades: [],
            skippedItems: [],
            failures: (0..<failures).map {
                InspectionFailureRecord(message: "failure \($0)", commandDisplay: "brew upgrade test", exitCode: 1)
            },
            inboxItemIDs: []
        )
    }
}
