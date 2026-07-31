# Automation Steward M5b Auto Repair Allowlist Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute explicitly allowlisted low-risk recovery actions once when advanced auto-repair is enabled.

**Architecture:** Add a pure `AutoRepairDecider` that gates recovery actions by `AutomationProfile`, `RecoveryAction.allowsAutomaticRepair`, and an attempted package set. Keep the first executable auto-repair narrow and safe: only `.rescan` actions are marked allowlisted and automatically executed. `StewardModel` records package IDs it already attempted so failures fall back to manual Inbox items without looping.

**Tech Stack:** Swift Foundation, SwiftUI, existing `swiftc` single-file tests, `npm test`, `npm run build`.

---

## Scope Check

This plan implements M5b only:

- Mark `RecoveryActionPlanner` rescan recovery as eligible for automatic repair.
- Add `AutoRepairDecider` for profile/allowlist/attempted-state decisions.
- Let `StewardModel` run allowlisted automatic repairs once and publish remaining failures to Inbox.
- Pass `AutomationProfile` from upgrade surfaces into upgrade execution.

This plan does not automatically retry package upgrades, clean caches, repair permissions, send notifications, persist auto-repair attempts across app launches, or add a custom per-action allowlist UI. Those are future M5/M6 slices.

## File Structure

- Modify `native/MacSoftwareSteward/RecoveryActionPlanner.swift`: mark `.rescan` recovery actions as automatic-repair eligible.
- Create `native/MacSoftwareSteward/AutoRepairDecider.swift`: pure allowlist gate.
- Modify `native/MacSoftwareSteward/StewardModel.swift`: track attempted auto-repairs and run allowlisted repairs once.
- Modify `native/MacSoftwareSteward/Views/UpdatesView.swift`: pass `automationProfile.profile` for direct upgrade jobs.
- Modify `native/MacSoftwareSteward/UpgradePlanView.swift`: pass `automationProfile.profile` for confirmed plan jobs.
- Modify `scripts/test-native.sh`: add new test and source dependencies.
- Create `tests/AutoRepairDeciderTest.swift`.
- Update `tests/RecoveryActionPlannerTest.swift`.
- Update `tests/StewardModelScanGuardTest.swift`.

---

### Task 1: Auto Repair Eligibility

**Files:**
- Modify: `native/MacSoftwareSteward/RecoveryActionPlanner.swift`
- Create: `native/MacSoftwareSteward/AutoRepairDecider.swift`
- Test: `tests/AutoRepairDeciderTest.swift`
- Test: `tests/RecoveryActionPlannerTest.swift`

- [ ] **Step 1: Extend the failing planner test**

In `tests/RecoveryActionPlannerTest.swift`, after the running-progress assertion, add:

```swift
        let rescan = PackageUpgradeProgress(
            packageID: "brew:formula:missing",
            packageName: "missing",
            status: .failed,
            detail: "所需的文件或工具未找到。",
            failureSummary: "所需的文件或工具未找到。",
            recoverySuggestion: "请点击「重新扫描」刷新软件列表后再试。",
            recoveryAction: .rescan
        )
        let rescanAction = RecoveryActionPlanner.actions(for: rescan)[0]
        precondition(rescanAction.kind == .rescan)
        precondition(rescanAction.allowsAutomaticRepair == true)
```

- [ ] **Step 2: Write the failing decider test**

Create `tests/AutoRepairDeciderTest.swift`:

```swift
import Foundation

@main
struct AutoRepairDeciderTest {
    static func main() {
        let rescanProgress = PackageUpgradeProgress(
            packageID: "brew:formula:missing",
            packageName: "missing",
            status: .failed,
            detail: "所需的文件或工具未找到。",
            failureSummary: "所需的文件或工具未找到。",
            recoverySuggestion: "请点击「重新扫描」刷新软件列表后再试。",
            recoveryAction: .rescan
        )

        var profile = AutomationProfile.manualDefault
        profile.onboardingCompleted = true
        profile.automationEnabled = true
        profile.advancedModeEnabled = true
        profile.autoRepairPolicy = .allowLowRisk

        let allowed = AutoRepairDecider.automaticAction(
            for: rescanProgress,
            profile: profile,
            attemptedPackageIDs: []
        )
        precondition(allowed?.kind == .rescan)

        let attempted = AutoRepairDecider.automaticAction(
            for: rescanProgress,
            profile: profile,
            attemptedPackageIDs: [rescanProgress.packageID]
        )
        precondition(attempted == nil)

        profile.advancedModeEnabled = false
        precondition(AutoRepairDecider.automaticAction(for: rescanProgress, profile: profile, attemptedPackageIDs: []) == nil)

        profile.advancedModeEnabled = true
        profile.autoRepairPolicy = .manualOnly
        precondition(AutoRepairDecider.automaticAction(for: rescanProgress, profile: profile, attemptedPackageIDs: []) == nil)

        let retryProgress = PackageUpgradeProgress(
            packageID: "brew:cask:android-studio",
            packageName: "Android Studio",
            status: .failed,
            detail: "下载失败",
            failureSummary: "下载失败",
            recoverySuggestion: "请重试。",
            recoveryAction: .cleanup
        )
        profile.autoRepairPolicy = .allowLowRisk
        precondition(AutoRepairDecider.automaticAction(for: retryProgress, profile: profile, attemptedPackageIDs: []) == nil)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/RecoveryActionPlanner.swift \
  tests/RecoveryActionPlannerTest.swift \
  -o build/RecoveryActionPlannerTest
./build/RecoveryActionPlannerTest
```

Expected: FAIL because the rescan action is not marked `allowsAutomaticRepair`.

Then run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/AutomationProfileStore.swift \
  native/MacSoftwareSteward/RecoveryActionPlanner.swift \
  tests/AutoRepairDeciderTest.swift \
  -o build/AutoRepairDeciderTest
```

Expected: FAIL with `cannot find 'AutoRepairDecider' in scope`.

- [ ] **Step 4: Mark rescan as allowlisted**

In `native/MacSoftwareSteward/RecoveryActionPlanner.swift`, change the `.rescan` primary action to:

```swift
        case .rescan:
            return RecoveryAction(
                kind: .rescan,
                title: "重新扫描",
                systemImage: "arrow.clockwise",
                allowsAutomaticRepair: true
            )
```

- [ ] **Step 5: Add the decider**

Create `native/MacSoftwareSteward/AutoRepairDecider.swift`:

```swift
import Foundation

enum AutoRepairDecider {
    static func automaticAction(
        for progress: PackageUpgradeProgress,
        profile: AutomationProfile,
        attemptedPackageIDs: Set<String>
    ) -> RecoveryAction? {
        guard profile.advancedModeEnabled else { return nil }
        guard profile.autoRepairPolicy == .allowLowRisk else { return nil }
        guard !attemptedPackageIDs.contains(progress.packageID) else { return nil }
        return RecoveryActionPlanner.actions(for: progress)
            .first { $0.allowsAutomaticRepair }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/RecoveryActionPlanner.swift \
  tests/RecoveryActionPlannerTest.swift \
  -o build/RecoveryActionPlannerTest
./build/RecoveryActionPlannerTest

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/AutomationProfileStore.swift \
  native/MacSoftwareSteward/RecoveryActionPlanner.swift \
  native/MacSoftwareSteward/AutoRepairDecider.swift \
  tests/AutoRepairDeciderTest.swift \
  -o build/AutoRepairDeciderTest
./build/AutoRepairDeciderTest
```

Expected: both commands exit with status 0.

- [ ] **Step 7: Commit**

```bash
git add native/MacSoftwareSteward/RecoveryActionPlanner.swift native/MacSoftwareSteward/AutoRepairDecider.swift tests/RecoveryActionPlannerTest.swift tests/AutoRepairDeciderTest.swift
git commit -m "feat: decide low-risk auto repairs"
```

---

### Task 2: One-Shot Auto Repair Execution

**Files:**
- Modify: `native/MacSoftwareSteward/StewardModel.swift`
- Test: `tests/StewardModelScanGuardTest.swift`

- [ ] **Step 1: Extend the failing model guard test**

In `tests/StewardModelScanGuardTest.swift`, after the first recovery Inbox assertions and before the Sparkle app block, add:

```swift
        let repairScanner = DelayedScanner()
        let repairModel = StewardModel(scanner: repairScanner)
        repairModel.packageProgress["brew:formula:missing"] = PackageUpgradeProgress(
            packageID: "brew:formula:missing",
            packageName: "missing",
            status: .failed,
            detail: "所需的文件或工具未找到。",
            failureSummary: "所需的文件或工具未找到。",
            recoverySuggestion: "请点击「重新扫描」刷新软件列表后再试。",
            recoveryAction: .rescan
        )
        var autoRepairProfile = AutomationProfile.manualDefault
        autoRepairProfile.advancedModeEnabled = true
        autoRepairProfile.autoRepairPolicy = .allowLowRisk

        let repairTask = Task {
            await repairModel.performAutomaticRepairIfAllowed(
                profile: autoRepairProfile,
                inboxStore: inboxStore,
                packageIDs: ["brew:formula:missing"]
            )
        }
        while repairScanner.callCount == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        repairScanner.finish()
        let repairedPackageIDs = await repairTask.value
        precondition(repairedPackageIDs == ["brew:formula:missing"])

        let secondRepair = await repairModel.performAutomaticRepairIfAllowed(
            profile: autoRepairProfile,
            inboxStore: inboxStore,
            packageIDs: ["brew:formula:missing"]
        )
        precondition(secondRepair.isEmpty)
        precondition(repairScanner.callCount == 1)
```

- [ ] **Step 2: Run the guard test to verify it fails**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/CommandRunner.swift \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/AutomationProfileStore.swift \
  native/MacSoftwareSteward/RegularAppUpdateDiscovery.swift \
  native/MacSoftwareSteward/RegularAppUpdateActionResolver.swift \
  native/MacSoftwareSteward/RecoveryActionPlanner.swift \
  native/MacSoftwareSteward/RecoveryInboxFactory.swift \
  native/MacSoftwareSteward/AutoRepairDecider.swift \
  native/MacSoftwareSteward/SparkleAppcastChecker.swift \
  native/MacSoftwareSteward/Scanner.swift \
  native/MacSoftwareSteward/SoftwareScanning.swift \
  native/MacSoftwareSteward/InboxStore.swift \
  native/MacSoftwareSteward/AppUpdateInboxFactory.swift \
  native/MacSoftwareSteward/UpgradePolicyStore.swift \
  native/MacSoftwareSteward/RiskAssessor.swift \
  native/MacSoftwareSteward/UpgradePlanner.swift \
  native/MacSoftwareSteward/RiskInboxFactory.swift \
  native/MacSoftwareSteward/DailyUpgradePolicy.swift \
  native/MacSoftwareSteward/InspectionReportStore.swift \
  native/MacSoftwareSteward/DailyInspectionScheduler.swift \
  native/MacSoftwareSteward/UpgradeHistoryStore.swift \
  native/MacSoftwareSteward/BrewCaskCleanupDetector.swift \
  native/MacSoftwareSteward/UpgradeFailureAnalyzer.swift \
  native/MacSoftwareSteward/HomebrewDownloadMonitor.swift \
  native/MacSoftwareSteward/HomebrewCaskDownloadSizeResolver.swift \
  native/MacSoftwareSteward/PackageProgressParser.swift \
  native/MacSoftwareSteward/SourceDiagnostics.swift \
  native/MacSoftwareSteward/UpgradeVerifier.swift \
  native/MacSoftwareSteward/StewardModel.swift \
  tests/StewardModelScanGuardTest.swift \
  -o build/StewardModelScanGuardTest
```

Expected: FAIL with `value of type 'StewardModel' has no member 'performAutomaticRepairIfAllowed'`.

- [ ] **Step 3: Add auto repair state and executor**

In `native/MacSoftwareSteward/StewardModel.swift`:

1. Add the property near other private state:

```swift
    private var autoRepairAttemptedPackageIDs: Set<String> = []
```

2. Add the method near `publishFailureRecoveryItems`:

```swift
    func performAutomaticRepairIfAllowed(
        profile: AutomationProfile,
        inboxStore: InboxStore?,
        packageIDs: Set<String>
    ) async -> Set<String> {
        var repairedPackageIDs: Set<String> = []
        let progresses = packageProgress.values.filter { packageIDs.contains($0.packageID) }

        for progress in progresses {
            guard let action = AutoRepairDecider.automaticAction(
                for: progress,
                profile: profile,
                attemptedPackageIDs: autoRepairAttemptedPackageIDs
            ) else { continue }

            autoRepairAttemptedPackageIDs.insert(progress.packageID)
            switch action.kind {
            case .rescan:
                repairedPackageIDs.insert(progress.packageID)
                await scanSoftware(inboxStore: inboxStore)
            case .retryPackage, .openUpdates, .openJobs, .openStorageSettings, .copyTerminalCommand:
                break
            }
        }

        return repairedPackageIDs
    }
```

- [ ] **Step 4: Run the guard test to verify it passes**

Run the command from Step 2 and then:

```bash
./build/StewardModelScanGuardTest
```

Expected: command exits with status 0.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/StewardModel.swift tests/StewardModelScanGuardTest.swift
git commit -m "feat: run low-risk auto repairs once"
```

---

### Task 3: Pass Auto Repair Profile Through Upgrade Jobs

**Files:**
- Modify: `native/MacSoftwareSteward/StewardModel.swift`
- Modify: `native/MacSoftwareSteward/Views/UpdatesView.swift`
- Modify: `native/MacSoftwareSteward/UpgradePlanView.swift`

- [ ] **Step 1: Extend job method signatures**

In `native/MacSoftwareSteward/StewardModel.swift`:

1. Change `pendingJobQueue` tuple to include `autoRepairProfile: AutomationProfile?`.
2. Add `autoRepairProfile: AutomationProfile? = nil` to `upgrade`, `confirmUpgradePlan`, `upgradeSelectedPlanRows`, `startJob`, `enqueueJob`, and `runJob`.
3. Store and forward `autoRepairProfile` through `pendingJobQueue`, `dequeueNext`, and `Task { await runJob(...) }`.

- [ ] **Step 2: Call automatic repair before manual Inbox publishing**

In `runJob`, replace:

```swift
        if let inboxStore {
            publishFailureRecoveryItems(to: inboxStore, packageIDs: Set(packageSteps.compactMap(\.packageID)))
        }
```

with:

```swift
        let failedPackageIDs = Set(packageSteps.compactMap(\.packageID))
        let automaticallyRepairedPackageIDs: Set<String>
        if let autoRepairProfile {
            automaticallyRepairedPackageIDs = await performAutomaticRepairIfAllowed(
                profile: autoRepairProfile,
                inboxStore: inboxStore,
                packageIDs: failedPackageIDs
            )
        } else {
            automaticallyRepairedPackageIDs = []
        }
        if let inboxStore {
            publishFailureRecoveryItems(
                to: inboxStore,
                packageIDs: failedPackageIDs.subtracting(automaticallyRepairedPackageIDs)
            )
        }
```

- [ ] **Step 3: Pass profile from UI entry points**

In `native/MacSoftwareSteward/Views/UpdatesView.swift`:

1. Add `@EnvironmentObject private var automationProfile: AutomationProfileStore` to `UpdateRow`.
2. Change the direct upgrade call to:

```swift
Task {
    await model.upgrade(
        package,
        inboxStore: inboxStore,
        autoRepairProfile: automationProfile.profile
    )
}
```

Do not change manual retry buttons; manual retries should not auto-repair again.

In `native/MacSoftwareSteward/UpgradePlanView.swift`:

1. Add `@EnvironmentObject private var automationProfile: AutomationProfileStore`.
2. Change confirmation to:

```swift
Task {
    await model.confirmUpgradePlan(
        inboxStore: inboxStore,
        autoRepairProfile: automationProfile.profile
    )
}
```

- [ ] **Step 4: Build to verify UI compiles**

Run:

```bash
npm run build
git restore native/Resources/AppIcon.iconset/*.png
```

Expected: app and Agent build, sign and verify successfully.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/StewardModel.swift native/MacSoftwareSteward/Views/UpdatesView.swift native/MacSoftwareSteward/UpgradePlanView.swift
git commit -m "feat: pass auto repair policy to upgrades"
```

---

### Task 4: Test Script And Final Verification

**Files:**
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Wire new test**

In `scripts/test-native.sh`, add:

```bash
run_test AutoRepairDeciderTest \
  "$SRC/Models.swift" \
  "$SRC/AutomationProfileStore.swift" \
  "$SRC/RecoveryActionPlanner.swift" \
  "$SRC/AutoRepairDecider.swift" \
  "$TESTS/AutoRepairDeciderTest.swift"
```

Add `"$SRC/AutoRepairDecider.swift"` to `StewardModelScanGuardTest`.

- [ ] **Step 2: Run full tests**

Run:

```bash
npm test
```

Expected: all native tests pass and output ends with `All native tests passed.`

- [ ] **Step 3: Commit**

```bash
git add scripts/test-native.sh
git commit -m "test: wire auto repair coverage"
```

- [ ] **Step 4: Final verification**

Run:

```bash
npm test
npm run build
git restore native/Resources/AppIcon.iconset/*.png
git status --short
```

Expected: tests pass, build signs/verifies, and only the existing untracked `code-risk-scanner/` directory remains.
