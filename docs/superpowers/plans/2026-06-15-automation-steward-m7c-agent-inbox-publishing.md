# Automation Steward M7c Agent Inbox Publishing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the daily inspection agent publish actionable scan outcomes into the local Inbox and link those Inbox items from inspection reports.

**Architecture:** Add a pure `DailyInspectionInboxPublisher` that combines existing `RiskInboxFactory` and `AppUpdateInboxFactory` output, writes items through `InboxStore`, and returns the written item IDs. Extend `InspectionReportBuilder` with an `inboxItemIDs` parameter while preserving the existing default. Wire `MacSoftwareStewardAgent` to publish Inbox items before report creation so the report references the user-visible decisions created by that inspection.

**Tech Stack:** Swift, SwiftUI/AppKit app target, standalone `swiftc` tests via `scripts/test-native.sh`, helper agent build through `scripts/build-native.sh`.

---

### Task 1: Inbox Publisher And Report IDs

**Files:**
- Create: `native/MacSoftwareSteward/DailyInspectionInboxPublisher.swift`
- Create: `tests/DailyInspectionInboxPublisherTest.swift`
- Modify: `native/MacSoftwareSteward/InspectionReportBuilder.swift`
- Modify: `tests/InspectionReportBuilderTest.swift`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Write the failing tests**

In `tests/InspectionReportBuilderTest.swift`, pass a known Inbox ID into the report builder and assert it is preserved:

```swift
let inboxID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
let report = InspectionReportBuilder.makeReport(
    trigger: .dailyAgent,
    startedAt: Date(timeIntervalSince1970: 100),
    finishedAt: Date(timeIntervalSince1970: 200),
    scan: scan,
    rows: rows,
    automaticPackages: [.brew(formula)],
    inboxItemIDs: [inboxID],
    failure: InspectionFailureRecord(message: "command failed", commandDisplay: "brew upgrade jq", exitCode: 1)
)
precondition(report.inboxItemIDs == [inboxID])
```

Create `tests/DailyInspectionInboxPublisherTest.swift`:

```swift
import Foundation

@main
struct DailyInspectionInboxPublisherTest {
    static func main() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("daily-inspection-inbox-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = InboxStore(fileURL: url)
        let risky = UpgradePlanRow(
            packageID: "brew:formula:node",
            packageName: "node",
            source: "Brew Formula",
            installedVersion: "20.1.0",
            currentVersion: "21.0.0",
            commandDisplay: "brew upgrade node",
            policy: .automatic,
            selection: .notSelected,
            riskLabels: ["major version"],
            skipReason: "需确认：major version",
            package: .brew(BrewPackage(id: "brew:formula:node", kind: "formula", name: "node", installedVersion: "20.1.0", currentVersion: "21.0.0", pinned: false, autoUpdates: false, outdated: true, upgradeable: true)),
            riskLevel: .high,
            riskSummary: "major version",
            automationDecision: .requireConfirmation
        )
        let lowRisk = UpgradePlanRow(
            packageID: "brew:formula:jq",
            packageName: "jq",
            source: "Brew Formula",
            installedVersion: "1.6",
            currentVersion: "1.7",
            commandDisplay: "brew upgrade jq",
            policy: .automatic,
            selection: .selected,
            riskLabels: [],
            skipReason: "",
            package: .brew(BrewPackage(id: "brew:formula:jq", kind: "formula", name: "jq", installedVersion: "1.6", currentVersion: "1.7", pinned: false, autoUpdates: false, outdated: true, upgradeable: true)),
            riskLevel: .low,
            riskSummary: "",
            automationDecision: .allowAutomatic
        )
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
        let scan = ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: false,
            summary: ScanSummary(applications: 1, brewFormulae: 2, brewCasks: 0, masApps: 0, outdated: 2, actionable: 2, scanMs: 10),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: [app]),
            brew: BrewScan(available: true, path: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew", version: "Homebrew", error: "", includeGreedy: false, formulae: [], casks: []),
            mas: MasScan(available: true, path: "/opt/homebrew/bin/mas", error: "", apps: [])
        )

        let firstIDs = DailyInspectionInboxPublisher.publish(scan: scan, rows: [risky, lowRisk], to: store)
        precondition(firstIDs.count == 2)
        precondition(Set(store.items.map(\.id)) == Set(firstIDs))
        precondition(store.items.contains { $0.kind == .upgradeDecision && $0.sourceID == "upgrade:brew:formula:node" })
        precondition(store.items.contains { $0.kind == .appUpdate && $0.sourceID == app.id })

        let secondIDs = DailyInspectionInboxPublisher.publish(scan: scan, rows: [risky, lowRisk], to: store)
        precondition(secondIDs.count == 2)
        precondition(store.items.count == 2)
        precondition(Set(store.items.map(\.id)) == Set(secondIDs))
    }
}
```

Add the new test to `scripts/test-native.sh` after `AppUpdateInboxFactoryTest`:

```bash
run_test DailyInspectionInboxPublisherTest \
  "$SRC/Models.swift" \
  "$SRC/UpgradePolicyStore.swift" \
  "$SRC/RiskAssessor.swift" \
  "$SRC/UpgradePlanner.swift" \
  "$SRC/InboxStore.swift" \
  "$SRC/RiskInboxFactory.swift" \
  "$SRC/AppUpdateInboxFactory.swift" \
  "$SRC/DailyInspectionInboxPublisher.swift" \
  "$TESTS/DailyInspectionInboxPublisherTest.swift"
```

- [ ] **Step 2: Run tests to verify red**

Run:

```bash
npm test
```

Expected: FAIL because `InspectionReportBuilder.makeReport` does not accept `inboxItemIDs`, or because `DailyInspectionInboxPublisher.swift` does not exist.

- [ ] **Step 3: Implement minimal green code**

Create `native/MacSoftwareSteward/DailyInspectionInboxPublisher.swift`:

```swift
import Foundation

enum DailyInspectionInboxPublisher {
    static func publish(scan: ScanResult, rows: [UpgradePlanRow], to inboxStore: InboxStore) -> [UUID] {
        let items = RiskInboxFactory.items(from: rows)
            + AppUpdateInboxFactory.items(from: scan.applications.items)

        return items.map { item in
            inboxStore.add(item)
            return item.id
        }
    }
}
```

Update `InspectionReportBuilder.makeReport`:

```swift
static func makeReport(
    trigger: InspectionReportTrigger,
    startedAt: Date,
    finishedAt: Date,
    scan: ScanResult,
    rows: [UpgradePlanRow],
    automaticPackages: [UpdatablePackage],
    inboxItemIDs: [UUID] = [],
    failure: InspectionFailureRecord? = nil
) -> InspectionReportRecord {
    ...
    inboxItemIDs: inboxItemIDs
)
```

- [ ] **Step 4: Run tests to verify green**

Run:

```bash
npm test
```

Expected: all native tests pass.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/DailyInspectionInboxPublisher.swift native/MacSoftwareSteward/InspectionReportBuilder.swift tests/DailyInspectionInboxPublisherTest.swift tests/InspectionReportBuilderTest.swift scripts/test-native.sh
git commit -m "feat: publish daily inspection inbox items"
```

### Task 2: Agent Wiring

**Files:**
- Modify: `native/MacSoftwareStewardAgent/AgentMain.swift`
- Modify: `scripts/build-native.sh`

- [ ] **Step 1: Wire Inbox publishing into the Agent**

In `native/MacSoftwareStewardAgent/AgentMain.swift`, after `automaticPackages` is computed, create an Inbox store and publish items:

```swift
let inboxStore = InboxStore()
let inboxItemIDs = DailyInspectionInboxPublisher.publish(scan: scan, rows: rows, to: inboxStore)
```

Pass `inboxItemIDs` to `InspectionReportBuilder.makeReport` inside `writeReportAndExit`.

- [ ] **Step 2: Add sources to Agent build**

In `scripts/build-native.sh`, add these files to the helper agent compile command before `native/MacSoftwareStewardAgent/*.swift`:

```bash
"$ROOT_DIR"/native/MacSoftwareSteward/InboxStore.swift \
"$ROOT_DIR"/native/MacSoftwareSteward/RiskInboxFactory.swift \
"$ROOT_DIR"/native/MacSoftwareSteward/AppUpdateInboxFactory.swift \
"$ROOT_DIR"/native/MacSoftwareSteward/DailyInspectionInboxPublisher.swift \
```

- [ ] **Step 3: Verify build and tests**

Run:

```bash
npm run build
git restore native/Resources/AppIcon.iconset/*.png
npm test
```

Expected: app and helper agent build, signature verification prints `Signature OK`, generated AppIcon PNGs are restored, and all native tests pass.

- [ ] **Step 4: Commit**

```bash
git add native/MacSoftwareStewardAgent/AgentMain.swift scripts/build-native.sh
git commit -m "feat: link agent inbox items to reports"
```

### Self-Review

- Spec coverage: This implements the remaining Agent flow requirement that background inspection writes Inbox items and associates them with an `InspectionReport`.
- Placeholder scan: No placeholders or TODOs remain.
- Type consistency: `DailyInspectionInboxPublisher.publish(scan:rows:to:)`, `InboxStore.add(_:)`, and `InspectionReportBuilder.makeReport(... inboxItemIDs:)` match the planned test and Agent call site.
