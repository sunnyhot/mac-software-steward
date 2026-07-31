# Automation Steward M7e Source Issue Inbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish Homebrew and Mac App Store source problems into the Inbox during foreground and background scans.

**Architecture:** Add a pure `SourceIssueInboxFactory` that converts `ScanResult` source availability/errors into stable `InboxItem` records. Include those items in `DailyInspectionInboxPublisher` for the helper agent and in `StewardModel.scanSoftware` for foreground scans, while keeping the factory Foundation-only so the helper agent remains non-GUI.

**Tech Stack:** Swift, standalone `swiftc` tests via `scripts/test-native.sh`, helper agent build through `scripts/build-native.sh`.

---

### Task 1: Source Issue Factory

**Files:**
- Create: `native/MacSoftwareSteward/SourceIssueInboxFactory.swift`
- Create: `tests/SourceIssueInboxFactoryTest.swift`
- Modify: `tests/DailyInspectionInboxPublisherTest.swift`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Write failing tests**

Create `tests/SourceIssueInboxFactoryTest.swift`:

```swift
import Foundation

@main
struct SourceIssueInboxFactoryTest {
    static func main() {
        let missingBrewScan = ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: false,
            summary: ScanSummary(applications: 0, brewFormulae: 0, brewCasks: 0, masApps: 0, outdated: 0, actionable: 0, scanMs: 1),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
            brew: BrewScan(available: false, path: "", prefix: "", version: "", error: "brew not found", includeGreedy: false, formulae: [], casks: []),
            mas: MasScan(available: true, path: "/opt/homebrew/bin/mas", error: "", apps: [])
        )
        let missingBrewItems = SourceIssueInboxFactory.items(from: missingBrewScan)
        precondition(missingBrewItems.count == 1)
        precondition(missingBrewItems[0].kind == .sourceIssue)
        precondition(missingBrewItems[0].severity == .warning)
        precondition(missingBrewItems[0].sourceID == "source:homebrew")
        precondition(missingBrewItems[0].title == "Homebrew 来源需要处理")
        precondition(missingBrewItems[0].actions.map(\.kind) == [.openSources, .rescan])

        let masUnavailableScan = ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: false,
            summary: ScanSummary(applications: 0, brewFormulae: 0, brewCasks: 0, masApps: 0, outdated: 0, actionable: 0, scanMs: 1),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
            brew: BrewScan(available: true, path: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew", version: "Homebrew", error: "", includeGreedy: false, formulae: [], casks: []),
            mas: MasScan(available: false, path: "", error: "mas not found", apps: [])
        )
        let masItems = SourceIssueInboxFactory.items(from: masUnavailableScan)
        precondition(masItems.count == 1)
        precondition(masItems[0].severity == .info)
        precondition(masItems[0].sourceID == "source:mas")
        precondition(masItems[0].summary.contains("App Store"))

        let healthyScan = ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: false,
            summary: ScanSummary(applications: 0, brewFormulae: 0, brewCasks: 0, masApps: 0, outdated: 0, actionable: 0, scanMs: 1),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
            brew: BrewScan(available: true, path: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew", version: "Homebrew", error: "", includeGreedy: false, formulae: [], casks: []),
            mas: MasScan(available: true, path: "/opt/homebrew/bin/mas", error: "", apps: [])
        )
        precondition(SourceIssueInboxFactory.items(from: healthyScan).isEmpty)
    }
}
```

Add a source-issue integration assertion to `tests/DailyInspectionInboxPublisherTest.swift` after the existing duplicate-publish checks:

```swift
let sourceURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("daily-inspection-source-inbox-\(UUID().uuidString).json")
defer { try? FileManager.default.removeItem(at: sourceURL) }
let sourceStore = InboxStore(fileURL: sourceURL)
let sourceScan = ScanResult(
    scannedAt: Date(timeIntervalSince1970: 1),
    includeGreedy: false,
    summary: ScanSummary(applications: 0, brewFormulae: 0, brewCasks: 0, masApps: 0, outdated: 0, actionable: 0, scanMs: 1),
    applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
    brew: BrewScan(available: false, path: "", prefix: "", version: "", error: "brew not found", includeGreedy: false, formulae: [], casks: []),
    mas: MasScan(available: true, path: "/opt/homebrew/bin/mas", error: "", apps: [])
)
let sourceIDs = DailyInspectionInboxPublisher.publish(scan: sourceScan, rows: [], to: sourceStore)
precondition(sourceIDs.count == 1)
precondition(sourceStore.items[0].kind == .sourceIssue)
precondition(sourceStore.items[0].sourceID == "source:homebrew")
```

Add `SourceIssueInboxFactoryTest` to `scripts/test-native.sh` after `AppUpdateInboxFactoryTest`, and include `SourceIssueInboxFactory.swift` in `DailyInspectionInboxPublisherTest`:

```bash
run_test SourceIssueInboxFactoryTest \
  "$SRC/Models.swift" \
  "$SRC/InboxStore.swift" \
  "$SRC/SourceIssueInboxFactory.swift" \
  "$TESTS/SourceIssueInboxFactoryTest.swift"
```

- [ ] **Step 2: Run tests to verify red**

Run:

```bash
npm test
```

Expected: FAIL because `SourceIssueInboxFactory.swift` does not exist or `DailyInspectionInboxPublisher` does not publish source items.

- [ ] **Step 3: Implement factory and background publisher integration**

Create `native/MacSoftwareSteward/SourceIssueInboxFactory.swift`:

```swift
import Foundation

enum SourceIssueInboxFactory {
    static func items(from scan: ScanResult) -> [InboxItem] {
        [brewItem(from: scan.brew), masItem(from: scan.mas)]
            .compactMap { $0 }
    }

    private static func brewItem(from brew: BrewScan) -> InboxItem? {
        if !brew.available {
            return item(
                severity: .warning,
                title: "Homebrew 来源需要处理",
                summary: "未检测到 Homebrew，Homebrew 软件扫描和升级不可用。",
                sourceID: "source:homebrew"
            )
        }
        guard !brew.error.isEmpty else { return nil }
        return item(
            severity: .warning,
            title: "Homebrew 来源需要处理",
            summary: "Homebrew 扫描遇到错误：\(trimmed(brew.error))",
            sourceID: "source:homebrew"
        )
    }

    private static func masItem(from mas: MasScan) -> InboxItem? {
        if !mas.available {
            return item(
                severity: .info,
                title: "App Store 来源需要处理",
                summary: "未检测到 mas CLI，App Store 应用扫描和升级不可用。",
                sourceID: "source:mas"
            )
        }
        guard !mas.error.isEmpty else { return nil }
        return item(
            severity: .warning,
            title: "App Store 来源需要处理",
            summary: "App Store 扫描遇到错误：\(trimmed(mas.error))",
            sourceID: "source:mas"
        )
    }

    private static func item(
        severity: InboxSeverity,
        title: String,
        summary: String,
        sourceID: String
    ) -> InboxItem {
        InboxItem(
            kind: .sourceIssue,
            severity: severity,
            title: title,
            summary: summary,
            sourceID: sourceID,
            actions: [
                InboxAction(title: "查看来源", systemImage: "tray.full", kind: .openSources),
                InboxAction(title: "重新扫描", systemImage: "arrow.clockwise", kind: .rescan)
            ]
        )
    }

    private static func trimmed(_ text: String) -> String {
        let singleLine = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first ?? text
        let trimmed = singleLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未知错误" : trimmed
    }
}
```

Update `DailyInspectionInboxPublisher.publish` so `items` starts with source issue items:

```swift
let items = SourceIssueInboxFactory.items(from: scan)
    + RiskInboxFactory.items(from: rows)
    + AppUpdateInboxFactory.items(from: scan.applications.items)
```

- [ ] **Step 4: Run tests to verify green**

Run:

```bash
npm test
```

Expected: all native tests pass.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/SourceIssueInboxFactory.swift native/MacSoftwareSteward/DailyInspectionInboxPublisher.swift tests/SourceIssueInboxFactoryTest.swift tests/DailyInspectionInboxPublisherTest.swift scripts/test-native.sh
git commit -m "feat: publish source issues to inbox"
```

### Task 2: Foreground Scan Integration

**Files:**
- Modify: `native/MacSoftwareSteward/StewardModel.swift`
- Modify: `scripts/test-native.sh`
- Modify: `scripts/build-native.sh`

- [ ] **Step 1: Wire foreground scans and compile dependencies**

In `StewardModel.scanSoftware`, replace the `AppUpdateInboxFactory.items` loop with:

```swift
for item in SourceIssueInboxFactory.items(from: result)
    + AppUpdateInboxFactory.items(from: result.applications.items) {
    if inboxStore.add(item) {
        newInboxItems.append(item)
    }
}
```

Add `SourceIssueInboxFactory.swift` to every `scripts/test-native.sh` test that compiles `StewardModel.swift`, and add it to the helper agent compile command in `scripts/build-native.sh`.

- [ ] **Step 2: Verify build and tests**

Run:

```bash
npm run build
git restore native/Resources/AppIcon.iconset/*.png
npm test
```

Expected: app and helper agent build, signature verification prints `Signature OK`, generated AppIcon PNGs are restored, and all native tests pass.

- [ ] **Step 3: Commit**

```bash
git add native/MacSoftwareSteward/StewardModel.swift scripts/test-native.sh scripts/build-native.sh
git commit -m "feat: surface source issues during scans"
```

### Self-Review

- Spec coverage: Source problems now reach the Inbox in both foreground scans and background daily inspections.
- Placeholder scan: No placeholders or TODOs remain.
- Type consistency: `SourceIssueInboxFactory.items(from:)`, `DailyInspectionInboxPublisher.publish(scan:rows:to:)`, and `StewardModel.scanSoftware(... inboxStore:)` match the planned call sites.
