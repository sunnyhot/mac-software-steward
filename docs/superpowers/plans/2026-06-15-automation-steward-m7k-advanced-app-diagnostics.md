# Automation Steward M7k Advanced App Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let advanced-mode users inspect regular app update diagnostics directly in the Applications view, including detector, state, summary, feed URL, and parser/check diagnostics.

**Architecture:** Add a pure `AppDiagnosticsPresenter` that converts `AppItem` update metadata into stable display rows. `ApplicationsView` reads the existing `AutomationProfileStore` and only renders diagnostic details when advanced mode is enabled.

**Tech Stack:** Native Swift, SwiftUI, standalone Swift tests through `scripts/test-native.sh`, app build through `scripts/build-native.sh`.

---

## File Structure

- Add `native/MacSoftwareSteward/AppDiagnosticsPresenter.swift`: pure display model for app update diagnostics.
- Add `tests/AppDiagnosticsPresenterTest.swift`: presenter coverage for Sparkle diagnostics, vendor fallback, and quiet apps.
- Modify `scripts/test-native.sh`: include the new standalone test.
- Modify `native/MacSoftwareSteward/Views/ApplicationsView.swift`: show diagnostic detail rows in advanced mode only.

## Task 1: Pure App Diagnostics Presenter

**Files:**
- Add: `tests/AppDiagnosticsPresenterTest.swift`
- Modify: `scripts/test-native.sh`
- Add: `native/MacSoftwareSteward/AppDiagnosticsPresenter.swift`

- [ ] **Step 1: Write the failing test**

Add a standalone test that verifies:

- Sparkle appcast diagnostics keep detector, state, summary, diagnostic, feed URL, and warning severity when an update is available.
- Vendor updater rows still render a useful fallback diagnostic when the diagnostic string is blank.
- Plain apps without update signals do not create diagnostic rows.

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
npm test
```

Expected: `AppDiagnosticsPresenterTest` fails to compile because `AppDiagnosticsPresenter` does not exist.

- [ ] **Step 3: Implement presenter**

Implement a small pure presenter that:

- Produces rows for apps with an update detector, app diagnostics, appcast feed URL, actionable manual update state, or outdated state.
- Keeps empty fields user-readable with fallback text.
- Maps `outdated` to warning, `checkable` to info, and unresolved unknown/manual states to info.

- [ ] **Step 4: Run native tests**

Run:

```bash
npm test
```

Expected: all native tests pass.

## Task 2: Advanced Applications View Diagnostics

**Files:**
- Modify: `native/MacSoftwareSteward/Views/ApplicationsView.swift`

- [ ] **Step 1: Wire advanced mode into applications view**

Read `AutomationProfileStore` in `ApplicationRow` and render `AppDiagnosticDetail` only when `advancedModeEnabled` is true and the presenter returns a row.

- [ ] **Step 2: Keep default mode unchanged**

The existing compact update capability line remains for manual actions; the new diagnostic detail is additive and hidden by default.

- [ ] **Step 3: Verify**

Run:

```bash
npm test
npm run build
git restore native/Resources/AppIcon.iconset/*.png
git status --short
```

Expected: tests and build pass; generated icon churn is restored.

- [ ] **Step 4: Commit**

Commit the plan, presenter, test, script, and UI changes.
