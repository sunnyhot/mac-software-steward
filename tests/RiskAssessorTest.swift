import Foundation

@main
struct RiskAssessorTest {
    static func main() {
        let lowFormula = UpdatablePackage.brew(BrewPackage(
            id: "brew:formula:jq",
            kind: "formula",
            name: "jq",
            installedVersion: "1.6",
            currentVersion: "1.7",
            pinned: false,
            autoUpdates: false,
            outdated: true,
            upgradeable: true
        ))
        let majorFormula = UpdatablePackage.brew(BrewPackage(
            id: "brew:formula:node",
            kind: "formula",
            name: "node",
            installedVersion: "20.1.0",
            currentVersion: "21.0.0",
            pinned: false,
            autoUpdates: false,
            outdated: true,
            upgradeable: true
        ))
        let autoUpdatingCask = UpdatablePackage.brew(BrewPackage(
            id: "brew:cask:arc",
            kind: "cask",
            name: "arc",
            installedVersion: "1.0",
            currentVersion: "1.1",
            pinned: false,
            autoUpdates: true,
            outdated: true,
            upgradeable: true
        ))
        let pinned = UpdatablePackage.brew(BrewPackage(
            id: "brew:formula:ruby",
            kind: "formula",
            name: "ruby",
            installedVersion: "3.0",
            currentVersion: "3.1",
            pinned: true,
            autoUpdates: false,
            outdated: true,
            upgradeable: false
        ))
        let mas = UpdatablePackage.mas(MasApp(
            id: "mas:123",
            appId: "123",
            name: "Store App",
            installedVersion: "1.0",
            currentVersion: "1.1",
            outdated: true,
            upgradeable: true
        ))
        let staleCask = UpdatablePackage.brew(BrewPackage(
            id: "brew:cask:removed-app",
            kind: "cask",
            name: "removed-app",
            installedVersion: "1.0",
            currentVersion: "2.0",
            pinned: false,
            autoUpdates: true,
            outdated: true,
            upgradeable: true,
            expectedAppPaths: ["/Applications/Removed.app"],
            hasStaleInstallRecord: true
        ))

        let baseScan = ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: false,
            summary: ScanSummary(applications: 0, brewFormulae: 0, brewCasks: 0, masApps: 0, outdated: 0, actionable: 0, scanMs: 1),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
            brew: BrewScan(available: true, path: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew", version: "Homebrew 5", error: "", includeGreedy: false, formulae: [], casks: []),
            mas: MasScan(available: true, path: "/opt/homebrew/bin/mas", error: "", apps: [])
        )

        let low = RiskAssessor.assess(package: lowFormula, scan: baseScan, includeGreedy: false)
        precondition(low.level == .low)
        precondition(low.automationDecision == .allowAutomatic)
        precondition(low.reasons.isEmpty)

        let major = RiskAssessor.assess(package: majorFormula, scan: baseScan, includeGreedy: false)
        precondition(major.level == .high)
        precondition(major.automationDecision == .requireConfirmation)
        precondition(major.reasons.contains(.majorVersion))

        let cask = RiskAssessor.assess(package: autoUpdatingCask, scan: baseScan, includeGreedy: false)
        precondition(cask.level == .medium)
        precondition(cask.automationDecision == .requireConfirmation)
        precondition(cask.labels.contains("auto_updates"))

        let blocked = RiskAssessor.assess(package: pinned, scan: baseScan, includeGreedy: false)
        precondition(blocked.level == .high)
        precondition(blocked.automationDecision == .blockExecution)
        precondition(blocked.reasons.contains(.pinned))

        let stale = RiskAssessor.assess(package: staleCask, scan: baseScan, includeGreedy: true)
        precondition(stale.level == .high)
        precondition(stale.automationDecision == .blockExecution)
        precondition(stale.reasons.contains(.staleInstallRecord))

        var missingMasScan = baseScan
        missingMasScan.mas = MasScan(available: false, path: "", error: "missing", apps: [])
        let blockedMas = RiskAssessor.assess(package: mas, scan: missingMasScan, includeGreedy: false)
        precondition(blockedMas.automationDecision == .blockExecution)
        precondition(blockedMas.labels.contains("mas unavailable"))
    }
}
