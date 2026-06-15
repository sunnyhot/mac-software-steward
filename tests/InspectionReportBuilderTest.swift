import Foundation

@main
struct InspectionReportBuilderTest {
    static func main() {
        let formula = BrewPackage(id: "brew:formula:jq", kind: "formula", name: "jq", installedVersion: "1", currentVersion: "2", pinned: false, autoUpdates: false, outdated: true, upgradeable: true)
        let risky = BrewPackage(id: "brew:formula:node", kind: "formula", name: "node", installedVersion: "20", currentVersion: "21", pinned: false, autoUpdates: false, outdated: true, upgradeable: true)
        let scan = ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: false,
            summary: ScanSummary(applications: 3, brewFormulae: 2, brewCasks: 0, masApps: 0, outdated: 2, actionable: 2, scanMs: 10),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
            brew: BrewScan(available: true, path: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew", version: "Homebrew", error: "", includeGreedy: false, formulae: [formula, risky], casks: []),
            mas: MasScan(available: true, path: "/opt/homebrew/bin/mas", error: "", apps: [])
        )
        let rows = [
            UpgradePlanRow(packageID: formula.id, packageName: formula.name, source: "Brew Formula", installedVersion: "1", currentVersion: "2", commandDisplay: "brew upgrade jq", policy: .automatic, selection: .selected, riskLabels: [], skipReason: "", package: .brew(formula), riskLevel: .low, riskSummary: "", automationDecision: .allowAutomatic),
            UpgradePlanRow(packageID: risky.id, packageName: risky.name, source: "Brew Formula", installedVersion: "20", currentVersion: "21", commandDisplay: "brew upgrade node", policy: .automatic, selection: .notSelected, riskLabels: ["major version"], skipReason: "需确认：检测到 major 版本变化", package: .brew(risky), riskLevel: .high, riskSummary: "检测到 major 版本变化", automationDecision: .requireConfirmation)
        ]

        let inboxID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let report = InspectionReportBuilder.makeReport(
            trigger: .dailyAgent,
            startedAt: Date(timeIntervalSince1970: 100),
            finishedAt: Date(timeIntervalSince1970: 200),
            scan: scan,
            rows: rows,
            automaticPackages: [.brew(formula)],
            inboxItemIDs: [inboxID],
            failure: InspectionFailureRecord(message: "command failed", commandDisplay: "brew upgrade jq", exitCode: 1)
        )

        precondition(report.status == .failed)
        precondition(report.scanSummary.applications == 3)
        precondition(report.automaticUpgrades.map(\.packageID) == [formula.id])
        precondition(report.skippedItems.map(\.packageID) == [risky.id])
        precondition(report.skippedItems[0].reason == "需确认：检测到 major 版本变化")
        precondition(report.failures.first?.exitCode == 1)
        precondition(report.inboxItemIDs == [inboxID])
    }
}
