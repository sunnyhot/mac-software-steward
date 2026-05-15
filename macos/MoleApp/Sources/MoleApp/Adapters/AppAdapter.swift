import Foundation

enum AppAdapter {
    static func convert(_ apps: [AppInfo]) -> [AppItem] {
        apps.map { app in
            AppItem(
                id: "app:\(app.path.path)",
                name: app.name,
                version: app.version,
                availableVersion: "",
                path: app.path.path,
                source: app.isSystemApp ? "Apple" : (app.isBrewCask ? "Homebrew" : "Applications"),
                obtainedFrom: app.isBrewCask ? "Homebrew" : "",
                architecture: "",
                managedBy: app.isBrewCask ? "brew-cask" : "manual",
                updateState: "current",
                relatedPackageID: ""
            )
        }
    }

    static func convert(_ item: AppItem) -> AppInfo? {
        let url = URL(fileURLWithPath: item.path)
        let bundle = Bundle(url: url)
        let bundleId = bundle?.bundleIdentifier ?? "unknown.\(item.name)"

        return AppInfo(
            id: bundleId,
            name: item.name,
            path: url,
            version: item.version,
            size: 0,
            lastUsed: nil,
            isBrewCask: item.managedBy == "brew-cask",
            brewCaskName: item.managedBy == "brew-cask" ? item.name.lowercased() : nil,
            isSystemApp: item.path.hasPrefix("/System/"),
            isBackgroundOnly: false
        )
    }
}
