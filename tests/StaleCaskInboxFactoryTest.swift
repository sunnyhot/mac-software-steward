import Foundation

@main
struct StaleCaskInboxFactoryTest {
    static func main() {
        let stale = BrewPackage(
            id: "brew:cask:stale",
            kind: "cask",
            name: "stale",
            installedVersion: "1",
            currentVersion: "2",
            pinned: false,
            autoUpdates: false,
            outdated: true,
            upgradeable: true,
            expectedAppPaths: ["/Applications/Stale.app"],
            hasStaleInstallRecord: true
        )
        let normal = BrewPackage(
            id: "brew:cask:normal",
            kind: "cask",
            name: "normal",
            installedVersion: "1",
            currentVersion: "2",
            pinned: false,
            autoUpdates: false,
            outdated: true,
            upgradeable: true
        )
        let scan = ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: true,
            summary: ScanSummary(applications: 0, brewFormulae: 0, brewCasks: 2, masApps: 0, outdated: 2, actionable: 2, scanMs: 1),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
            brew: BrewScan(available: true, path: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew", version: "Homebrew 5", error: "", includeGreedy: true, formulae: [], casks: [stale, normal]),
            mas: MasScan(available: false, path: "", error: "", apps: [])
        )
        let items = StaleCaskInboxFactory.items(from: scan)
        precondition(items.count == 1)
        precondition(items[0].kind == .failureRecovery)
        precondition(items[0].sourceID == stale.id)
        precondition(items[0].title == "stale 残留记录待清理")
        precondition(items[0].actions.map(\.kind) == [.openUpdates])
        precondition(items[0].summary.contains("不会使用 --zap"))
    }
}
