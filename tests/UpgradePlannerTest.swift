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

        // 一键升级的选包语义：makePlan 后 filter(\.canExecute) 必须只保留可执行包，
        // 排除被固定(notSelectable)、策略跳过(notSelected 但 canExecute=true 仍会被纳入)、
        // 以及高风险被阻断(notSelectable)的项。这是 upgradeAllExecutable 的核心契约：
        // 它把 canExecute 集合作为单次批量任务入队。
        let autoFormula = BrewPackage(
            id: "brew:formula:jq",
            kind: "formula",
            name: "jq",
            installedVersion: "1.6",
            currentVersion: "1.7",
            pinned: false,
            autoUpdates: false,
            outdated: true,
            upgradeable: true
        )
        let pinnedFormula = BrewPackage(
            id: "brew:formula:locked",
            kind: "formula",
            name: "locked",
            installedVersion: "1.0",
            currentVersion: "2.0",
            pinned: true,
            autoUpdates: false,
            outdated: true,
            upgradeable: false
        )
        let greedyCask = BrewPackage(
            id: "brew:cask:greedy",
            kind: "cask",
            name: "greedy",
            installedVersion: "1.0",
            currentVersion: "2.0",
            pinned: false,
            autoUpdates: true,
            outdated: true,
            upgradeable: false
        )
        let upgradeAllScan = ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: false,
            summary: ScanSummary(applications: 0, brewFormulae: 2, brewCasks: 1, masApps: 0, outdated: 3, actionable: 1, scanMs: 1),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
            brew: BrewScan(
                available: true,
                path: "/opt/homebrew/bin/brew",
                prefix: "/opt/homebrew",
                version: "Homebrew 5",
                error: "",
                includeGreedy: false,
                formulae: [autoFormula, pinnedFormula],
                casks: [greedyCask]
            ),
            mas: MasScan(available: false, path: "", error: "", apps: [])
        )
        let upgradeAllStore = UpgradePolicyStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("upgrade-all-\(UUID().uuidString).json"))
        let upgradeAllRows = UpgradePlanner.makePlan(scan: upgradeAllScan, policyStore: upgradeAllStore, includeGreedy: false)
        let executable = upgradeAllRows.filter(\.canExecute)
        // 只有低风险、可自动执行的 jq 进入选包集合；固定的 locked 和高风险 greedy cask 被排除。
        precondition(executable.map(\.packageID) == [autoFormula.id], "一键升级应只选可执行包，实际：\(executable.map(\.packageID))")
        precondition(executable.contains { $0.packageID == pinnedFormula.id } == false, "固定包不得进入一键升级")
        precondition(executable.contains { $0.packageID == greedyCask.id } == false, "高风险 cask 不得进入一键升级")
    }
}
