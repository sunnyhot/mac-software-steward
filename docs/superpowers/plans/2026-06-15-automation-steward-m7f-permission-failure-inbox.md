# Automation Steward M7f Permission Failure Inbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Classify permission-related upgrade failures as `.permissionIssue` inbox items while preserving existing recovery actions and deduplication.

**Architecture:** Keep failure detection in `UpgradeFailureAnalyzer` and recovery actions in `RecoveryActionPlanner`. Add only a small classification helper inside `RecoveryInboxFactory` so permission failures use the existing `InboxItemKind.permissionIssue` type without changing storage or UI contracts.

**Tech Stack:** Native Swift, pure Foundation tests compiled through `scripts/test-native.sh`.

---

## File Structure

- Modify `tests/RecoveryInboxFactoryTest.swift`: add a deterministic test case for `FailureActionType.repairPerms`.
- Modify `native/MacSoftwareSteward/RecoveryInboxFactory.swift`: choose inbox kind from `PackageUpgradeProgress.recoveryAction`.
- Modify `scripts/test-native.sh`: no change expected; `RecoveryInboxFactoryTest` already compiles the required source files.

## Task 1: Permission Failure Classification

**Files:**
- Modify: `tests/RecoveryInboxFactoryTest.swift`
- Modify: `native/MacSoftwareSteward/RecoveryInboxFactory.swift`

- [ ] **Step 1: Write the failing test**

Append this case in `tests/RecoveryInboxFactoryTest.swift` after the existing `failed` assertions and before the `running` case:

```swift
        let permissionFailure = PackageUpgradeProgress(
            packageID: "brew:cask:secured-app",
            packageName: "Secured App",
            status: .failed,
            detail: "Permission denied",
            failureSummary: "没有写入权限，无法完成安装。",
            recoverySuggestion: "请尝试点击「重试」。如果仍然失败，可在「系统设置 > 隐私与安全性」中检查 Homebrew 的磁盘访问权限。",
            recoveryAction: .repairPerms,
            lastFailedCommand: "brew upgrade --cask secured-app"
        )

        let permissionItems = RecoveryInboxFactory.items(from: [permissionFailure])
        precondition(permissionItems.count == 1)
        precondition(permissionItems[0].kind == .permissionIssue)
        precondition(permissionItems[0].severity == .critical)
        precondition(permissionItems[0].sourceID == permissionFailure.packageID)
        precondition(permissionItems[0].actions.map(\.kind) == [.retryPackage, .openUpdates, .openJobs])
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
npm test
```

Expected: `RecoveryInboxFactoryTest` fails because permission failures are still emitted as `.failureRecovery`.

- [ ] **Step 3: Implement minimal classification**

In `native/MacSoftwareSteward/RecoveryInboxFactory.swift`, change the item creation to use `kind(for:)`:

```swift
                InboxItem(
                    kind: kind(for: progress),
                    severity: severity(for: progress),
                    title: "\(progress.packageName) 升级失败",
                    summary: summary(for: progress),
                    sourceID: progress.packageID,
                    actions: RecoveryActionPlanner.actions(for: progress).map(inboxAction)
                )
```

Add this helper near the existing `severity(for:)` helper:

```swift
    private static func kind(for progress: PackageUpgradeProgress) -> InboxItemKind {
        switch progress.recoveryAction {
        case .repairPerms:
            return .permissionIssue
        default:
            return .failureRecovery
        }
    }
```

- [ ] **Step 4: Run verification**

Run:

```bash
npm test
```

Expected: all native tests pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add native/MacSoftwareSteward/RecoveryInboxFactory.swift tests/RecoveryInboxFactoryTest.swift
git commit -m "feat: classify permission failures in inbox"
```

## Self-Review

- Spec coverage: Covers the major spec requirement that permission failures become inbox items, using the existing `.permissionIssue` type.
- Placeholder scan: No placeholders, TODOs, or ambiguous follow-up steps remain.
- Type consistency: Uses existing `PackageUpgradeProgress`, `FailureActionType.repairPerms`, `InboxItemKind.permissionIssue`, and `RecoveryInboxFactory.items(from:)`.
