# Unified Window Chrome Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the macOS window chrome, sidebar, and detail header read as one continuous top surface.

**Architecture:** Preserve `NavigationSplitView` and add visual continuity at the container level. Use SwiftUI toolbar background APIs plus a non-interactive background rail and spacing adjustments in `ContentView.swift`.

**Tech Stack:** SwiftUI + AppKit, macOS 14.0+, existing npm build/test scripts.

## Global Constraints

- Keep UI copy in Chinese and code identifiers in English.
- Do not add package dependencies.
- Keep `NavigationSplitView` as the top-level navigation structure.
- Do not change scan, upgrade, persistence, or automation behavior.
- Use semantic system colors and existing surface helpers.

---

### Task 1: Add Unified Top Rail

**Files:**
- Modify: `native/MacSoftwareSteward/ContentView.swift`

**Interfaces:**
- Consumes: existing `StewardCanvasBackground`, `TaskFirstSidebar`, and `HeaderView`.
- Produces: a private `UnifiedTopRail` SwiftUI view used behind the detail content by `ContentView`.

- [ ] **Step 1: Add detail background**

Replace the detail canvas background with a chrome-aware background:

```swift
.background(DetailChromeBackground())
.toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
.toolbarBackground(.visible, for: .windowToolbar)
```

- [ ] **Step 2: Define the rail view**

Add this private view near the other container-level views:

```swift
private enum AppChromeMetrics {
    static let topRailHeight: CGFloat = 82
}

private struct DetailChromeBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            StewardCanvasBackground()
                .ignoresSafeArea()
            UnifiedTopRail()
                .allowsHitTesting(false)
        }
    }
}

private struct UnifiedTopRail: View {
    var body: some View {
        VStack(spacing: 0) {
            Color(nsColor: .windowBackgroundColor)
                .frame(height: AppChromeMetrics.topRailHeight)
            Divider().opacity(0.35)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }
}
```

- [ ] **Step 3: Verify build**

Run: `npm run build`

Expected: build succeeds and `build/MacSoftwareSteward.app` is produced.

### Task 2: Align Sidebar and Header Spacing

**Files:**
- Modify: `native/MacSoftwareSteward/ContentView.swift`

**Interfaces:**
- Consumes: existing `TaskFirstSidebar` and `HeaderView`.
- Produces: adjusted top padding values that align the sidebar content and detail header with the new top rail.

- [ ] **Step 1: Adjust sidebar spacing**

Change the sidebar top padding from `54` to `58` so the first sidebar content clears the unified rail with a small breathing gap:

```swift
.padding(.top, 58)
```

- [ ] **Step 2: Keep detail header rhythm**

Keep `HeaderView` using its current horizontal and bottom spacing, and increase only the top padding if visual QA shows the title row crowds the rail:

```swift
.padding(.top, 18)
```

The current value is acceptable unless the final screenshot shows overlap.

- [ ] **Step 3: Verify tests and build**

Run:

```bash
npm test
npm run build
```

Expected: all tests pass and the app builds.

## Self-Review

- The plan covers the approved continuous top rail direction.
- It does not introduce a full custom split layout.
- It avoids data-model, scanner, upgrade, and persistence changes.
- It contains exact files and verification commands.
