import Foundation

@main
struct UpgradePlannerTest {
    static func main() {
        let formula = BrewPackage(
            id: "brew:formula:node",
            kind: "formula",
            name: "node",
            installedVersion: "1.0",
            currentVersion: "2.0",
            pinned: false,
            autoUpdates: false,
            outdated: true,
            upgradeable: true
        )
        let pinned = BrewPackage(
            id: "brew:formula:ruby",
            kind: "formula",
            name: "ruby",
            installedVersion: "3.0",
            currentVersion: "3.1",
            pinned: true,
            autoUpdates: false,
            outdated: true,
            upgradeable: false
        )
        let cask = BrewPackage(
            id: "brew:cask:warp",
            kind: "cask",
            name: "warp",
            installedVersion: "1.0",
            currentVersion: "2.0",
            pinned: false,
            autoUpdates: true,
            outdated: true,
            upgradeable: false
        )
        let mas = MasApp(
            id: "mas:123",
            appId: "123",
            name: "Store App",
            installedVersion: "1.0",
            currentVersion: "2.0",
            outdated: true,
            upgradeable: true
        )
        let scan = ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: true,
            summary: ScanSummary(applications: 0, brewFormulae: 2, brewCasks: 1, masApps: 1, outdated: 4, actionable: 2, scanMs: 1),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
            brew: BrewScan(available: true, path: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew", version: "Homebrew 5", error: "brew warning", includeGreedy: true, formulae: [formula, pinned], casks: [cask]),
            mas: MasScan(available: false, path: "", error: "mas missing", apps: [mas])
        )
        let store = UpgradePolicyStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("planner-\(UUID().uuidString).json"))
        store.set(.skip, forPackageID: formula.id)

        let rows = UpgradePlanner.makePlan(scan: scan, policyStore: store, includeGreedy: true)
        let formulaRow = rows.first { $0.packageID == formula.id }
        let pinnedRow = rows.first { $0.packageID == pinned.id }
        let caskRow = rows.first { $0.packageID == cask.id }
        let masRow = rows.first { $0.packageID == mas.id }

        precondition(formulaRow?.selection == .notSelected)
        precondition(formulaRow?.skipReason == "策略设置为跳过")
        precondition(formulaRow?.riskLevel == .high)
        precondition(pinnedRow?.riskLabels.contains("pinned") == true)
        precondition(pinnedRow?.selection == .notSelectable)
        precondition(pinnedRow?.automationDecision == .blockExecution)
        precondition(caskRow?.riskLabels.contains("greedy cask") == true)
        precondition(caskRow?.riskLabels.contains("auto_updates") == true)
        precondition(caskRow?.selection == .notSelected)
        precondition(caskRow?.automationDecision == .requireConfirmation)
        precondition(caskRow?.skipReason.hasPrefix("需确认") == true)
        precondition(masRow?.riskLabels.contains("mas unavailable") == true)
        precondition(masRow?.selection == .notSelectable)
        precondition(masRow?.automationDecision == .blockExecution)
    }
}
