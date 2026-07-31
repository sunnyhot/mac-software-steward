# Automation Steward M5a Failure Recovery Inbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the first M5 failure-recovery slice: structured recovery actions and pending Inbox items for failed package upgrades.

**Architecture:** Keep the existing `UpgradeFailureAnalyzer` and `FailureActionType` as the classifier, then add a focused `RecoveryActionPlanner` that maps failure hints into UI-agnostic recovery actions. Add a `RecoveryInboxFactory` that converts failed package progress into `InboxItem` values, and let `StewardModel` publish those items to `InboxStore` when an upgrade job fails. Inbox buttons execute only manual actions in this slice; automatic repair allowlists are left for M5b.

**Tech Stack:** Swift Foundation, SwiftUI, AppKit `NSPasteboard` / `NSWorkspace`, existing `swiftc` single-file tests, `npm test`, `npm run build`.

---

## Scope Check

This plan implements M5a only:

- Add `RecoveryActionKind` and `RecoveryAction`.
- Add `RecoveryActionPlanner` for known failure actions.
- Add `RecoveryInboxFactory` for failed/timed-out package progress.
- Add Inbox action support for retry, copying terminal commands and opening Storage settings.
- Publish failure recovery items when upgrade jobs run with an `InboxStore`.

This plan does not implement background automatic repair, per-action allowlist persistence, repeated auto-repair suppression, notifications, or new failure classifiers.

## File Structure

- Modify `native/MacSoftwareSteward/Models.swift`: add structured recovery action model.
- Modify `native/MacSoftwareSteward/InboxStore.swift`: add Inbox action kinds for direct recovery actions.
- Create `native/MacSoftwareSteward/RecoveryActionPlanner.swift`: map `PackageUpgradeProgress.recoveryAction` to structured actions.
- Create `native/MacSoftwareSteward/RecoveryInboxFactory.swift`: convert failed progress values into Inbox items.
- Modify `native/MacSoftwareSteward/StewardModel.swift`: pass optional `InboxStore` through jobs and publish recovery Inbox items after failures.
- Modify `native/MacSoftwareSteward/Views/InboxView.swift`: execute new recovery Inbox actions.
- Modify `native/MacSoftwareSteward/Views/UpdatesView.swift`: pass `InboxStore` into retry/upgrade calls.
- Modify `native/MacSoftwareSteward/UpgradePlanView.swift`: pass `InboxStore` into plan confirmation.
- Modify `scripts/test-native.sh`: add new tests and source dependencies.
- Create `tests/RecoveryActionPlannerTest.swift`.
- Create `tests/RecoveryInboxFactoryTest.swift`.

---

### Task 1: Structured Recovery Actions

**Files:**
- Modify: `native/MacSoftwareSteward/Models.swift`
- Create: `native/MacSoftwareSteward/RecoveryActionPlanner.swift`
- Test: `tests/RecoveryActionPlannerTest.swift`

- [ ] **Step 1: Write the failing planner test**

Create `tests/RecoveryActionPlannerTest.swift`:

```swift
import Foundation

@main
struct RecoveryActionPlannerTest {
    static func main() {
        let cleanup = PackageUpgradeProgress(
            packageID: "brew:cask:android-studio",
            packageName: "Android Studio",
            status: .failed,
            detail: "下载的文件校验不通过",
            failureSummary: "下载的文件校验不通过，可能是缓存损坏。",
            recoverySuggestion: "请点击「重试」，系统会自动清理缓存后重新下载。",
            copyText: "命令：brew upgrade --cask android-studio",
            recoveryAction: .cleanup,
            lastFailedCommand: "brew upgrade --cask android-studio"
        )

        let cleanupActions = RecoveryActionPlanner.actions(for: cleanup)
        precondition(cleanupActions.map(\.kind) == [.retryPackage, .openUpdates, .openJobs])
        precondition(cleanupActions[0].title == "清理并重试")
        precondition(cleanupActions[0].systemImage == "trash.circle")

        let terminal = PackageUpgradeProgress(
            packageID: "mas:123",
            packageName: "Pages",
            status: .timedOut,
            detail: "升级命令超时。",
            failureSummary: "升级命令超时。",
            recoverySuggestion: "请稍后重试，或在终端中手动运行命令检查。",
            copyText: "命令：mas upgrade 123",
            recoveryAction: .retryInTerminal,
            lastFailedCommand: "mas upgrade 123"
        )

        let terminalActions = RecoveryActionPlanner.actions(for: terminal)
        precondition(terminalActions.map(\.kind) == [.copyTerminalCommand, .openUpdates, .openJobs])
        precondition(terminalActions[0].title == "复制终端命令")

        let running = PackageUpgradeProgress(
            packageID: "brew:formula:jq",
            packageName: "jq",
            status: .running,
            detail: "执行命令"
        )
        precondition(RecoveryActionPlanner.actions(for: running).isEmpty)
    }
}
```

- [ ] **Step 2: Run the planner test to verify it fails**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  tests/RecoveryActionPlannerTest.swift \
  -o build/RecoveryActionPlannerTest
```

Expected: FAIL with `cannot find 'RecoveryActionPlanner' in scope`.

- [ ] **Step 3: Add recovery action models**

In `native/MacSoftwareSteward/Models.swift`, add after `FailureActionType`:

```swift
enum RecoveryActionKind: String, Codable, Hashable {
    case retryPackage
    case openUpdates
    case openJobs
    case rescan
    case openStorageSettings
    case copyTerminalCommand
}

struct RecoveryAction: Codable, Hashable {
    var kind: RecoveryActionKind
    var title: String
    var systemImage: String
    var allowsAutomaticRepair: Bool = false
}
```

- [ ] **Step 4: Add the planner**

Create `native/MacSoftwareSteward/RecoveryActionPlanner.swift`:

```swift
import Foundation

enum RecoveryActionPlanner {
    static func actions(for progress: PackageUpgradeProgress) -> [RecoveryAction] {
        guard progress.status == .failed || progress.status == .timedOut else { return [] }
        guard let recoveryAction = progress.recoveryAction else {
            return supportingActions()
        }
        return deduplicated([primaryAction(for: recoveryAction)] + supportingActions())
    }

    private static func primaryAction(for action: FailureActionType) -> RecoveryAction {
        switch action {
        case .retry:
            return RecoveryAction(kind: .retryPackage, title: "重试", systemImage: "arrow.clockwise")
        case .quitAndRetry:
            return RecoveryAction(kind: .retryPackage, title: "关闭后重试", systemImage: "xmark.circle")
        case .reimport:
            return RecoveryAction(kind: .retryPackage, title: "覆盖重装", systemImage: "square.and.arrow.down.on.square")
        case .cleanup:
            return RecoveryAction(kind: .retryPackage, title: "清理并重试", systemImage: "trash.circle")
        case .repairPerms:
            return RecoveryAction(kind: .retryPackage, title: "重试", systemImage: "lock.shield")
        case .rescan:
            return RecoveryAction(kind: .rescan, title: "重新扫描", systemImage: "arrow.clockwise")
        case .checkNetwork:
            return RecoveryAction(kind: .retryPackage, title: "重试", systemImage: "wifi")
        case .freeDisk:
            return RecoveryAction(kind: .openStorageSettings, title: "清理空间", systemImage: "internaldrive")
        case .retryInTerminal:
            return RecoveryAction(kind: .copyTerminalCommand, title: "复制终端命令", systemImage: "terminal")
        case .openLog:
            return RecoveryAction(kind: .openJobs, title: "查看日志", systemImage: "terminal")
        }
    }

    private static func supportingActions() -> [RecoveryAction] {
        [
            RecoveryAction(kind: .openUpdates, title: "查看升级", systemImage: "arrow.triangle.2.circlepath"),
            RecoveryAction(kind: .openJobs, title: "查看日志", systemImage: "terminal")
        ]
    }

    private static func deduplicated(_ actions: [RecoveryAction]) -> [RecoveryAction] {
        var seen: Set<RecoveryActionKind> = []
        return actions.filter { action in
            seen.insert(action.kind).inserted
        }
    }
}
```

- [ ] **Step 5: Run the planner test to verify it passes**

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

Expected: command exits with status 0.

- [ ] **Step 6: Commit**

```bash
git add native/MacSoftwareSteward/Models.swift native/MacSoftwareSteward/RecoveryActionPlanner.swift tests/RecoveryActionPlannerTest.swift
git commit -m "feat: plan structured recovery actions"
```

---

### Task 2: Failure Recovery Inbox Items

**Files:**
- Modify: `native/MacSoftwareSteward/InboxStore.swift`
- Create: `native/MacSoftwareSteward/RecoveryInboxFactory.swift`
- Test: `tests/RecoveryInboxFactoryTest.swift`

- [ ] **Step 1: Write the failing factory test**

Create `tests/RecoveryInboxFactoryTest.swift`:

```swift
import Foundation

@main
struct RecoveryInboxFactoryTest {
    static func main() {
        let failed = PackageUpgradeProgress(
            packageID: "brew:cask:android-studio",
            packageName: "Android Studio",
            status: .failed,
            detail: "下载的文件校验不通过",
            failureSummary: "下载的文件校验不通过，可能是缓存损坏。",
            recoverySuggestion: "请点击「重试」，系统会自动清理缓存后重新下载。",
            copyText: "命令：brew upgrade --cask android-studio",
            recoveryAction: .cleanup,
            lastFailedCommand: "brew upgrade --cask android-studio"
        )

        let items = RecoveryInboxFactory.items(from: [failed])
        precondition(items.count == 1)
        precondition(items[0].kind == .failureRecovery)
        precondition(items[0].severity == .critical)
        precondition(items[0].sourceID == failed.packageID)
        precondition(items[0].title == "Android Studio 升级失败")
        precondition(items[0].summary.contains("下载的文件校验不通过"))
        precondition(items[0].actions.map(\.kind) == [.retryPackage, .openUpdates, .openJobs])

        let running = PackageUpgradeProgress(
            packageID: "brew:formula:jq",
            packageName: "jq",
            status: .running,
            detail: "执行命令"
        )
        precondition(RecoveryInboxFactory.items(from: [running]).isEmpty)
    }
}
```

- [ ] **Step 2: Run the factory test to verify it fails**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/InboxStore.swift \
  native/MacSoftwareSteward/RecoveryActionPlanner.swift \
  tests/RecoveryInboxFactoryTest.swift \
  -o build/RecoveryInboxFactoryTest
```

Expected: FAIL with `cannot find 'RecoveryInboxFactory' in scope` and missing `InboxActionKind.retryPackage`.

- [ ] **Step 3: Add Inbox action kinds**

In `native/MacSoftwareSteward/InboxStore.swift`, extend `InboxActionKind` with:

```swift
    case retryPackage
    case copyRecoveryCommand
    case openStorageSettings
```

- [ ] **Step 4: Add recovery Inbox factory**

Create `native/MacSoftwareSteward/RecoveryInboxFactory.swift`:

```swift
import Foundation

enum RecoveryInboxFactory {
    static func items(from progresses: [PackageUpgradeProgress]) -> [InboxItem] {
        progresses
            .filter { $0.status == .failed || $0.status == .timedOut }
            .filter { !$0.failureSummary.isEmpty || $0.recoveryAction != nil }
            .map { progress in
                InboxItem(
                    kind: .failureRecovery,
                    severity: severity(for: progress),
                    title: "\(progress.packageName) 升级失败",
                    summary: summary(for: progress),
                    sourceID: progress.packageID,
                    actions: RecoveryActionPlanner.actions(for: progress).map(inboxAction)
                )
            }
    }

    private static func inboxAction(from action: RecoveryAction) -> InboxAction {
        InboxAction(title: action.title, systemImage: action.systemImage, kind: inboxActionKind(for: action.kind))
    }

    private static func inboxActionKind(for kind: RecoveryActionKind) -> InboxActionKind {
        switch kind {
        case .retryPackage:
            return .retryPackage
        case .openUpdates:
            return .openUpdates
        case .openJobs:
            return .openJobs
        case .rescan:
            return .rescan
        case .openStorageSettings:
            return .openStorageSettings
        case .copyTerminalCommand:
            return .copyRecoveryCommand
        }
    }

    private static func severity(for progress: PackageUpgradeProgress) -> InboxSeverity {
        progress.status == .timedOut ? .warning : .critical
    }

    private static func summary(for progress: PackageUpgradeProgress) -> String {
        let suggestion = progress.recoverySuggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suggestion.isEmpty else { return progress.failureSummary }
        return "\(progress.failureSummary) \(suggestion)"
    }
}
```

- [ ] **Step 5: Run the factory test to verify it passes**

Run:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/InboxStore.swift \
  native/MacSoftwareSteward/RecoveryActionPlanner.swift \
  native/MacSoftwareSteward/RecoveryInboxFactory.swift \
  tests/RecoveryInboxFactoryTest.swift \
  -o build/RecoveryInboxFactoryTest
./build/RecoveryInboxFactoryTest
```

Expected: command exits with status 0.

- [ ] **Step 6: Commit**

```bash
git add native/MacSoftwareSteward/InboxStore.swift native/MacSoftwareSteward/RecoveryInboxFactory.swift tests/RecoveryInboxFactoryTest.swift
git commit -m "feat: create recovery inbox items"
```

---

### Task 3: Publish And Execute Recovery Inbox Actions

**Files:**
- Modify: `native/MacSoftwareSteward/StewardModel.swift`
- Modify: `native/MacSoftwareSteward/Views/InboxView.swift`
- Modify: `native/MacSoftwareSteward/Views/UpdatesView.swift`
- Modify: `native/MacSoftwareSteward/UpgradePlanView.swift`
- Test: `tests/StewardModelScanGuardTest.swift`

- [ ] **Step 1: Extend the failing compile guard test**

In `tests/StewardModelScanGuardTest.swift`, after `let model = StewardModel(scanner: scanner)`, add:

```swift
        let inboxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recovery-inbox-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: inboxURL) }
        let inboxStore = InboxStore(fileURL: inboxURL)
        model.publishFailureRecoveryItems(to: inboxStore, packageIDs: ["missing"])
```

- [ ] **Step 2: Run the guard test to verify it fails**

Run the existing `StewardModelScanGuardTest` compile command with these additional sources included:

```bash
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH" \
  native/MacSoftwareSteward/CommandRunner.swift \
  native/MacSoftwareSteward/Models.swift \
  native/MacSoftwareSteward/AutomationProfileStore.swift \
  native/MacSoftwareSteward/RegularAppUpdateDiscovery.swift \
  native/MacSoftwareSteward/RegularAppUpdateActionResolver.swift \
  native/MacSoftwareSteward/SparkleAppcastChecker.swift \
  native/MacSoftwareSteward/RecoveryActionPlanner.swift \
  native/MacSoftwareSteward/RecoveryInboxFactory.swift \
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

Expected: FAIL with `value of type 'StewardModel' has no member 'publishFailureRecoveryItems'`.

- [ ] **Step 3: Publish recovery items from model**

In `native/MacSoftwareSteward/StewardModel.swift`:

1. Change `pendingJobQueue` to store an optional `InboxStore`.
2. Add optional `inboxStore` parameters to `upgrade`, `retryPackage`, `confirmUpgradePlan`, `upgradeSelectedPlanRows`, `startJob`, `enqueueJob`, `dequeueNext`, `scheduleRescanAfterJobCompletion`, and `runJob`.
3. Add:

```swift
    func publishFailureRecoveryItems(to inboxStore: InboxStore, packageIDs: Set<String>) {
        let progresses = packageProgress.values.filter { packageIDs.contains($0.packageID) }
        for item in RecoveryInboxFactory.items(from: Array(progresses)) {
            inboxStore.add(item)
        }
    }
```

4. In `runJob`, after final job status is written and before `upgradeProgress = nil`, add:

```swift
        if let inboxStore {
            publishFailureRecoveryItems(to: inboxStore, packageIDs: Set(packageSteps.compactMap(\.packageID)))
        }
```

- [ ] **Step 4: Wire Inbox action execution**

In `native/MacSoftwareSteward/Views/InboxView.swift`:

1. Add `import AppKit` above `import SwiftUI`.
2. Extend `perform(_:)`:

```swift
        case .retryPackage:
            guard let packageID = item.sourceID else { return }
            Task {
                await model.retryPackage(packageID, inboxStore: inboxStore)
            }
        case .copyRecoveryCommand:
            guard
                let packageID = item.sourceID,
                let progress = model.packageProgress[packageID]
            else { return }
            let command = progress.lastFailedCommand.isEmpty ? progress.copyText : progress.lastFailedCommand
            guard !command.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            open(tab: .jobs)
        case .openStorageSettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
                NSWorkspace.shared.open(url)
            }
```

- [ ] **Step 5: Pass InboxStore from upgrade surfaces**

In `native/MacSoftwareSteward/Views/UpdatesView.swift`, add:

```swift
    @EnvironmentObject private var inboxStore: InboxStore
```

Then change calls to:

```swift
Task { await model.retryPackage(package.id, inboxStore: inboxStore) }
Task { await model.upgrade(package, inboxStore: inboxStore) }
Task { await model.retryPackage(progress.packageID, inboxStore: inboxStore) }
```

In `native/MacSoftwareSteward/UpgradePlanView.swift`, add:

```swift
    @EnvironmentObject private var inboxStore: InboxStore
```

Then change confirmation to:

```swift
Task { await model.confirmUpgradePlan(inboxStore: inboxStore) }
```

- [ ] **Step 6: Run model guard test and build**

Run the guard test compile command from Step 2, then:

```bash
./build/StewardModelScanGuardTest
npm run build
git restore native/Resources/AppIcon.iconset/*.png
```

Expected: guard test exits with status 0; build signs and verifies the app.

- [ ] **Step 7: Commit**

```bash
git add native/MacSoftwareSteward/StewardModel.swift native/MacSoftwareSteward/Views/InboxView.swift native/MacSoftwareSteward/Views/UpdatesView.swift native/MacSoftwareSteward/UpgradePlanView.swift tests/StewardModelScanGuardTest.swift
git commit -m "feat: publish recovery actions to inbox"
```

---

### Task 4: Test Script And Final Verification

**Files:**
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Wire new tests**

In `scripts/test-native.sh`, add:

```bash
run_test RecoveryActionPlannerTest \
  "$SRC/Models.swift" \
  "$SRC/RecoveryActionPlanner.swift" \
  "$TESTS/RecoveryActionPlannerTest.swift"

run_test RecoveryInboxFactoryTest \
  "$SRC/Models.swift" \
  "$SRC/InboxStore.swift" \
  "$SRC/RecoveryActionPlanner.swift" \
  "$SRC/RecoveryInboxFactory.swift" \
  "$TESTS/RecoveryInboxFactoryTest.swift"
```

Also add these sources to `StewardModelScanGuardTest`:

```bash
  "$SRC/RecoveryActionPlanner.swift" \
  "$SRC/RecoveryInboxFactory.swift" \
```

- [ ] **Step 2: Run full tests**

Run:

```bash
npm test
```

Expected: all native tests pass and output ends with `All native tests passed.`

- [ ] **Step 3: Commit**

```bash
git add scripts/test-native.sh
git commit -m "test: wire recovery inbox coverage"
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
