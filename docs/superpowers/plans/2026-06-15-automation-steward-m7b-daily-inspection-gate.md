# Automation Steward M7b Daily Inspection Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent users who have not enabled Automation Steward from accidentally enabling daily inspection automation.

**Architecture:** Add a pure presenter that maps `AutomationProfile` to the daily inspection toggle's enabled state and explanatory copy. Wire the settings row through that presenter so enabling is blocked until onboarding is completed and automation is on, while disabling an already-installed LaunchAgent remains possible. Keep the behavior testable without SwiftUI or LaunchAgent side effects.

**Tech Stack:** Swift, SwiftUI, standalone `swiftc` tests via `scripts/test-native.sh`.

---

### Task 1: Daily Inspection Gate Presenter

**Files:**
- Create: `native/MacSoftwareSteward/AutomationMaintenanceAccess.swift`
- Create: `tests/AutomationMaintenanceAccessTest.swift`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/AutomationMaintenanceAccessTest.swift`:

```swift
import Foundation

@main
struct AutomationMaintenanceAccessTest {
    static func main() {
        let defaultAccess = AutomationMaintenanceAccessPresenter.dailyInspectionAccess(for: .manualDefault)
        precondition(defaultAccess.canEnable == false)
        precondition(defaultAccess.caption == "先开启自动化管家后再启用每日巡检")
        precondition(defaultAccess.disabledReason == "自动化引导未完成")

        var manualProfile = AutomationProfile.manualDefault
        manualProfile.onboardingCompleted = true
        manualProfile.automationEnabled = false

        let manualAccess = AutomationMaintenanceAccessPresenter.dailyInspectionAccess(for: manualProfile)
        precondition(manualAccess.canEnable == false)
        precondition(manualAccess.caption == "自动化管家关闭时不会启用每日巡检")
        precondition(manualAccess.disabledReason == "自动化管家已关闭")

        var enabledProfile = manualProfile
        enabledProfile.automationEnabled = true
        enabledProfile.dailyInspectionEnabled = true

        let enabledAccess = AutomationMaintenanceAccessPresenter.dailyInspectionAccess(for: enabledProfile)
        precondition(enabledAccess.canEnable == true)
        precondition(enabledAccess.caption == "定时扫描可管理来源，发现可升级项后自动执行低风险升级")
        precondition(enabledAccess.disabledReason == nil)
    }
}
```

Add the test to `scripts/test-native.sh` after `AutomationProfileStoreTest`:

```bash
run_test AutomationMaintenanceAccessTest \
  "$SRC/AutomationProfileStore.swift" \
  "$SRC/AutomationMaintenanceAccess.swift" \
  "$TESTS/AutomationMaintenanceAccessTest.swift"
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```bash
npm test
```

Expected: FAIL while building `AutomationMaintenanceAccessTest` because `AutomationMaintenanceAccess.swift` does not exist or `AutomationMaintenanceAccessPresenter` is not in scope.

- [ ] **Step 3: Implement the presenter**

Create `native/MacSoftwareSteward/AutomationMaintenanceAccess.swift`:

```swift
import Foundation

struct AutomationMaintenanceAccess: Equatable {
    var canEnable: Bool
    var caption: String
    var disabledReason: String?
}

enum AutomationMaintenanceAccessPresenter {
    static func dailyInspectionAccess(for profile: AutomationProfile) -> AutomationMaintenanceAccess {
        guard profile.onboardingCompleted else {
            return AutomationMaintenanceAccess(
                canEnable: false,
                caption: "先开启自动化管家后再启用每日巡检",
                disabledReason: "自动化引导未完成"
            )
        }

        guard profile.automationEnabled else {
            return AutomationMaintenanceAccess(
                canEnable: false,
                caption: "自动化管家关闭时不会启用每日巡检",
                disabledReason: "自动化管家已关闭"
            )
        }

        return AutomationMaintenanceAccess(
            canEnable: true,
            caption: "定时扫描可管理来源，发现可升级项后自动执行低风险升级",
            disabledReason: nil
        )
    }
}
```

- [ ] **Step 4: Run the focused test to verify it passes**

Run:

```bash
npm test
```

Expected: PASS for `AutomationMaintenanceAccessTest` and all existing native tests.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/plans/2026-06-15-automation-steward-m7b-daily-inspection-gate.md native/MacSoftwareSteward/AutomationMaintenanceAccess.swift tests/AutomationMaintenanceAccessTest.swift scripts/test-native.sh
git commit -m "feat: add daily inspection automation gate"
```

### Task 2: Settings Wiring

**Files:**
- Modify: `native/MacSoftwareSteward/Views/SettingsView.swift`

- [ ] **Step 1: Wire the settings row to the presenter**

Update `DailyInspectionToggleRow` to read `AutomationProfileStore`, display the presenter copy, block enabling when unavailable, keep disabling available, and persist the profile daily-inspection preference:

```swift
struct DailyInspectionToggleRow: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    private var access: AutomationMaintenanceAccess {
        AutomationMaintenanceAccessPresenter.dailyInspectionAccess(for: automationProfile.profile)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("启用每日巡检")
                    .font(.body)
                Text(access.caption)
                    .font(.caption)
                    .foregroundStyle(access.canEnable || model.dailyInspectionEnabled ? .secondary : .orange)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { model.dailyInspectionEnabled },
                set: { enabled in
                    Task {
                        if enabled {
                            guard access.canEnable else { return }
                            automationProfile.setDailyInspectionEnabled(true)
                            await model.enableDailyInspection()
                        } else {
                            automationProfile.setDailyInspectionEnabled(false)
                            await model.disableDailyInspection()
                        }
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(!access.canEnable && !model.dailyInspectionEnabled)
            .help(access.disabledReason ?? access.caption)
        }
    }
}
```

- [ ] **Step 2: Build to verify SwiftUI wiring**

Run:

```bash
npm run build
git restore native/Resources/AppIcon.iconset/*.png
```

Expected: build exits 0 and signature verification prints `Signature OK`; AppIcon generated PNG changes are restored.

- [ ] **Step 3: Run full native tests**

Run:

```bash
npm test
```

Expected: all native tests pass.

- [ ] **Step 4: Commit**

```bash
git add native/MacSoftwareSteward/Views/SettingsView.swift
git commit -m "feat: gate daily inspection settings"
```

### Self-Review

- Spec coverage: This implements the documented acceptance point that users who have not completed onboarding cannot accidentally enable automatic automation. It also handles the disabled-automation state after onboarding.
- Placeholder scan: No placeholders or TODOs remain.
- Type consistency: `AutomationMaintenanceAccess`, `AutomationMaintenanceAccessPresenter.dailyInspectionAccess(for:)`, and `AutomationProfile` names match the planned test and UI usage.
