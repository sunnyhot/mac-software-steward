# Automation Steward M3 Inspection Reports Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist daily inspection reports from the background Agent and show those reports in the History view alongside existing upgrade history.

**Architecture:** Add focused report models and JSON persistence in `InspectionReportStore`, add pure report construction in `InspectionReportBuilder`, then let `MacSoftwareStewardAgent` append a report before every normal or error exit. The main app owns an `InspectionReportStore` through `StewardModel`, and `HistoryView` renders reports without parsing text logs.

**Tech Stack:** Swift 5, SwiftUI, Foundation JSON persistence, existing `swiftc` scripts, existing single-file Swift tests.

---

## Scope Check

This plan implements M3 only:

- Local inspection report model and persistence.
- Report construction from scan results, upgrade plan rows, automatic package selection and failures.
- Background Agent writes a report for daily checks.
- History view shows inspection reports and existing upgrade records.
- Tests and build script wiring.

This plan does not implement ordinary `.app` update discovery, system notification delivery, auto-repair execution or import/export.

## File Structure

- Create `native/MacSoftwareSteward/InspectionReportStore.swift`: report models, JSON storage, append/clear/reload.
- Create `native/MacSoftwareSteward/InspectionReportBuilder.swift`: pure helper that builds report records from scan and upgrade plan data.
- Modify `native/MacSoftwareSteward/StewardModel.swift`: add `inspectionReportStore`.
- Modify `native/MacSoftwareSteward/Views/HistoryView.swift`: render inspection reports above upgrade history.
- Modify `native/MacSoftwareStewardAgent/AgentMain.swift`: append a report before exit.
- Modify `scripts/build-native.sh`: include report files in Agent compilation.
- Modify `scripts/test-native.sh`: add new tests and required source lists.
- Create `tests/InspectionReportStoreTest.swift`.
- Create `tests/InspectionReportBuilderTest.swift`.

---

### Task 1: Inspection Report Store

**Files:**
- Create: `native/MacSoftwareSteward/InspectionReportStore.swift`
- Test: `tests/InspectionReportStoreTest.swift`

- [ ] **Step 1: Write the failing test**

Create `tests/InspectionReportStoreTest.swift`:

```swift
import Foundation

@main
struct InspectionReportStoreTest {
    static func main() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("inspection-reports-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = InspectionReportRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            trigger: .dailyAgent,
            startedAt: Date(timeIntervalSince1970: 1),
            finishedAt: Date(timeIntervalSince1970: 2),
            status: .succeeded,
            scanSummary: InspectionScanSummary(applications: 10, brewFormulae: 2, brewCasks: 3, masApps: 4, outdated: 5, actionable: 6),
            automaticUpgrades: [
                InspectionPackageRecord(packageID: "brew:formula:jq", packageName: "jq", source: "Brew Formula")
            ],
            skippedItems: [],
            failures: [],
            inboxItemIDs: []
        )
        let second = InspectionReportRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            trigger: .manualRun,
            startedAt: Date(timeIntervalSince1970: 3),
            finishedAt: Date(timeIntervalSince1970: 4),
            status: .failed,
            scanSummary: InspectionScanSummary(applications: 1, brewFormulae: 1, brewCasks: 1, masApps: 1, outdated: 1, actionable: 1),
            automaticUpgrades: [],
            skippedItems: [
                InspectionSkippedRecord(packageID: "brew:formula:node", packageName: "node", reason: "需确认：检测到 major 版本变化")
            ],
            failures: [
                InspectionFailureRecord(message: "brew upgrade failed", commandDisplay: "brew upgrade jq", exitCode: 1)
            ],
            inboxItemIDs: []
        )

        let store = InspectionReportStore(fileURL: url, limit: 1)
        precondition(store.reports.isEmpty)
        store.append(first)
        store.append(second)
        precondition(store.reports.map(\.id) == [second.id])

        let reloaded = InspectionReportStore(fileURL: url, limit: 5)
        precondition(reloaded.reports.count == 1)
        precondition(reloaded.reports[0].status == .failed)
        precondition(reloaded.reports[0].failures[0].exitCode == 1)

        reloaded.clear()
        precondition(reloaded.reports.isEmpty)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  tests/InspectionReportStoreTest.swift \
  -o build/InspectionReportStoreTest
```

Expected: FAIL with `cannot find 'InspectionReportStore' in scope`.

- [ ] **Step 3: Add report models and store**

Create `native/MacSoftwareSteward/InspectionReportStore.swift` with:

- `InspectionReportTrigger`
- `InspectionReportStatus`
- `InspectionScanSummary`
- `InspectionPackageRecord`
- `InspectionSkippedRecord`
- `InspectionFailureRecord`
- `InspectionReportRecord`
- `InspectionReportStore`

`InspectionReportStore` must mirror existing store style: `@Published private(set) var reports`, default URL at `~/Library/Application Support/MacSoftwareSteward/inspection-reports.json`, `append`, `clear`, `reload`, JSON date strategy `.iso8601`, newest-first sort and limit trimming.

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/InspectionReportStore.swift \
  tests/InspectionReportStoreTest.swift \
  -o build/InspectionReportStoreTest
./build/InspectionReportStoreTest
```

Expected: command exits with status 0.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/InspectionReportStore.swift tests/InspectionReportStoreTest.swift
git commit -m "feat: add inspection report store"
```

---

### Task 2: Inspection Report Builder

**Files:**
- Create: `native/MacSoftwareSteward/InspectionReportBuilder.swift`
- Test: `tests/InspectionReportBuilderTest.swift`

- [ ] **Step 1: Write the failing test**

Create `tests/InspectionReportBuilderTest.swift`:

```swift
import Foundation

@main
struct InspectionReportBuilderTest {
    static func main() {
        let formula = BrewPackage(id: "brew:formula:jq", kind: "formula", name: "jq", installedVersion: "1", currentVersion: "2", pinned: false, autoUpdates: false, outdated: true, upgradeable: true)
        let risky = BrewPackage(id: "brew:formula:node", kind: "formula", name: "node", installedVersion: "20", currentVersion: "21", pinned: false, autoUpdates: false, outdated: true, upgradeable: true)
        let scan = ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: false,
            summary: ScanSummary(applications: 3, brewFormulae: 2, brewCasks: 0, masApps: 0, outdated: 2, actionable: 2, scanMs: 10),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
            brew: BrewScan(available: true, path: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew", version: "Homebrew", error: "", includeGreedy: false, formulae: [formula, risky], casks: []),
            mas: MasScan(available: true, path: "/opt/homebrew/bin/mas", error: "", apps: [])
        )
        let rows = [
            UpgradePlanRow(packageID: formula.id, packageName: formula.name, source: "Brew Formula", installedVersion: "1", currentVersion: "2", commandDisplay: "brew upgrade jq", policy: .automatic, selection: .selected, riskLabels: [], skipReason: "", package: .brew(formula), riskLevel: .low, riskSummary: "", automationDecision: .allowAutomatic),
            UpgradePlanRow(packageID: risky.id, packageName: risky.name, source: "Brew Formula", installedVersion: "20", currentVersion: "21", commandDisplay: "brew upgrade node", policy: .automatic, selection: .notSelected, riskLabels: ["major version"], skipReason: "需确认：检测到 major 版本变化", package: .brew(risky), riskLevel: .high, riskSummary: "检测到 major 版本变化", automationDecision: .requireConfirmation)
        ]

        let report = InspectionReportBuilder.makeReport(
            trigger: .dailyAgent,
            startedAt: Date(timeIntervalSince1970: 100),
            finishedAt: Date(timeIntervalSince1970: 200),
            scan: scan,
            rows: rows,
            automaticPackages: [.brew(formula)],
            failure: InspectionFailureRecord(message: "command failed", commandDisplay: "brew upgrade jq", exitCode: 1)
        )

        precondition(report.status == .failed)
        precondition(report.scanSummary.applications == 3)
        precondition(report.automaticUpgrades.map(\.packageID) == [formula.id])
        precondition(report.skippedItems.map(\.packageID) == [risky.id])
        precondition(report.skippedItems[0].reason == "需确认：检测到 major 版本变化")
        precondition(report.failures.first?.exitCode == 1)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/InspectionReportStore.swift \
  native/MacSoftwareSteward/UpgradePolicyStore.swift \
  native/MacSoftwareSteward/RiskAssessor.swift \
  native/MacSoftwareSteward/UpgradePlanner.swift \
  tests/InspectionReportBuilderTest.swift \
  -o build/InspectionReportBuilderTest
```

Expected: FAIL with `cannot find 'InspectionReportBuilder' in scope`.

- [ ] **Step 3: Add report builder**

Create `native/MacSoftwareSteward/InspectionReportBuilder.swift`.

It must provide:

```swift
enum InspectionReportBuilder {
    static func makeReport(
        trigger: InspectionReportTrigger,
        startedAt: Date,
        finishedAt: Date,
        scan: ScanResult,
        rows: [UpgradePlanRow],
        automaticPackages: [UpdatablePackage],
        failure: InspectionFailureRecord? = nil
    ) -> InspectionReportRecord
}
```

Rules:

- `status` is `.failed` when `failure != nil`, otherwise `.succeeded`.
- `scanSummary` copies counts from `scan.summary`.
- `automaticUpgrades` maps `automaticPackages`.
- `skippedItems` includes rows that were not automatically upgraded and either cannot execute, are not selected, or have a non-empty `skipReason`.
- `reason` uses `skipReason` if non-empty, otherwise `riskSummary`, otherwise `policy.title`.

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/InspectionReportStore.swift \
  native/MacSoftwareSteward/InspectionReportBuilder.swift \
  native/MacSoftwareSteward/UpgradePolicyStore.swift \
  native/MacSoftwareSteward/RiskAssessor.swift \
  native/MacSoftwareSteward/UpgradePlanner.swift \
  tests/InspectionReportBuilderTest.swift \
  -o build/InspectionReportBuilderTest
./build/InspectionReportBuilderTest
```

Expected: command exits with status 0.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/InspectionReportBuilder.swift tests/InspectionReportBuilderTest.swift
git commit -m "feat: build inspection report records"
```

---

### Task 3: Agent Writes Inspection Reports

**Files:**
- Modify: `native/MacSoftwareStewardAgent/AgentMain.swift`
- Modify: `scripts/build-native.sh`

- [ ] **Step 1: Refactor Agent exit paths**

In `native/MacSoftwareStewardAgent/AgentMain.swift`, keep the existing printed output, but avoid direct `Foundation.exit` after scan. Track:

```swift
var reportFailure: InspectionFailureRecord?
var exitCode: Int32 = 0
```

Before each exit after scan and plan generation, append:

```swift
InspectionReportStore().append(
    InspectionReportBuilder.makeReport(
        trigger: .dailyAgent,
        startedAt: startedAtDate,
        finishedAt: Date(),
        scan: scan,
        rows: rows,
        automaticPackages: automaticPackages,
        failure: reportFailure
    )
)
Foundation.exit(exitCode)
```

For command failure, set:

```swift
reportFailure = InspectionFailureRecord(message: "命令失败", commandDisplay: command.2, exitCode: Int32(code))
exitCode = Int32(code)
```

For missing brew when updates exist, set:

```swift
reportFailure = InspectionFailureRecord(message: "发现 Homebrew 更新，但找不到 brew", commandDisplay: "brew", exitCode: 1)
exitCode = 1
```

Keep the pre-scan usage failure as direct exit code 2, because no inspection report can be built without a scan.

- [ ] **Step 2: Add report files to Agent build**

In `scripts/build-native.sh`, add these source files to the Agent compile command before `native/MacSoftwareStewardAgent/*.swift`:

```bash
"$ROOT_DIR"/native/MacSoftwareSteward/InspectionReportStore.swift \
"$ROOT_DIR"/native/MacSoftwareSteward/InspectionReportBuilder.swift \
```

- [ ] **Step 3: Build to verify Agent compiles**

Run:

```bash
npm run build
```

Expected: app and Agent build, sign and verify successfully.

- [ ] **Step 4: Commit**

```bash
git add native/MacSoftwareStewardAgent/AgentMain.swift scripts/build-native.sh
git commit -m "feat: write daily inspection reports from agent"
```

---

### Task 4: History View Shows Inspection Reports

**Files:**
- Modify: `native/MacSoftwareSteward/StewardModel.swift`
- Modify: `native/MacSoftwareSteward/Views/HistoryView.swift`

- [ ] **Step 1: Add report store to model**

In `StewardModel`, add:

```swift
let inspectionReportStore = InspectionReportStore()
```

near `historyStore`.

- [ ] **Step 2: Render reports above upgrade history**

In `HistoryView`, change the empty state to only show when both `model.inspectionReportStore.reports` and `model.historyStore.records` are empty.

On appear, call:

```swift
model.inspectionReportStore.reload()
```

Render a `SectionHeader`-style text for "巡检报告" when reports exist, then rows with status, date, automatic upgrade count, skipped count and failure count. Render "升级历史" above existing upgrade records when those exist.

Use compact SwiftUI only; do not add new persistence behavior in the view.

- [ ] **Step 3: Build to verify view compiles**

Run:

```bash
npm run build
```

Expected: build succeeds and signs app.

- [ ] **Step 4: Commit**

```bash
git add native/MacSoftwareSteward/StewardModel.swift native/MacSoftwareSteward/Views/HistoryView.swift
git commit -m "feat: show inspection reports in history"
```

---

### Task 5: Test Script Wiring

**Files:**
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Add new tests**

Add:

```bash
run_test InspectionReportStoreTest \
  "$SRC/InspectionReportStore.swift" \
  "$TESTS/InspectionReportStoreTest.swift"

run_test InspectionReportBuilderTest \
  "$SRC/Models.swift" \
  "$SRC/InspectionReportStore.swift" \
  "$SRC/InspectionReportBuilder.swift" \
  "$SRC/UpgradePolicyStore.swift" \
  "$SRC/RiskAssessor.swift" \
  "$SRC/UpgradePlanner.swift" \
  "$TESTS/InspectionReportBuilderTest.swift"
```

Add `"$SRC/InspectionReportStore.swift"` to `StewardModelScanGuardTest` sources because `StewardModel` now owns that store.

- [ ] **Step 2: Run full tests**

Run:

```bash
npm test
```

Expected: all native tests pass and output ends with `All native tests passed.`

- [ ] **Step 3: Commit**

```bash
git add scripts/test-native.sh
git commit -m "test: cover inspection reports"
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

- [ ] **Step 3: Clean build side effects**

Run:

```bash
git restore native/Resources/AppIcon.iconset/*.png
git status --short
```

Expected: only intentional changes remain. The existing untracked `code-risk-scanner/` directory may still appear and should not be staged.

