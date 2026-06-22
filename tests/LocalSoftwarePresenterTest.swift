import Foundation

@main
struct LocalSoftwarePresenterTest {
    static func main() {
        let sparkleApp = makeApp(
            name: "SparkleApp",
            source: "Developer",
            managedBy: "manual",
            updateState: "checkable",
            capability: AppUpdateCapability(
                detector: .sparkle,
                confidence: .high,
                feedURLString: "https://example.com/appcast.xml",
                installedVersion: "1.0",
                summary: "可通过 Sparkle 检查更新",
                diagnostic: ""
            )
        )
        let manualUpdateApp = makeApp(
            name: "ManualSparkleUpdate",
            source: "Developer",
            managedBy: "manual",
            updateState: "outdated",
            availableVersion: "2.0",
            capability: AppUpdateCapability(
                detector: .sparkle,
                confidence: .high,
                feedURLString: "https://example.com/manual-appcast.xml",
                installedVersion: "1.0",
                summary: "Sparkle 发现新版本 2.0",
                diagnostic: ""
            )
        )
        let caskManagedApp = makeApp(
            name: "Rectangle",
            source: "Homebrew",
            managedBy: "brew-cask",
            updateState: "current",
            relatedPackageID: "brew:cask:rectangle"
        )
        let masManagedApp = makeApp(
            name: "Store App",
            source: "App Store",
            managedBy: "mas",
            updateState: "current",
            relatedPackageID: "mas:123"
        )
        let unsupportedSystemApp = makeApp(
            name: "Calculator",
            path: "/System/Applications/Calculator.app",
            source: "Apple",
            managedBy: "manual",
            updateState: "unknown"
        )
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
        let cask = BrewPackage(
            id: "brew:cask:rectangle",
            kind: "cask",
            name: "rectangle",
            installedVersion: "1.0",
            currentVersion: "1.0",
            pinned: false,
            autoUpdates: false,
            outdated: false,
            upgradeable: false
        )
        let mas = MasApp(
            id: "mas:123",
            appId: "123",
            name: "Store App",
            installedVersion: "1.0",
            currentVersion: "1.1",
            outdated: true,
            upgradeable: true
        )

        let rows = LocalSoftwarePresenter.rows(
            applications: [sparkleApp, manualUpdateApp, caskManagedApp, masManagedApp, unsupportedSystemApp],
            brew: BrewScan(
                available: true,
                path: "/opt/homebrew/bin/brew",
                prefix: "/opt/homebrew",
                version: "Homebrew 5",
                error: "",
                includeGreedy: false,
                formulae: [formula],
                casks: [cask]
            ),
            mas: MasScan(
                available: true,
                path: "/opt/homebrew/bin/mas",
                error: "",
                apps: [mas]
            )
        )

        precondition(rows.count == 5)
        precondition(rows.map(\.name) == ["SparkleApp", "ManualSparkleUpdate", "node", "rectangle", "Store App"])
        precondition(rows.filter { $0.kind == .app }.map(\.name) == ["SparkleApp", "ManualSparkleUpdate"])
        precondition(rows.filter { $0.kind == .brewFormula }.map(\.name) == ["node"])
        precondition(rows.filter { $0.kind == .brewCask }.map(\.name) == ["rectangle"])
        precondition(rows.filter { $0.kind == .appStore }.map(\.name) == ["Store App"])
        precondition(!rows.contains { $0.id == caskManagedApp.id })
        precondition(!rows.contains { $0.id == masManagedApp.id })
        precondition(!rows.contains { $0.id == unsupportedSystemApp.id })

        let manualUpdateRow = rows.first { $0.name == "ManualSparkleUpdate" }
        precondition(manualUpdateRow?.isOutdated == true)
        precondition(manualUpdateRow?.isUpgradeable == false)
        precondition(manualUpdateRow?.package == nil)

        let summary = LocalSoftwarePresenter.summary(for: rows)
        precondition(summary.total == 5)
        precondition(summary.app == 2)
        precondition(summary.upgradable == 2)
        precondition(summary.brew == 2)
        precondition(summary.appStore == 1)
        precondition(summary.total == summary.app + summary.brew + summary.appStore)

        precondition(LocalSoftwarePresenter.filteredRows(rows, filter: .all).count == 5)
        precondition(LocalSoftwarePresenter.filteredRows(rows, filter: .app).map(\.name) == ["SparkleApp", "ManualSparkleUpdate"])
        precondition(LocalSoftwarePresenter.filteredRows(rows, filter: .formula).map(\.name) == ["node"])
        precondition(LocalSoftwarePresenter.filteredRows(rows, filter: .cask).map(\.name) == ["rectangle"])
        precondition(LocalSoftwarePresenter.filteredRows(rows, filter: .appStore).map(\.name) == ["Store App"])
        precondition(LocalSoftwarePresenter.filteredRows(rows, filter: .upgradable).map(\.name) == ["node", "Store App"])
    }

    private static func makeApp(
        name: String,
        path: String? = nil,
        source: String,
        managedBy: String,
        updateState: String,
        availableVersion: String = "",
        relatedPackageID: String = "",
        capability: AppUpdateCapability = .none
    ) -> AppItem {
        AppItem(
            id: "app:\(path ?? "/Applications/\(name).app")",
            name: name,
            version: "1.0",
            availableVersion: availableVersion,
            path: path ?? "/Applications/\(name).app",
            source: source,
            obtainedFrom: "",
            architecture: "arm64",
            managedBy: managedBy,
            updateState: updateState,
            relatedPackageID: relatedPackageID,
            updateCapability: capability
        )
    }
}
