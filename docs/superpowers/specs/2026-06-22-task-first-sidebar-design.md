# Task-First Sidebar UI Refresh Design

## Context

Mac Software Steward currently uses a flat SwiftUI `List` sidebar. In advanced mode,
all tabs have equal visual weight: inbox, updates, applications, sources, rules,
history, performance, jobs, and settings. This makes routine maintenance actions
compete with diagnostics and configuration pages.

The user selected the "task-first" direction and chose to fold advanced pages into
an expandable advanced tools group. The user then decided to remove the user-facing
`待处理` page from navigation.

## Goals

- Make the sidebar emphasize the daily maintenance path.
- Keep advanced diagnostics available without letting them dominate the first scan.
- Remove the user-facing `待处理` tab and stop using it as the default or fallback
  destination.
- Improve perceived polish with focused hover, selection, and transition motion.
- Preserve existing non-inbox tab destinations and application behavior.
- Keep the implementation scoped to navigation and view presentation.

## Non-Goals

- Do not redesign scanner, upgrade, policy, inbox, or persistence logic.
- Do not merge existing pages or delete source files.
- Do not introduce new frameworks, assets, or a separate design system.
- Do not change default advanced mode semantics beyond navigation presentation.
- Do not delete underlying inbox storage or factories in this pass; only remove the
  user-visible `待处理` page from navigation.

## Navigation Design

The sidebar will be replaced with a custom SwiftUI sidebar inside the existing
`NavigationSplitView` column.

Primary section:

- `可升级`
- `本机应用`

Advanced tools section:

- A single row labeled `高级工具`.
- The row expands and collapses with a spring animation.
- Expanded contents include `管理来源`, `自动化策略`, `历史`, `性能`, and `任务日志`.
- If one of these advanced tabs is selected while the group is collapsed, the group
  uses the selected row style and shows the active tab title as a short caption.

Footer:

- `设置` stays visible near the bottom of the sidebar as a quieter utility entry.

Advanced mode behavior:

- When advanced mode is disabled, only the simplified set remains available:
  `本机应用`, `历史`, and `设置`.
- When advanced mode is enabled, the task-first grouping applies.
- If the current selected tab becomes unavailable after advanced mode changes, the
  app falls back to `本机应用`.

## Visual Design

The sidebar should feel like a macOS maintenance console, not a marketing surface.
The design should stay quiet and utility-focused.

- Use a slightly wider sidebar than the current default so labels and status text
  have breathing room.
- Use a compact status chip near the top for app state:
  - scanning
  - upgrade running
  - pending update count
  - all clear
- Use a lightweight pill selection state with an accent-colored leading mark.
- Make hover state visibly distinct from selected state so the pointer target is
  obvious before clicking.
- Use lower emphasis for advanced rows through smaller type, softer color, and
  tighter spacing.
- Keep settings visually separate from primary work by pinning it near the bottom.
- Keep radius modest and avoid decorative backgrounds that fight with macOS
  materials.

## Interaction Design

- Sidebar row hover should gently lift or tint the row.
- Hover state uses a soft row background, icon tint, and subtle scale so the user
  can always tell which tab the pointer is over.
- Selected row uses a stronger pill background, an accent leading mark, bold text,
  and accent icon color; it must remain clearly different from hover.
- Selected row should animate with a spring response when it changes.
- Advanced tools expansion should animate disclosure, opacity, and vertical movement.
- Tab content transition uses a short fade with subtle vertical movement to avoid
  abrupt switches.
- Tab switching also animates the selected sidebar indicator and page title so the
  new active destination is visually confirmed.
- Status chip should animate changes but avoid constant motion unless scanning or
  upgrading is active.
- Respect platform availability for symbol effects and avoid relying on macOS 15+
  APIs without guards.

## Component Design

Add small, local components in `ContentView.swift`:

- `TaskFirstSidebar`
- `SidebarSection`
- `SidebarRow`
- `SidebarStatusChip`
- `AdvancedToolsDisclosure`

Add a small presenter/model helper for testability:

- `AppTabNavigationPresenter`

The presenter exposes:

- primary tabs for advanced and non-advanced modes
- advanced tabs
- footer tabs
- visibility checks
- fallback selection behavior

## Data Flow

- `ContentView` keeps using `model.selectedTab`.
- `TaskFirstSidebar` reads `model`, `automationProfile`, and relevant counts.
- Tapping a row sets `model.selectedTab`.
- Advanced disclosure state is view-local `@State`, defaults to expanded when the
  selected tab is in the advanced tools set, and is not persisted.
- `AppTab.visibleTabs(advancedModeEnabled:)` remains available for compatibility;
  `AppTabNavigationPresenter` centralizes the new grouped navigation rules.

## Error Handling

There is no new backend error surface.

- If advanced mode disables the current tab, fall back to `本机应用`.
- If counts are unavailable before the first scan, status chip shows a neutral
  preparing or ready state.
- If a job fails, existing `JobNoticeView` remains the detail-level failure surface.

## Testing

Add focused Swift tests for navigation grouping and fallback behavior.

Test cases:

- Advanced mode enabled exposes primary tabs, advanced tabs, and settings footer.
- Advanced mode disabled hides advanced-only tabs and keeps `本机应用`, `历史`, and
  `设置`.
- `待处理` is not visible in advanced or simple navigation.
- Selecting an unavailable tab falls back to `本机应用`.
- Advanced group active state is true when selected tab belongs to the advanced set.
- Sidebar hover and selected presentation are separate style states.
- Tab transition identity changes when `selectedTab` changes, allowing the content
  transition to run.

Existing verification remains:

```bash
npm test
npm run build
```

## Implementation Notes

- Keep UI copy in Chinese and code identifiers in English.
- Avoid changing page internals unless needed for spacing consistency.
- Use existing SwiftUI/AppKit patterns; do not add package dependencies.
- Keep generated icon files untouched.
