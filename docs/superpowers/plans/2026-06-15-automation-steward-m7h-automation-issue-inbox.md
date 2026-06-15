# Automation Steward M7h Automation Issue Inbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish an `.automationIssue` inbox item when the profile expects daily inspection to be enabled but the LaunchAgent is not currently installed.

**Architecture:** Add a pure Foundation automation issue factory and publisher. The publisher adds a pending issue for broken daily inspection state and resolves the same stable source item when the state becomes healthy or no longer expected.

**Tech Stack:** Native Swift, SwiftUI app lifecycle integration, standalone Swift tests through `scripts/test-native.sh`, app build through `scripts/build-native.sh`.

---

## File Structure

- Create `native/MacSoftwareSteward/AutomationIssueInboxFactory.swift`: builds daily inspection automation issue items.
- Create `tests/AutomationIssueInboxFactoryTest.swift`: verifies pending, dedupe, and resolved replacement behavior.
- Modify `scripts/test-native.sh`: add the new test.
- Modify `native/MacSoftwareSteward/App.swift`: publish automation issues on startup and foreground refresh.

## Task 1: Automation Issue Factory And Publisher

**Files:**
- Create: `native/MacSoftwareSteward/AutomationIssueInboxFactory.swift`
- Create: `tests/AutomationIssueInboxFactoryTest.swift`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/AutomationIssueInboxFactoryTest.swift`:

```swift
import Foundation

@main
struct AutomationIssueInboxFactoryTest {
    static func main() {
        var profile = AutomationProfile.manualDefault
        profile.onboardingCompleted = true
        profile.automationEnabled = true
        profile.dailyInspectionEnabled = true

        let healthyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("automation-issue-healthy-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: healthyURL) }
        let healthyStore = InboxStore(fileURL: healthyURL)
        let healthyPublished = AutomationIssueInboxPublisher.publishDailyInspectionIssue(
            profile: profile,
            dailyInspectionEnabled: true,
            to: healthyStore
        )
        precondition(healthyPublished == false)
        precondition(healthyStore.items.isEmpty)

        let issueURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("automation-issue-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: issueURL) }
        let issueStore = InboxStore(fileURL: issueURL)
        let firstPublished = AutomationIssueInboxPublisher.publishDailyInspectionIssue(
            profile: profile,
            dailyInspectionEnabled: false,
            to: issueStore
        )
        precondition(firstPublished == true)
        precondition(issueStore.pendingItems.count == 1)
        precondition(issueStore.pendingItems[0].kind == .automationIssue)
        precondition(issueStore.pendingItems[0].sourceID == AutomationIssueInboxFactory.dailyInspectionSourceID)
        precondition(issueStore.pendingItems[0].actions.map(\.kind) == [.openSettings])

        let secondPublished = AutomationIssueInboxPublisher.publishDailyInspectionIssue(
            profile: profile,
            dailyInspectionEnabled: false,
            to: issueStore
        )
        precondition(secondPublished == false)
        precondition(issueStore.items.count == 1)

        let resolvedPublished = AutomationIssueInboxPublisher.publishDailyInspectionIssue(
            profile: profile,
            dailyInspectionEnabled: true,
            to: issueStore
        )
        precondition(resolvedPublished == false)
        precondition(issueStore.pendingItems.isEmpty)
        precondition(issueStore.items[0].status == .resolved)
    }
}
```

Add this block to `scripts/test-native.sh` after `AutomationNotificationDeciderTest`:

```bash
run_test AutomationIssueInboxFactoryTest \
  "$SRC/AutomationProfileStore.swift" \
  "$SRC/InboxStore.swift" \
  "$SRC/AutomationIssueInboxFactory.swift" \
  "$TESTS/AutomationIssueInboxFactoryTest.swift"
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
npm test
```

Expected: build fails for `AutomationIssueInboxFactoryTest` because `native/MacSoftwareSteward/AutomationIssueInboxFactory.swift` does not exist yet.

- [ ] **Step 3: Implement factory and publisher**

Create `native/MacSoftwareSteward/AutomationIssueInboxFactory.swift`:

```swift
import Foundation

enum AutomationIssueInboxFactory {
    static let dailyInspectionSourceID = "automation:daily-inspection"

    static func pendingDailyInspectionItem(
        profile: AutomationProfile,
        dailyInspectionEnabled: Bool
    ) -> InboxItem? {
        guard profile.onboardingCompleted,
              profile.automationEnabled,
              profile.dailyInspectionEnabled,
              !dailyInspectionEnabled else {
            return nil
        }

        return dailyInspectionItem(
            title: "每日巡检需要重新启用",
            summary: "自动化配置要求每日巡检，但当前未检测到 LaunchAgent。请打开设置重新启用每日巡检。",
            status: .pending
        )
    }

    static func resolvedDailyInspectionItem() -> InboxItem {
        dailyInspectionItem(
            title: "每日巡检状态已恢复",
            summary: "每日巡检 LaunchAgent 已恢复或当前配置不再要求启用。",
            status: .resolved
        )
    }

    private static func dailyInspectionItem(
        title: String,
        summary: String,
        status: InboxStatus
    ) -> InboxItem {
        InboxItem(
            kind: .automationIssue,
            severity: .warning,
            title: title,
            summary: summary,
            sourceID: dailyInspectionSourceID,
            status: status,
            actions: [
                InboxAction(title: "打开设置", systemImage: "gearshape", kind: .openSettings)
            ]
        )
    }
}

enum AutomationIssueInboxPublisher {
    @discardableResult
    static func publishDailyInspectionIssue(
        profile: AutomationProfile,
        dailyInspectionEnabled: Bool,
        to inboxStore: InboxStore
    ) -> Bool {
        if let item = AutomationIssueInboxFactory.pendingDailyInspectionItem(
            profile: profile,
            dailyInspectionEnabled: dailyInspectionEnabled
        ) {
            return inboxStore.add(item)
        }

        let hasPendingIssue = inboxStore.items.contains { item in
            item.kind == .automationIssue
                && item.sourceID == AutomationIssueInboxFactory.dailyInspectionSourceID
                && item.status == .pending
        }
        guard hasPendingIssue else { return false }
        inboxStore.add(AutomationIssueInboxFactory.resolvedDailyInspectionItem())
        return false
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
git add native/MacSoftwareSteward/AutomationIssueInboxFactory.swift tests/AutomationIssueInboxFactoryTest.swift scripts/test-native.sh
git commit -m "feat: publish automation issues to inbox"
```

## Task 2: Foreground Automation Issue Publishing

**Files:**
- Modify: `native/MacSoftwareSteward/App.swift`

- [ ] **Step 1: Publish automation issues on startup and foreground refresh**

In `MacSoftwareStewardApp`, add helpers:

```swift
    private func refreshForegroundStores() {
        inboxStore.reload()
        model.inspectionReportStore.reload()
        model.refreshDailyInspectionStatus()
        publishAutomationIssues()
    }

    private func publishAutomationIssues() {
        AutomationIssueInboxPublisher.publishDailyInspectionIssue(
            profile: automationProfile.profile,
            dailyInspectionEnabled: model.dailyInspectionEnabled,
            to: inboxStore
        )
    }
```

In the `.task` block, after `applyDockIconPolicy()`, add:

```swift
                    model.refreshDailyInspectionStatus()
                    publishAutomationIssues()
```

Replace the active scene phase block with:

```swift
                    refreshForegroundStores()
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
git add native/MacSoftwareSteward/App.swift
git commit -m "feat: refresh automation issues on foreground"
```

## Self-Review

- Spec coverage: Covers the major spec error handling requirement that background Agent path failures prompt users to re-enable daily inspection.
- Placeholder scan: No TODO, TBD, or unspecified implementation steps remain.
- Type consistency: Uses existing `AutomationProfile`, `InboxStore`, `InboxItemKind.automationIssue`, and `InboxActionKind.openSettings`.
