# Automation Steward M7g Advanced Inbox Filters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add advanced-mode inbox filters so users can inspect pending items by issue type and severity without changing the default simple inbox.

**Architecture:** Keep filtering as pure Foundation logic in a focused presenter. `InboxView` owns only transient UI state and shows the filter controls when advanced mode is enabled.

**Tech Stack:** Native Swift, SwiftUI, standalone Swift tests through `scripts/test-native.sh`, app build through `scripts/build-native.sh`.

---

## File Structure

- Create `native/MacSoftwareSteward/InboxFilterPresenter.swift`: filter enums and pure filtering helper.
- Create `tests/InboxFilterPresenterTest.swift`: deterministic unit tests for type/severity combinations.
- Modify `scripts/test-native.sh`: add `InboxFilterPresenterTest`.
- Modify `native/MacSoftwareSteward/Views/InboxView.swift`: show advanced filter controls and filtered empty state.

## Task 1: Pure Inbox Filter Presenter

**Files:**
- Create: `native/MacSoftwareSteward/InboxFilterPresenter.swift`
- Create: `tests/InboxFilterPresenterTest.swift`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/InboxFilterPresenterTest.swift`:

```swift
import Foundation

@main
struct InboxFilterPresenterTest {
    static func main() {
        let items = [
            InboxItem(kind: .upgradeDecision, severity: .warning, title: "Risk", summary: "Needs confirmation"),
            InboxItem(kind: .sourceIssue, severity: .warning, title: "Source", summary: "Homebrew missing"),
            InboxItem(kind: .permissionIssue, severity: .critical, title: "Permission", summary: "Permission denied"),
            InboxItem(kind: .appUpdate, severity: .info, title: "App", summary: "Update available")
        ]

        precondition(InboxFilterPresenter.items(from: items, kind: .all, severity: .all).count == 4)

        let permissionItems = InboxFilterPresenter.items(from: items, kind: .permissions, severity: .all)
        precondition(permissionItems.map(\.kind) == [.permissionIssue])

        let sourceWarnings = InboxFilterPresenter.items(from: items, kind: .sources, severity: .warning)
        precondition(sourceWarnings.map(\.kind) == [.sourceIssue])

        let criticalItems = InboxFilterPresenter.items(from: items, kind: .all, severity: .critical)
        precondition(criticalItems.map(\.kind) == [.permissionIssue])
    }
}
```

Add this block to `scripts/test-native.sh` after `InboxStoreTest`:

```bash
run_test InboxFilterPresenterTest \
  "$SRC/InboxStore.swift" \
  "$SRC/InboxFilterPresenter.swift" \
  "$TESTS/InboxFilterPresenterTest.swift"
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
npm test
```

Expected: build fails for `InboxFilterPresenterTest` because `native/MacSoftwareSteward/InboxFilterPresenter.swift` does not exist yet.

- [ ] **Step 3: Implement presenter**

Create `native/MacSoftwareSteward/InboxFilterPresenter.swift`:

```swift
import Foundation

enum InboxKindFilter: String, CaseIterable, Identifiable {
    case all
    case decisions
    case apps
    case failures
    case sources
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .decisions: return "升级决策"
        case .apps: return "应用更新"
        case .failures: return "失败恢复"
        case .sources: return "来源异常"
        case .permissions: return "权限"
        }
    }

    func matches(_ kind: InboxItemKind) -> Bool {
        switch self {
        case .all:
            return true
        case .decisions:
            return kind == .upgradeDecision
        case .apps:
            return kind == .appUpdate
        case .failures:
            return kind == .failureRecovery
        case .sources:
            return kind == .sourceIssue
        case .permissions:
            return kind == .permissionIssue
        }
    }
}

enum InboxSeverityFilter: String, CaseIterable, Identifiable {
    case all
    case critical
    case warning
    case info

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .critical: return "严重"
        case .warning: return "需确认"
        case .info: return "信息"
        }
    }

    func matches(_ severity: InboxSeverity) -> Bool {
        switch self {
        case .all:
            return true
        case .critical:
            return severity == .critical
        case .warning:
            return severity == .warning
        case .info:
            return severity == .info
        }
    }
}

enum InboxFilterPresenter {
    static func items(
        from items: [InboxItem],
        kind: InboxKindFilter,
        severity: InboxSeverityFilter
    ) -> [InboxItem] {
        items.filter { item in
            kind.matches(item.kind) && severity.matches(item.severity)
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
git add native/MacSoftwareSteward/InboxFilterPresenter.swift tests/InboxFilterPresenterTest.swift scripts/test-native.sh
git commit -m "feat: add inbox filter presenter"
```

## Task 2: Advanced Inbox Filter Controls

**Files:**
- Modify: `native/MacSoftwareSteward/Views/InboxView.swift`

- [ ] **Step 1: Wire filtered item state**

In `InboxView`, add transient state and visible item selection:

```swift
    @State private var kindFilter: InboxKindFilter = .all
    @State private var severityFilter: InboxSeverityFilter = .all

    private var visibleItems: [InboxItem] {
        guard automationProfile.profile.advancedModeEnabled else { return pendingItems }
        return InboxFilterPresenter.items(from: pendingItems, kind: kindFilter, severity: severityFilter)
    }
```

- [ ] **Step 2: Add advanced filter bar and filtered empty state**

Update the list area so advanced users see filters above the list:

```swift
            if automationProfile.profile.advancedModeEnabled && !pendingItems.isEmpty {
                InboxFilterBar(kindFilter: $kindFilter, severityFilter: $severityFilter)
            }

            if pendingItems.isEmpty {
                EmptyStateView(
                    symbol: "checkmark.circle",
                    title: "暂无待处理事项",
                    text: "需要确认的升级、失败恢复和来源异常会出现在这里。"
                )
            } else if visibleItems.isEmpty {
                EmptyStateView(
                    symbol: "line.3.horizontal.decrease.circle",
                    title: "当前筛选暂无事项",
                    text: "调整类型或严重级别筛选后再查看。"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(visibleItems) { item in
                            InboxItemRow(item: item)
                                .environmentObject(model)
                                .environmentObject(automationProfile)
                                .environmentObject(inboxStore)
                        }
                    }
                }
            }
```

Add this private view near the other private `InboxView` helper views:

```swift
private struct InboxFilterBar: View {
    @Binding var kindFilter: InboxKindFilter
    @Binding var severityFilter: InboxSeverityFilter

    var body: some View {
        HStack(spacing: 10) {
            Picker("类型", selection: $kindFilter) {
                ForEach(InboxKindFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.menu)

            Picker("严重级别", selection: $severityFilter) {
                ForEach(InboxSeverityFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
```

- [ ] **Step 3: Verify build and tests**

Run:

```bash
npm run build
git restore native/Resources/AppIcon.iconset/*.png
npm test
```

Expected: app and helper agent build successfully, generated AppIcon PNGs are restored, and all native tests pass.

- [ ] **Step 4: Commit**

Run:

```bash
git add native/MacSoftwareSteward/Views/InboxView.swift
git commit -m "feat: add advanced inbox filters"
```

## Self-Review

- Spec coverage: Implements the major spec direction that default inbox stays simple while advanced mode exposes control-panel style filtering.
- Placeholder scan: No TODO, TBD, or unspecified implementation steps remain.
- Type consistency: Uses existing `InboxItem`, `InboxItemKind`, `InboxSeverity`, and `AutomationProfileStore.profile.advancedModeEnabled`.
