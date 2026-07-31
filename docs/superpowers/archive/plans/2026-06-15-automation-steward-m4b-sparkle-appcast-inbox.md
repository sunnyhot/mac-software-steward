# Automation Steward M4b Sparkle Appcast Inbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Check Sparkle appcast feeds under the regular app network policy, mark ordinary apps with available versions, and create inbox items for manual app update decisions.

**Architecture:** Keep M4a local detector intact and add a focused appcast parser/checker plus an inbox factory. `SoftwareScanner.scanAll` accepts a `RegularAppNetworkPolicy` parameter, fetches only declared Sparkle feed URLs when policy allows, and never uploads the local app list. `StewardModel.scanSoftware` accepts optional policy and inbox store parameters so main-window scans can honor settings and create local inbox items.

**Tech Stack:** Swift Foundation, URLSession, XMLParser, SwiftUI wiring, existing `swiftc` single-file tests.

---

## Scope Check

This plan implements M4b only:

- Parse Sparkle appcast XML into a latest version string.
- Fetch declared Sparkle feed URLs when `regularAppNetworkPolicy != .localOnly`.
- Mark Sparkle apps as `outdated` when the appcast version differs from the installed version.
- Preserve local-only behavior by skipping feed fetches under `.localOnly`.
- Create deduplicated `InboxItemKind.appUpdate` items for ordinary apps with available versions.
- Wire main-window scan buttons and Inbox rescan actions to pass the user's network policy and inbox store.

This plan does not implement vendor-specific online checks, appcast signature validation, download/install actions, notifications, or silent replacement of `.app` bundles.

## File Structure

- Create `native/MacSoftwareSteward/SparkleAppcastChecker.swift`: appcast parsing and declared feed fetching.
- Modify `native/MacSoftwareSteward/Scanner.swift`: pass network policy and enrich Sparkle app capabilities.
- Create `native/MacSoftwareSteward/AppUpdateInboxFactory.swift`: convert ordinary app updates into inbox items.
- Modify `native/MacSoftwareSteward/StewardModel.swift`: accept `regularAppNetworkPolicy` and `inboxStore` during scans.
- Modify `native/MacSoftwareSteward/App.swift`, `native/MacSoftwareSteward/ContentView.swift` and `native/MacSoftwareSteward/Views/InboxView.swift`: pass settings/inbox into startup scan, main scan and rescan actions.
- Modify `scripts/build-native.sh`: include `AutomationProfileStore.swift` and `SparkleAppcastChecker.swift` in Agent compilation because `Scanner.swift` now depends on them.
- Modify `scripts/test-native.sh`: add tests and source dependencies.
- Create `tests/SparkleAppcastCheckerTest.swift`.
- Create `tests/ScannerSparkleAppcastPolicyTest.swift`.
- Create `tests/AppUpdateInboxFactoryTest.swift`.

---

### Task 1: Sparkle Appcast Parser And Checker

**Files:**
- Create: `native/MacSoftwareSteward/SparkleAppcastChecker.swift`
- Test: `tests/SparkleAppcastCheckerTest.swift`

- [ ] **Step 1: Write the failing appcast test**

Create `tests/SparkleAppcastCheckerTest.swift`:

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
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  tests/SparkleAppcastCheckerTest.swift \
  -o build/SparkleAppcastCheckerTest
```

Expected: FAIL with `cannot find 'SparkleAppcastChecker' in scope`.

- [ ] **Step 3: Add appcast parser/checker**

Create `native/MacSoftwareSteward/SparkleAppcastChecker.swift`:

```swift
import Foundation

struct SparkleAppcastCheckResult: Hashable {
    var availableVersion: String
    var diagnostic: String
}

enum SparkleAppcastChecker {
    static func check(feedURLString: String, installedVersion: String) async -> SparkleAppcastCheckResult {
        guard let url = URL(string: feedURLString), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return SparkleAppcastCheckResult(availableVersion: "", diagnostic: "Sparkle feed URL 无效。")
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
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
            return SparkleAppcastCheckResult(availableVersion: "", diagnostic: "Sparkle feed 检查失败：\(error.localizedDescription)")
        }
    }

    static func parseLatestVersion(from data: Data) -> String? {
        let parser = SparkleAppcastVersionParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else { return nil }
        return parser.version
    }

    static func isNewerVersion(_ candidate: String, than installed: String) -> Bool {
        candidate.compare(installed, options: [.numeric, .caseInsensitive]) == .orderedDescending
    }
}

private final class SparkleAppcastVersionParser: NSObject, XMLParserDelegate {
    var version: String?
    private var captureVersionText = false
    private var versionText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = (qName ?? elementName).lowercased()
        if name == "enclosure" {
            version = attributeDict["sparkle:shortVersionString"]
                ?? attributeDict["sparkle:version"]
                ?? attributeDict["shortVersionString"]
                ?? attributeDict["version"]
        } else if name == "sparkle:version" || name == "version" {
            captureVersionText = true
            versionText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if captureVersionText {
            versionText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = (qName ?? elementName).lowercased()
        if name == "sparkle:version" || name == "version" {
            let trimmed = versionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if version == nil, !trimmed.isEmpty {
                version = trimmed
            }
            captureVersionText = false
        }
    }
}
```

- [ ] **Step 4: Run the appcast test to verify it passes**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/SparkleAppcastChecker.swift \
  tests/SparkleAppcastCheckerTest.swift \
  -o build/SparkleAppcastCheckerTest
./build/SparkleAppcastCheckerTest
```

Expected: command exits with status 0.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/SparkleAppcastChecker.swift tests/SparkleAppcastCheckerTest.swift
git commit -m "feat: parse sparkle appcasts"
```

---

### Task 2: Scanner Policy And Sparkle Enrichment

**Files:**
- Modify: `native/MacSoftwareSteward/Scanner.swift`
- Test: `tests/ScannerSparkleAppcastPolicyTest.swift`

- [ ] **Step 1: Write the failing scanner policy test**

Create `tests/ScannerSparkleAppcastPolicyTest.swift`:

```swift
import Foundation

@main
struct ScannerSparkleAppcastPolicyTest {
    static func main() async {
        let app = AppItem(
            id: "app:/Applications/Sparkle.app",
            name: "Sparkle",
            version: "1.0",
            availableVersion: "",
            path: "/Applications/Sparkle.app",
            source: "Developer",
            obtainedFrom: "Identified Developer",
            architecture: "arm64",
            managedBy: "manual",
            updateState: "checkable",
            relatedPackageID: "",
            updateCapability: AppUpdateCapability(
                detector: .sparkle,
                confidence: .high,
                feedURLString: "https://example.com/appcast.xml",
                installedVersion: "1.0",
                summary: "可通过 Sparkle 检查更新",
                diagnostic: ""
            )
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
    }
}
```

- [ ] **Step 2: Run the scanner policy test to verify it fails**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/CommandRunner.swift \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/AutomationProfileStore.swift \
  native/MacSoftwareSteward/RegularAppUpdateDiscovery.swift \
  native/MacSoftwareSteward/SparkleAppcastChecker.swift \
  native/MacSoftwareSteward/Scanner.swift \
  tests/ScannerSparkleAppcastPolicyTest.swift \
  -o build/ScannerSparkleAppcastPolicyTest
```

Expected: FAIL with `type 'SoftwareScanner' has no member 'enrichRegularAppUpdates'`.

- [ ] **Step 3: Add scanner appcast enrichment**

In `native/MacSoftwareSteward/Scanner.swift`:

1. Change `scanAll` signature:

```swift
static func scanAll(
    includeGreedy: Bool,
    regularAppNetworkPolicy: RegularAppNetworkPolicy = .declaredSourcesOnly,
    onPhaseChange: ((ScanPhase) -> Void)? = nil
) async -> ScanResult
```

2. After classification, call:

```swift
applications.items = await enrichRegularAppUpdates(applications.items, networkPolicy: regularAppNetworkPolicy)
```

3. Add:

```swift
    typealias SparkleChecker = (String, String) async -> SparkleAppcastCheckResult

    static func enrichRegularAppUpdates(
        _ apps: [AppItem],
        networkPolicy: RegularAppNetworkPolicy,
        sparkleChecker: SparkleChecker = SparkleAppcastChecker.check
    ) async -> [AppItem] {
        guard networkPolicy != .localOnly else { return apps }
        var enriched: [AppItem] = []
        for app in apps {
            var next = app
            guard next.managedBy == "manual",
                  next.updateCapability.detector == .sparkle,
                  !next.updateCapability.feedURLString.isEmpty else {
                enriched.append(next)
                continue
            }

            let installedVersion = next.updateCapability.installedVersion.isEmpty ? next.version : next.updateCapability.installedVersion
            let result = await sparkleChecker(next.updateCapability.feedURLString, installedVersion)
            next.updateCapability.diagnostic = result.diagnostic
            if !result.availableVersion.isEmpty {
                next.availableVersion = result.availableVersion
                next.updateState = "outdated"
                next.updateCapability.summary = "Sparkle 发现新版本 \(result.availableVersion)"
            }
            enriched.append(next)
        }
        return enriched
    }
```

- [ ] **Step 4: Run the scanner policy test to verify it passes**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/CommandRunner.swift \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/AutomationProfileStore.swift \
  native/MacSoftwareSteward/RegularAppUpdateDiscovery.swift \
  native/MacSoftwareSteward/SparkleAppcastChecker.swift \
  native/MacSoftwareSteward/Scanner.swift \
  tests/ScannerSparkleAppcastPolicyTest.swift \
  -o build/ScannerSparkleAppcastPolicyTest
./build/ScannerSparkleAppcastPolicyTest
```

Expected: command exits with status 0.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/Scanner.swift tests/ScannerSparkleAppcastPolicyTest.swift
git commit -m "feat: check sparkle appcasts during scans"
```

---

### Task 3: App Update Inbox Items

**Files:**
- Create: `native/MacSoftwareSteward/AppUpdateInboxFactory.swift`
- Test: `tests/AppUpdateInboxFactoryTest.swift`

- [ ] **Step 1: Write the failing inbox factory test**

Create `tests/AppUpdateInboxFactoryTest.swift`:

```swift
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
```

- [ ] **Step 2: Run the inbox factory test to verify it fails**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/InboxStore.swift \
  tests/AppUpdateInboxFactoryTest.swift \
  -o build/AppUpdateInboxFactoryTest
```

Expected: FAIL with `cannot find 'AppUpdateInboxFactory' in scope`.

- [ ] **Step 3: Add app update inbox factory**

Create `native/MacSoftwareSteward/AppUpdateInboxFactory.swift`:

```swift
import Foundation

enum AppUpdateInboxFactory {
    static func items(from apps: [AppItem]) -> [InboxItem] {
        apps
            .filter { app in
                app.managedBy == "manual"
                    && app.updateState == "outdated"
                    && !app.availableVersion.isEmpty
                    && app.updateCapability.hasManualAction
            }
            .map { app in
                InboxItem(
                    kind: .appUpdate,
                    severity: .info,
                    title: "\(app.name) 可更新",
                    summary: "当前 \(versionText(app.version))，可用 \(app.availableVersion)。\(app.updateCapability.detector.title) 需要手动打开应用或更新器处理。",
                    sourceID: app.id,
                    actions: [
                        InboxAction(title: "查看应用", systemImage: "macwindow", kind: .openApplications),
                        InboxAction(title: "重新扫描", systemImage: "arrow.clockwise", kind: .rescan)
                    ]
                )
            }
    }

    private static func versionText(_ version: String) -> String {
        version.isEmpty ? "未知版本" : version
    }
}
```

- [ ] **Step 4: Run the inbox factory test to verify it passes**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/InboxStore.swift \
  native/MacSoftwareSteward/AppUpdateInboxFactory.swift \
  tests/AppUpdateInboxFactoryTest.swift \
  -o build/AppUpdateInboxFactoryTest
./build/AppUpdateInboxFactoryTest
```

Expected: command exits with status 0.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/AppUpdateInboxFactory.swift tests/AppUpdateInboxFactoryTest.swift
git commit -m "feat: create inbox items for app updates"
```

---

### Task 4: Steward Model And UI Wiring

**Files:**
- Modify: `native/MacSoftwareSteward/App.swift`
- Modify: `native/MacSoftwareSteward/StewardModel.swift`
- Modify: `native/MacSoftwareSteward/SoftwareScanning.swift`
- Modify: `native/MacSoftwareSteward/ContentView.swift`
- Modify: `native/MacSoftwareSteward/Views/InboxView.swift`
- Modify: `tests/StewardModelScanGuardTest.swift`

- [ ] **Step 1: Wire scan policy and inbox into model**

In `native/MacSoftwareSteward/StewardModel.swift`, change `scanSoftware` signature and scanner call:

```swift
    func scanSoftware(
        regularAppNetworkPolicy: RegularAppNetworkPolicy = .declaredSourcesOnly,
        inboxStore: InboxStore? = nil
    ) async {
```

```swift
        let result = await scanner.scanAll(includeGreedy: includeGreedy, regularAppNetworkPolicy: regularAppNetworkPolicy) { [weak self] phase in
```

After `recomputeDerivedData()` add:

```swift
        if let inboxStore {
            for item in AppUpdateInboxFactory.items(from: result.applications.items) {
                inboxStore.add(item)
            }
        }
```

- [ ] **Step 2: Extend software scanning protocol**

In `native/MacSoftwareSteward/SoftwareScanning.swift`, change protocol and live implementation:

```swift
func scanAll(
    includeGreedy: Bool,
    regularAppNetworkPolicy: RegularAppNetworkPolicy,
    onPhaseChange: ((ScanPhase) -> Void)?
) async -> ScanResult
```

and:

```swift
func scanAll(
    includeGreedy: Bool,
    regularAppNetworkPolicy: RegularAppNetworkPolicy = .declaredSourcesOnly,
    onPhaseChange: ((ScanPhase) -> Void)? = nil
) async -> ScanResult {
    await SoftwareScanner.scanAll(
        includeGreedy: includeGreedy,
        regularAppNetworkPolicy: regularAppNetworkPolicy,
        onPhaseChange: onPhaseChange
    )
}
```

- [ ] **Step 3: Update scan guard test mock**

In `tests/StewardModelScanGuardTest.swift`, change the mock scanner signature:

```swift
    func scanAll(
        includeGreedy: Bool,
        regularAppNetworkPolicy: RegularAppNetworkPolicy,
        onPhaseChange: ((ScanPhase) -> Void)?
    ) async -> ScanResult {
```

The body stays the same.

- [ ] **Step 4: Pass settings from startup and main scan buttons**

In `native/MacSoftwareSteward/App.swift`, where startup and menu actions call `model.scanSoftware()`, use:

```swift
Task {
    await model.scanSoftware(
        regularAppNetworkPolicy: automationProfile.profile.regularAppNetworkPolicy,
        inboxStore: inboxStore
    )
}
```

In `native/MacSoftwareSteward/ContentView.swift`, where scan buttons call `model.scanSoftware()`, use:

```swift
Task {
    await model.scanSoftware(
        regularAppNetworkPolicy: automationProfile.profile.regularAppNetworkPolicy,
        inboxStore: inboxStore
    )
}
```

In `native/MacSoftwareSteward/Views/InboxView.swift`, change `.rescan` to the same call using `automationProfile` and `inboxStore`.

- [ ] **Step 5: Build to verify UI compiles**

Run:

```bash
npm run build
git restore native/Resources/AppIcon.iconset/*.png
```

Expected: app and Agent build, sign and verify successfully.

- [ ] **Step 6: Commit**

```bash
git add native/MacSoftwareSteward/App.swift native/MacSoftwareSteward/StewardModel.swift native/MacSoftwareSteward/SoftwareScanning.swift native/MacSoftwareSteward/ContentView.swift native/MacSoftwareSteward/Views/InboxView.swift tests/StewardModelScanGuardTest.swift
git commit -m "feat: write app updates to inbox during scans"
```

---

### Task 5: Build And Test Wiring

**Files:**
- Modify: `scripts/build-native.sh`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Add new sources to Agent build**

In `scripts/build-native.sh`, add before `Scanner.swift`:

```bash
  "$ROOT_DIR"/native/MacSoftwareSteward/AutomationProfileStore.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/SparkleAppcastChecker.swift \
```

- [ ] **Step 2: Add tests to script**

In `scripts/test-native.sh`, add:

```bash
run_test SparkleAppcastCheckerTest \
  "$SRC/Models.swift" \
  "$SRC/SparkleAppcastChecker.swift" \
  "$TESTS/SparkleAppcastCheckerTest.swift"

run_test ScannerSparkleAppcastPolicyTest \
  "$SRC/CommandRunner.swift" \
  "$SRC/Models.swift" \
  "$SRC/AutomationProfileStore.swift" \
  "$SRC/RegularAppUpdateDiscovery.swift" \
  "$SRC/SparkleAppcastChecker.swift" \
  "$SRC/Scanner.swift" \
  "$TESTS/ScannerSparkleAppcastPolicyTest.swift"

run_test AppUpdateInboxFactoryTest \
  "$SRC/Models.swift" \
  "$SRC/InboxStore.swift" \
  "$SRC/AppUpdateInboxFactory.swift" \
  "$TESTS/AppUpdateInboxFactoryTest.swift"
```

Also add `"$SRC/AutomationProfileStore.swift"` and `"$SRC/SparkleAppcastChecker.swift"` to tests that compile `Scanner.swift`, and add `"$SRC/AppUpdateInboxFactory.swift"` to `StewardModelScanGuardTest`.

- [ ] **Step 3: Run full tests**

Run:

```bash
npm test
```

Expected: all native tests pass and output ends with `All native tests passed.`

- [ ] **Step 4: Commit**

```bash
git add scripts/build-native.sh scripts/test-native.sh
git commit -m "test: wire sparkle appcast coverage"
```

---

### Task 6: Final Verification

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
