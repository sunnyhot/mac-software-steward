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
            policy: .askFirst,
            selection: .notSelected,
            riskLabels: ["major version"],
            skipReason: "需确认：major version",
            package: .brew(BrewPackage(id: "brew:formula:node", kind: "formula", name: "node", installedVersion: "20.1.0", currentVersion: "21.0.0", pinned: false, autoUpdates: false, outdated: true, upgradeable: true)),
            riskLevel: .high,
            riskSummary: "major version",
            automationDecision: .requireConfirmation
        )
        // 默认策略 automatic 且已预选：会被自动升级，不再生成「需要确认升级」待办。
        let autoRisk = UpgradePlanRow(
            packageID: "brew:cask:warp",
            packageName: "warp",
            source: "Brew Cask",
            installedVersion: "1.0",
            currentVersion: "2.0",
            commandDisplay: "brew upgrade --cask warp",
            policy: .automatic,
            selection: .selected,
            riskLabels: ["greedy cask"],
            skipReason: "",
            package: .brew(BrewPackage(id: "brew:cask:warp", kind: "cask", name: "warp", installedVersion: "1.0", currentVersion: "2.0", pinned: false, autoUpdates: true, outdated: true, upgradeable: false)),
            riskLevel: .medium,
            riskSummary: "greedy cask",
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

        let items = RiskInboxFactory.items(from: [risky, autoRisk, low])
        precondition(items.count == 1, "仅「需确认且未预选」的行应生成待办，得到 \(items.count)")
        precondition(items[0].kind == .upgradeDecision)
        precondition(items[0].severity == .warning)
        precondition(items[0].sourceID == "upgrade:brew:formula:node")
        precondition(items[0].actions.contains(InboxAction(title: "查看升级计划", systemImage: "arrow.down.circle", kind: .openUpdates)))
    }
}
