import Foundation

@main
struct UpgradeVerifierTest {
    static func main() {
        let before = PackageUpgradeProgress(packageID: "brew:formula:node", packageName: "node", status: .succeeded, detail: "升级完成")
        let stillOutdated = BrewPackage(id: "brew:formula:node", kind: "formula", name: "node", installedVersion: "1", currentVersion: "2", pinned: false, autoUpdates: false, outdated: true, upgradeable: true)
        let current = BrewPackage(id: "brew:formula:node", kind: "formula", name: "node", installedVersion: "2", currentVersion: "", pinned: false, autoUpdates: false, outdated: false, upgradeable: false)

        let warning = UpgradeVerifier.verify(progress: before, remainingPackageIDs: Set([stillOutdated.id]))
        precondition(warning.status == .warning)
        precondition(warning.detail == "命令成功，状态未确认")

        let verified = UpgradeVerifier.verify(progress: before, remainingPackageIDs: Set<String>())
        precondition(verified.status == .succeeded)
        precondition(verified.detail == "升级完成，已验证")

        _ = current
    }
}
