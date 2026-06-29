# UI and Effects Upgrade Design

## Context

Mac Software Steward is a native SwiftUI macOS utility for scanning local software,
planning upgrades, and running maintenance tasks. The current interface already
uses a task-first sidebar and Chinese UI copy, but the visual system still feels
assembled page by page: status feedback, cards, list rows, empty states, and motion
do not yet feel like one polished maintenance console.

The chosen direction is a professional macOS control-console feel with restrained
technology effects. The application should feel calmer, clearer, and more premium,
while using stronger animation only when the system is genuinely scanning,
upgrading, completing, or failing work.

## Goals

- Upgrade the whole app's perceived polish without changing scan, upgrade, rules,
  persistence, or automation behavior.
- Keep the current task-first navigation model and improve its visual confidence.
- Make the main content feel like a local software maintenance cockpit: current
  state first, actionable software tasks second.
- Unify visual treatment across update rows, local software rows, progress panels,
  warnings, empty states, and utility controls.
- Add motion that explains real state changes instead of decorative constant
  movement.
- Respect macOS native conventions, system appearance, accent color, keyboard
  focus, and reduced-motion settings.

## Non-Goals

- Do not replace SwiftUI/AppKit with a web UI or add external UI dependencies.
- Do not redesign scanner, upgrade planner, policy, inbox, history, source, or
  persistence logic.
- Do not reintroduce hidden navigation pages or change advanced-mode semantics.
- Do not create a marketing-style landing page, oversized hero, decorative orbs,
  or a one-note purple/blue gradient theme.
- Do not edit generated app icons or release artifacts.

## Visual Direction

The app should read as a native macOS maintenance console with a subtle technical
surface language:

- Surfaces use modest radius, material backgrounds, crisp 1px separators, and
  restrained shadows.
- Functional colors come from state: blue/cyan for scanning and active work,
  orange for pending attention, green for healthy completion, red for failure,
  and system accent for primary action.
- Typography stays compact and utility-focused with rounded system headings,
  readable body copy, and monospaced digits for counts, percentages, versions, and
  command-like values.
- Visual emphasis should be spent on one signature element: a live maintenance
  status band that anchors the main content and subtly animates during scanning or
  upgrading.
- The app should avoid decorative backgrounds. Effects must be attached to status
  surfaces, progress bars, selected navigation, or active rows.

## Layout Design

The existing `NavigationSplitView` remains the top-level structure.

Sidebar:

- Keep the task-first sections from the current design.
- Refine the top status chip so it feels like a live console indicator.
- Strengthen selected state with a compact accent rail, subtle tint, and clear
  icon/text contrast.
- Keep hover and selected states visually distinct.
- Keep settings visually quiet near the bottom.

Main detail area:

- Add or refine a maintenance status band near the top of non-settings pages.
- The status band summarizes scan/update state, scan phase when available, pending
  update count, job state, and the most relevant primary actions.
- Preserve current page titles and page ownership, but make page headers and
  controls align to the same spacing system.
- Keep content scrollable and avoid nested card-in-card layouts.

Lists and task rows:

- Update rows should feel like compact task cards with a clear source icon, name,
  version transition, policy picker, status badge, and action.
- Active package rows should be visibly linked to the running upgrade state.
- Failure rows should provide stronger but calm feedback, with red used for state
  and recovery actions staying discoverable.
- Shared row styling should be reusable by other pages where practical, but the
  implementation should stay scoped and avoid a large design-system rewrite.

## Motion Design

Motion is state-driven:

- Scanning: symbol rotation where available, soft pulse, smooth phase text changes,
  and an animated status-band accent line.
- Upgrading: progress bar shimmer, active row tint, package-stage changes with
  short fade/slide transitions, and completion/failure feedback.
- Navigation: tab content switches with a short fade and slight vertical movement.
- Hover and press: sidebar rows, buttons, and task rows use small scale/tint changes
  with spring timing.
- Empty and warning states: enter with a short opacity/scale transition, not a
  looping animation.

Motion constraints:

- Prefer `opacity`, `scaleEffect`, and `offset` over layout-changing animation.
- Keep most interaction animations around 150-300ms.
- Guard macOS 15-only symbol effects with availability checks.
- Respect `@Environment(\.accessibilityReduceMotion)` and fall back to static
  color/opacity changes when reduced motion is enabled.

## Component Design

Likely changes should focus on these areas:

- `ContentView.swift`
  - Refine `TaskFirstSidebar`, `SidebarStatusChip`, and `SidebarRow`.
  - Improve detail transition behavior.
  - Introduce the shared status-band entry point if it naturally belongs at the
    main container level.
- `Views/SharedComponents.swift`
  - Add shared styling helpers or small components for status surfaces, animated
    progress treatment, section headers, empty states, warnings, and task rows.
  - Keep helpers simple and SwiftUI-native.
- `Views/UpdatesView.swift`
  - Upgrade scanning view, filter/header area, update row treatment, progress
    feedback, and active/failure states.
- Other `Views/*.swift`
  - Lightly align spacing, surface treatment, and state badges only where needed
    for consistency.

No new persistent data model is required. Any presentational helper should be
derived from existing model state.

## Data Flow

- `StewardModel` remains the single source for scan state, selected tab, update
  counts, running jobs, package progress, and policy state.
- `AutomationProfileStore` continues to control advanced-mode visibility.
- UI-only status summaries derive from existing values such as `isScanning`,
  `scanPhase`, `hasRunningJob`, `allUpgradeablePackages`, `upgradeProgress`, and
  `packageProgress`.
- Tapping existing actions should continue to call the same model methods.
- No scan, upgrade, scheduler, app update, or persistence contract changes are
  part of this design.

## Accessibility

- Preserve visible focus behavior for buttons, pickers, and rows.
- Keep text at native readable sizes and allow wrapping where row content may be
  long.
- Do not rely on color alone for failures, warnings, skipped items, or success
  states; keep icons/text labels.
- Maintain touch/click target comfort even though this is a macOS app.
- Respect reduced motion and avoid constant ambient animation.
- Use system semantic colors and materials so light/dark appearance remains
  legible.

## Error Handling

This upgrade does not add new backend error paths.

- Existing job, package, source, and update failures remain the source of truth.
- Failure states become more visible through row tint, iconography, and concise
  recovery affordances.
- If animation APIs are unavailable on macOS 14, the UI falls back to static
  symbols and regular transitions.
- If counts or phase data are not available before the first scan, the status band
  and sidebar chip should show a neutral ready state.

## Testing

Verification should include:

- `npm test`
- `npm run build`

Focused tests may be added if presenter logic changes. Pure view styling changes
do not require broad model tests, but any new status-summary helper should have
small Swift tests for:

- idle with no updates
- idle with pending updates
- scanning with phase
- running upgrade
- failed package state where exposed by helper logic

Manual QA should check:

- light and dark appearance
- advanced mode on and off
- empty update list
- scanning state
- running upgrade/progress state where feasible
- reduced-motion behavior
- narrow and normal window widths

## Implementation Notes

- Keep UI copy in Chinese and code identifiers in English.
- Prefer local SwiftUI components over new abstractions unless duplication becomes
  meaningful.
- Keep edits closely scoped to visual presentation files.
- Avoid raw hex proliferation in view bodies; use small semantic helpers when a
  color is repeated.
- Do not touch version numbers, release files, generated icons, or unrelated logic.
