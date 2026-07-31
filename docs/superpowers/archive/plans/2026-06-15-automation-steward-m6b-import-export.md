# Automation Steward M6b Import Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add local JSON import/export for the automation profile, upgrade risk policy overrides, and inspection report archive.

**Architecture:** Introduce a schema-versioned `AutomationDataBundle` DTO plus a small codec service that owns JSON date strategy and schema validation. Add explicit replace methods to existing stores so imports use public store APIs, then wire export/import actions into the advanced `RulesView`.

**Tech Stack:** Swift, SwiftUI/AppKit panels, Foundation `Codable`, native single-file tests through `scripts/test-native.sh`, native app build through `scripts/build-native.sh`.

---

### Task 1: Add Schema-Versioned Bundle Logic

**Files:**
- Create: `native/MacSoftwareSteward/AutomationDataBundle.swift`
- Create: `tests/AutomationDataBundleTest.swift`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Write the failing bundle test**

Create `tests/AutomationDataBundleTest.swift`:

```swift
import Foundation

@main
struct AutomationDataBundleTest {
    static func main() throws {
        var profile = AutomationProfile.manualDefault
        profile.onboardingCompleted = true
        profile.advancedModeEnabled = true
        profile.regularAppNetworkPolicy = .localOnly
        profile.autoRepairPolicy = .allowLowRisk

        let report = InspectionReportRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            trigger: .manualRun,
            startedAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 20),
            status: .succeeded,
            scanSummary: InspectionScanSummary(applications: 1, brewFormulae: 2, brewCasks: 3, masApps: 4, outdated: 5, actionable: 6),
            automaticUpgrades: [
                InspectionPackageRecord(packageID: "brew:formula:jq", packageName: "jq", source: "Brew Formula")
            ],
            skippedItems: [],
            failures: [],
            inboxItemIDs: []
        )

        let bundle = AutomationDataBundleService.makeBundle(
            profile: profile,
            upgradePolicyOverrides: ["brew:formula:jq": .askFirst],
            inspectionReports: [report],
            exportedAt: Date(timeIntervalSince1970: 100)
        )

        let encoded = try AutomationDataBundleService.encode(bundle)
        let decoded = try AutomationDataBundleService.decode(encoded)

        precondition(decoded.schemaVersion == 1)
        precondition(decoded.exportedAt == Date(timeIntervalSince1970: 100))
        precondition(decoded.automationProfile.regularAppNetworkPolicy == .localOnly)
        precondition(decoded.upgradePolicyOverrides["brew:formula:jq"] == .askFirst)
        precondition(decoded.inspectionReports.map(\.id) == [report.id])

        let incompatible = AutomationDataBundle(
            schemaVersion: 99,
            exportedAt: Date(timeIntervalSince1970: 100),
            automationProfile: profile,
            upgradePolicyOverrides: [:],
            inspectionReports: []
        )
        let incompatibleData = try AutomationDataBundleService.encode(incompatible)
        do {
            _ = try AutomationDataBundleService.decode(incompatibleData)
            preconditionFailure("Unsupported schema version should fail")
        } catch let error as AutomationDataBundleError {
            precondition(error == .unsupportedSchemaVersion(99))
        }
    }
}
```

Add it to `scripts/test-native.sh` after `AutomationProfileStoreTest`:

```bash
run_test AutomationDataBundleTest \
  "$SRC/Models.swift" \
  "$SRC/AutomationProfileStore.swift" \
  "$SRC/UpgradePolicyStore.swift" \
  "$SRC/InspectionReportStore.swift" \
  "$SRC/AutomationDataBundle.swift" \
  "$TESTS/AutomationDataBundleTest.swift"
```

- [ ] **Step 2: Run RED**

Run:

```bash
npm test
```

Expected: build fails because `AutomationDataBundle.swift` and related types do not exist.

- [ ] **Step 3: Implement the minimal bundle DTO and codec**

Create `native/MacSoftwareSteward/AutomationDataBundle.swift`:

```swift
import Foundation

struct AutomationDataBundle: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var exportedAt: Date
    var automationProfile: AutomationProfile
    var upgradePolicyOverrides: [String: UpgradePolicy]
    var inspectionReports: [InspectionReportRecord]
}

enum AutomationDataBundleError: Error, Equatable, LocalizedError {
    case unsupportedSchemaVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "不支持的导入文件版本：\(version)"
        }
    }
}

enum AutomationDataBundleService {
    static func makeBundle(
        profile: AutomationProfile,
        upgradePolicyOverrides: [String: UpgradePolicy],
        inspectionReports: [InspectionReportRecord],
        exportedAt: Date = Date()
    ) -> AutomationDataBundle {
        AutomationDataBundle(
            schemaVersion: AutomationDataBundle.currentSchemaVersion,
            exportedAt: exportedAt,
            automationProfile: profile,
            upgradePolicyOverrides: upgradePolicyOverrides,
            inspectionReports: inspectionReports
        )
    }

    static func encode(_ bundle: AutomationDataBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(bundle)
    }

    static func decode(_ data: Data) throws -> AutomationDataBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(AutomationDataBundle.self, from: data)
        guard bundle.schemaVersion == AutomationDataBundle.currentSchemaVersion else {
            throw AutomationDataBundleError.unsupportedSchemaVersion(bundle.schemaVersion)
        }
        return bundle
    }
}
```

- [ ] **Step 4: Run GREEN**

Run:

```bash
npm test
```

Expected: all native tests pass.

- [ ] **Step 5: Commit Task 1**

```bash
git add native/MacSoftwareSteward/AutomationDataBundle.swift tests/AutomationDataBundleTest.swift scripts/test-native.sh
git commit -m "feat: add automation data bundle"
```

### Task 2: Add Import Apply APIs To Stores

**Files:**
- Modify: `native/MacSoftwareSteward/AutomationProfileStore.swift`
- Modify: `native/MacSoftwareSteward/UpgradePolicyStore.swift`
- Modify: `native/MacSoftwareSteward/InspectionReportStore.swift`
- Modify: `tests/AutomationProfileStoreTest.swift`
- Modify: `tests/UpgradePolicyStoreTest.swift`
- Modify: `tests/InspectionReportStoreTest.swift`

- [ ] **Step 1: Write failing store apply tests**

Add this to `tests/AutomationProfileStoreTest.swift` before the final `setAutomationEnabled(false)` assertions:

```swift
var importedProfile = AutomationProfile.manualDefault
importedProfile.onboardingCompleted = true
importedProfile.advancedModeEnabled = true
importedProfile.notificationPolicy = .silent
importedProfile.regularAppNetworkPolicy = .aggressive
importedProfile.autoRepairPolicy = .allowLowRisk
reloaded.replace(with: importedProfile)

let importedReloaded = AutomationProfileStore(fileURL: url)
precondition(importedReloaded.profile == importedProfile)
```

Add this to `tests/UpgradePolicyStoreTest.swift` after the existing persistence assertions:

```swift
store.replaceOverrides([
    "brew:cask:arc": .askFirst,
    "mas:123": .remindOnly
])
precondition(store.policyOverride(forPackageID: formula.id) == nil)
precondition(store.policyOverride(forPackageID: "brew:cask:arc") == .askFirst)

let importedPolicies = UpgradePolicyStore(fileURL: tempURL)
precondition(importedPolicies.policyOverride(forPackageID: "mas:123") == .remindOnly)
```

Add this to `tests/InspectionReportStoreTest.swift` after `reloaded.clear()`:

```swift
let replacementStore = InspectionReportStore(fileURL: url, limit: 1)
replacementStore.replaceReports([first, second])
precondition(replacementStore.reports.map(\.id) == [second.id])

let replacementReloaded = InspectionReportStore(fileURL: url, limit: 5)
precondition(replacementReloaded.reports.map(\.id) == [second.id])
```

- [ ] **Step 2: Run RED**

Run:

```bash
npm test
```

Expected: build fails because `replace(with:)`, `replaceOverrides(_:)`, and `replaceReports(_:)` do not exist.

- [ ] **Step 3: Implement store apply APIs**

In `AutomationProfileStore`, add:

```swift
func replace(with newProfile: AutomationProfile) {
    profile = newProfile
    save()
}
```

In `UpgradePolicyStore`, add:

```swift
func replaceOverrides(_ newOverrides: [String: UpgradePolicy]) {
    overrides = newOverrides
    save()
}
```

In `InspectionReportStore`, add:

```swift
func replaceReports(_ newReports: [InspectionReportRecord]) {
    reports = newReports
    trimToLimit()
    save()
}
```

- [ ] **Step 4: Run GREEN**

Run:

```bash
npm test
```

Expected: all native tests pass.

- [ ] **Step 5: Commit Task 2**

```bash
git add native/MacSoftwareSteward/AutomationProfileStore.swift native/MacSoftwareSteward/UpgradePolicyStore.swift native/MacSoftwareSteward/InspectionReportStore.swift tests/AutomationProfileStoreTest.swift tests/UpgradePolicyStoreTest.swift tests/InspectionReportStoreTest.swift
git commit -m "feat: apply imported automation stores"
```

### Task 3: Wire Import Export Into RulesView

**Files:**
- Modify: `native/MacSoftwareSteward/Views/RulesView.swift`

- [ ] **Step 1: Add export/import controls**

Update `RulesView.swift` to import `AppKit` and `UniformTypeIdentifiers`, add a `RulesTransferMessage` state, render a `SettingsGroupBox` titled `导入导出`, and provide two buttons:

```swift
Button {
    exportAutomationData()
} label: {
    Label("导出", systemImage: "square.and.arrow.up")
}

Button {
    importAutomationData()
} label: {
    Label("导入", systemImage: "square.and.arrow.down")
}
```

The export action must create a bundle from:

```swift
AutomationDataBundleService.makeBundle(
    profile: automationProfile.profile,
    upgradePolicyOverrides: model.policyStore.overrides,
    inspectionReports: model.inspectionReportStore.reports
)
```

The import action must decode the selected JSON and call:

```swift
automationProfile.replace(with: bundle.automationProfile)
model.policyStore.replaceOverrides(bundle.upgradePolicyOverrides)
model.inspectionReportStore.replaceReports(bundle.inspectionReports)
```

Use `NSSavePanel` and `NSOpenPanel` with `allowedContentTypes = [.json]`. Before applying an import, show an `NSAlert` with `导入` and `取消` buttons because import replaces local profile, policy overrides, and reports.

- [ ] **Step 2: Build verify**

Run:

```bash
npm run build
```

Expected: app and agent build successfully, then signing reports `Signature OK`.

- [ ] **Step 3: Restore generated icon churn**

Run:

```bash
git restore native/Resources/AppIcon.iconset/*.png
```

Expected: AppIcon PNG changes are gone.

- [ ] **Step 4: Commit Task 3**

```bash
git add native/MacSoftwareSteward/Views/RulesView.swift
git commit -m "feat: add rules import export controls"
```

### Task 4: Final Verification

**Files:**
- Inspect: `git status --short`

- [ ] **Step 1: Run native tests**

Run:

```bash
npm test
```

Expected: ends with `All native tests passed.`

- [ ] **Step 2: Run native build**

Run:

```bash
npm run build
```

Expected: app and helper agent build, and signature verification reports `Signature OK`.

- [ ] **Step 3: Restore generated icon churn**

Run:

```bash
git restore native/Resources/AppIcon.iconset/*.png
```

- [ ] **Step 4: Confirm status**

Run:

```bash
git status --short
```

Expected: only pre-existing `?? code-risk-scanner/` remains.
