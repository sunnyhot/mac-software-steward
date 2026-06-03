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
            UpgradePlanRow(packageID: formula.id, packageName: formula.name, source: "Brew Formula", installedVersion: "1", currentVersion: "2", commandDisplay: "brew upgrade node", policy: .automatic, selection: .selected, riskLabels: [], skipReason: "", package: .brew(formula)),
            UpgradePlanRow(packageID: cask.id, packageName: cask.name, source: "Brew Cask", installedVersion: "1", currentVersion: "2", commandDisplay: "brew upgrade --cask --greedy warp", policy: .askFirst, selection: .selected, riskLabels: ["greedy cask"], skipReason: "", package: .brew(cask)),
            UpgradePlanRow(packageID: pinned.id, packageName: pinned.name, source: "Brew Formula", installedVersion: "1", currentVersion: "2", commandDisplay: "brew upgrade ruby", policy: .automatic, selection: .notSelectable, riskLabels: ["pinned"], skipReason: "软件包已固定", package: nil)
        ]

        let automatic = DailyUpgradePolicy.automaticPackages(from: rows)
        precondition(automatic.count == 1)
        precondition(automatic.first?.id == formula.id)
    }
}
