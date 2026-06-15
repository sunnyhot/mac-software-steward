import Foundation

@main
struct DailyInspectionInboxPublisherTest {
    static func main() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("daily-inspection-inbox-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = InboxStore(fileURL: url)
        let risky = UpgradePlanRow(
            packageID: "brew:formula:node",
            packageName: "node",
            source: "Brew Formula",
            installedVersion: "20.1.0",
            currentVersion: "21.0.0",
            commandDisplay: "brew upgrade node",
            policy: .automatic,
            selection: .notSelected,
            riskLabels: ["major version"],
            skipReason: "需确认：major version",
            package: .brew(BrewPackage(id: "brew:formula:node", kind: "formula", name: "node", installedVersion: "20.1.0", currentVersion: "21.0.0", pinned: false, autoUpdates: false, outdated: true, upgradeable: true)),
            riskLevel: .high,
            riskSummary: "major version",
            automationDecision: .requireConfirmation
        )
        let lowRisk = UpgradePlanRow(
            packageID: "brew:formula:jq",
            packageName: "jq",
            source: "Brew Formula",
            installedVersion: "1.6",
            currentVersion: "1.7",
            commandDisplay: "brew upgrade jq",
            policy: .automatic,
            selection: .selected,
            riskLabels: [],
            skipReason: "",
            package: .brew(BrewPackage(id: "brew:formula:jq", kind: "formula", name: "jq", installedVersion: "1.6", currentVersion: "1.7", pinned: false, autoUpdates: false, outdated: true, upgradeable: true)),
            riskLevel: .low,
            riskSummary: "",
            automationDecision: .allowAutomatic
        )
        let app = AppItem(
            id: "app:/Applications/Sparkle.app",
            name: "Sparkle",
            version: "1.0",
            availableVersion: "2.0",
            path: "/Applications/Sparkle.app",
            source: "Developer",
            obtainedFrom: "Identified Developer",
            architecture: "arm64",
            managedBy: "manual",
            updateState: "outdated",
            relatedPackageID: "",
            updateCapability: AppUpdateCapability(
                detector: .sparkle,
                confidence: .high,
                feedURLString: "https://example.com/appcast.xml",
                installedVersion: "1.0",
                summary: "Sparkle 发现新版本 2.0",
                diagnostic: "ok"
            )
        )
        let scan = ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: false,
            summary: ScanSummary(applications: 1, brewFormulae: 2, brewCasks: 0, masApps: 0, outdated: 2, actionable: 2, scanMs: 10),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: [app]),
            brew: BrewScan(available: true, path: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew", version: "Homebrew", error: "", includeGreedy: false, formulae: [], casks: []),
            mas: MasScan(available: true, path: "/opt/homebrew/bin/mas", error: "", apps: [])
        )

        let firstIDs = DailyInspectionInboxPublisher.publish(scan: scan, rows: [risky, lowRisk], to: store)
        precondition(firstIDs.count == 2)
        precondition(Set(store.items.map(\.id)) == Set(firstIDs))
        precondition(store.items.contains { $0.kind == .upgradeDecision && $0.sourceID == "upgrade:brew:formula:node" })
        precondition(store.items.contains { $0.kind == .appUpdate && $0.sourceID == app.id })

        let secondIDs = DailyInspectionInboxPublisher.publish(scan: scan, rows: [risky, lowRisk], to: store)
        precondition(secondIDs.count == 2)
        precondition(store.items.count == 2)
        precondition(Set(store.items.map(\.id)) == Set(secondIDs))
    }
}
