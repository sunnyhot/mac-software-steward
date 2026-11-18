import Foundation

@main
struct SmartMaintenancePolicyTest {
    static func main() {
        let stale = BrewPackage(
            id: "brew:cask:stale",
            kind: "cask",
            name: "stale",
            installedVersion: "1",
            currentVersion: "2",
            pinned: false,
            autoUpdates: true,
            outdated: true,
            upgradeable: true,
            expectedAppPaths: ["/Applications/Stale.app"],
            hasStaleInstallRecord: true
        )
        let selfUpdating = BrewPackage(
            id: "brew:cask:self",
            kind: "cask",
            name: "self",
            installedVersion: "1",
            currentVersion: "2",
            pinned: false,
            autoUpdates: true,
            outdated: true,
            upgradeable: true
        )
        let scan = ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: true,
            summary: ScanSummary(applications: 0, brewFormulae: 0, brewCasks: 2, masApps: 0, outdated: 2, actionable: 2, scanMs: 1),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
            brew: BrewScan(available: true, path: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew", version: "Homebrew 5", error: "", includeGreedy: true, formulae: [], casks: [stale, selfUpdating]),
            mas: MasScan(available: false, path: "", error: "", apps: [])
        )

        precondition(SmartMaintenancePolicy.canReconcileStaleRecords(scan: scan))
        var incompleteScan = scan
        incompleteScan.brew.metadataComplete = false
        precondition(!SmartMaintenancePolicy.canReconcileStaleRecords(scan: incompleteScan))
        incompleteScan = scan
        incompleteScan.brew.available = false
        precondition(!SmartMaintenancePolicy.canReconcileStaleRecords(scan: incompleteScan))
        incompleteScan = scan
        incompleteScan.brew.uncheckedCasks = ["unknown"]
        precondition(!SmartMaintenancePolicy.canReconcileStaleRecords(scan: incompleteScan))
        incompleteScan = scan
        incompleteScan.brew.error = "metadata failed"
        precondition(!SmartMaintenancePolicy.canReconcileStaleRecords(scan: incompleteScan))

        precondition(SmartMaintenancePolicy.shouldDeferToSelfUpdater(.brew(selfUpdating)))
        precondition(!SmartMaintenancePolicy.shouldDeferToSelfUpdater(.brew(stale)), "Stale records are cleanup work, not self-updates")

        var profile = AutomationProfile.manualDefault
        profile.dailyInspectionEnabled = true
        profile.lowRiskAutoUpgradeEnabled = true
        profile.autoRepairPolicy = .allowLowRisk
        precondition(SmartMaintenancePolicy.automaticStaleCleanupCandidates(scan: scan, profile: profile).map(\.id) == [stale.id])

        profile.dailyInspectionEnabled = false
        precondition(SmartMaintenancePolicy.automaticStaleCleanupCandidates(scan: scan, profile: profile).isEmpty)
        profile.dailyInspectionEnabled = true
        profile.lowRiskAutoUpgradeEnabled = false
        precondition(SmartMaintenancePolicy.automaticStaleCleanupCandidates(scan: scan, profile: profile).isEmpty)
        profile.lowRiskAutoUpgradeEnabled = true
        profile.autoRepairPolicy = .manualOnly
        precondition(SmartMaintenancePolicy.automaticStaleCleanupCandidates(scan: scan, profile: profile).isEmpty)

        profile.autoRepairPolicy = .allowLowRisk
        let updated = SmartMaintenancePolicy.removingCasks(packageIDs: [stale.id], from: scan)
        precondition(updated.brew.casks.map(\.id) == [selfUpdating.id])
        precondition(updated.summary.brewCasks == 1)
        precondition(updated.summary.outdated == 1)
        precondition(updated.summary.actionable == 1)
        precondition(updated.performance.brewCasks == 1)
        precondition(updated.performance.outdated == 1)
        precondition(updated.performance.actionable == 1)
        let unchanged = SmartMaintenancePolicy.removingCasks(packageIDs: ["missing"], from: scan)
        precondition(unchanged.brew.casks == scan.brew.casks)
        precondition(unchanged.summary.actionable == scan.summary.actionable)
        precondition(unchanged.summary.outdated == scan.summary.outdated)
    }
}
