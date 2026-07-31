# Automation Steward M7i Inbox Handling History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record a local history entry when a user completes or ignores an Inbox item.

**Architecture:** Add a pure Foundation `InboxHistoryRecorder` that converts an `InboxItem` status transition into an `UpgradeHistoryRecord`. Keep persistence in the existing `UpgradeHistoryStore`; `InboxView` only coordinates the status update and append.

**Tech Stack:** Native Swift, SwiftUI, standalone Swift tests through `scripts/test-native.sh`, app build through `scripts/build-native.sh`.

---

## File Structure

- Create `native/MacSoftwareSteward/InboxHistoryRecorder.swift`: pure helper to generate history records for handled inbox items.
- Create `tests/InboxHistoryRecorderTest.swift`: deterministic tests for resolved and ignored inbox status records.
- Modify `scripts/test-native.sh`: add the new test.
- Modify `native/MacSoftwareSteward/Views/InboxView.swift`: append a history record after marking an inbox item completed or ignored.

## Task 1: Pure Inbox History Recorder

**Files:**
- Create: `native/MacSoftwareSteward/InboxHistoryRecorder.swift`
- Create: `tests/InboxHistoryRecorderTest.swift`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/InboxHistoryRecorderTest.swift`:

```swift
import Foundation

@main
struct InboxHistoryRecorderTest {
    static func main() {
        let item = InboxItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            kind: .sourceIssue,
            severity: .warning,
            title: "Homebrew 来源需要处理",
            summary: "未检测到 Homebrew。",
            sourceID: "source:homebrew",
            createdAt: Date(timeIntervalSince1970: 10),
            status: .pending,
            actions: [
                InboxAction(title: "查看来源", systemImage: "tray.full", kind: .openSources)
            ]
        )

        let resolved = InboxHistoryRecorder.record(for: item, status: .resolved, handledAt: Date(timeIntervalSince1970: 20))
        precondition(resolved.label == "处理待办：Homebrew 来源需要处理")
        precondition(resolved.status == "完成")
        precondition(resolved.startedAt == Date(timeIntervalSince1970: 20))
        precondition(resolved.finishedAt == Date(timeIntervalSince1970: 20))
        precondition(resolved.commands.isEmpty)
        precondition(resolved.exitCode == nil)
        precondition(resolved.summary == "收件箱事项已完成：未检测到 Homebrew。")

        let ignored = InboxHistoryRecorder.record(for: item, status: .ignored, handledAt: Date(timeIntervalSince1970: 30))
        precondition(ignored.status == "已忽略")
        precondition(ignored.summary == "收件箱事项已忽略：未检测到 Homebrew。")
    }
}
```

Add this block to `scripts/test-native.sh` after `InboxStoreTest`:

```bash
run_test InboxHistoryRecorderTest \
  "$SRC/InboxStore.swift" \
  "$SRC/UpgradeHistoryStore.swift" \
  "$SRC/InboxHistoryRecorder.swift" \
  "$TESTS/InboxHistoryRecorderTest.swift"
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
npm test
```

Expected: build fails for `InboxHistoryRecorderTest` because `native/MacSoftwareSteward/InboxHistoryRecorder.swift` does not exist yet.

- [ ] **Step 3: Implement recorder**

Create `native/MacSoftwareSteward/InboxHistoryRecorder.swift`:

```swift
import Foundation

enum InboxHistoryRecorder {
    static func record(
        for item: InboxItem,
        status: InboxStatus,
        handledAt: Date = Date()
    ) -> UpgradeHistoryRecord {
        UpgradeHistoryRecord(
            id: UUID(),
            label: "处理待办：\(item.title)",
            status: statusTitle(for: status),
            startedAt: handledAt,
            finishedAt: handledAt,
            commands: [],
            exitCode: nil,
            summary: "收件箱事项已\(actionText(for: status))：\(item.summary)"
        )
    }

    private static func statusTitle(for status: InboxStatus) -> String {
        switch status {
        case .resolved:
            return "完成"
        case .ignored:
            return "已忽略"
        case .pending:
            return "待处理"
        }
    }

    private static func actionText(for status: InboxStatus) -> String {
        switch status {
        case .resolved:
            return "完成"
        case .ignored:
            return "忽略"
        case .pending:
            return "保留"
        }
    }
}
```

- [ ] **Step 4: Run the test suite**

Run:

```bash
npm test
```

Expected: all native tests pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add native/MacSoftwareSteward/InboxHistoryRecorder.swift tests/InboxHistoryRecorderTest.swift scripts/test-native.sh
git commit -m "feat: record inbox handling history"
```

## Task 2: InboxView History Integration

**Files:**
- Modify: `native/MacSoftwareSteward/Views/InboxView.swift`

- [ ] **Step 1: Replace direct status updates**

In `InboxItemRow`, replace the two direct `inboxStore.updateStatus` button actions with:

```swift
                    mark(status: .resolved)
```

and:

```swift
                    mark(status: .ignored)
```

Add this private helper in `InboxItemRow`:

```swift
    private func mark(status: InboxStatus) {
        inboxStore.updateStatus(id: item.id, status: status)
        model.historyStore.append(InboxHistoryRecorder.record(for: item, status: status))
    }
```

- [ ] **Step 2: Verify build and tests**

Run:

```bash
npm run build
git restore native/Resources/AppIcon.iconset/*.png
npm test
```

Expected: app and helper agent build successfully, generated AppIcon PNGs are restored, and all native tests pass.

- [ ] **Step 3: Commit**

Run:

```bash
git add native/MacSoftwareSteward/Views/InboxView.swift
git commit -m "feat: append history when handling inbox items"
```

## Self-Review

- Spec coverage: Covers the requirement that completed or ignored inbox items update status and record handling history.
- Placeholder scan: No TODO, TBD, or unspecified steps remain.
- Type consistency: Uses existing `InboxItem`, `InboxStatus`, `UpgradeHistoryRecord`, `UpgradeHistoryStore`, and `InboxView` environment objects.
