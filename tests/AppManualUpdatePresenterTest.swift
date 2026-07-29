import Foundation

@main
struct AppManualUpdatePresenterTest {
    static func main() {
        let manualUpdate = makeApp(
            updateState: "outdated",
            availableVersion: "2.0",
            actions: [
                AppUpdateAction(kind: .openApp, title: "打开应用", systemImage: "play.circle"),
                AppUpdateAction(kind: .revealInFinder, title: "Finder", systemImage: "arrow.up.forward.app")
            ]
        )

        let updatePresentation = AppManualUpdatePresenter.presentation(for: manualUpdate)
        precondition(updatePresentation.statusTitle == "需手动更新")
        precondition(updatePresentation.primaryAction?.kind == .openApp)
        precondition(updatePresentation.primaryTitle == "打开应用更新")
        precondition(updatePresentation.guidanceText.contains("应用内提示"))
        precondition(updatePresentation.secondaryActions.map(\.kind) == [.revealInFinder])

        let checkableWithUpdater = makeApp(
            updateState: "checkable",
            actions: [
                AppUpdateAction(kind: .openUpdater, title: "打开更新器", systemImage: "arrow.down.app"),
                AppUpdateAction(kind: .openApp, title: "打开应用", systemImage: "play.circle"),
                AppUpdateAction(kind: .revealInFinder, title: "Finder", systemImage: "arrow.up.forward.app")
            ]
        )

        let checkPresentation = AppManualUpdatePresenter.presentation(for: checkableWithUpdater)
        precondition(checkPresentation.statusTitle == "可手动检查")
        precondition(checkPresentation.primaryAction?.kind == .openUpdater)
        precondition(checkPresentation.primaryTitle == "打开更新器")
        precondition(checkPresentation.guidanceText.contains("确认是否有新版本"))
        precondition(checkPresentation.secondaryActions.map(\.kind) == [.openApp, .revealInFinder])

        let managedApp = makeApp(
            managedBy: "brew-cask",
            updateState: "outdated",
            actions: [
                AppUpdateAction(kind: .openApp, title: "打开应用", systemImage: "play.circle")
            ]
        )
        let managedPresentation = AppManualUpdatePresenter.presentation(for: managedApp)
        precondition(managedPresentation.primaryAction == nil)
        precondition(managedPresentation.secondaryActions.isEmpty)
    }

    private static func makeApp(
        managedBy: String = "manual",
        updateState: String,
        availableVersion: String = "",
        actions: [AppUpdateAction]
    ) -> AppItem {
        AppItem(
            id: "app:/Applications/Test.app",
            name: "Test",
            version: "1.0",
            availableVersion: availableVersion,
            path: "/Applications/Test.app",
            source: "Developer",
            obtainedFrom: "Identified Developer",
            architecture: "arm64",
            managedBy: managedBy,
            updateState: updateState,
            relatedPackageID: "",
            updateCapability: AppUpdateCapability(
                detector: .sparkle,
                confidence: .high,
                feedURLString: "https://example.com/appcast.xml",
                installedVersion: "1.0",
                summary: "可通过 Sparkle 检查更新",
                actions: actions,
                diagnostic: "",
                downloadURLString: "https://example.com/Test.zip"
            )
        )
    }
}
