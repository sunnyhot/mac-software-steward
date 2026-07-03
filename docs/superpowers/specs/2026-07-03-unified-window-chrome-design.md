# Unified Window Chrome Design

## Context

The current macOS window reads as visually split around the top-left traffic-light
area. The sidebar owns a gray titlebar-height block, while the detail column starts
with a separate white header surface. The result makes the window chrome, sidebar,
and page header feel assembled from different layers.

## Goal

Make the top-left traffic-light area, sidebar, and detail header feel like one
continuous native macOS control surface without changing scan, upgrade, routing, or
settings behavior.

## Chosen Direction

Use a continuous top rail:

- Keep `NavigationSplitView` and the current task-first sidebar.
- Give the macOS window toolbar an explicit system window background.
- Add a non-interactive top rail across the content layer to visually bridge the
  sidebar and detail column below the toolbar.
- Align sidebar and detail header spacing to the same vertical rhythm.
- Keep the app's existing quiet maintenance-console styling: system colors, modest
  radius, light separators, and state-driven accent color only where it already
  conveys work status.

## Alternatives Considered

- Minimal patch: only shorten or recolor the left gray block. This would reduce the
  obvious mismatch but keep the sidebar and detail header as separate layers.
- Full custom split layout: replace `NavigationSplitView` with a hand-built
  `HStack`. This gives maximum visual control but risks losing native split-view
  behavior for a cosmetic fix.

The continuous top rail is the smallest change that fixes the perceived split
while preserving native behavior.

## Non-Goals

- Do not redesign the scanner, upgrade planner, or navigation model.
- Do not add new dependencies or image assets.
- Do not replace `NavigationSplitView`.
- Do not change visible Chinese copy except spacing-related presentation.

## Verification

- `npm test`
- `npm run build`

