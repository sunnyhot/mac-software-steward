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
        precondition(sparkleCapability.actions.map(\.kind) == [.openApp, .revealInFinder])

        let chrome = try makeApp(
            root: root,
            name: "Google Chrome",
            plist: [
                "CFBundleIdentifier": "com.google.Chrome",
                "CFBundleShortVersionString": "120.0"
            ]
        )
        let chromeCapability = RegularAppUpdateDiscovery.discover(appPath: chrome.path)
        precondition(chromeCapability.detector == .chromeKeystone)
        precondition(chromeCapability.actions.map(\.kind) == [.openApp, .revealInFinder])

        let keystoneMetadataCapability = RegularAppUpdateDiscovery.discover(plist: [
            "CFBundleIdentifier": "com.example.browser",
            "CFBundleShortVersionString": "1.0",
            "KSProductID": "com.google.Chrome",
            "KSUpdateURL": "https://tools.google.com/service/update2"
        ])
        precondition(keystoneMetadataCapability.detector == .chromeKeystone)
        precondition(keystoneMetadataCapability.confidence == .medium)
        precondition(keystoneMetadataCapability.diagnostic.contains("KSProductID"))

        let adobeMetadataCapability = RegularAppUpdateDiscovery.discover(plist: [
            "CFBundleIdentifier": "com.example.editor",
            "CFBundleShortVersionString": "25.0",
            "AdobeUpdaterEnabled": "true"
        ])
        precondition(adobeMetadataCapability.detector == .adobeUpdater)
        precondition(adobeMetadataCapability.confidence == .medium)
        precondition(adobeMetadataCapability.diagnostic.contains("AdobeUpdaterEnabled"))

        let jetBrainsMetadataCapability = RegularAppUpdateDiscovery.discover(plist: [
            "CFBundleIdentifier": "com.example.idea",
            "CFBundleShortVersionString": "2024.1",
            "JetBrainsToolboxApp": "JetBrains Toolbox"
        ])
        precondition(jetBrainsMetadataCapability.detector == .jetBrainsToolbox)
        precondition(jetBrainsMetadataCapability.confidence == .medium)
        precondition(jetBrainsMetadataCapability.diagnostic.contains("JetBrainsToolboxApp"))

        let microsoft = try makeApp(
            root: root,
            name: "Word",
            plist: [
                "CFBundleIdentifier": "com.microsoft.Word",
                "CFBundleShortVersionString": "16.0"
            ]
        )
        let microsoftCapability = RegularAppUpdateDiscovery.discover(appPath: microsoft.path)
        precondition(microsoftCapability.detector == .microsoftAutoUpdate)
        precondition(microsoftCapability.actions.map(\.kind) == [.openUpdater, .openApp, .revealInFinder])

        let microsoftMetadataCapability = RegularAppUpdateDiscovery.discover(plist: [
            "CFBundleIdentifier": "com.example.word",
            "CFBundleShortVersionString": "16.0",
            "MAUApplicationID": "MSWD2019"
        ])
        precondition(microsoftMetadataCapability.detector == .microsoftAutoUpdate)
        precondition(microsoftMetadataCapability.confidence == .medium)
        precondition(microsoftMetadataCapability.diagnostic.contains("MAUApplicationID"))

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
