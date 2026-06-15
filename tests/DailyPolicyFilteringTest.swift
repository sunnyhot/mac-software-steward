import Foundation

@main
struct DailyPolicyFilteringTest {
    static func main() {
        let formula = BrewPackage(
            id: "brew:formula:node",
            kind: "formula",
            name: "node",
            installedVersion: "1",
            currentVersion: "2",
            pinned: false,
            autoUpdates: false,
            outdated: true,
            upgradeable: true
        )
        let cask = BrewPackage(
            id: "brew:cask:warp",
            kind: "cask",
            name: "warp",
            installedVersion: "1",
            currentVersion: "2",
            pinned: false,
            autoUpdates: true,
            outdated: true,
            upgradeable: false
        )
        let pinned = BrewPackage(
            id: "brew:formula:ruby",
            kind: "formula",
            name: "ruby",
            installedVersion: "1",
            currentVersion: "2",
            pinned: true,
            autoUpdates: false,
            outdated: true,
            upgradeable: false
        )
        let rows = [
            UpgradePlanRow(packageID: formula.id, packageName: formula.name, source: "Brew Formula", installedVersion: "1", currentVersion: "2", commandDisplay: "brew upgrade node", policy: .automatic, selection: .selected, riskLabels: [], skipReason: "", package: .brew(formula), riskLevel: .low, riskSummary: "", automationDecision: .allowAutomatic),
            UpgradePlanRow(packageID: cask.id, packageName: cask.name, source: "Brew Cask", installedVersion: "1", currentVersion: "2", commandDisplay: "brew upgrade --cask --greedy warp", policy: .askFirst, selection: .notSelected, riskLabels: ["greedy cask"], skipReason: "需确认：greedy cask", package: .brew(cask), riskLevel: .medium, riskSummary: "greedy cask", automationDecision: .requireConfirmation),
            UpgradePlanRow(packageID: pinned.id, packageName: pinned.name, source: "Brew Formula", installedVersion: "1", currentVersion: "2", commandDisplay: "brew upgrade ruby", policy: .automatic, selection: .notSelectable, riskLabels: ["pinned"], skipReason: "软件包已固定", package: nil, riskLevel: .high, riskSummary: "软件包已固定", automationDecision: .blockExecution)
        ]

        let automatic = DailyUpgradePolicy.automaticPackages(from: rows)
        precondition(automatic.count == 1)
        precondition(automatic.first?.id == formula.id)
    }
}
