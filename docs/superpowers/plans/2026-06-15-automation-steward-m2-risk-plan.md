# Automation Steward M2 Risk Plan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add risk-based upgrade decisions so low-risk upgrades remain selected/automatic, high-risk upgrades require confirmation, notification decisions are deterministic, and high-risk upgrade rows can become inbox items.

**Architecture:** Keep risk logic in pure helpers (`RiskAssessor`, `AutomationNotificationDecider`, `RiskInboxFactory`) and let `UpgradePlanner` consume those helpers. Existing UI and agent flows continue to use `UpgradePlanRow`, now enriched with risk level and automation decision.

**Tech Stack:** Swift 5, SwiftUI, Foundation, existing `swiftc` scripts, existing single-file Swift tests.

---

## Scope Check

This plan implements M2 from the major enhancement spec:

- Risk assessment for Homebrew and mas upgrade rows.
- Manual upgrade plan defaults: low risk selected, high risk not selected but executable, blocked rows not selectable.
- Daily automatic upgrade policy only returns low-risk automatic rows.
- Notification decision logic for automation policies.
- Inbox generation for high-risk upgrade decisions.

This plan does not implement actual macOS notification delivery, ordinary `.app` update discovery, inspection report persistence, or automatic repair execution.

## File Structure

- Create `native/MacSoftwareSteward/RiskAssessor.swift`: risk enums, `RiskAssessment`, and deterministic assessment rules.
- Create `native/MacSoftwareSteward/AutomationNotificationDecider.swift`: pure notification decision logic.
- Create `native/MacSoftwareSteward/RiskInboxFactory.swift`: converts high-risk upgrade plan rows into inbox items.
- Modify `native/MacSoftwareSteward/UpgradePlanner.swift`: add risk metadata to rows and default high-risk rows to manual confirmation.
- Modify `native/MacSoftwareSteward/DailyUpgradePolicy.swift`: filter out anything not explicitly low-risk automatic.
- Modify `native/MacSoftwareSteward/InboxStore.swift`: deduplicate generated inbox items by kind and source ID.
- Modify `native/MacSoftwareSteward/StewardModel.swift`: allow `prepareUpgradePlan(inboxStore:)` to create risk inbox items.
- Modify `native/MacSoftwareSteward/App.swift`: pass `inboxStore` when preparing plans from app commands and menu bar.
- Modify `native/MacSoftwareSteward/ContentView.swift`: pass `inboxStore` when preparing plans from the header.
- Modify `native/MacSoftwareSteward/UpgradePlanView.swift`: display risk level near existing risk labels.
- Modify `scripts/build-native.sh`: include `RiskAssessor.swift` in Agent compilation.
- Modify `scripts/test-native.sh`: add M2 tests and source dependencies.
- Create `tests/RiskAssessorTest.swift`.
- Create `tests/AutomationNotificationDeciderTest.swift`.
- Create `tests/RiskInboxFactoryTest.swift`.

---

### Task 1: Risk Assessor

**Files:**
- Create: `native/MacSoftwareSteward/RiskAssessor.swift`
- Test: `tests/RiskAssessorTest.swift`

- [ ] **Step 1: Write the failing test**

Create `tests/RiskAssessorTest.swift`:

```swift
import Foundation

@main
struct RiskAssessorTest {
    static func main() {
        let lowFormula = UpdatablePackage.brew(BrewPackage(
            id: "brew:formula:jq",
            kind: "formula",
            name: "jq",
            installedVersion: "1.6",
            currentVersion: "1.7",
            pinned: false,
            autoUpdates: false,
            outdated: true,
            upgradeable: true
        ))
        let majorFormula = UpdatablePackage.brew(BrewPackage(
            id: "brew:formula:node",
            kind: "formula",
            name: "node",
            installedVersion: "20.1.0",
            currentVersion: "21.0.0",
            pinned: false,
            autoUpdates: false,
            outdated: true,
            upgradeable: true
        ))
        let autoUpdatingCask = UpdatablePackage.brew(BrewPackage(
            id: "brew:cask:arc",
            kind: "cask",
            name: "arc",
            installedVersion: "1.0",
            currentVersion: "1.1",
            pinned: false,
            autoUpdates: true,
            outdated: true,
            upgradeable: true
        ))
        let pinned = UpdatablePackage.brew(BrewPackage(
            id: "brew:formula:ruby",
            kind: "formula",
            name: "ruby",
            installedVersion: "3.0",
            currentVersion: "3.1",
            pinned: true,
            autoUpdates: false,
            outdated: true,
            upgradeable: false
        ))
        let mas = UpdatablePackage.mas(MasApp(
            id: "mas:123",
            appId: "123",
            name: "Store App",
            installedVersion: "1.0",
            currentVersion: "1.1",
            outdated: true,
            upgradeable: true
        ))

        let baseScan = ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: false,
            summary: ScanSummary(applications: 0, brewFormulae: 0, brewCasks: 0, masApps: 0, outdated: 0, actionable: 0, scanMs: 1),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
            brew: BrewScan(available: true, path: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew", version: "Homebrew 5", error: "", includeGreedy: false, formulae: [], casks: []),
            mas: MasScan(available: true, path: "/opt/homebrew/bin/mas", error: "", apps: [])
        )

        let low = RiskAssessor.assess(package: lowFormula, scan: baseScan, includeGreedy: false)
        precondition(low.level == .low)
        precondition(low.automationDecision == .allowAutomatic)
        precondition(low.reasons.isEmpty)

        let major = RiskAssessor.assess(package: majorFormula, scan: baseScan, includeGreedy: false)
        precondition(major.level == .high)
        precondition(major.automationDecision == .requireConfirmation)
        precondition(major.reasons.contains(.majorVersion))

        let cask = RiskAssessor.assess(package: autoUpdatingCask, scan: baseScan, includeGreedy: false)
        precondition(cask.level == .medium)
        precondition(cask.automationDecision == .requireConfirmation)
        precondition(cask.labels.contains("auto_updates"))

        let blocked = RiskAssessor.assess(package: pinned, scan: baseScan, includeGreedy: false)
        precondition(blocked.level == .high)
        precondition(blocked.automationDecision == .blockExecution)
        precondition(blocked.reasons.contains(.pinned))

        var missingMasScan = baseScan
        missingMasScan.mas = MasScan(available: false, path: "", error: "missing", apps: [])
        let blockedMas = RiskAssessor.assess(package: mas, scan: missingMasScan, includeGreedy: false)
        precondition(blockedMas.automationDecision == .blockExecution)
        precondition(blockedMas.labels.contains("mas unavailable"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  tests/RiskAssessorTest.swift \
  -o build/RiskAssessorTest
```

Expected: FAIL with `cannot find 'RiskAssessor' in scope`.

- [ ] **Step 3: Add the risk assessor**

Create `native/MacSoftwareSteward/RiskAssessor.swift` with risk levels, reasons, decisions, `RiskAssessment`, and `RiskAssessor.assess(package:scan:includeGreedy:)`.

The implementation must follow these concrete rules:

- Source unavailable is `.high` and `.blockExecution`.
- Pinned packages are `.high` and `.blockExecution`.
- Packages that are not upgradeable and are not greedy casks are `.high` and `.blockExecution`.
- Major version changes are `.high` and `.requireConfirmation`.
- Greedy cask, auto-updating cask, related running app, source warning, and unknown target version are `.medium` and `.requireConfirmation`.
- Rows with no reasons are `.low` and `.allowAutomatic`.

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/RiskAssessor.swift \
  tests/RiskAssessorTest.swift \
  -o build/RiskAssessorTest
./build/RiskAssessorTest
```

Expected: command exits with status 0.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/RiskAssessor.swift tests/RiskAssessorTest.swift
git commit -m "feat: add upgrade risk assessor"
```

---

### Task 2: Risk-Aware Upgrade Planning

**Files:**
- Modify: `native/MacSoftwareSteward/UpgradePlanner.swift`
- Modify: `tests/UpgradePlannerTest.swift`
- Modify: `tests/DailyPolicyFilteringTest.swift`

- [ ] **Step 1: Update failing planner tests**

In `tests/UpgradePlannerTest.swift`, change the cask expectation from selected to manual confirmation:

```swift
precondition(caskRow?.selection == .notSelected)
precondition(caskRow?.automationDecision == .requireConfirmation)
precondition(caskRow?.skipReason.hasPrefix("需确认") == true)
```

Add assertions for low-risk formula risk and blocked mas:

```swift
precondition(formulaRow?.riskLevel == .high)
precondition(pinnedRow?.automationDecision == .blockExecution)
precondition(masRow?.automationDecision == .blockExecution)
```

In `tests/DailyPolicyFilteringTest.swift`, update the manual rows so the formula row has `automationDecision: .allowAutomatic`, the cask row has `automationDecision: .requireConfirmation`, and the pinned row has `automationDecision: .blockExecution`.

- [ ] **Step 2: Run planner tests to verify they fail**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/UpgradePolicyStore.swift \
  native/MacSoftwareSteward/UpgradePlanner.swift \
  tests/UpgradePlannerTest.swift \
  -o build/UpgradePlannerTest
```

Expected: FAIL because `UpgradePlanRow` has no `automationDecision` and `riskLevel`.

- [ ] **Step 3: Enrich `UpgradePlanRow` and integrate risk assessment**

In `native/MacSoftwareSteward/UpgradePlanner.swift`:

- Add `riskLevel: RiskLevel = .low`, `riskSummary: String = ""`, and `automationDecision: AutomationDecision = .allowAutomatic` to `UpgradePlanRow`.
- In `row(for:scan:policyStore:includeGreedy:)`, compute `let risk = RiskAssessor.assess(...)`.
- Use `risk.automationDecision == .blockExecution` for non-selectable rows.
- For `.requireConfirmation`, set selection to `.notSelected` and `skipReason` to `"需确认：\(risk.summary)"`.
- For `.allowAutomatic`, keep existing policy behavior.
- Replace `riskLabels(...)` with `risk.labels`.

- [ ] **Step 4: Run planner tests to verify they pass**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/RiskAssessor.swift \
  native/MacSoftwareSteward/UpgradePolicyStore.swift \
  native/MacSoftwareSteward/UpgradePlanner.swift \
  tests/UpgradePlannerTest.swift \
  -o build/UpgradePlannerTest
./build/UpgradePlannerTest
```

Expected: command exits with status 0.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/UpgradePlanner.swift tests/UpgradePlannerTest.swift tests/DailyPolicyFilteringTest.swift
git commit -m "feat: make upgrade plans risk aware"
```

---

### Task 3: Daily Automatic Policy

**Files:**
- Modify: `native/MacSoftwareSteward/DailyUpgradePolicy.swift`
- Modify: `native/MacSoftwareStewardAgent/AgentMain.swift`
- Modify: `scripts/build-native.sh`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Run daily policy test to verify it fails**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/UpgradePolicyStore.swift \
  native/MacSoftwareSteward/RiskAssessor.swift \
  native/MacSoftwareSteward/UpgradePlanner.swift \
  native/MacSoftwareSteward/DailyUpgradePolicy.swift \
  tests/DailyPolicyFilteringTest.swift \
  -o build/DailyPolicyFilteringTest
```

Expected: FAIL until `DailyUpgradePolicy` checks `automationDecision`.

- [ ] **Step 2: Filter daily automatic packages by risk**

Change `DailyUpgradePolicy.automaticPackages(from:)` so it returns a package only when:

```swift
row.policy == .automatic && row.canExecute && row.automationDecision == .allowAutomatic
```

- [ ] **Step 3: Include `RiskAssessor.swift` in agent and test scripts**

In `scripts/build-native.sh`, add:

```bash
"$ROOT_DIR"/native/MacSoftwareSteward/RiskAssessor.swift \
```

immediately before `UpgradePlanner.swift` in the Agent compile command.

In `scripts/test-native.sh`, add `"$SRC/RiskAssessor.swift"` to `DailyPolicyFilteringTest`, `UpgradePlannerTest`, and any later test entry that compiles `UpgradePlanner.swift`.

- [ ] **Step 4: Run daily policy test to verify it passes**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/UpgradePolicyStore.swift \
  native/MacSoftwareSteward/RiskAssessor.swift \
  native/MacSoftwareSteward/UpgradePlanner.swift \
  native/MacSoftwareSteward/DailyUpgradePolicy.swift \
  tests/DailyPolicyFilteringTest.swift \
  -o build/DailyPolicyFilteringTest
./build/DailyPolicyFilteringTest
```

Expected: command exits with status 0.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/DailyUpgradePolicy.swift native/MacSoftwareStewardAgent/AgentMain.swift scripts/build-native.sh scripts/test-native.sh
git commit -m "feat: limit daily upgrades to low risk packages"
```

---

### Task 4: Notification Decision Logic

**Files:**
- Create: `native/MacSoftwareSteward/AutomationNotificationDecider.swift`
- Test: `tests/AutomationNotificationDeciderTest.swift`

- [ ] **Step 1: Write the failing test**

Create `tests/AutomationNotificationDeciderTest.swift`:

```swift
import Foundation

@main
struct AutomationNotificationDeciderTest {
    static func main() {
        let warning = InboxItem(
            kind: .upgradeDecision,
            severity: .warning,
            title: "Node 需要确认",
            summary: "major version",
            sourceID: "upgrade:node",
            actions: []
        )

        precondition(AutomationNotificationDecider.decision(policy: .silent, newInboxItems: [warning], automaticUpgradeCount: 2) == nil)

        let decisions = AutomationNotificationDecider.decision(policy: .decisionsAndFailures, newInboxItems: [warning], automaticUpgradeCount: 2)
        precondition(decisions?.title == "有 1 项需要处理")
        precondition(decisions?.isUrgent == true)

        let quietSuccess = AutomationNotificationDecider.decision(policy: .decisionsAndFailures, newInboxItems: [], automaticUpgradeCount: 2)
        precondition(quietSuccess == nil)

        let everyInspection = AutomationNotificationDecider.decision(policy: .everyInspection, newInboxItems: [], automaticUpgradeCount: 2)
        precondition(everyInspection?.title == "巡检完成")
        precondition(everyInspection?.isUrgent == false)

        let everyAction = AutomationNotificationDecider.decision(policy: .everyAction, newInboxItems: [], automaticUpgradeCount: 1)
        precondition(everyAction?.body.contains("自动处理 1 项") == true)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/AutomationProfileStore.swift \
  native/MacSoftwareSteward/InboxStore.swift \
  tests/AutomationNotificationDeciderTest.swift \
  -o build/AutomationNotificationDeciderTest
```

Expected: FAIL with `cannot find 'AutomationNotificationDecider' in scope`.

- [ ] **Step 3: Add notification decider**

Create `native/MacSoftwareSteward/AutomationNotificationDecider.swift` with:

- `struct AutomationNotificationDecision: Equatable`
- `enum AutomationNotificationDecider`
- `static func decision(policy:newInboxItems:automaticUpgradeCount:) -> AutomationNotificationDecision?`

Decision rules:

- `.silent` returns nil.
- `.decisionsAndFailures` returns nil unless `newInboxItems` has pending warning/critical items.
- `.everyInspection` always returns a non-urgent summary.
- `.everyAction` returns a non-urgent summary when automatic upgrades occurred, and urgent when pending warning/critical items exist.

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/AutomationProfileStore.swift \
  native/MacSoftwareSteward/InboxStore.swift \
  native/MacSoftwareSteward/AutomationNotificationDecider.swift \
  tests/AutomationNotificationDeciderTest.swift \
  -o build/AutomationNotificationDeciderTest
./build/AutomationNotificationDeciderTest
```

Expected: command exits with status 0.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/AutomationNotificationDecider.swift tests/AutomationNotificationDeciderTest.swift
git commit -m "feat: add automation notification decisions"
```

---

### Task 5: Risk Inbox Generation

**Files:**
- Create: `native/MacSoftwareSteward/RiskInboxFactory.swift`
- Modify: `native/MacSoftwareSteward/InboxStore.swift`
- Modify: `native/MacSoftwareSteward/StewardModel.swift`
- Modify: `native/MacSoftwareSteward/App.swift`
- Modify: `native/MacSoftwareSteward/ContentView.swift`
- Test: `tests/RiskInboxFactoryTest.swift`

- [ ] **Step 1: Write the failing test**

Create `tests/RiskInboxFactoryTest.swift`:

```swift
import Foundation

@main
struct RiskInboxFactoryTest {
    static func main() {
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
        let low = UpgradePlanRow(
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
            package: nil,
            riskLevel: .low,
            riskSummary: "",
            automationDecision: .allowAutomatic
        )

        let items = RiskInboxFactory.items(from: [risky, low])
        precondition(items.count == 1)
        precondition(items[0].kind == .upgradeDecision)
        precondition(items[0].severity == .warning)
        precondition(items[0].sourceID == "upgrade:brew:formula:node")
        precondition(items[0].actions.contains(InboxAction(title: "查看升级计划", systemImage: "arrow.down.circle", kind: .openUpdates)))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/InboxStore.swift \
  native/MacSoftwareSteward/RiskAssessor.swift \
  native/MacSoftwareSteward/UpgradePolicyStore.swift \
  native/MacSoftwareSteward/UpgradePlanner.swift \
  tests/RiskInboxFactoryTest.swift \
  -o build/RiskInboxFactoryTest
```

Expected: FAIL with `cannot find 'RiskInboxFactory' in scope`.

- [ ] **Step 3: Add risk inbox factory and source-ID deduplication**

Create `native/MacSoftwareSteward/RiskInboxFactory.swift` with `items(from:)` returning one pending warning inbox item per `UpgradePlanRow` where `automationDecision == .requireConfirmation`.

Modify `InboxStore.add(_:)` so if the new item has a non-empty `sourceID`, it removes existing items with the same `kind` and `sourceID` before appending. This prevents repeated plan generation from duplicating the same risk item.

- [ ] **Step 4: Connect plan preparation to inbox generation**

Change `StewardModel.prepareUpgradePlan()` to:

```swift
func prepareUpgradePlan(inboxStore: InboxStore? = nil)
```

After `upgradePlanRows = rows`, add:

```swift
if let inboxStore {
    for item in RiskInboxFactory.items(from: rows) {
        inboxStore.add(item)
    }
}
```

Update callers:

- Header upgrade button in `ContentView.swift`: `model.prepareUpgradePlan(inboxStore: inboxStore)`
- App command in `App.swift`: `model.prepareUpgradePlan(inboxStore: inboxStore)`
- Menu bar upgrade button in `App.swift`: `model.prepareUpgradePlan(inboxStore: inboxStore)` and inject `.environmentObject(inboxStore)` into `MenuBarUpgradeMenu`.

- [ ] **Step 5: Run the test to verify it passes**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/InboxStore.swift \
  native/MacSoftwareSteward/RiskAssessor.swift \
  native/MacSoftwareSteward/UpgradePolicyStore.swift \
  native/MacSoftwareSteward/UpgradePlanner.swift \
  native/MacSoftwareSteward/RiskInboxFactory.swift \
  tests/RiskInboxFactoryTest.swift \
  -o build/RiskInboxFactoryTest
./build/RiskInboxFactoryTest
```

Expected: command exits with status 0.

- [ ] **Step 6: Commit**

```bash
git add native/MacSoftwareSteward/RiskInboxFactory.swift native/MacSoftwareSteward/InboxStore.swift native/MacSoftwareSteward/StewardModel.swift native/MacSoftwareSteward/App.swift native/MacSoftwareSteward/ContentView.swift tests/RiskInboxFactoryTest.swift
git commit -m "feat: create inbox items for risky upgrades"
```

---

### Task 6: Plan UI And Test Script Wiring

**Files:**
- Modify: `native/MacSoftwareSteward/UpgradePlanView.swift`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Show risk level in plan rows**

In `UpgradePlanRowView`, add a risk badge near the policy badge:

```swift
Badge(text: row.riskLevel.title, color: riskColor(row.riskLevel))
```

Add helper:

```swift
private func riskColor(_ level: RiskLevel) -> Color {
    switch level {
    case .low: return .green
    case .medium: return .orange
    case .high: return .red
    }
}
```

- [ ] **Step 2: Wire tests into `scripts/test-native.sh`**

Add entries for:

- `RiskAssessorTest`
- `AutomationNotificationDeciderTest`
- `RiskInboxFactoryTest`

Also ensure existing `UpgradePlannerTest` and `DailyPolicyFilteringTest` include `RiskAssessor.swift`.

- [ ] **Step 3: Run all tests**

Run:

```bash
npm test
```

Expected: all native tests pass and output ends with `All native tests passed.`

- [ ] **Step 4: Run build**

Run:

```bash
npm run build
```

Expected: build succeeds, signs the app bundle, and verifies signature.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/UpgradePlanView.swift scripts/test-native.sh
git commit -m "test: wire risk planning coverage"
```

---

### Task 7: Final Verification

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

