# Task-First Sidebar UI Refresh Design

## Context

Mac Software Steward currently uses a flat SwiftUI `List` sidebar. In advanced mode,
all tabs have equal visual weight: inbox, updates, applications, sources, rules,
history, performance, jobs, and settings. This makes routine maintenance actions
compete with diagnostics and configuration pages.

The user selected the "task-first" direction and chose to fold advanced pages into
an expandable advanced tools group. The user then decided to remove the user-facing
`待处理`, `管理来源`, `历史`, and `性能` pages from navigation.

## Goals

- Make the sidebar emphasize the daily maintenance path.
- Keep advanced controls available without letting diagnostics dominate the first
  scan.
- Remove the user-facing `待处理`, `管理来源`, `历史`, and `性能` tabs and stop
  using them as default or fallback destinations.
- Rename the user-facing `本机应用` destination to `本机软件` and make it cover
  all software the user can manually maintain, not only `.app` bundles.
- Simplify `自动化策略` into selectable option groups and remove import/export and
  rule filtering from that page.
- Improve perceived polish with focused hover, selection, and transition motion.
- Preserve underlying stores, scanners, diagnostics, and recovery logic.

## Non-Goals

- Do not redesign scanner, upgrade, inbox, or persistence logic.
- Do not delete source files for hidden pages or underlying diagnostics.
- Do not introduce new frameworks, assets, or a separate design system.
- Do not change default advanced mode semantics beyond navigation presentation.
- Do not delete underlying inbox, history, source, or performance storage/factories
  in this pass; only remove the user-visible entries from navigation.

## Navigation Design

The sidebar will be replaced with a custom SwiftUI sidebar inside the existing
`NavigationSplitView` column.

`日常维护` section:

- `可升级`
- `本机软件`

`诊断与控制` section:

- `自动化策略` when advanced mode is enabled
- `任务日志` when advanced mode is enabled

Footer:

- `设置` stays visible near the bottom of the sidebar as a quieter utility entry.

Advanced mode behavior:

- When advanced mode is disabled, only the simplified set remains available:
  `本机软件` and `设置`.
- When advanced mode is enabled, `可升级`, `本机软件`, `自动化策略`, and
  `任务日志` are directly visible as normal sidebar rows split across
  `日常维护` and `诊断与控制`.
- If the current selected tab becomes unavailable after advanced mode changes, the
  app falls back to `本机软件`.

Local software list behavior:

- `本机软件` is the maintainable-software inventory.
- Include regular Apps with a practical manual update/check path, such as Sparkle or
  a recognized vendor updater.
- Include Brew Formula, Brew Cask, and Mac App Store rows.
- Do not double-count `.app` bundles already represented by Brew Cask or App Store
  rows.
- Hide system or unknown Apps that have no manual update action, no available
  version, and no checkable update state.
- Provide filters for `全部`, `App`, `Formula`, `Cask`, `App Store`, and `可升级`.
- Header metrics use the same local software rows as the list and show the
  composition explicitly: total software, App total, Brew total, and App Store
  total.
- `可升级` means software with an executable upgrade action, matching the sidebar
  and update page count. Regular Apps that only expose a manual checker or detected
  version are shown as `需确认` or `可检查`, not counted as `可升级`.

Automation rules behavior:

- `自动化策略` uses three direct-control groups: `自动化策略`, `风险规则`, and
  `恢复规则`.
- Each group exposes selectable options through existing pickers, toggles, or
  steppers.
- `自动化策略` owns automation manager, daily inspection, scan scope, upgrade
  execution, notification, network-check, and recovery policy controls.
- `设置` is reserved for application preferences such as appearance, launch,
  Dock visibility, advanced mode, and app self-update.
- Remove the import/export card from this page.
- Remove rule search and category filtering from this page.
- Keep the underlying data bundle service and rules presenter available for tests
  and non-visible logic.

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
- Keep `自动化策略` and `任务日志` visually equal to other work destinations; do
  not hide them behind a disclosure row.
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

Add a small presenter/model helper for testability:

- `AppTabNavigationPresenter`

The presenter exposes:

- primary maintenance tabs for advanced and non-advanced modes
- direct control tabs for advanced mode
- no hidden advanced tab group; advanced mode shows control tabs as direct rows
- footer tabs
- visibility checks
- fallback selection behavior

## Data Flow

- `ContentView` keeps using `model.selectedTab`.
- `TaskFirstSidebar` reads `model`, `automationProfile`, and relevant counts.
- Tapping a row sets `model.selectedTab`.
- `AppTab.visibleTabs(advancedModeEnabled:)` remains available for compatibility;
  `AppTabNavigationPresenter` centralizes the new grouped navigation rules.

## Error Handling

There is no new backend error surface.

- If advanced mode disables the current tab, fall back to `本机软件`.
- If counts are unavailable before the first scan, status chip shows a neutral
  preparing or ready state.
- If a job fails, existing `JobNoticeView` remains the detail-level failure surface.

## Testing

Add focused Swift tests for navigation grouping and fallback behavior.

Test cases:

- Advanced mode enabled exposes `日常维护`, `诊断与控制`, and settings footer.
- Advanced mode disabled hides advanced-only tabs and keeps `本机软件` and `设置`.
- `待处理`, `管理来源`, `历史`, and `性能` are not visible in advanced or simple
  navigation.
- Selecting an unavailable tab falls back to `本机软件`.
- Advanced tool state remains false because control tabs are ordinary direct rows.
- Sidebar hover and selected presentation are separate style states.
- Tab transition identity changes when `selectedTab` changes, allowing the content
  transition to run.
- Local software visibility includes regular update-capable Apps, Brew Formula,
  Brew Cask, and App Store rows, while hiding unsupported system/manual Apps and
  avoiding managed-App duplicates.

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
