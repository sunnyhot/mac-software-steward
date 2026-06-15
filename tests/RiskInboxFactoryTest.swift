import Foundation

@main
struct RiskInboxFactoryTest {
    static func main() {
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
        let low = UpgradePlanRow(
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
            package: nil,
            riskLevel: .low,
            riskSummary: "",
            automationDecision: .allowAutomatic
        )

        let items = RiskInboxFactory.items(from: [risky, low])
        precondition(items.count == 1)
        precondition(items[0].kind == .upgradeDecision)
        precondition(items[0].severity == .warning)
        precondition(items[0].sourceID == "upgrade:brew:formula:node")
        precondition(items[0].actions.contains(InboxAction(title: "查看升级计划", systemImage: "arrow.down.circle", kind: .openUpdates)))
    }
}
