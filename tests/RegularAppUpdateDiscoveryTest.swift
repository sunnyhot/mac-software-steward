import Foundation

@main
struct RegularAppUpdateDiscoveryTest {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("regular-app-discovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sparkle = try makeApp(
            root: root,
            name: "SparkleApp",
            plist: [
                "CFBundleIdentifier": "com.example.sparkle",
                "CFBundleShortVersionString": "1.2.3",
                "SUFeedURL": "https://example.com/appcast.xml"
            ]
        )
        let sparkleCapability = RegularAppUpdateDiscovery.discover(appPath: sparkle.path)
        precondition(sparkleCapability.detector == .sparkle)
        precondition(sparkleCapability.confidence == .high)
        precondition(sparkleCapability.feedURLString == "https://example.com/appcast.xml")
        precondition(sparkleCapability.installedVersion == "1.2.3")

        let chrome = try makeApp(
            root: root,
            name: "Google Chrome",
            plist: [
                "CFBundleIdentifier": "com.google.Chrome",
                "CFBundleShortVersionString": "120.0"
            ]
        )
        precondition(RegularAppUpdateDiscovery.discover(appPath: chrome.path).detector == .chromeKeystone)

        let microsoft = try makeApp(
            root: root,
            name: "Word",
            plist: [
                "CFBundleIdentifier": "com.microsoft.Word",
                "CFBundleShortVersionString": "16.0"
            ]
        )
        precondition(RegularAppUpdateDiscovery.discover(appPath: microsoft.path).detector == .microsoftAutoUpdate)

        let unknown = try makeApp(
            root: root,
            name: "UnknownUpdater",
            plist: [
                "CFBundleIdentifier": "com.example.unknown",
                "CFBundleShortVersionString": "1.0",
                "UpdateFeedURL": "https://example.com/updates.json"
            ]
        )
        precondition(RegularAppUpdateDiscovery.discover(appPath: unknown.path).detector == .unknownUpdater)

        let plain = try makeApp(
            root: root,
            name: "Plain",
            plist: [
                "CFBundleIdentifier": "com.example.plain",
                "CFBundleShortVersionString": "1.0"
            ]
        )
        precondition(RegularAppUpdateDiscovery.discover(appPath: plain.path).detector == .none)
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
