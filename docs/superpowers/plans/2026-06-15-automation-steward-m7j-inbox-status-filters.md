# Automation Steward M7j Inbox Status Filters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let advanced-mode users review pending, completed, ignored, or all Inbox items from the Inbox control panel.

**Architecture:** Extend the existing pure `InboxFilterPresenter` with a status filter. Keep default mode focused on pending items only; `InboxView` switches to the full store only when advanced mode is enabled.

**Tech Stack:** Native Swift, SwiftUI, standalone Swift tests through `scripts/test-native.sh`, app build through `scripts/build-native.sh`.

---

## File Structure

- Modify `native/MacSoftwareSteward/InboxFilterPresenter.swift`: add `InboxStatusFilter` and apply it in filtering.
- Modify `tests/InboxFilterPresenterTest.swift`: verify status filtering with pending, resolved, ignored, and all.
- Modify `native/MacSoftwareSteward/Views/InboxView.swift`: add an advanced status picker and make advanced mode filter across all inbox items.

## Task 1: Pure Status Filter

**Files:**
- Modify: `tests/InboxFilterPresenterTest.swift`
- Modify: `native/MacSoftwareSteward/InboxFilterPresenter.swift`

- [ ] **Step 1: Write the failing test**

Update `tests/InboxFilterPresenterTest.swift` so the sample items include statuses and add status filter assertions:

```swift
        let items = [
            InboxItem(kind: .upgradeDecision, severity: .warning, title: "Risk", summary: "Needs confirmation", status: .pending),
            InboxItem(kind: .sourceIssue, severity: .warning, title: "Source", summary: "Homebrew missing", status: .resolved),
            InboxItem(kind: .permissionIssue, severity: .critical, title: "Permission", summary: "Permission denied", status: .ignored),
            InboxItem(kind: .appUpdate, severity: .info, title: "App", summary: "Update available", status: .pending)
        ]
```

Append:

```swift
        let pendingItems = InboxFilterPresenter.items(from: items, kind: .all, severity: .all, status: .pending)
        precondition(pendingItems.map(\.title) == ["Risk", "App"])

        let resolvedItems = InboxFilterPresenter.items(from: items, kind: .all, severity: .all, status: .resolved)
        precondition(resolvedItems.map(\.kind) == [.sourceIssue])

        let ignoredPermissions = InboxFilterPresenter.items(from: items, kind: .permissions, severity: .all, status: .ignored)
        precondition(ignoredPermissions.map(\.kind) == [.permissionIssue])

        let allStatusItems = InboxFilterPresenter.items(from: items, kind: .all, severity: .all, status: .all)
        precondition(allStatusItems.count == 4)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
npm test
```

Expected: `InboxFilterPresenterTest` fails to compile because `InboxStatusFilter` and the `status:` parameter do not exist.

- [ ] **Step 3: Implement status filter**

Add this enum in `native/MacSoftwareSteward/InboxFilterPresenter.swift` after `InboxSeverityFilter`:

```swift
enum InboxStatusFilter: String, CaseIterable, Identifiable {
    case pending
    case resolved
    case ignored
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: return "待处理"
        case .resolved: return "已完成"
        case .ignored: return "已忽略"
        case .all: return "全部"
        }
    }

    func matches(_ status: InboxStatus) -> Bool {
        switch self {
        case .pending:
            return status == .pending
        case .resolved:
            return status == .resolved
        case .ignored:
            return status == .ignored
        case .all:
            return true
        }
    }
}
```

Change `InboxFilterPresenter.items` to accept and apply `status`:

```swift
    static func items(
        from items: [InboxItem],
        kind: InboxKindFilter,
        severity: InboxSeverityFilter,
        status: InboxStatusFilter = .all
    ) -> [InboxItem] {
        items.filter { item in
            kind.matches(item.kind)
                && severity.matches(item.severity)
                && status.matches(item.status)
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
git add native/MacSoftwareSteward/InboxFilterPresenter.swift tests/InboxFilterPresenterTest.swift
git commit -m "feat: add inbox status filter"
```

## Task 2: Advanced Status Controls

**Files:**
- Modify: `native/MacSoftwareSteward/Views/InboxView.swift`

- [ ] **Step 1: Wire status filter state**

Add state:

```swift
    @State private var statusFilter: InboxStatusFilter = .pending
```

Update `visibleItems`:

```swift
    private var visibleItems: [InboxItem] {
        guard automationProfile.profile.advancedModeEnabled else { return pendingItems }
        return InboxFilterPresenter.items(
            from: inboxStore.items,
            kind: kindFilter,
            severity: severityFilter,
            status: statusFilter
        )
    }

    private var hasAnyVisibleScopeItems: Bool {
        automationProfile.profile.advancedModeEnabled ? !inboxStore.items.isEmpty : !pendingItems.isEmpty
    }
```

- [ ] **Step 2: Update filter bar and empty state**

Show the filter bar when advanced mode has any inbox item:

```swift
            if automationProfile.profile.advancedModeEnabled && !inboxStore.items.isEmpty {
                InboxFilterBar(kindFilter: $kindFilter, severityFilter: $severityFilter, statusFilter: $statusFilter)
            }
```

Change empty check:

```swift
            if !hasAnyVisibleScopeItems {
```

Update `InboxFilterBar` to bind and render status:

```swift
private struct InboxFilterBar: View {
    @Binding var kindFilter: InboxKindFilter
    @Binding var severityFilter: InboxSeverityFilter
    @Binding var statusFilter: InboxStatusFilter

    var body: some View {
        HStack(spacing: 10) {
            Picker("类型", selection: $kindFilter) {
                ForEach(InboxKindFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.menu)

            Picker("状态", selection: $statusFilter) {
                ForEach(InboxStatusFilter.allCases) { filter in
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
git commit -m "feat: add advanced inbox status filters"
```

## Self-Review

- Spec coverage: Extends the advanced control panel so users can view current and handled inbox items while default mode remains simple.
- Placeholder scan: No TODO, TBD, or unspecified steps remain.
- Type consistency: Uses existing `InboxItem.status`, `InboxStatus`, `InboxFilterPresenter`, and `InboxView` state patterns.
