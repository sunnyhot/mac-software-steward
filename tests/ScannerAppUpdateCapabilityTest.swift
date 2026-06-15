import Foundation

@main
struct ScannerAppUpdateCapabilityTest {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scanner-app-capability-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let appURL = try makeApp(
            root: root,
            name: "SparkleApp",
            plist: [
                "CFBundleIdentifier": "com.example.sparkle",
                "CFBundleShortVersionString": "1.0",
                "SUFeedURL": "https://example.com/appcast.xml"
            ]
        )
        let app = AppItem(
            id: "app:\(appURL.path)",
            name: "SparkleApp",
            version: "1.0",
            availableVersion: "",
            path: appURL.path,
            source: "Developer",
            obtainedFrom: "Identified Developer",
            architecture: "arm64",
            managedBy: "manual",
            updateState: "unknown",
            relatedPackageID: ""
        )

        let enriched = SoftwareScanner.attachUpdateCapabilities(to: [app])
        precondition(enriched.count == 1)
        precondition(enriched[0].updateCapability.detector == .sparkle)
        precondition(enriched[0].updateState == "checkable")

        let brew = BrewPackage(id: "brew:cask:sparkleapp", kind: "cask", name: "SparkleApp", installedVersion: "1.0", currentVersion: "2.0", pinned: false, autoUpdates: false, outdated: true, upgradeable: true)
        let classified = SoftwareScanner.classifyForTesting(
            enriched,
            brew: BrewScan(available: true, path: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew", version: "Homebrew", error: "", includeGreedy: false, formulae: [], casks: [brew]),
            mas: MasScan(available: false, path: "", error: "", apps: [])
        )
        precondition(classified[0].managedBy == "brew-cask")
        precondition(classified[0].updateState == "outdated")
        precondition(classified[0].updateCapability.detector == .sparkle)
    }

    private static func makeApp(root: URL, name: String, plist: [String: String]) throws -> URL {
        let appURL = root.appendingPathComponent("\(name).app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contentsURL.appendingPathComponent("Info.plist"))
        return appURL
    }
}
