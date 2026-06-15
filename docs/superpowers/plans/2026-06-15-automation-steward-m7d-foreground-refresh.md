# Automation Steward M7d Foreground Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh Inbox items and inspection reports when the main app becomes active so background agent output appears without restarting the app.

**Architecture:** Add a `reload()` method to `InboxStore`, mirroring `InspectionReportStore.reload()`. Wire `MacSoftwareStewardApp` to observe `scenePhase` and reload both `InboxStore` and `InspectionReportStore` when the app returns to `.active`.

**Tech Stack:** Swift, SwiftUI scene phase, standalone `swiftc` tests via `scripts/test-native.sh`, app build via `scripts/build-native.sh`.

---

### Task 1: Inbox Store Reload

**Files:**
- Modify: `native/MacSoftwareSteward/InboxStore.swift`
- Modify: `tests/InboxStoreTest.swift`

- [ ] **Step 1: Write the failing test**

Append this scenario to `tests/InboxStoreTest.swift` before the closing brace of `main()`:

```swift
let foregroundStore = InboxStore(fileURL: url)
precondition(foregroundStore.items.map(\.id) == [secondID])

let externalID = UUID()
let externalItem = InboxItem(
    id: externalID,
    kind: .appUpdate,
    severity: .info,
    title: "Sparkle 可更新",
    summary: "后台巡检发现普通 App 更新。",
    sourceID: "app:/Applications/Sparkle.app",
    createdAt: Date(timeIntervalSince1970: 30),
    status: .pending,
    actions: [
        InboxAction(title: "查看应用", systemImage: "macwindow", kind: .openApplications)
    ]
)
let externalStore = InboxStore(fileURL: url)
precondition(externalStore.add(externalItem) == true)

foregroundStore.reload()
precondition(foregroundStore.items.map(\.id) == [externalID, secondID])
```

- [ ] **Step 2: Run tests to verify red**

Run:

```bash
npm test
```

Expected: FAIL while building `InboxStoreTest` because `InboxStore` has no `reload()` method.

- [ ] **Step 3: Implement `InboxStore.reload()`**

In `native/MacSoftwareSteward/InboxStore.swift`, add this method after `replaceAll(_:)`:

```swift
func reload() {
    items = Self.load(from: fileURL)
}
```

- [ ] **Step 4: Run tests to verify green**

Run:

```bash
npm test
```

Expected: all native tests pass.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/InboxStore.swift tests/InboxStoreTest.swift
git commit -m "feat: reload inbox store from disk"
```

### Task 2: Foreground Refresh Wiring

**Files:**
- Modify: `native/MacSoftwareSteward/App.swift`

- [ ] **Step 1: Wire scene phase refresh**

In `MacSoftwareStewardApp`, add scene phase environment storage near the existing property wrappers:

```swift
@Environment(\.scenePhase) private var scenePhase
```

Add this `onChange` handler in the main `ContentView()` modifier chain after the existing dock icon handler:

```swift
.onChange(of: scenePhase) {
    guard scenePhase == .active else { return }
    inboxStore.reload()
    model.inspectionReportStore.reload()
}
```

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
git add native/MacSoftwareSteward/App.swift
git commit -m "feat: refresh automation stores on foreground"
```

### Self-Review

- Spec coverage: This implements the foreground-refresh part of the automation flow: reports and Inbox items written by the background agent become visible when the app returns to the foreground.
- Placeholder scan: No placeholders or TODOs remain.
- Type consistency: `InboxStore.reload()` mirrors `InspectionReportStore.reload()`, and `scenePhase` is used through SwiftUI's environment.
