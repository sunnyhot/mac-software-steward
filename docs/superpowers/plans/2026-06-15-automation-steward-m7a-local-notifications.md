# Automation Steward M7a Local Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver local macOS notifications when scans create new actionable inbox items, while avoiding repeat notifications for the same deduped item.

**Architecture:** Keep `AutomationNotificationDecider` as the pure policy layer, add a small notification delivery protocol with a `UNUserNotificationCenter` production implementation, and inject it into `StewardModel` for testing. Make `InboxStore.add(_:)` report whether an item is newly created so scan notifications only fire for new actionable items.

**Tech Stack:** Swift, Foundation, UserNotifications, SwiftUI/AppKit call sites, existing standalone `swiftc` tests through `scripts/test-native.sh`.

---

### Task 1: Expand Notification Decision And Inbox Dedup Signal

**Files:**
- Modify: `native/MacSoftwareSteward/AutomationNotificationDecider.swift`
- Modify: `native/MacSoftwareSteward/InboxStore.swift`
- Modify: `tests/AutomationNotificationDeciderTest.swift`
- Modify: `tests/InboxStoreTest.swift`

- [ ] **Step 1: Write failing tests**

Add this to `tests/AutomationNotificationDeciderTest.swift` after the warning item setup:

```swift
let appUpdate = InboxItem(
    kind: .appUpdate,
    severity: .info,
    title: "Sparkle 可更新",
    summary: "需要手动打开更新器。",
    sourceID: "app:/Applications/Sparkle.app",
    actions: [
        InboxAction(title: "查看应用", systemImage: "macwindow", kind: .openApplications)
    ]
)
let appUpdateDecision = AutomationNotificationDecider.decision(
    policy: .decisionsAndFailures,
    newInboxItems: [appUpdate],
    automaticUpgradeCount: 0
)
precondition(appUpdateDecision?.title == "有 1 项需要处理")
```

Update `tests/InboxStoreTest.swift` so `add` return values are asserted:

```swift
precondition(store.add(first) == true)
precondition(store.add(second) == true)
precondition(store.add(second) == false)
```

- [ ] **Step 2: Run RED**

Run:

```bash
npm test
```

Expected: test build fails because `InboxStore.add(_:)` returns `Void`, or the decider test fails because info app updates are not notify-worthy.

- [ ] **Step 3: Implement minimal logic**

In `InboxStore.add(_:)`, change the signature to:

```swift
@discardableResult
func add(_ item: InboxItem) -> Bool
```

Return `true` only when there was no existing item with the same `(kind, sourceID)` or same `id`.

In `AutomationNotificationDecider`, replace the severity-only filter with:

```swift
let actionableItems = newInboxItems.filter { item in
    item.status == .pending && (item.severity != .info || !item.actions.isEmpty)
}
```

Use `actionableItems` for the `decisionsAndFailures`, `everyInspection`, and `everyAction` pending decision branches.

- [ ] **Step 4: Run GREEN**

Run:

```bash
npm test
```

Expected: all native tests pass.

- [ ] **Step 5: Commit Task 1**

```bash
git add native/MacSoftwareSteward/AutomationNotificationDecider.swift native/MacSoftwareSteward/InboxStore.swift tests/AutomationNotificationDeciderTest.swift tests/InboxStoreTest.swift
git commit -m "feat: classify actionable inbox notifications"
```

### Task 2: Add Notification Dispatcher And Scan Hook

**Files:**
- Create: `native/MacSoftwareSteward/AutomationNotificationDispatcher.swift`
- Modify: `native/MacSoftwareSteward/StewardModel.swift`
- Modify: `native/MacSoftwareSteward/App.swift`
- Modify: `native/MacSoftwareSteward/ContentView.swift`
- Modify: `native/MacSoftwareSteward/Views/InboxView.swift`
- Modify: `native/MacSoftwareSteward/Views/UpdatesView.swift`
- Modify: `tests/StewardModelScanGuardTest.swift`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Write failing model test**

In `tests/StewardModelScanGuardTest.swift`, add a recording dispatcher:

```swift
@MainActor
final class RecordingNotificationDispatcher: AutomationNotificationDelivering {
    private(set) var decisions: [AutomationNotificationDecision] = []

    func deliver(_ decision: AutomationNotificationDecision) async {
        decisions.append(decision)
    }
}
```

Add a static scanner that returns a manual app update, then assert scan notification behavior:

```swift
let notificationDispatcher = RecordingNotificationDispatcher()
let notificationModel = StewardModel(
    scanner: StaticScanner(result: appUpdateScanResult()),
    notificationDispatcher: notificationDispatcher
)
let notificationInboxURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("notification-inbox-\(UUID().uuidString).json")
defer { try? FileManager.default.removeItem(at: notificationInboxURL) }
let notificationInboxStore = InboxStore(fileURL: notificationInboxURL)

await notificationModel.scanSoftware(
    notificationPolicy: .decisionsAndFailures,
    inboxStore: notificationInboxStore
)
precondition(notificationDispatcher.decisions.map(\.title) == ["有 1 项需要处理"])

await notificationModel.scanSoftware(
    notificationPolicy: .decisionsAndFailures,
    inboxStore: notificationInboxStore
)
precondition(notificationDispatcher.decisions.count == 1)
```

Update `scripts/test-native.sh` so `StewardModelScanGuardTest` compiles `AutomationNotificationDispatcher.swift`.

- [ ] **Step 2: Run RED**

Run:

```bash
npm test
```

Expected: build fails because `AutomationNotificationDelivering`, the new `StewardModel` initializer parameter, and `notificationPolicy` scan parameter do not exist.

- [ ] **Step 3: Implement dispatcher and model hook**

Create `native/MacSoftwareSteward/AutomationNotificationDispatcher.swift`:

```swift
import Foundation
import UserNotifications

@MainActor
protocol AutomationNotificationDelivering {
    func deliver(_ decision: AutomationNotificationDecision) async
}

@MainActor
final class UserNotificationDispatcher: AutomationNotificationDelivering {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func deliver(_ decision: AutomationNotificationDecision) async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = decision.title
            content.body = decision.body
            if decision.isUrgent {
                content.sound = .default
            }

            let request = UNNotificationRequest(
                identifier: "automation-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try await center.add(request)
        } catch {
            NSLog("Failed to deliver automation notification: \(error.localizedDescription)")
        }
    }
}
```

In `StewardModel`, add:

```swift
private let notificationDispatcher: AutomationNotificationDelivering
```

Update the initializer to accept `notificationDispatcher: AutomationNotificationDelivering = UserNotificationDispatcher()`.

Update `scanSoftware` to accept `notificationPolicy: NotificationPolicy = .silent`, collect only newly added inbox items, and deliver the decider result:

```swift
var newInboxItems: [InboxItem] = []
if let inboxStore {
    for item in AppUpdateInboxFactory.items(from: result.applications.items) {
        if inboxStore.add(item) {
            newInboxItems.append(item)
        }
    }
}
if let decision = AutomationNotificationDecider.decision(
    policy: notificationPolicy,
    newInboxItems: newInboxItems,
    automaticUpgradeCount: 0
) {
    await notificationDispatcher.deliver(decision)
}
```

Update app scan call sites that have access to `AutomationProfileStore` to pass `notificationPolicy: automationProfile.profile.notificationPolicy`.

- [ ] **Step 4: Run GREEN**

Run:

```bash
npm test
```

Expected: all native tests pass.

- [ ] **Step 5: Build verify**

Run:

```bash
npm run build
```

Expected: app and agent build, signing reports `Signature OK`.

- [ ] **Step 6: Restore generated icon churn**

Run:

```bash
git restore native/Resources/AppIcon.iconset/*.png
```

- [ ] **Step 7: Commit Task 2**

```bash
git add native/MacSoftwareSteward/AutomationNotificationDispatcher.swift native/MacSoftwareSteward/StewardModel.swift native/MacSoftwareSteward/App.swift native/MacSoftwareSteward/ContentView.swift native/MacSoftwareSteward/Views/InboxView.swift native/MacSoftwareSteward/Views/UpdatesView.swift tests/StewardModelScanGuardTest.swift scripts/test-native.sh
git commit -m "feat: deliver scan inbox notifications"
```

### Task 3: Final Verification

**Files:**
- Inspect: `git status --short`

- [ ] **Step 1: Run native tests**

Run:

```bash
npm test
```

Expected: ends with `All native tests passed.`

- [ ] **Step 2: Run native build**

Run:

```bash
npm run build
```

Expected: app and helper agent build, and signature verification reports `Signature OK`.

- [ ] **Step 3: Restore generated icon churn**

Run:

```bash
git restore native/Resources/AppIcon.iconset/*.png
```

- [ ] **Step 4: Confirm status**

Run:

```bash
git status --short
```

Expected: only pre-existing `?? code-risk-scanner/` remains.
