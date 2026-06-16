import Foundation

@main
struct RegularAppUpdateDiscoveryCacheTest {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("regular-app-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let cacheURL = root.appendingPathComponent("cache.json")
        let appURL = try makeApp(
            root: root,
            name: "SparkleApp",
            version: "1.0",
            feed: "https://example.com/appcast.xml"
        )

        let cache = RegularAppUpdateDiscoveryCache(fileURL: cacheURL, limit: 2)
        var loadCount = 0
        let first = cache.capability(for: appURL.path) { path in
            loadCount += 1
            precondition(path == appURL.path)
            return sparkleCapability(version: "1.0", feed: "https://example.com/appcast.xml")
        }
        precondition(first.detector == .sparkle)
        precondition(loadCount == 1)
        precondition(cache.records.count == 1)

        let reloaded = RegularAppUpdateDiscoveryCache(fileURL: cacheURL, limit: 2)
        let second = reloaded.capability(for: appURL.path) { _ in
            preconditionFailure("unchanged Info.plist must hit cache")
        }
        precondition(second.feedURLString == "https://example.com/appcast.xml")

        try rewriteInfoPlist(
            appURL: appURL,
            version: "2.0",
            feed: "https://example.com/appcast-v2.xml"
        )
        let third = reloaded.capability(for: appURL.path) { path in
            loadCount += 1
            precondition(path == appURL.path)
            return sparkleCapability(version: "2.0", feed: "https://example.com/appcast-v2.xml")
        }
        precondition(third.feedURLString == "https://example.com/appcast-v2.xml")
        precondition(loadCount == 2)

        try FileManager.default.removeItem(at: appURL.appendingPathComponent("Contents/Info.plist"))
        let missing = reloaded.capability(for: appURL.path) { _ in
            preconditionFailure("missing Info.plist must not call loader")
        }
        precondition(missing == .none)
        precondition(reloaded.records.isEmpty)

        let firstTrimApp = try makeApp(root: root, name: "One", version: "1.0", feed: "https://example.com/one.xml")
        let secondTrimApp = try makeApp(root: root, name: "Two", version: "1.0", feed: "https://example.com/two.xml")
        let thirdTrimApp = try makeApp(root: root, name: "Three", version: "1.0", feed: "https://example.com/three.xml")
        _ = reloaded.capability(for: firstTrimApp.path) { _ in sparkleCapability(version: "1.0", feed: "https://example.com/one.xml") }
        _ = reloaded.capability(for: secondTrimApp.path) { _ in sparkleCapability(version: "1.0", feed: "https://example.com/two.xml") }
        _ = reloaded.capability(for: thirdTrimApp.path) { _ in sparkleCapability(version: "1.0", feed: "https://example.com/three.xml") }
        precondition(reloaded.records.count == 2)
        precondition(!reloaded.records.contains { $0.appPath == firstTrimApp.path })

        try "not-json".write(to: cacheURL, atomically: true, encoding: .utf8)
        let corrupt = RegularAppUpdateDiscoveryCache(fileURL: cacheURL, limit: 2)
        precondition(corrupt.records.isEmpty)
    }

    private static func makeApp(root: URL, name: String, version: String, feed: String) throws -> URL {
        let appURL = root.appendingPathComponent("\(name).app", isDirectory: true)
        try rewriteInfoPlist(appURL: appURL, version: version, feed: feed)
        return appURL
    }

    private static func rewriteInfoPlist(appURL: URL, version: String, feed: String) throws {
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let plist = [
            "CFBundleIdentifier": "com.example.\(appURL.deletingPathExtension().lastPathComponent.lowercased())",
            "CFBundleShortVersionString": version,
            "SUFeedURL": feed
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contentsURL.appendingPathComponent("Info.plist"))
    }

    private static func sparkleCapability(version: String, feed: String) -> AppUpdateCapability {
        AppUpdateCapability(
            detector: .sparkle,
            confidence: .high,
            feedURLString: feed,
            installedVersion: version,
            summary: "可通过 Sparkle 检查更新",
            actions: [AppUpdateAction(kind: .openApp, title: "打开应用", systemImage: "play.circle")],
            diagnostic: "cached"
        )
    }
}
