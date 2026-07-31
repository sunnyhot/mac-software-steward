# Scan Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Optimize ordinary app update scanning with bounded Sparkle feed concurrency, explicit feed timeouts, and local `Info.plist` discovery caching.

**Architecture:** Keep `SoftwareScanner.scanAll` as the orchestration point and preserve existing scan phases. Add a focused `RegularAppUpdateDiscoveryCache` JSON store for local metadata results, make Sparkle appcast enrichment bounded-concurrent while preserving input order, and add testable timeout helpers to `SparkleAppcastChecker`.

**Tech Stack:** Swift, Foundation, Combine, Swift concurrency task groups, existing single-file `swiftc` test harness, local JSON persistence.

---

## Scope Check

This plan implements the full scan optimization design in `docs/superpowers/specs/2026-06-16-scan-optimization-design.md`. It does not optimize Homebrew, `mas`, `system_profiler`, UI rendering, build scripts, or test execution speed. It does not persist remote Sparkle feed results; only local `Info.plist` discovery results are cached.

## File Structure

- Modify: `native/MacSoftwareSteward/Scanner.swift`
  - Bound Sparkle appcast concurrency, preserve input order, wire local discovery cache.
- Modify: `native/MacSoftwareSteward/SparkleAppcastChecker.swift`
  - Add explicit request timeout and timeout diagnostic helper.
- Create: `native/MacSoftwareSteward/RegularAppUpdateDiscoveryCache.swift`
  - Cache `AppUpdateCapability` by app path plus `Info.plist` metadata.
- Modify: `scripts/build-native.sh`
  - Include `RegularAppUpdateDiscoveryCache.swift` in the Agent compile source list because `Scanner.swift` will reference it.
- Modify: `scripts/test-native.sh`
  - Add new cache test and include the cache file in scanner test source lists.
- Modify: `tests/ScannerSparkleAppcastPolicyTest.swift`
  - Add bounded-concurrency and stable-order coverage.
- Modify: `tests/SparkleAppcastCheckerTest.swift`
  - Add request timeout and timeout diagnostic coverage.
- Create: `tests/RegularAppUpdateDiscoveryCacheTest.swift`
  - Cover cache hit, invalidation, trim, corrupt JSON, and stale entry removal.
- Modify: `tests/ScannerAppUpdateCapabilityTest.swift`
  - Cover scanner cache integration and checkable state preservation.
- Modify: `PROJECT_MAP.md`
  - Document the new cache file and updated scanner responsibility.

## Task 1: Bounded Concurrent Sparkle Enrichment

**Files:**
- Modify: `tests/ScannerSparkleAppcastPolicyTest.swift`
- Modify: `native/MacSoftwareSteward/Scanner.swift`

- [ ] **Step 1: Replace the Sparkle policy test with concurrency coverage**

Replace `tests/ScannerSparkleAppcastPolicyTest.swift` with:

```swift
import Foundation

actor SparkleConcurrencyProbe {
    private var active = 0
    private var maximumActive = 0
    private var feeds: [String] = []

    func start(feed: String) {
        active += 1
        maximumActive = max(maximumActive, active)
        feeds.append(feed)
    }

    func finish() {
        active -= 1
    }

    func maxActive() -> Int { maximumActive }

    func observedFeeds() -> [String] { feeds }
}

@main
struct ScannerSparkleAppcastPolicyTest {
    static func main() async {
        let app = makeSparkleApp(
            name: "Sparkle",
            feed: "https://example.com/appcast.xml"
        )

        let localOnly = await SoftwareScanner.enrichRegularAppUpdates(
            [app],
            networkPolicy: .localOnly,
            sparkleChecker: { _, _ in
                preconditionFailure("localOnly must not fetch Sparkle feeds")
            }
        )
        precondition(localOnly[0].availableVersion.isEmpty)
        precondition(localOnly[0].updateState == "checkable")

        let checked = await SoftwareScanner.enrichRegularAppUpdates(
            [app],
            networkPolicy: .declaredSourcesOnly,
            sparkleChecker: { feed, installed in
                precondition(feed == "https://example.com/appcast.xml")
                precondition(installed == "1.0")
                return SparkleAppcastCheckResult(availableVersion: "2.0", diagnostic: "ok")
            }
        )
        precondition(checked[0].availableVersion == "2.0")
        precondition(checked[0].updateState == "outdated")
        precondition(checked[0].updateCapability.diagnostic == "ok")

        let plain = AppItem(
            id: "app:/Applications/Plain.app",
            name: "Plain",
            version: "1.0",
            availableVersion: "",
            path: "/Applications/Plain.app",
            source: "Developer",
            obtainedFrom: "Identified Developer",
            architecture: "arm64",
            managedBy: "manual",
            updateState: "unknown",
            relatedPackageID: "",
            updateCapability: .none
        )
        let apps = [
            makeSparkleApp(name: "One", feed: "https://example.com/one.xml"),
            plain,
            makeSparkleApp(name: "Two", feed: "https://example.com/two.xml"),
            makeSparkleApp(name: "Three", feed: "https://example.com/three.xml")
        ]
        let probe = SparkleConcurrencyProbe()
        let concurrent = await SoftwareScanner.enrichRegularAppUpdates(
            apps,
            networkPolicy: .declaredSourcesOnly,
            sparkleConcurrencyLimit: 2,
            sparkleChecker: { feed, _ in
                await probe.start(feed: feed)
                if feed.contains("one") {
                    try? await Task.sleep(for: .milliseconds(40))
                } else {
                    try? await Task.sleep(for: .milliseconds(10))
                }
                await probe.finish()
                let name = feed
                    .replacingOccurrences(of: "https://example.com/", with: "")
                    .replacingOccurrences(of: ".xml", with: "")
                return SparkleAppcastCheckResult(availableVersion: "2.0-\(name)", diagnostic: "checked \(name)")
            }
        )

        precondition(await probe.maxActive() == 2)
        precondition(await probe.observedFeeds() == [
            "https://example.com/one.xml",
            "https://example.com/two.xml",
            "https://example.com/three.xml"
        ])
        precondition(concurrent.map(\.id) == apps.map(\.id))
        precondition(concurrent[0].availableVersion == "2.0-one")
        precondition(concurrent[1].availableVersion.isEmpty)
        precondition(concurrent[2].availableVersion == "2.0-two")
        precondition(concurrent[3].availableVersion == "2.0-three")

        let clamped = await SoftwareScanner.enrichRegularAppUpdates(
            [apps[0], apps[2]],
            networkPolicy: .declaredSourcesOnly,
            sparkleConcurrencyLimit: 0,
            sparkleChecker: { _, _ in
                SparkleAppcastCheckResult(availableVersion: "2.0", diagnostic: "ok")
            }
        )
        precondition(clamped[0].availableVersion == "2.0")
        precondition(clamped[1].availableVersion == "2.0")
    }

    private static func makeSparkleApp(name: String, feed: String) -> AppItem {
        AppItem(
            id: "app:/Applications/\(name).app",
            name: name,
            version: "1.0",
            availableVersion: "",
            path: "/Applications/\(name).app",
            source: "Developer",
            obtainedFrom: "Identified Developer",
            architecture: "arm64",
            managedBy: "manual",
            updateState: "checkable",
            relatedPackageID: "",
            updateCapability: AppUpdateCapability(
                detector: .sparkle,
                confidence: .high,
                feedURLString: feed,
                installedVersion: "1.0",
                summary: "可通过 Sparkle 检查更新",
                diagnostic: ""
            )
        )
    }
}
```

- [ ] **Step 2: Run the failing Sparkle policy test**

Run:

```bash
bash scripts/test-native.sh
```

Expected: FAIL while compiling `ScannerSparkleAppcastPolicyTest` because `SoftwareScanner.enrichRegularAppUpdates` does not accept `sparkleConcurrencyLimit` yet.

- [ ] **Step 3: Add bounded concurrent enrichment**

In `native/MacSoftwareSteward/Scanner.swift`, replace the `SparkleChecker` typealias and `enrichRegularAppUpdates` implementation with this block:

```swift
    typealias SparkleChecker = (String, String) async -> SparkleAppcastCheckResult

    private struct SparkleEnrichmentCandidate {
        var index: Int
        var app: AppItem
    }

    static func enrichRegularAppUpdates(
        _ apps: [AppItem],
        networkPolicy: RegularAppNetworkPolicy,
        sparkleConcurrencyLimit: Int = 4,
        sparkleChecker: SparkleChecker = { feed, installed in
            await SparkleAppcastChecker.check(feedURLString: feed, installedVersion: installed)
        }
    ) async -> [AppItem] {
        guard networkPolicy != .localOnly else { return apps }

        let candidates = apps.enumerated().compactMap { index, app -> SparkleEnrichmentCandidate? in
            guard app.managedBy == "manual",
                  app.updateCapability.detector == .sparkle,
                  !app.updateCapability.feedURLString.isEmpty else {
                return nil
            }
            return SparkleEnrichmentCandidate(index: index, app: app)
        }
        guard !candidates.isEmpty else { return apps }

        let limit = max(1, sparkleConcurrencyLimit)
        var enriched = apps

        await withTaskGroup(of: (Int, AppItem).self) { group in
            var nextCandidateIndex = 0
            let initialCount = min(limit, candidates.count)
            for _ in 0..<initialCount {
                let candidate = candidates[nextCandidateIndex]
                nextCandidateIndex += 1
                group.addTask {
                    (candidate.index, await sparkleEnrichedApp(candidate.app, sparkleChecker: sparkleChecker))
                }
            }

            while let result = await group.next() {
                enriched[result.0] = result.1
                if nextCandidateIndex < candidates.count {
                    let candidate = candidates[nextCandidateIndex]
                    nextCandidateIndex += 1
                    group.addTask {
                        (candidate.index, await sparkleEnrichedApp(candidate.app, sparkleChecker: sparkleChecker))
                    }
                }
            }
        }

        return enriched
    }

    private static func sparkleEnrichedApp(
        _ app: AppItem,
        sparkleChecker: SparkleChecker
    ) async -> AppItem {
        var next = app
        let installedVersion = next.updateCapability.installedVersion.isEmpty
            ? next.version
            : next.updateCapability.installedVersion
        let result = await sparkleChecker(next.updateCapability.feedURLString, installedVersion)
        next.updateCapability.diagnostic = result.diagnostic
        if !result.availableVersion.isEmpty {
            next.availableVersion = result.availableVersion
            next.updateState = "outdated"
            next.updateCapability.summary = "Sparkle 发现新版本 \(result.availableVersion)"
        }
        return next
    }
```

- [ ] **Step 4: Run the Sparkle policy test**

Run:

```bash
bash scripts/test-native.sh
```

Expected: PASS through `ScannerSparkleAppcastPolicyTest` and all existing scanner tests.

- [ ] **Step 5: Commit Sparkle concurrency**

Run:

```bash
git add native/MacSoftwareSteward/Scanner.swift tests/ScannerSparkleAppcastPolicyTest.swift
git commit -m "feat: bound sparkle appcast concurrency"
```

## Task 2: Sparkle Request Timeout

**Files:**
- Modify: `tests/SparkleAppcastCheckerTest.swift`
- Modify: `native/MacSoftwareSteward/SparkleAppcastChecker.swift`

- [ ] **Step 1: Replace the Sparkle checker test with timeout helper coverage**

Replace `tests/SparkleAppcastCheckerTest.swift` with:

```swift
import Foundation

@main
struct SparkleAppcastCheckerTest {
    static func main() {
        let appcast = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <item>
              <title>Version 2.0</title>
              <enclosure sparkle:shortVersionString="2.0" sparkle:version="200" url="https://example.com/app.zip" />
            </item>
          </channel>
        </rss>
        """

        let parsed = SparkleAppcastChecker.parseLatestVersion(from: Data(appcast.utf8))
        precondition(parsed == "2.0")

        let fallback = """
        <rss><channel><item><sparkle:version>3.1</sparkle:version></item></channel></rss>
        """
        precondition(SparkleAppcastChecker.parseLatestVersion(from: Data(fallback.utf8)) == "3.1")
        precondition(SparkleAppcastChecker.isNewerVersion("2.0", than: "1.9"))
        precondition(!SparkleAppcastChecker.isNewerVersion("1.0", than: "1.0"))

        let url = URL(string: "https://example.com/appcast.xml")!
        let request = SparkleAppcastChecker.request(for: url, timeout: 3.5)
        precondition(request.url == url)
        precondition(request.timeoutInterval == 3.5)

        let timeout = URLError(.timedOut)
        precondition(SparkleAppcastChecker.diagnostic(for: timeout) == "Sparkle feed 检查超时。")

        let cancelled = URLError(.cancelled)
        precondition(SparkleAppcastChecker.diagnostic(for: cancelled).hasPrefix("Sparkle feed 检查失败："))
    }
}
```

- [ ] **Step 2: Run the failing Sparkle checker test**

Run:

```bash
bash scripts/test-native.sh
```

Expected: FAIL while compiling `SparkleAppcastCheckerTest` because `request(for:timeout:)` and `diagnostic(for:)` do not exist yet.

- [ ] **Step 3: Add timeout request and diagnostic helpers**

Replace the top of `native/MacSoftwareSteward/SparkleAppcastChecker.swift`, from `enum SparkleAppcastChecker {` through the end of `check(...)`, with:

```swift
enum SparkleAppcastChecker {
    static func check(
        feedURLString: String,
        installedVersion: String,
        timeout: TimeInterval = 8
    ) async -> SparkleAppcastCheckResult {
        guard let url = URL(string: feedURLString),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return SparkleAppcastCheckResult(availableVersion: "", diagnostic: "Sparkle feed URL 无效。")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request(for: url, timeout: timeout))
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return SparkleAppcastCheckResult(availableVersion: "", diagnostic: "Sparkle feed HTTP 状态码 \(http.statusCode)。")
            }
            guard let version = parseLatestVersion(from: data), !version.isEmpty else {
                return SparkleAppcastCheckResult(availableVersion: "", diagnostic: "Sparkle feed 未找到可用版本。")
            }
            if isNewerVersion(version, than: installedVersion) {
                return SparkleAppcastCheckResult(availableVersion: version, diagnostic: "Sparkle feed 发现版本 \(version)。")
            }
            return SparkleAppcastCheckResult(availableVersion: "", diagnostic: "Sparkle feed 未发现更新。")
        } catch {
            return SparkleAppcastCheckResult(availableVersion: "", diagnostic: diagnostic(for: error))
        }
    }

    static func request(for url: URL, timeout: TimeInterval = 8) -> URLRequest {
        URLRequest(url: url, timeoutInterval: timeout)
    }

    static func diagnostic(for error: Error) -> String {
        if (error as? URLError)?.code == .timedOut {
            return "Sparkle feed 检查超时。"
        }
        return "Sparkle feed 检查失败：\(error.localizedDescription)"
    }
```

Keep the existing `parseLatestVersion(from:)` and `isNewerVersion(_:than:)` methods below this new block.

- [ ] **Step 4: Run the Sparkle checker test**

Run:

```bash
bash scripts/test-native.sh
```

Expected: PASS through `SparkleAppcastCheckerTest`.

- [ ] **Step 5: Commit Sparkle timeout**

Run:

```bash
git add native/MacSoftwareSteward/SparkleAppcastChecker.swift tests/SparkleAppcastCheckerTest.swift
git commit -m "feat: add sparkle appcast timeout"
```

## Task 3: Regular App Discovery Cache

**Files:**
- Create: `native/MacSoftwareSteward/RegularAppUpdateDiscoveryCache.swift`
- Create: `tests/RegularAppUpdateDiscoveryCacheTest.swift`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Add the cache test**

Create `tests/RegularAppUpdateDiscoveryCacheTest.swift`:

```swift
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
```

- [ ] **Step 2: Wire and run the failing cache test**

Add this block to `scripts/test-native.sh` after `RegularAppUpdateDiscoveryTest`:

```bash
run_test RegularAppUpdateDiscoveryCacheTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/RegularAppUpdateDiscovery.swift" \
  "$SRC/RegularAppUpdateDiscoveryCache.swift" \
  "$TESTS/RegularAppUpdateDiscoveryCacheTest.swift"
```

Run:

```bash
bash scripts/test-native.sh
```

Expected: FAIL while compiling `RegularAppUpdateDiscoveryCacheTest` because `RegularAppUpdateDiscoveryCache.swift` does not exist yet.

- [ ] **Step 3: Add the cache store**

Create `native/MacSoftwareSteward/RegularAppUpdateDiscoveryCache.swift`:

```swift
import Combine
import Foundation

struct RegularAppUpdateDiscoveryCacheMetadata: Codable, Hashable {
    var modifiedAt: TimeInterval
    var size: UInt64
}

struct RegularAppUpdateDiscoveryCacheRecord: Codable, Identifiable, Hashable {
    var id: String { appPath }
    var appPath: String
    var metadata: RegularAppUpdateDiscoveryCacheMetadata
    var capability: AppUpdateCapability
    var lastSeenAt: Date
}

final class RegularAppUpdateDiscoveryCache: ObservableObject {
    static let cacheVersion = 1
    static let defaultFileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacSoftwareSteward", isDirectory: true)
            .appendingPathComponent("regular-app-discovery-cache.json")
    }()

    @Published private(set) var records: [RegularAppUpdateDiscoveryCacheRecord]

    private let fileURL: URL
    private let limit: Int

    init(fileURL: URL = RegularAppUpdateDiscoveryCache.defaultFileURL, limit: Int = 1000) {
        self.fileURL = fileURL
        self.limit = limit
        records = Self.load(from: fileURL)
        trimToLimit()
    }

    func capability(
        for appPath: String,
        loader: (String) -> AppUpdateCapability = RegularAppUpdateDiscovery.discover
    ) -> AppUpdateCapability {
        guard let metadata = Self.metadata(for: appPath) else {
            remove(appPath)
            save()
            return .none
        }

        if let index = records.firstIndex(where: { $0.appPath == appPath }),
           records[index].metadata == metadata {
            records[index].lastSeenAt = Date()
            trimToLimit()
            save()
            return records[index].capability
        }

        let capability = loader(appPath)
        let record = RegularAppUpdateDiscoveryCacheRecord(
            appPath: appPath,
            metadata: metadata,
            capability: capability,
            lastSeenAt: Date()
        )
        upsert(record)
        save()
        return capability
    }

    func reload() {
        records = Self.load(from: fileURL)
        trimToLimit()
    }

    func clear() {
        records.removeAll()
        save()
    }

    private func upsert(_ record: RegularAppUpdateDiscoveryCacheRecord) {
        remove(record.appPath)
        records.insert(record, at: 0)
        trimToLimit()
    }

    private func remove(_ appPath: String) {
        records.removeAll { $0.appPath == appPath }
    }

    private func sortNewestFirst() {
        records.sort { lhs, rhs in
            lhs.lastSeenAt > rhs.lastSeenAt
        }
    }

    private func trimToLimit() {
        sortNewestFirst()
        if records.count > limit {
            records.removeLast(records.count - limit)
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(CacheFile(version: Self.cacheVersion, records: records))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Failed to save regular app discovery cache: \(error.localizedDescription)")
        }
    }

    private static func load(from url: URL) -> [RegularAppUpdateDiscoveryCacheRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(CacheFile.self, from: data),
              file.version == cacheVersion else {
            NSLog("Failed to load regular app discovery cache.")
            return []
        }
        return file.records.sorted { lhs, rhs in
            lhs.lastSeenAt > rhs.lastSeenAt
        }
    }

    private static func metadata(for appPath: String) -> RegularAppUpdateDiscoveryCacheMetadata? {
        let plistURL = URL(fileURLWithPath: appPath)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: plistURL.path),
              let modifiedAt = attributes[.modificationDate] as? Date,
              let size = (attributes[.size] as? NSNumber)?.uint64Value else {
            return nil
        }
        return RegularAppUpdateDiscoveryCacheMetadata(
            modifiedAt: modifiedAt.timeIntervalSince1970,
            size: size
        )
    }

    private struct CacheFile: Codable {
        var version: Int
        var records: [RegularAppUpdateDiscoveryCacheRecord]
    }
}
```

- [ ] **Step 4: Run the cache test**

Run:

```bash
bash scripts/test-native.sh
```

Expected: PASS through `RegularAppUpdateDiscoveryCacheTest`.

- [ ] **Step 5: Commit the cache store**

Run:

```bash
git add native/MacSoftwareSteward/RegularAppUpdateDiscoveryCache.swift tests/RegularAppUpdateDiscoveryCacheTest.swift scripts/test-native.sh
git commit -m "feat: cache regular app discovery"
```

## Task 4: Scanner Cache Integration

**Files:**
- Modify: `tests/ScannerAppUpdateCapabilityTest.swift`
- Modify: `native/MacSoftwareSteward/Scanner.swift`
- Modify: `scripts/test-native.sh`
- Modify: `scripts/build-native.sh`

- [ ] **Step 1: Update the scanner capability test for cache integration**

In `tests/ScannerAppUpdateCapabilityTest.swift`, add this block after the existing `enriched` assertions and before the `brew` package setup:

```swift
        let cacheURL = root.appendingPathComponent("regular-app-cache.json")
        let cache = RegularAppUpdateDiscoveryCache(fileURL: cacheURL, limit: 10)
        var loaderCalls = 0
        let cachedFirst = SoftwareScanner.attachUpdateCapabilities(
            to: [app],
            cache: cache,
            capabilityLoader: { path in
                loaderCalls += 1
                return RegularAppUpdateDiscovery.discover(appPath: path)
            }
        )
        precondition(cachedFirst[0].updateCapability.detector == .sparkle)
        precondition(cachedFirst[0].updateState == "checkable")
        precondition(loaderCalls == 1)

        let cachedSecond = SoftwareScanner.attachUpdateCapabilities(
            to: [app],
            cache: cache,
            capabilityLoader: { _ in
                preconditionFailure("unchanged Info.plist must use scanner cache")
            }
        )
        precondition(cachedSecond[0].updateCapability.detector == .sparkle)
        precondition(cachedSecond[0].updateState == "checkable")
```

In `scripts/test-native.sh`, add `"$SRC/RegularAppUpdateDiscoveryCache.swift"` to the `ScannerAppUpdateCapabilityTest` source list immediately after `"$SRC/RegularAppUpdateDiscovery.swift"`.

Run:

```bash
bash scripts/test-native.sh
```

Expected: FAIL while compiling `ScannerAppUpdateCapabilityTest` because `attachUpdateCapabilities` does not accept `cache` or `capabilityLoader` yet.

- [ ] **Step 2: Wire cache into scanner update capability discovery**

In `native/MacSoftwareSteward/Scanner.swift`, add this static cache property near `BrewInstalledPackagesResult`:

```swift
    static let regularAppUpdateDiscoveryCache = RegularAppUpdateDiscoveryCache()
```

In `scanAll`, change the regular app discovery timing block to:

```swift
        let discoveryTimed = timedSync(.regularAppDiscovery) {
            attachUpdateCapabilities(to: applications.items, cache: regularAppUpdateDiscoveryCache)
        }
```

Replace `attachUpdateCapabilities(to:)` with:

```swift
    static func attachUpdateCapabilities(
        to apps: [AppItem],
        cache: RegularAppUpdateDiscoveryCache? = nil,
        capabilityLoader: (String) -> AppUpdateCapability = RegularAppUpdateDiscovery.discover
    ) -> [AppItem] {
        apps.map { app in
            var next = app
            let capability = cache?.capability(for: app.path, loader: capabilityLoader)
                ?? capabilityLoader(app.path)
            next.updateCapability = capability
            if next.managedBy == "manual", capability.hasManualAction, next.updateState == "unknown" {
                next.updateState = "checkable"
            }
            return next
        }
    }
```

- [ ] **Step 3: Add cache source to scanner test compile lists**

In `scripts/test-native.sh`, add this source file immediately after `"$SRC/RegularAppUpdateDiscovery.swift"` in every `run_test` block that compiles `"$SRC/Scanner.swift"`:

```bash
  "$SRC/RegularAppUpdateDiscoveryCache.swift" \
```

The scanner test blocks to update are:

```text
ScannerBrewListFallbackTest
ScannerAppUpdateCapabilityTest
ScannerSparkleAppcastPolicyTest
ScannerNormalizeTokenTest
StewardModelScanGuardTest
```

Verify with:

```bash
rg -n 'RegularAppUpdateDiscovery(Cache)?\.swift|Scanner\.swift' scripts/test-native.sh
```

Expected: every scanner test source list includes `RegularAppUpdateDiscoveryCache.swift` before `Scanner.swift`.

- [ ] **Step 4: Add cache source to Agent build**

In `scripts/build-native.sh`, add this line immediately after `RegularAppUpdateDiscovery.swift` in the Agent compile source list:

```bash
  "$ROOT_DIR"/native/MacSoftwareSteward/RegularAppUpdateDiscoveryCache.swift \
```

Run:

```bash
bash scripts/test-native.sh
npm run build
```

Expected: both PASS. `npm run build` must print `Signature OK`.

- [ ] **Step 5: Restore generated icon diffs**

Run:

```bash
git status --short
```

If `native/Resources/AppIcon.iconset/*.png` appears, run:

```bash
git restore native/Resources/AppIcon.iconset
```

Expected: only intentional source, test, and script changes remain.

- [ ] **Step 6: Commit scanner cache integration**

Run:

```bash
git add native/MacSoftwareSteward/Scanner.swift tests/ScannerAppUpdateCapabilityTest.swift scripts/test-native.sh scripts/build-native.sh
git commit -m "feat: use cached regular app discovery"
```

## Task 5: Documentation And Final Verification

**Files:**
- Modify: `PROJECT_MAP.md`
- Verify: `scripts/test-native.sh`
- Verify: `scripts/build-native.sh`

- [ ] **Step 1: Update PROJECT_MAP**

In `PROJECT_MAP.md`, update the main app table so scanner and regular app discovery cache responsibilities are represented:

```markdown
| `Scanner.swift` | 约 740 | `SoftwareScanner`：扫描 Applications/Homebrew/mas，记录阶段耗时，缓存普通 App 更新能力，并有界并发检查 Sparkle appcast |
| `RegularAppUpdateDiscovery.swift` / `RegularAppUpdateDiscoveryCache.swift` | 约 380 | 普通 `.app` 更新能力识别和基于 `Info.plist` 元数据的本机缓存 |
```

Also update the Agent compile note so it mentions `RegularAppUpdateDiscoveryCache.swift`.

- [ ] **Step 2: Run all tests**

Run:

```bash
npm test
```

Expected: PASS with `All native tests passed.`

- [ ] **Step 3: Run full build**

Run:

```bash
npm run build
```

Expected: PASS with `Signature OK`.

- [ ] **Step 4: Restore generated icon diffs**

Run:

```bash
git status --short
```

If `native/Resources/AppIcon.iconset/*.png` appears, run:

```bash
git restore native/Resources/AppIcon.iconset
```

Expected: only `PROJECT_MAP.md` remains changed.

- [ ] **Step 5: Commit docs**

Run:

```bash
git add PROJECT_MAP.md
git commit -m "docs: document scan optimizations"
```

- [ ] **Step 6: Final status check**

Run:

```bash
git status --short
git log --oneline -8
```

Expected: clean working tree and recent commits for Sparkle concurrency, Sparkle timeout, discovery cache, scanner cache integration, and docs.
