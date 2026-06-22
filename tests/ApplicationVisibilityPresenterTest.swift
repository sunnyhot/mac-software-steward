import Foundation

@main
struct ApplicationVisibilityPresenterTest {
    static func main() {
        let brewApp = makeApp(
            name: "Rectangle",
            source: "Homebrew",
            managedBy: "brew-cask",
            updateState: "current"
        )
        let masApp = makeApp(
            name: "Xcode",
            source: "App Store",
            managedBy: "mas",
            updateState: "current"
        )
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
        let unsupportedSystemApp = makeApp(
            name: "Calculator",
            path: "/System/Applications/Calculator.app",
            source: "Apple",
            managedBy: "manual",
            updateState: "unknown"
        )
        let unsupportedManualApp = makeApp(
            name: "Quiet",
            source: "Unknown",
            managedBy: "manual",
            updateState: "unknown"
        )

        let visible = ApplicationVisibilityPresenter.visibleApplications([
            brewApp,
            masApp,
            sparkleApp,
            unsupportedSystemApp,
            unsupportedManualApp
        ])

        precondition(visible.map(\.name) == ["Rectangle", "Xcode", "SparkleApp"])
        precondition(ApplicationVisibilityPresenter.visibleApplicationCount([
            brewApp,
            masApp,
            sparkleApp,
            unsupportedSystemApp,
            unsupportedManualApp
        ]) == visible.count)
        precondition(ApplicationVisibilityPresenter.shouldShowInApplications(brewApp))
        precondition(ApplicationVisibilityPresenter.shouldShowInApplications(masApp))
        precondition(ApplicationVisibilityPresenter.shouldShowInApplications(sparkleApp))
        precondition(!ApplicationVisibilityPresenter.shouldShowInApplications(unsupportedSystemApp))
        precondition(!ApplicationVisibilityPresenter.shouldShowInApplications(unsupportedManualApp))
    }

    private static func makeApp(
        name: String,
        path: String? = nil,
        source: String,
        managedBy: String,
        updateState: String,
        capability: AppUpdateCapability = .none
    ) -> AppItem {
        AppItem(
            id: "app:\(path ?? "/Applications/\(name).app")",
            name: name,
            version: "1.0",
            availableVersion: "",
            path: path ?? "/Applications/\(name).app",
            source: source,
            obtainedFrom: "",
            architecture: "arm64",
            managedBy: managedBy,
            updateState: updateState,
            relatedPackageID: "",
            updateCapability: capability
        )
    }
}
