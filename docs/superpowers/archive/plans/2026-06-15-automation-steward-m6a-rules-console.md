# Automation Steward M6a Rules Console Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an advanced-mode rules console that makes automation risk, network, and auto-repair policy visible and controllable.

**Architecture:** Keep policy state in the existing `AutomationProfileStore` and `StewardModel`; add a pure `RulesConsolePresenter` so the rule summaries are testable without SwiftUI. Add a SwiftUI `RulesView` for advanced operators and route it through `AppTab`.

**Tech Stack:** Swift, SwiftUI, AppKit target built by `scripts/build-native.sh`, single-file native tests driven by `scripts/test-native.sh`.

---

### Task 1: Add Rules Tab And Presenter Contract

**Files:**
- Modify: `native/MacSoftwareSteward/Models.swift`
- Create: `native/MacSoftwareSteward/RulesConsolePresenter.swift`
- Modify: `tests/AppTabVisibilityTest.swift`
- Create: `tests/RulesConsolePresenterTest.swift`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Write the failing navigation test**

Update `tests/AppTabVisibilityTest.swift` so advanced mode expects `rules` between `sources` and `history`, and so the new tab has no search field:

```swift
precondition(AppTab.visibleTabs(advancedModeEnabled: true) == [
    .inbox,
    .updates,
    .applications,
    .sources,
    .rules,
    .history,
    .jobs,
    .settings
])
precondition(AppTab.rules.symbol == "list.bullet.clipboard")
precondition(AppTab.rules.usesSearch == false)
```

- [ ] **Step 2: Write the failing presenter test**

Create `tests/RulesConsolePresenterTest.swift`:

```swift
import Foundation

@main
struct RulesConsolePresenterTest {
    static func main() {
        var profile = AutomationProfile.manualDefault
        profile.advancedModeEnabled = true
        profile.lowRiskAutoUpgradeEnabled = true
        profile.regularAppNetworkPolicy = .localOnly
        profile.autoRepairPolicy = .allowLowRisk

        let sections = RulesConsolePresenter.sections(profile: profile, includeGreedy: true)
        precondition(sections.map(\.title) == ["自动化策略", "风险规则", "恢复规则"])

        let policyRows = sections[0].rows
        precondition(policyRows.contains { row in
            row.title == "普通 App 联网策略"
                && row.status == "仅本地识别"
                && row.detail.contains("不访问外部页面")
        })
        precondition(policyRows.contains { row in
            row.title == "低风险自动升级" && row.status == "开启"
        })
        precondition(policyRows.contains { row in
            row.title == "包含 greedy cask" && row.status == "开启"
        })

        precondition(sections[1].rows.contains { row in
            row.title == "Cask 自更新保护" && row.status == "需确认"
        })
        precondition(sections[2].rows.contains { row in
            row.title == "自动修复 allowlist"
                && row.status == "仅低风险"
                && row.detail.contains("重新扫描")
        })
    }
}
```

- [ ] **Step 3: Run RED**

Run:

```bash
npm test
```

Expected: build fails because `AppTab.rules` and `RulesConsolePresenter` do not exist yet.

- [ ] **Step 4: Implement minimal navigation and presenter**

In `native/MacSoftwareSteward/Models.swift`, add:

```swift
case rules = "规则"
```

Update advanced visible tabs to:

```swift
return [.inbox, .updates, .applications, .sources, .rules, .history, .jobs, .settings]
```

Update `symbol`:

```swift
case .rules: return "list.bullet.clipboard"
```

Update `usesSearch` false cases:

```swift
case .inbox, .rules, .history, .settings, .jobs:
    return false
```

Create `native/MacSoftwareSteward/RulesConsolePresenter.swift`:

```swift
import Foundation

struct RulesConsoleSection: Hashable {
    var title: String
    var summary: String
    var rows: [RulesConsoleRow]
}

struct RulesConsoleRow: Hashable, Identifiable {
    var id: String { title }
    var title: String
    var detail: String
    var symbol: String
    var status: String
}

enum RulesConsolePresenter {
    static func sections(profile: AutomationProfile, includeGreedy: Bool) -> [RulesConsoleSection] {
        [
            policySection(profile: profile, includeGreedy: includeGreedy),
            riskSection(includeGreedy: includeGreedy),
            recoverySection(profile: profile)
        ]
    }

    private static func policySection(profile: AutomationProfile, includeGreedy: Bool) -> RulesConsoleSection {
        RulesConsoleSection(
            title: "自动化策略",
            summary: "当前生效的扫描、升级与修复开关。",
            rows: [
                RulesConsoleRow(
                    title: "普通 App 联网策略",
                    detail: networkPolicyDetail(profile.regularAppNetworkPolicy),
                    symbol: "network",
                    status: profile.regularAppNetworkPolicy.title
                ),
                RulesConsoleRow(
                    title: "低风险自动升级",
                    detail: "每日巡检只会自动执行已判定为低风险的升级项。",
                    symbol: "bolt.badge.checkmark",
                    status: enabledText(profile.lowRiskAutoUpgradeEnabled)
                ),
                RulesConsoleRow(
                    title: "自动修复",
                    detail: "失败恢复默认进入待处理；开启后只允许白名单内的低风险动作自动执行。",
                    symbol: "wrench.and.screwdriver",
                    status: profile.autoRepairPolicy.title
                ),
                RulesConsoleRow(
                    title: "包含 greedy cask",
                    detail: "开启后会把 auto_updates 或 latest Cask 纳入扫描，升级仍受风险规则约束。",
                    symbol: "shippingbox.and.arrow.backward",
                    status: enabledText(includeGreedy)
                )
            ]
        )
    }

    private static func riskSection(includeGreedy: Bool) -> RulesConsoleSection {
        RulesConsoleSection(
            title: "风险规则",
            summary: "升级计划中始终保留人工确认的边界。",
            rows: [
                RulesConsoleRow(
                    title: "Cask 自更新保护",
                    detail: "auto_updates 或 latest Cask 不直接自动升级，避免覆盖应用自身更新节奏。",
                    symbol: "exclamationmark.shield",
                    status: "需确认"
                ),
                RulesConsoleRow(
                    title: "固定版本保护",
                    detail: "已 pin 的 Formula 或 Cask 默认跳过自动升级。",
                    symbol: "pin",
                    status: "阻止"
                ),
                RulesConsoleRow(
                    title: "greedy 扫描范围",
                    detail: includeGreedy ? "当前会扫描 greedy Cask，但自动执行仍要通过低风险规则。" : "当前不扫描 greedy Cask。",
                    symbol: "slider.horizontal.3",
                    status: includeGreedy ? "扩大" : "标准"
                )
            ]
        )
    }

    private static func recoverySection(profile: AutomationProfile) -> RulesConsoleSection {
        RulesConsoleSection(
            title: "恢复规则",
            summary: "失败恢复动作按风险分层进入自动或待处理路径。",
            rows: [
                RulesConsoleRow(
                    title: "自动修复 allowlist",
                    detail: "当前白名单只允许重新扫描一类低风险恢复动作自动执行。",
                    symbol: "checklist.checked",
                    status: profile.autoRepairPolicy == .allowLowRisk ? "仅低风险" : "关闭"
                ),
                RulesConsoleRow(
                    title: "防循环保护",
                    detail: "自动修复动作只执行一次；失败后继续进入待处理。",
                    symbol: "arrow.triangle.2.circlepath.circle",
                    status: "一次"
                ),
                RulesConsoleRow(
                    title: "人工兜底",
                    detail: "清理、重装、重试等恢复建议会写入待处理，由用户确认。",
                    symbol: "tray.and.arrow.down",
                    status: "待处理"
                )
            ]
        )
    }

    private static func networkPolicyDetail(_ policy: RegularAppNetworkPolicy) -> String {
        switch policy {
        case .declaredSourcesOnly:
            return "只访问应用声明的 Sparkle appcast 和受控更新接口。"
        case .aggressive:
            return "允许访问公开厂商页面来尝试识别普通 App 更新。"
        case .localOnly:
            return "不访问外部页面，只根据本机元数据识别普通 App。"
        }
    }

    private static func enabledText(_ enabled: Bool) -> String {
        enabled ? "开启" : "关闭"
    }
}
```

Add the new test to `scripts/test-native.sh` after `AutomationProfileStoreTest`:

```bash
run_test RulesConsolePresenterTest \
  "$SRC/AutomationProfileStore.swift" \
  "$SRC/RulesConsolePresenter.swift" \
  "$TESTS/RulesConsolePresenterTest.swift"
```

- [ ] **Step 5: Run GREEN**

Run:

```bash
npm test
```

Expected: all native tests pass.

- [ ] **Step 6: Commit Task 1**

```bash
git add native/MacSoftwareSteward/Models.swift native/MacSoftwareSteward/RulesConsolePresenter.swift tests/AppTabVisibilityTest.swift tests/RulesConsolePresenterTest.swift scripts/test-native.sh
git commit -m "feat: add rules console presenter"
```

### Task 2: Add RulesView And Route It

**Files:**
- Create: `native/MacSoftwareSteward/Views/RulesView.swift`
- Modify: `native/MacSoftwareSteward/ContentView.swift`

- [ ] **Step 1: Add the SwiftUI rules view**

Create `native/MacSoftwareSteward/Views/RulesView.swift` with a compact advanced-operator layout:

```swift
import SwiftUI

struct RulesView: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    private var sections: [RulesConsoleSection] {
        RulesConsolePresenter.sections(
            profile: automationProfile.profile,
            includeGreedy: model.includeGreedy
        )
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                policyControls

                ForEach(sections, id: \.title) { section in
                    RulesSectionView(section: section)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var policyControls: some View {
        SettingsGroupBox {
            SettingsGroupHeader(title: "策略控制", symbol: "slider.horizontal.3")
            RulesPickerRow(
                title: "普通 App 联网策略",
                detail: "控制 Sparkle、声明来源与厂商页面检查范围。",
                selection: Binding(
                    get: { automationProfile.profile.regularAppNetworkPolicy },
                    set: { automationProfile.setRegularAppNetworkPolicy($0) }
                ),
                options: RegularAppNetworkPolicy.allCases
            )
            SettingsDivider()
            RulesToggleRow(
                title: "低风险自动升级",
                detail: "每日巡检可自动执行低风险升级项。",
                isOn: Binding(
                    get: { automationProfile.profile.lowRiskAutoUpgradeEnabled },
                    set: { automationProfile.setLowRiskAutoUpgradeEnabled($0) }
                )
            )
            SettingsDivider()
            RulesPickerRow(
                title: "自动修复策略",
                detail: "控制失败后的低风险恢复动作是否可自动执行。",
                selection: Binding(
                    get: { automationProfile.profile.autoRepairPolicy },
                    set: { automationProfile.setAutoRepairPolicy($0) }
                ),
                options: AutoRepairPolicy.allCases
            )
            SettingsDivider()
            RulesToggleRow(
                title: "包含 greedy cask",
                detail: "将 auto_updates 或 latest Cask 纳入扫描。",
                isOn: $model.includeGreedy
            )
        }
    }
}
```

The file should also define `RulesSectionView`, `RulesConsoleRowView`, `RulesPickerRow`, and `RulesToggleRow` in the same style as `SettingsView`: native controls, SF Symbols, short row text, and no nested cards.

- [ ] **Step 2: Route the new tab**

In `native/MacSoftwareSteward/ContentView.swift`, add a switch case:

```swift
case .rules:
    RulesView()
```

- [ ] **Step 3: Build verify**

Run:

```bash
npm run build
```

Expected: App and helper agent build successfully and signing reports `Signature OK`.

- [ ] **Step 4: Restore generated icon churn**

Run:

```bash
git restore native/Resources/AppIcon.iconset/*.png
```

Expected: no AppIcon PNG changes remain.

- [ ] **Step 5: Commit Task 2**

```bash
git add native/MacSoftwareSteward/Views/RulesView.swift native/MacSoftwareSteward/ContentView.swift
git commit -m "feat: add advanced rules view"
```

### Task 3: Final Verification

**Files:**
- Inspect: `git status --short`

- [ ] **Step 1: Run full native tests**

Run:

```bash
npm test
```

Expected: ends with `All native tests passed.`

- [ ] **Step 2: Run full native build**

Run:

```bash
npm run build
```

Expected: app and helper agent build, `Signature OK`.

- [ ] **Step 3: Restore generated icon churn**

Run:

```bash
git restore native/Resources/AppIcon.iconset/*.png
```

Expected: iconset PNGs are clean.

- [ ] **Step 4: Confirm workspace state**

Run:

```bash
git status --short
```

Expected: only the pre-existing untracked `code-risk-scanner/` remains.
