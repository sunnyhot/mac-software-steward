# Automation Steward M4 Regular App Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add local ordinary `.app` update capability discovery so unmanaged apps can show whether they use Sparkle or a known vendor updater, with a manual action path and no silent replacement.

**Architecture:** Add focused capability models to `Models.swift`, implement pure plist-based detection in `RegularAppUpdateDiscovery`, attach capabilities during application scanning, and surface the result in `ApplicationsView`. This M4 slice is local-only: it records Sparkle feed URLs and known updater families, but does not fetch appcasts or vendor pages yet.

**Tech Stack:** Swift 5/6, Foundation plist parsing, SwiftUI, existing `swiftc` scripts, existing single-file Swift tests.

---

## Scope Check

This plan implements M4a only:

- Local `.app` update capability models.
- Sparkle feed URL recognition from `Info.plist`.
- Known updater family detection for Chrome, Adobe, JetBrains and Microsoft.
- Unknown updater heuristic when app metadata clearly contains updater/appcast keys.
- Scanner integration that preserves existing Homebrew and Mac App Store classification.
- Applications list badges and an "open app" action for manually checking updates.

This plan does not implement network fetching, Sparkle appcast version comparison, automatic install, notification delivery, inbox creation for app updates, or vendor-specific update execution.

## File Structure

- Modify `native/MacSoftwareSteward/Models.swift`: add app update capability enums/model and store the capability on `AppItem`.
- Create `native/MacSoftwareSteward/RegularAppUpdateDiscovery.swift`: pure helper that reads `.app/Contents/Info.plist` and returns `AppUpdateCapability`.
- Modify `native/MacSoftwareSteward/Scanner.swift`: attach local capabilities after application discovery and preserve them during classification.
- Modify `native/MacSoftwareSteward/StewardModel.swift`: add a safe `open(_ app:)` manual action helper.
- Modify `native/MacSoftwareSteward/Views/ApplicationsView.swift`: show capability badges/details and an open-app button for detected manual updaters.
- Modify `scripts/build-native.sh`: include `RegularAppUpdateDiscovery.swift` in Agent compilation because `Scanner.swift` will depend on it.
- Modify `scripts/test-native.sh`: add M4 tests and required source lists.
- Create `tests/RegularAppUpdateDiscoveryTest.swift`: detector unit coverage with temporary fake `.app` bundles.
- Create `tests/ScannerAppUpdateCapabilityTest.swift`: scanner wiring coverage using fake `AppItem` values.

---

### Task 1: App Update Capability Detector

**Files:**
- Modify: `native/MacSoftwareSteward/Models.swift`
- Create: `native/MacSoftwareSteward/RegularAppUpdateDiscovery.swift`
- Test: `tests/RegularAppUpdateDiscoveryTest.swift`

- [ ] **Step 1: Write the failing detector test**

Create `tests/RegularAppUpdateDiscoveryTest.swift`:

```swift
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  tests/RegularAppUpdateDiscoveryTest.swift \
  -o build/RegularAppUpdateDiscoveryTest
```

Expected: FAIL with `cannot find 'RegularAppUpdateDiscovery' in scope`.

- [ ] **Step 3: Add capability models**

In `native/MacSoftwareSteward/Models.swift`, add these types before `AppItem`:

```swift
enum AppUpdateDetectorKind: String, Codable, Hashable {
    case none
    case sparkle
    case chromeKeystone
    case adobeUpdater
    case jetBrainsToolbox
    case microsoftAutoUpdate
    case unknownUpdater

    var title: String {
        switch self {
        case .none: return "无"
        case .sparkle: return "Sparkle"
        case .chromeKeystone: return "Chrome Keystone"
        case .adobeUpdater: return "Adobe"
        case .jetBrainsToolbox: return "JetBrains"
        case .microsoftAutoUpdate: return "Microsoft"
        case .unknownUpdater: return "内置更新器"
        }
    }
}

enum DetectionConfidence: String, Codable, Hashable {
    case none
    case low
    case medium
    case high
}

struct AppUpdateCapability: Codable, Hashable {
    var detector: AppUpdateDetectorKind
    var confidence: DetectionConfidence
    var feedURLString: String
    var installedVersion: String
    var summary: String
    var diagnostic: String

    static let none = AppUpdateCapability(
        detector: .none,
        confidence: .none,
        feedURLString: "",
        installedVersion: "",
        summary: "",
        diagnostic: ""
    )

    var hasManualAction: Bool {
        detector != .none
    }
}
```

Add to `AppItem`:

```swift
var updateCapability: AppUpdateCapability = .none
```

- [ ] **Step 4: Add `RegularAppUpdateDiscovery`**

Create `native/MacSoftwareSteward/RegularAppUpdateDiscovery.swift`:

```swift
import Foundation

enum RegularAppUpdateDiscovery {
    static func discover(appPath: String) -> AppUpdateCapability {
        let plistURL = URL(fileURLWithPath: appPath)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")

        guard
            let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            return .none
        }

        return discover(plist: plist)
    }

    static func discover(plist: [String: Any]) -> AppUpdateCapability {
        let bundleID = string(plist["CFBundleIdentifier"]).lowercased()
        let version = string(plist["CFBundleShortVersionString"])
        if let feedURL = sparkleFeedURL(from: plist) {
            return AppUpdateCapability(
                detector: .sparkle,
                confidence: .high,
                feedURLString: feedURL,
                installedVersion: version,
                summary: "可通过 Sparkle 检查更新",
                diagnostic: "Info.plist 声明了 Sparkle appcast。"
            )
        }

        if bundleID == "com.google.chrome" || bundleID.hasPrefix("com.google.chrome.") {
            return vendorCapability(.chromeKeystone, version: version, summary: "可通过 Chrome 内置更新器检查")
        }
        if bundleID.hasPrefix("com.adobe.") {
            return vendorCapability(.adobeUpdater, version: version, summary: "可通过 Adobe 更新器检查")
        }
        if bundleID.hasPrefix("com.jetbrains.") {
            return vendorCapability(.jetBrainsToolbox, version: version, summary: "可通过 JetBrains Toolbox 或应用内更新检查")
        }
        if bundleID.hasPrefix("com.microsoft.") {
            return vendorCapability(.microsoftAutoUpdate, version: version, summary: "可通过 Microsoft AutoUpdate 检查")
        }
        if containsUpdaterHint(plist) {
            return AppUpdateCapability(
                detector: .unknownUpdater,
                confidence: .medium,
                feedURLString: "",
                installedVersion: version,
                summary: "检测到内置更新相关配置",
                diagnostic: "Info.plist 中存在 update/appcast 相关键。"
            )
        }

        return .none
    }

    private static func vendorCapability(
        _ detector: AppUpdateDetectorKind,
        version: String,
        summary: String
    ) -> AppUpdateCapability {
        AppUpdateCapability(
            detector: detector,
            confidence: .high,
            feedURLString: "",
            installedVersion: version,
            summary: summary,
            diagnostic: "根据 bundle identifier 识别为 \(detector.title) 更新家族。"
        )
    }

    private static func sparkleFeedURL(from plist: [String: Any]) -> String? {
        for key in ["SUFeedURL", "SUFeedURLForSparkle", "SUAppcastURL"] {
            let value = string(plist[key]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("http://") || value.hasPrefix("https://") {
                return value
            }
        }
        return nil
    }

    private static func containsUpdaterHint(_ plist: [String: Any]) -> Bool {
        plist.contains { key, value in
            let lowerKey = key.lowercased()
            guard lowerKey.contains("update") || lowerKey.contains("appcast") else {
                return false
            }
            return !string(value).isEmpty
        }
    }

    private static func string(_ value: Any?) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return ""
        }
    }
}
```

- [ ] **Step 5: Run the detector test to verify it passes**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/RegularAppUpdateDiscovery.swift \
  tests/RegularAppUpdateDiscoveryTest.swift \
  -o build/RegularAppUpdateDiscoveryTest
./build/RegularAppUpdateDiscoveryTest
```

Expected: command exits with status 0.

- [ ] **Step 6: Commit**

```bash
git add native/MacSoftwareSteward/Models.swift native/MacSoftwareSteward/RegularAppUpdateDiscovery.swift tests/RegularAppUpdateDiscoveryTest.swift
git commit -m "feat: detect regular app update capabilities"
```

---

### Task 2: Scanner Capability Wiring

**Files:**
- Modify: `native/MacSoftwareSteward/Scanner.swift`
- Test: `tests/ScannerAppUpdateCapabilityTest.swift`

- [ ] **Step 1: Write the failing scanner wiring test**

Create `tests/ScannerAppUpdateCapabilityTest.swift`:

```swift
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
```

- [ ] **Step 2: Run the scanner wiring test to verify it fails**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/CommandRunner.swift \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/RegularAppUpdateDiscovery.swift \
  native/MacSoftwareSteward/Scanner.swift \
  tests/ScannerAppUpdateCapabilityTest.swift \
  -o build/ScannerAppUpdateCapabilityTest
```

Expected: FAIL with `type 'SoftwareScanner' has no member 'attachUpdateCapabilities'`.

- [ ] **Step 3: Attach capabilities in scanner**

In `native/MacSoftwareSteward/Scanner.swift`:

1. In `scanApplications()`, after normalizing system profiler items, call:

```swift
let enrichedItems = attachUpdateCapabilities(to: items)
```

and return `enrichedItems`.

2. In `scanApplicationsByFind(reason:)`, after sorting items, return `attachUpdateCapabilities(to: items)`.

3. Add testable helpers near `classify`:

```swift
    static func attachUpdateCapabilities(to apps: [AppItem]) -> [AppItem] {
        apps.map { app in
            var next = app
            let capability = RegularAppUpdateDiscovery.discover(appPath: app.path)
            next.updateCapability = capability
            if next.managedBy == "manual", capability.hasManualAction, next.updateState == "unknown" {
                next.updateState = "checkable"
            }
            return next
        }
    }

    static func classifyForTesting(_ apps: [AppItem], brew: BrewScan, mas: MasScan) -> [AppItem] {
        classify(apps, brew: brew, mas: mas)
    }
```

Ensure `classify` does not overwrite `updateCapability`.

- [ ] **Step 4: Run the scanner wiring test to verify it passes**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/CommandRunner.swift \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/RegularAppUpdateDiscovery.swift \
  native/MacSoftwareSteward/Scanner.swift \
  tests/ScannerAppUpdateCapabilityTest.swift \
  -o build/ScannerAppUpdateCapabilityTest
./build/ScannerAppUpdateCapabilityTest
```

Expected: command exits with status 0.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/Scanner.swift tests/ScannerAppUpdateCapabilityTest.swift
git commit -m "feat: attach regular app update capabilities"
```

---

### Task 3: Applications UI Manual Update Entry

**Files:**
- Modify: `native/MacSoftwareSteward/StewardModel.swift`
- Modify: `native/MacSoftwareSteward/Views/ApplicationsView.swift`

- [ ] **Step 1: Add manual app opening helper**

In `native/MacSoftwareSteward/StewardModel.swift`, add near `reveal(_:)`:

```swift
    func open(_ app: AppItem) {
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: configuration) { _, error in
            if let error {
                Task { @MainActor in
                    self.errorMessage = "打开 \(app.name) 失败：\(error.localizedDescription)"
                }
            }
        }
    }
```

- [ ] **Step 2: Surface capability in app rows**

In `native/MacSoftwareSteward/Views/ApplicationsView.swift`:

1. Update the search text to include capability data:

```swift
"\($0.updateCapability.detector.title) \($0.updateCapability.summary)"
```

2. In `ApplicationRow`, after the outdated badge block, add:

```swift
                } else if app.updateState == "checkable" {
                    Badge(text: "可检查", color: .blue)
```

3. Before the Finder reveal button, add an open-app button for detected manual updaters:

```swift
                if app.updateCapability.hasManualAction && app.managedBy == "manual" {
                    Button {
                        model.open(app)
                    } label: {
                        Image(systemName: "play.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("打开应用检查更新")
                }
```

4. After the version/path row, add:

```swift
            if app.updateCapability.hasManualAction && app.managedBy == "manual" {
                AppUpdateCapabilityLine(capability: app.updateCapability)
                    .padding(.leading, 40)
            }
```

5. Add:

```swift
private struct AppUpdateCapabilityLine: View {
    var capability: AppUpdateCapability

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.app")
                .font(.caption)
                .foregroundStyle(.blue)
            Text(capability.detector.title)
                .font(.caption)
                .fontWeight(.semibold)
            Text(capability.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !capability.feedURLString.isEmpty {
                Text(capability.feedURLString)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }
}
```

- [ ] **Step 3: Build to verify UI compiles**

Run:

```bash
npm run build
git restore native/Resources/AppIcon.iconset/*.png
```

Expected: app and Agent build, sign and verify successfully.

- [ ] **Step 4: Commit**

```bash
git add native/MacSoftwareSteward/StewardModel.swift native/MacSoftwareSteward/Views/ApplicationsView.swift
git commit -m "feat: show regular app update capabilities"
```

---

### Task 4: Build And Test Wiring

**Files:**
- Modify: `scripts/build-native.sh`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Add detector to Agent build**

In `scripts/build-native.sh`, add before `Scanner.swift`:

```bash
  "$ROOT_DIR"/native/MacSoftwareSteward/RegularAppUpdateDiscovery.swift \
```

- [ ] **Step 2: Add tests to script**

In `scripts/test-native.sh`, add:

```bash
run_test RegularAppUpdateDiscoveryTest \
  "$SRC/Models.swift" \
  "$SRC/RegularAppUpdateDiscovery.swift" \
  "$TESTS/RegularAppUpdateDiscoveryTest.swift"

run_test ScannerAppUpdateCapabilityTest \
  "$SRC/CommandRunner.swift" \
  "$SRC/Models.swift" \
  "$SRC/RegularAppUpdateDiscovery.swift" \
  "$SRC/Scanner.swift" \
  "$TESTS/ScannerAppUpdateCapabilityTest.swift"
```

Also add `"$SRC/RegularAppUpdateDiscovery.swift"` to `ScannerBrewListFallbackTest`, `ScannerNormalizeTokenTest`, and `StewardModelScanGuardTest` source lists because they compile `Scanner.swift` or `StewardModel.swift`.

- [ ] **Step 3: Run full tests**

Run:

```bash
npm test
```

Expected: all native tests pass and output ends with `All native tests passed.`

- [ ] **Step 4: Commit**

```bash
git add scripts/build-native.sh scripts/test-native.sh
git commit -m "test: wire regular app discovery coverage"
```

---

### Task 5: Final Verification

**Files:**
- No source changes expected.

- [ ] **Step 1: Run full tests**

Run:

```bash
npm test
```

Expected: `All native tests passed.`

- [ ] **Step 2: Run full build**

Run:

```bash
npm run build
```

Expected: app build, Agent build, signing, signature verification and quarantine clearing all succeed.

- [ ] **Step 3: Clean build side effects and inspect status**

Run:

```bash
git restore native/Resources/AppIcon.iconset/*.png
git status --short
```

Expected: only the existing untracked `code-risk-scanner/` directory may appear and should not be staged.
