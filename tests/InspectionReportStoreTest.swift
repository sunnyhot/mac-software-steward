import Foundation

@main
struct InspectionReportStoreTest {
    static func main() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("inspection-reports-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = InspectionReportRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            trigger: .dailyAgent,
            startedAt: Date(timeIntervalSince1970: 1),
            finishedAt: Date(timeIntervalSince1970: 2),
            status: .succeeded,
            scanSummary: InspectionScanSummary(applications: 10, brewFormulae: 2, brewCasks: 3, masApps: 4, outdated: 5, actionable: 6),
            automaticUpgrades: [
                InspectionPackageRecord(packageID: "brew:formula:jq", packageName: "jq", source: "Brew Formula")
            ],
            skippedItems: [],
            failures: [],
            inboxItemIDs: []
        )
        let second = InspectionReportRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            trigger: .manualRun,
            startedAt: Date(timeIntervalSince1970: 3),
            finishedAt: Date(timeIntervalSince1970: 4),
            status: .failed,
            scanSummary: InspectionScanSummary(applications: 1, brewFormulae: 1, brewCasks: 1, masApps: 1, outdated: 1, actionable: 1),
            automaticUpgrades: [],
            skippedItems: [
                InspectionSkippedRecord(packageID: "brew:formula:node", packageName: "node", reason: "需确认：检测到 major 版本变化")
            ],
            failures: [
                InspectionFailureRecord(message: "brew upgrade failed", commandDisplay: "brew upgrade jq", exitCode: 1)
            ],
            inboxItemIDs: []
        )

        let store = InspectionReportStore(fileURL: url, limit: 1)
        precondition(store.reports.isEmpty)
        store.append(first)
        store.append(second)
        precondition(store.reports.map(\.id) == [second.id])

        let reloaded = InspectionReportStore(fileURL: url, limit: 5)
        precondition(reloaded.reports.count == 1)
        precondition(reloaded.reports[0].status == .failed)
        precondition(reloaded.reports[0].failures[0].exitCode == 1)

        reloaded.clear()
        precondition(reloaded.reports.isEmpty)
    }
}
