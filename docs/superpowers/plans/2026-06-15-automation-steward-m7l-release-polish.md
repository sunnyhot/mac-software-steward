# Automation Steward M7l Release Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the advanced diagnostics, vendor updater recognition, rules/history polish, import/export completion, and release packaging checks for the current local main branch.

**Architecture:** Keep behavioral logic in pure Foundation presenters/services, then wire SwiftUI views to those models. Preserve the simple default mode while advanced mode exposes diagnostic and control-panel detail. Keep the automation bundle backward compatible with older exports.

**Tech Stack:** Native Swift, SwiftUI/AppKit, standalone Swift tests through `scripts/test-native.sh`, package flow through `scripts/package-release.sh`.

---

## File Structure

- Modify `native/MacSoftwareSteward/AppDiagnosticsPresenter.swift` and `tests/AppDiagnosticsPresenterTest.swift`: add diagnostic categories, action hints, and detail rows for update-source failures and version-unknown apps.
- Modify `native/MacSoftwareSteward/RegularAppUpdateDiscovery.swift` and `tests/RegularAppUpdateDiscoveryTest.swift`: add Chrome Keystone, Adobe, JetBrains, and Microsoft metadata evidence rules.
- Modify `native/MacSoftwareSteward/RulesConsolePresenter.swift`, `native/MacSoftwareSteward/Views/RulesView.swift`, and `tests/RulesConsolePresenterTest.swift`: add rule categories, query/category filtering, and expandable row detail.
- Add `native/MacSoftwareSteward/HistoryPresenter.swift` and `tests/HistoryPresenterTest.swift`; modify `native/MacSoftwareSteward/Views/HistoryView.swift`: add unified history entries, filters, categories, and expandable detail.
- Modify `native/MacSoftwareSteward/AutomationDataBundle.swift`, `native/MacSoftwareSteward/UpgradeHistoryStore.swift`, `native/MacSoftwareSteward/Views/RulesView.swift`, `tests/AutomationDataBundleTest.swift`, `tests/UpgradeHistoryStoreTest.swift`, and `scripts/test-native.sh`: export/import upgrade history with schema compatibility and import preview messaging.
- Modify `package.json`, `native/Info.plist`, `README.md`, `CHANGELOG.md`, and `PROJECT_MAP.md`: bump version and document the release-facing behavior.

## Task 1: Test-First Pure Logic

- [ ] **Step 1: Write failing tests** for app diagnostics detail rows, vendor metadata detection, rules filtering, history filtering, and bundle history export/import.
- [ ] **Step 2: Run `npm test`** and verify failures are due to missing/old behavior.

## Task 2: Implement Pure Helpers

- [ ] **Step 1: Implement app diagnostic detail rows and source/version reason mapping.**
- [ ] **Step 2: Implement vendor metadata detection evidence and summaries.**
- [ ] **Step 3: Implement rules categories/filtering and history presenter.**
- [ ] **Step 4: Implement automation bundle schema v2 with v1 decode compatibility and history replacement.**
- [ ] **Step 5: Run `npm test`** and verify all native tests pass.

## Task 3: Wire UI

- [ ] **Step 1: Expand application diagnostic detail UI with reason, action hint, and key-value detail rows.**
- [ ] **Step 2: Add Rules view search/category filter and expandable rule detail.**
- [ ] **Step 3: Add History view search/kind/status filters and expandable report/history detail.**
- [ ] **Step 4: Improve Rules import/export messages and import confirmation summary.**
- [ ] **Step 5: Run `npm test` and `npm run build`; restore generated AppIcon PNGs.**

## Task 4: Release Closure

- [ ] **Step 1: Bump version to `0.13.20` in `package.json`, `native/Info.plist`, and `PROJECT_MAP.md`.**
- [ ] **Step 2: Update README and CHANGELOG with advanced diagnostics, rules/history filters, bundle import/export, and package workflow notes.**
- [ ] **Step 3: Run `npm test`, `npm run build`, `npm run package`; restore generated AppIcon PNGs and keep `release/` uncommitted.**
- [ ] **Step 4: Commit all source/docs changes to local `main`.**
