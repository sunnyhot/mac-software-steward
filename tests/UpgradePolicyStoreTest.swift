import Foundation

@main
struct UpgradePolicyStoreTest {
    static func main() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpgradePolicyStoreTest-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let store = UpgradePolicyStore(fileURL: tempURL)

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
        let pinnedFormula = BrewPackage(
            id: "brew:formula:ruby",
            kind: "formula",
            name: "ruby",
            installedVersion: "1.0",
            currentVersion: "2.0",
            pinned: true,
            autoUpdates: false,
            outdated: true,
            upgradeable: false
        )
        let greedyCask = BrewPackage(
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
        let autoUpdatingCask = BrewPackage(
            id: "brew:cask:arc",
            kind: "cask",
            name: "arc",
            installedVersion: "1.0",
            currentVersion: "2.0",
            pinned: false,
            autoUpdates: true,
            outdated: true,
            upgradeable: false
        )
        let greedyOnlyCask = BrewPackage(
            id: "brew:cask:figma",
            kind: "cask",
            name: "figma",
            installedVersion: "1.0",
            currentVersion: "2.0",
            pinned: false,
            autoUpdates: false,
            outdated: true,
            upgradeable: true
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

        precondition(store.effectivePolicy(for: .brew(formula), includeGreedy: false) == .automatic)
        precondition(store.effectivePolicy(for: .brew(pinnedFormula), includeGreedy: false) == .automatic)
        precondition(store.effectivePolicy(for: .brew(greedyCask), includeGreedy: true) == .askFirst)
        precondition(store.effectivePolicy(for: .brew(autoUpdatingCask), includeGreedy: false) == .askFirst)
        precondition(store.effectivePolicy(for: .brew(greedyOnlyCask), includeGreedy: true) == .askFirst)
        precondition(store.effectivePolicy(for: .mas(mas), includeGreedy: false) == .askFirst)

        store.set(.skip, forPackageID: formula.id)
        precondition(store.effectivePolicy(for: .brew(formula), includeGreedy: false) == .skip)

        let reloaded = UpgradePolicyStore(fileURL: tempURL)
        precondition(reloaded.effectivePolicy(for: .brew(formula), includeGreedy: false) == .skip)

        store.set(.automatic, forPackageID: formula.id)
        precondition(store.policyOverride(forPackageID: formula.id) == .automatic)
    }
}
