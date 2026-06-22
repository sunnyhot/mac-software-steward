# Task-First Sidebar Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the user-facing `待处理` navigation entry and replace the flat sidebar with a task-first sidebar that has clear hover, selected, and tab-switch feedback.

**Architecture:** Add a small navigation presenter that owns grouped tab rules and fallback behavior. `ContentView` uses the presenter to render a custom SwiftUI sidebar while existing page views remain intact. Tests protect the user-visible navigation contract before UI wiring changes.

**Tech Stack:** Swift, SwiftUI, AppKit, existing `xcrun swiftc` single-file test runner.

---

### Task 1: Navigation Rules Presenter

**Files:**
- Create: `native/MacSoftwareSteward/AppTabNavigationPresenter.swift`
- Modify: `native/MacSoftwareSteward/Models.swift`
- Modify: `scripts/test-native.sh`
- Test: `tests/AppTabVisibilityTest.swift`

- [ ] **Step 1: Write the failing test**

Replace the visible tab assertions in `tests/AppTabVisibilityTest.swift` with:

```swift
precondition(AppTab.visibleTabs(advancedModeEnabled: false) == [
    .applications,
    .history,
    .settings
])
precondition(AppTab.visibleTabs(advancedModeEnabled: true) == [
    .updates,
    .applications,
    .sources,
    .rules,
    .history,
    .performance,
    .jobs,
    .settings
])
precondition(!AppTab.visibleTabs(advancedModeEnabled: false).contains(.inbox))
precondition(!AppTab.visibleTabs(advancedModeEnabled: true).contains(.inbox))
precondition(AppTabNavigationPresenter.primaryTabs(advancedModeEnabled: true) == [.updates, .applications])
precondition(AppTabNavigationPresenter.primaryTabs(advancedModeEnabled: false) == [.applications, .history])
precondition(AppTabNavigationPresenter.advancedTabs(advancedModeEnabled: true) == [.sources, .rules, .history, .performance, .jobs])
precondition(AppTabNavigationPresenter.advancedTabs(advancedModeEnabled: false).isEmpty)
precondition(AppTabNavigationPresenter.footerTabs == [.settings])
precondition(AppTabNavigationPresenter.fallbackTab(for: .inbox, advancedModeEnabled: true) == .applications)
precondition(AppTabNavigationPresenter.fallbackTab(for: .sources, advancedModeEnabled: false) == .applications)
precondition(AppTabNavigationPresenter.isAdvancedTool(.jobs, advancedModeEnabled: true))
precondition(!AppTabNavigationPresenter.isAdvancedTool(.updates, advancedModeEnabled: true))
precondition(SidebarRowInteractionState.hovered != SidebarRowInteractionState.selected)
precondition(SidebarRowInteractionState.selected.showsSelectionIndicator)
precondition(!SidebarRowInteractionState.hovered.showsSelectionIndicator)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
xcrun swiftc -target arm64-apple-macosx14.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  native/MacSoftwareSteward/ScanPerformance.swift \
  native/MacSoftwareSteward/Models.swift \
  tests/AppTabVisibilityTest.swift \
  -o build/tests/AppTabVisibilityTest-red && build/tests/AppTabVisibilityTest-red
```

Expected: compile failure because `AppTabNavigationPresenter` and `SidebarRowInteractionState` do not exist, or assertion failure because `待处理` is still visible.

- [ ] **Step 3: Implement the presenter**

Create `native/MacSoftwareSteward/AppTabNavigationPresenter.swift`:

```swift
import Foundation

enum SidebarRowInteractionState: Equatable {
    case normal
    case hovered
    case selected

    var showsSelectionIndicator: Bool {
        self == .selected
    }
}

enum AppTabNavigationPresenter {
    static func primaryTabs(advancedModeEnabled: Bool) -> [AppTab] {
        advancedModeEnabled ? [.updates, .applications] : [.applications, .history]
    }

    static func advancedTabs(advancedModeEnabled: Bool) -> [AppTab] {
        advancedModeEnabled ? [.sources, .rules, .history, .performance, .jobs] : []
    }

    static let footerTabs: [AppTab] = [.settings]

    static func visibleTabs(advancedModeEnabled: Bool) -> [AppTab] {
        primaryTabs(advancedModeEnabled: advancedModeEnabled)
            + advancedTabs(advancedModeEnabled: advancedModeEnabled)
            + footerTabs
    }

    static func fallbackTab(for selectedTab: AppTab, advancedModeEnabled: Bool) -> AppTab {
        visibleTabs(advancedModeEnabled: advancedModeEnabled).contains(selectedTab)
            ? selectedTab
            : .applications
    }

    static func isAdvancedTool(_ tab: AppTab, advancedModeEnabled: Bool) -> Bool {
        advancedTabs(advancedModeEnabled: advancedModeEnabled).contains(tab)
    }

    static func advancedCaption(for selectedTab: AppTab, advancedModeEnabled: Bool) -> String {
        isAdvancedTool(selectedTab, advancedModeEnabled: advancedModeEnabled) ? selectedTab.rawValue : ""
    }
}
```

Update `AppTab.visibleTabs(advancedModeEnabled:)` in `native/MacSoftwareSteward/Models.swift` to delegate:

```swift
static func visibleTabs(advancedModeEnabled: Bool) -> [AppTab] {
    AppTabNavigationPresenter.visibleTabs(advancedModeEnabled: advancedModeEnabled)
}
```

Update the `AppTabVisibilityTest` compile command in `scripts/test-native.sh` to include:

```bash
"$SRC/AppTabNavigationPresenter.swift" \
```

- [ ] **Step 4: Run the focused test to verify it passes**

Run the same focused `xcrun swiftc` command, now with `native/MacSoftwareSteward/AppTabNavigationPresenter.swift` added before the test file.

Expected: command exits 0.

### Task 2: Custom Task-First Sidebar

**Files:**
- Modify: `native/MacSoftwareSteward/ContentView.swift`
- Modify: `native/MacSoftwareSteward/StewardModel.swift`

- [ ] **Step 1: Change default and fallback destination**

In `StewardModel`, initialize:

```swift
@Published var selectedTab: AppTab = .applications
```

In `ContentView.onChange(of: automationProfile.profile.advancedModeEnabled)`, replace manual fallback with:

```swift
model.selectedTab = AppTabNavigationPresenter.fallbackTab(
    for: model.selectedTab,
    advancedModeEnabled: automationProfile.profile.advancedModeEnabled
)
```

- [ ] **Step 2: Replace the flat sidebar**

Replace the `List(...)` in `NavigationSplitView` with:

```swift
TaskFirstSidebar()
    .environmentObject(model)
    .environmentObject(automationProfile)
    .navigationSplitViewColumnWidth(min: 210, ideal: 230)
```

Add `TaskFirstSidebar`, `SidebarStatusChip`, `AdvancedToolsDisclosure`, and `SidebarRow` as private views in `ContentView.swift`.

- [ ] **Step 3: Implement hover and selected states**

Use `@State private var isHovered = false` in `SidebarRow`.

Use `SidebarRowInteractionState`:

```swift
let state: SidebarRowInteractionState = isSelected ? .selected : (isHovered ? .hovered : .normal)
```

Render selected rows with a stronger pill background, accent icon, bold title, and a leading accent mark. Render hovered rows with a softer background, no leading mark, and lighter scale.

- [ ] **Step 4: Add advanced disclosure behavior**

Use view-local state:

```swift
@State private var advancedExpanded = true
```

If `model.selectedTab` is an advanced tool, keep the disclosure visually active and show `AppTabNavigationPresenter.advancedCaption(...)` when collapsed.

### Task 3: Tab Transition Polish

**Files:**
- Modify: `native/MacSoftwareSteward/ContentView.swift`

- [ ] **Step 1: Add transition identity to title**

In `MainPanel`, give the page title a tab identity and transition:

```swift
Text(model.selectedTab.rawValue)
    .id(model.selectedTab.rawValue)
    .transition(.opacity.combined(with: .move(edge: .top)))
```

- [ ] **Step 2: Add transition identity to content**

Wrap the switched page content with:

```swift
.id(model.selectedTab)
.transition(.opacity.combined(with: .move(edge: .bottom)))
.animation(.easeOut(duration: 0.18), value: model.selectedTab)
```

- [ ] **Step 3: Keep `.inbox` from surfacing**

Keep the existing `.inbox` switch branch compiled for now, but because `.inbox` is no longer visible or the default fallback, it should not be reachable through the sidebar.

### Task 4: Verification

**Files:**
- No new files.

- [ ] **Step 1: Run full native tests**

```bash
npm test
```

Expected: `All native tests passed.`

- [ ] **Step 2: Run app build**

```bash
npm run build
```

Expected: app and agent build, ad-hoc signing succeeds, signature verifies.

- [ ] **Step 3: Restore generated iconset if build rewrites it**

```bash
git restore --worktree native/Resources/AppIcon.iconset
```

Expected: no generated icon PNG changes remain unless intentionally changed.
