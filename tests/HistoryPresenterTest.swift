import Foundation

@main
struct HistoryPresenterTest {
    static func main() {
        let dailyReport = InspectionReportRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            trigger: .dailyAgent,
            startedAt: Date(timeIntervalSince1970: 30),
            finishedAt: Date(timeIntervalSince1970: 40),
            status: .failed,
            scanSummary: InspectionScanSummary(applications: 10, brewFormulae: 2, brewCasks: 3, masApps: 1, outdated: 4, actionable: 2),
            automaticUpgrades: [],
            skippedItems: [
                InspectionSkippedRecord(packageID: "brew:formula:node", packageName: "node", reason: "需确认：检测到 major 版本变化")
            ],
            failures: [
                InspectionFailureRecord(message: "brew upgrade failed", commandDisplay: "brew upgrade node", exitCode: 1)
            ],
            inboxItemIDs: [UUID(uuidString: "00000000-0000-0000-0000-000000000301")!]
        )
        let manualReport = InspectionReportRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
            trigger: .manualRun,
            startedAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 20),
            status: .succeeded,
            scanSummary: InspectionScanSummary(applications: 1, brewFormulae: 1, brewCasks: 0, masApps: 0, outdated: 1, actionable: 1),
            automaticUpgrades: [
                InspectionPackageRecord(packageID: "brew:formula:jq", packageName: "jq", source: "Brew Formula")
            ],
            skippedItems: [],
            failures: [],
            inboxItemIDs: []
        )
        let upgradeRecord = UpgradeHistoryRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
            label: "一键升级",
            status: "完成",
            startedAt: Date(timeIntervalSince1970: 50),
            finishedAt: Date(timeIntervalSince1970: 60),
            commands: ["brew upgrade jq"],
            exitCode: 0,
            summary: "完成"
        )
        let inboxRecord = UpgradeHistoryRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000204")!,
            label: "处理待办：权限不足",
            status: "已忽略",
            startedAt: Date(timeIntervalSince1970: 70),
            finishedAt: Date(timeIntervalSince1970: 70),
            commands: [],
            exitCode: nil,
            summary: "收件箱事项已忽略：需要授予完整磁盘访问权限"
        )

        let entries = HistoryPresenter.entries(
            reports: [dailyReport, manualReport],
            records: [upgradeRecord, inboxRecord],
            kind: .all,
            status: .all,
            query: ""
        )
        precondition(entries.map(\.title) == ["处理待办：权限不足", "一键升级", "每日巡检", "手动巡检"])
        precondition(entries[0].kind == .inbox)
        precondition(entries[0].status == .ignored)
        precondition(entries[0].detailItems.contains(HistoryDetailItem(title: "处理结果", value: "已忽略", symbol: "checklist")))

        let failedInspections = HistoryPresenter.entries(
            reports: [dailyReport, manualReport],
            records: [upgradeRecord, inboxRecord],
            kind: .inspection,
            status: .failed,
            query: "node"
        )
        precondition(failedInspections.map(\.id) == ["inspection:\(dailyReport.id.uuidString)"])
        precondition(failedInspections[0].detailItems.contains(HistoryDetailItem(title: "失败", value: "brew upgrade failed", symbol: "exclamationmark.triangle")))

        let upgrades = HistoryPresenter.entries(
            reports: [dailyReport, manualReport],
            records: [upgradeRecord, inboxRecord],
            kind: .upgrade,
            status: .succeeded,
            query: "jq"
        )
        precondition(upgrades.map(\.id) == ["history:\(upgradeRecord.id.uuidString)"])
        precondition(upgrades[0].detailItems.contains(HistoryDetailItem(title: "命令", value: "brew upgrade jq", symbol: "terminal")))
    }
}
