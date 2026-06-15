import Foundation

@main
struct AppUpdateInboxFactoryTest {
    static func main() {
        let app = AppItem(
            id: "app:/Applications/Sparkle.app",
            name: "Sparkle",
            version: "1.0",
            availableVersion: "2.0",
            path: "/Applications/Sparkle.app",
            source: "Developer",
            obtainedFrom: "Identified Developer",
            architecture: "arm64",
            managedBy: "manual",
            updateState: "outdated",
            relatedPackageID: "",
            updateCapability: AppUpdateCapability(
                detector: .sparkle,
                confidence: .high,
                feedURLString: "https://example.com/appcast.xml",
                installedVersion: "1.0",
                summary: "Sparkle 发现新版本 2.0",
                diagnostic: "ok"
            )
        )

        let items = AppUpdateInboxFactory.items(from: [app])
        precondition(items.count == 1)
        precondition(items[0].kind == .appUpdate)
        precondition(items[0].severity == .info)
        precondition(items[0].sourceID == app.id)
        precondition(items[0].title == "Sparkle 可更新")
        precondition(items[0].actions.map(\.kind) == [.openApplications, .rescan])
    }
}
