import Foundation

enum ApplicationVisibilityPresenter {
    static func visibleApplications(_ apps: [AppItem]) -> [AppItem] {
        apps.filter(shouldShowInApplications)
    }

    static func visibleApplicationCount(_ apps: [AppItem]) -> Int {
        visibleApplications(apps).count
    }

    static func shouldShowInApplications(_ app: AppItem) -> Bool {
        isManagedByUpgradeableSource(app)
            || app.updateCapability.hasManualAction
            || app.updateState == "outdated"
            || app.updateState == "checkable"
            || !app.availableVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isManagedByUpgradeableSource(_ app: AppItem) -> Bool {
        app.managedBy == "brew-cask" || app.managedBy == "mas"
    }
}
