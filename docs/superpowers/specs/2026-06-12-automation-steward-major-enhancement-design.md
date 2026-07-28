# Automation Steward Major Enhancement Design

## Context

Mac 软件管家当前是纯本机运行的 SwiftUI macOS 应用，已经覆盖本机 `.app` 扫描、Homebrew formula/cask 扫描与升级、Mac App Store 扫描与升级、每日巡检、自更新、任务日志和基础设置。

本次大版本功能增强的产品定位是：默认成为少打扰的自动化管家，同时提供可开启的高级模式和详细控制面板。默认模式帮助个人 Mac 用户自动完成低风险维护；高级模式服务开发者和重度用户，提供风险原因、规则、诊断、日志和恢复动作。

用户明确选择的方向：

- 默认是自动化管家，但提供高级模式和详细控制面板。
- Homebrew 和 App Store 可按策略自动升级；普通 `.app` 深入识别更新能力，但不静默替换。
- 默认只在需要用户决策或失败时通知；成功动作沉淀到控制面板和历史。
- 高级模式通过全局开关露出。
- 首次使用时通过引导开启自动化，用户明确同意后才启用每日巡检和自动升级。
- 自动升级遵循低风险自动、高风险待确认的边界。
- 普通 `.app` 更新发现覆盖 Sparkle、Chrome、Adobe、JetBrains、Microsoft 等常见更新器。
- 联网检查默认只访问应用声明的更新源和受控厂商接口，高级模式可配置更积极或更保守的策略。
- 控制面板默认使用待处理收件箱，高级模式可切换来源、风险、历史和规则视图。
- 失败恢复默认给可执行动作，高级模式允许部分低风险自动修复。
- 先服务个人 Mac 日常维护和开发者/重度用户，小团队多机能力仅预留导入导出边界。
- 继续坚持纯本机运行，不引入账号、云同步或远程服务。

## Goals

- 将应用首屏从单纯的可升级列表升级为待处理收件箱和自动化摘要。
- 通过首次引导让用户明确启用自动化管家能力。
- 为升级项生成结构化风险评估，决定低风险自动执行或高风险待确认。
- 让每日巡检生成可追溯的本机报告，而不是只触发命令。
- 为普通 `.app` 增加更新能力识别和可操作入口。
- 将失败原因、恢复建议和恢复动作结构化。
- 通过高级模式暴露控制台能力，同时保持默认模式简单。
- 保持纯本机数据存储，并为未来导入导出策略和报告预留格式边界。

## Non-Goals

- 不引入云账号、云同步、远程设备管理或服务端 API。
- 不对普通 `.app` 做静默替换安装。
- 不在默认模式下展示完整命令日志、规则引擎或诊断细节。
- 不一次性实现所有厂商更新器的完整自动检查；厂商规则可以分阶段扩展。
- 不把项目迁移到 Xcode 工程或 Swift Package。
- 不改变自更新分发模式、签名策略或 GitHub Release 机制。

## Users

### Personal Mac User

作为个人 Mac 用户，我想让应用自动处理低风险升级，以便减少维护负担。

### Developer And Power User

作为开发者或重度用户，我想查看升级风险、规则、日志和恢复动作，以便避免自动化影响开发环境。

### Future Multi-Mac User

作为未来可能管理多台 Mac 的用户，我想导出策略和报告，以便在多台设备之间复用本机配置。本次设计只预留导入导出，不实现集中管理。

## Requirements

### Automation Onboarding

**用户故事：** 作为个人 Mac 用户，我想在首次使用时理解自动化范围并明确同意开启，以便应用不会在我不知情时自动升级。

**验收标准：**

1. WHEN 用户首次进入大版本 AND 尚未完成自动化引导 THEN 系统 SHALL 显示本机隐私、自动化范围、风险边界和通知策略。
2. WHEN 用户同意开启自动化管家 THEN 系统 SHALL 记录引导完成状态并允许每日巡检和低风险自动升级。
3. WHEN 用户跳过引导 THEN 系统 SHALL 保持手动模式，并在设置页显示开启自动化管家的入口。
4. IF 自动化引导未完成 THEN 系统 SHALL NOT 启用每日自动升级。

Priority: 高
Complexity: 中
Dependencies: `DailyInspectionScheduler`、设置持久化、通知能力

### Advanced Mode

**用户故事：** 作为重度用户，我想通过全局开关打开高级模式，以便查看风险原因、规则、诊断和日志。

**验收标准：**

1. WHEN 高级模式关闭 THEN 系统 SHALL 只显示默认首页、本机应用、历史和设置中的基础内容。
2. WHEN 高级模式开启 THEN 系统 SHALL 显示可升级控制台、管理来源、规则、任务日志和详细诊断入口。
3. WHERE 默认首页展示待处理事项 THEN 系统 SHALL 保持高级信息折叠，除非用户开启高级模式。
4. WHEN 用户切换高级模式 THEN 系统 SHALL 持久化该偏好并立即更新导航结构。

Priority: 高
Complexity: 中
Dependencies: `ContentView` 导航、设置持久化

### Risk-Based Upgrade Automation

**用户故事：** 作为个人 Mac 用户，我想让系统只自动执行低风险升级，以便享受自动化又避免重大变更。

**验收标准：**

1. WHEN 扫描发现可升级项 THEN 系统 SHALL 为每个升级项生成 `RiskAssessment`。
2. WHEN 升级项被评估为低风险 AND 自动化管家已开启 THEN 系统 SHALL 允许每日巡检自动执行该升级。
3. WHEN 升级项被评估为高风险 THEN 系统 SHALL 将其写入待处理收件箱并等待用户确认。
4. WHEN 用户手动打开一键升级计划 THEN 系统 SHALL 默认选中低风险项，并标记高风险项的原因。
5. IF 升级项需要 `sudo`、运行中应用退出、清理冲突、major 版本、固定版本、依赖异常或开发工具链风险 THEN 系统 SHALL NOT 自动执行该升级。

> **澄清（2026-07-28 sudo cask auto-elevation 设计补充）：** 本规则的「sudo」指**升级项本身在风险评估阶段需要提权**。对已通过风险评估、被批准执行的升级，若执行阶段因 macOS 密码策略卡住，允许通过 `osascript with administrator privileges` 弹原生密码框提权——这是执行方式，不改变风险评估结论。详见 `docs/superpowers/specs/2026-07-28-sudo-cask-auto-elevation-design.md`。

Priority: 高
Complexity: 高
Dependencies: `UpgradePlanner`、`UpgradePolicyStore`、`UpgradeFailureAnalyzer`、Homebrew/mas 扫描结果

### Inbox And Automation Summary

**用户故事：** 作为普通用户，我想只看到真正需要我处理的事项，以便不用理解所有扫描和升级细节。

**验收标准：**

1. WHEN 有高风险升级、普通 App 可更新、失败任务、来源异常或权限问题 THEN 系统 SHALL 创建 `InboxItem`。
2. WHEN 自动升级成功 THEN 系统 SHALL 记录到巡检报告和历史，而不主动通知用户。
3. WHEN 新增待决策或失败事项 THEN 系统 SHALL 通知用户并在首页收件箱展示。
4. WHEN 收件箱事项被用户处理或忽略 THEN 系统 SHALL 更新其状态并记录处理历史。
5. WHERE 高级模式开启 THEN 系统 SHALL 允许按来源、风险、历史和规则维度查看同一批事项。

Priority: 高
Complexity: 高
Dependencies: 通知、持久化、`JobsView`、`SourcesView`、`UpdatesView`

### Daily Inspection Reports

**用户故事：** 作为用户，我想查看每日巡检做了什么，以便信任自动化行为并能追溯问题。

**验收标准：**

1. WHEN 每日巡检开始 THEN 系统 SHALL 创建一份 `InspectionReport` 草稿。
2. WHEN 巡检结束 THEN 系统 SHALL 记录扫描摘要、自动升级项、跳过项、失败项和待处理事项。
3. WHEN 巡检遇到网络失败且没有用户必须处理的事项 THEN 系统 SHALL 只记录报告而不通知用户。
4. WHEN 主应用打开历史页 THEN 系统 SHALL 展示最近巡检报告和升级记录。
5. IF 后台 Agent 路径失效 THEN 系统 SHALL 创建自动化异常事项，并提示重新启用每日巡检。

Priority: 中
Complexity: 中
Dependencies: `DailyInspectionScheduler`、Agent、历史持久化

### Regular App Update Discovery

**用户故事：** 作为用户，我想知道普通 `.app` 是否有可用更新，以便不只依赖 Homebrew 和 App Store。

**验收标准：**

1. WHEN 扫描普通 `.app` THEN 系统 SHALL 尝试识别 Sparkle、Chrome、Adobe、JetBrains、Microsoft 和未知内置更新器。
2. WHEN 系统识别到 Sparkle feed THEN 系统 SHALL 在默认联网策略允许时检查可用版本。
3. WHEN 系统识别到受控厂商更新器 THEN 系统 SHALL 使用本机规则或受控接口判断更新状态。
4. WHEN 普通 `.app` 发现可更新 THEN 系统 SHALL 创建待处理事项，并提供打开应用、打开更新器、打开官网或在 Finder 中定位的动作。
5. WHEN 普通 `.app` 需要更新 THEN 系统 SHALL NOT 静默替换该应用。
6. IF 更新源异常或无法确认版本 THEN 系统 SHALL 标记为无法确认，并在高级模式中展示诊断细节。

Priority: 高
Complexity: 高
Dependencies: `Scanner`、应用 `Info.plist` 解析、联网策略、厂商规则 fixtures

### Network Policy

**用户故事：** 作为重视隐私的用户，我想控制普通 App 更新检查的联网深度，以便应用保持纯本机、少上传。

**验收标准：**

1. WHEN 默认联网策略启用 THEN 系统 SHALL 只访问应用声明的更新源和受控厂商接口。
2. WHEN 高级用户选择更积极策略 THEN 系统 SHALL 允许访问厂商官网或 release 页面补充版本信息。
3. WHEN 高级用户选择仅本地识别 THEN 系统 SHALL NOT 主动联网检查普通 `.app` 更新。
4. WHERE 任意联网检查执行 THEN 系统 SHALL NOT 上传完整本机应用清单。
5. WHEN 联网检查失败 THEN 系统 SHALL 记录诊断，不因单个普通 App 失败中断整体扫描。

Priority: 中
Complexity: 中
Dependencies: 设置持久化、网络客户端、普通 App 更新发现

### Failure Recovery And Auto Repair

**用户故事：** 作为用户，我想在失败后看到可执行恢复动作，以便不用从日志里猜下一步。

**验收标准：**

1. WHEN 升级或巡检失败 THEN 系统 SHALL 生成结构化失败原因、影响说明和恢复动作。
2. WHEN 恢复动作属于低风险类别 AND 高级模式允许自动修复 THEN 系统 SHALL 允许在后台自动执行该动作。
3. WHEN 恢复动作可能改变系统状态较大 THEN 系统 SHALL 等待用户确认。
4. WHEN 自动修复失败 THEN 系统 SHALL 降级为手动恢复事项，并避免循环自动重试。
5. WHERE 恢复动作执行 THEN 系统 SHALL 写入任务日志和历史记录。

Priority: 高
Complexity: 高
Dependencies: `UpgradeFailureAnalyzer`、`CommandRunner`、任务日志、历史持久化

### Local-Only Data

**用户故事：** 作为用户，我想让所有报告、策略和历史保存在本机，以便维护隐私和可控性。

**验收标准：**

1. WHERE 自动化策略、历史报告、风险结果和收件箱数据存储 THEN 系统 SHALL 仅写入本机应用支持目录或用户默认配置。
2. WHEN 用户导出策略或报告 THEN 系统 SHALL 生成本机文件，不上传到远程服务。
3. IF 未来支持多机使用 THEN 系统 SHALL 通过导入导出文件扩展，而不是依赖云服务。

Priority: 中
Complexity: 中
Dependencies: 存储目录规范、JSON 编码模型

## Proposed Architecture

### Product Layers

```text
Default Mode
  InboxView
    - pending decisions
    - failures requiring action
    - regular app update actions
    - automation summary
  ApplicationsView
    - installed apps
    - source relation
    - update capability summary
  HistoryView
    - inspection reports
    - upgrade records
    - recovery records
  SettingsView
    - automation profile
    - notification policy
    - privacy and app update settings

Advanced Mode
  UpdatesView
    - full upgrade plan
    - risk reasons
  SourcesView
    - Homebrew, mas, regular app updater diagnostics
  RulesView
    - risk rules
    - network policy
    - auto repair allowlist
  JobsView
    - command output
    - recovery logs
```

### Domain Modules

`AutomationProfileStore` owns onboarding completion, advanced mode, daily inspection preference, low-risk auto-upgrade preference, notification policy, network policy and auto-repair allowlist.

`RiskAssessor` turns `UpdatablePackage` plus source diagnostics into `RiskAssessment`. It should be pure and testable, with no direct process execution.

`InboxStore` persists `InboxItem` records and updates lifecycle states such as pending, acknowledged, resolved and ignored.

`InspectionReportStore` records daily inspection summaries and manual maintenance sessions.

`RegularAppUpdateDiscovery` inspects `.app` bundles and returns `AppUpdateCapability` plus optional available update metadata.

`RecoveryActionPlanner` maps failures and diagnostics to structured `RecoveryAction` values. It builds on the existing `UpgradeFailureAnalyzer` instead of replacing it wholesale.

`AutomationCoordinator` connects reports, risk assessments, inbox generation, notifications and optional auto repair. It should remain separate from view code.

### Interaction With Existing Code

- `StewardModel` remains the main view model in the near term, but it should delegate new logic to focused helpers instead of growing further.
- `Scanner` should add ordinary app update capability discovery through a separate helper, keeping source scanning readable.
- `UpgradePlanner` should accept risk assessments or call `RiskAssessor` before producing the plan.
- `DailyInspectionScheduler` and `MacSoftwareStewardAgent` should write inspection reports and inbox items, not only command logs.
- `ContentView` should choose navigation items based on `AutomationProfile.advancedModeEnabled`.
- Existing `UpdatesView`, `SourcesView` and `JobsView` become advanced control surfaces.

## Data Model Sketch

```swift
struct AutomationProfile: Codable, Equatable {
    var onboardingCompleted: Bool
    var automationEnabled: Bool
    var dailyInspectionEnabled: Bool
    var lowRiskAutoUpgradeEnabled: Bool
    var advancedModeEnabled: Bool
    var notificationPolicy: NotificationPolicy
    var regularAppNetworkPolicy: RegularAppNetworkPolicy
    var autoRepairPolicy: AutoRepairPolicy
}
```

```swift
struct RiskAssessment: Codable, Equatable, Identifiable {
    var id: String
    var packageID: String
    var level: RiskLevel
    var reasons: [RiskReason]
    var automationDecision: AutomationDecision
    var userAction: InboxAction?
}
```

```swift
struct InboxItem: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: InboxItemKind
    var severity: InboxSeverity
    var title: String
    var summary: String
    var sourceID: String?
    var createdAt: Date
    var status: InboxStatus
    var actions: [InboxAction]
}
```

```swift
struct AppUpdateCapability: Codable, Equatable {
    var bundleIdentifier: String?
    var detector: AppUpdateDetectorKind
    var confidence: DetectionConfidence
    var feedURL: URL?
    var installedVersion: String?
    var availableVersion: String?
    var actions: [InboxAction]
    var diagnostic: String?
}
```

```swift
struct InspectionReport: Codable, Equatable, Identifiable {
    var id: UUID
    var startedAt: Date
    var finishedAt: Date?
    var trigger: InspectionTrigger
    var scannedSummary: ScanSummary
    var automaticUpgrades: [PackageUpgradeRecord]
    var skippedItems: [SkippedUpgradeRecord]
    var failures: [FailureRecord]
    var inboxItemIDs: [UUID]
}
```

The exact fields can evolve during implementation, but the first implementation should preserve these boundaries: profile, risk, inbox, app update capability, inspection report and recovery action.

## Key Flows

### Onboarding

1. App loads `AutomationProfile`.
2. If onboarding is incomplete, default mode shows manual controls and an onboarding prompt.
3. User reviews local-only privacy, automation scope, notification policy and risk boundary.
4. If user enables automation, profile records automation and daily inspection preferences.
5. App schedules or refreshes the LaunchAgent.

### Daily Inspection

1. LaunchAgent starts `MacSoftwareStewardAgent`.
2. Agent scans managed sources and regular app update capabilities.
3. Agent generates risk assessments for upgradeable packages.
4. Low-risk upgrades run automatically when allowed.
5. High-risk upgrades, app updates, failures and source issues become inbox items.
6. Agent writes `InspectionReport`.
7. Main app reads reports and inbox items on next launch or foreground refresh.
8. Notification fires only when new pending decisions or failures exist.

### Manual Upgrade

1. User opens default inbox or advanced update console.
2. App generates an upgrade plan with risk reasons.
3. Low-risk items are selected by default.
4. High-risk items require explicit confirmation.
5. Completed actions write records to history and update inbox status.

### Regular App Update Discovery

1. Scanner inspects app bundle metadata.
2. Detector identifies Sparkle, vendor updater, unknown updater or no updater.
3. Network policy decides whether to check available versions.
4. Discovery result becomes app metadata and optionally an inbox item.
5. User action opens the app, update helper, vendor page or Finder location.

### Failure Recovery

1. Command or scan failure is classified.
2. Recovery planner returns structured actions.
3. Default mode shows the best manual action.
4. Advanced auto-repair can execute allowlisted low-risk actions.
5. Failed auto-repair becomes a manual inbox item and does not loop.

## Error Handling

- Network failures during regular app discovery should not stop managed source scanning.
- Hash, permission, replacement conflict, running app and dependency failures should become inbox items.
- Background Agent path failures should prompt the user to re-enable daily inspection.
- Auto repair should have no unbounded retry loop; one failure converts to manual recovery.
- Ordinary app update feed parse failures should be visible in advanced diagnostics and quiet in default mode.
- Notification delivery failures should be logged but should not block inbox or report creation.

## Storage And Privacy

All new data remains local:

- `AutomationProfile` may use `UserDefaults` for small preferences.
- `InboxItem` and `InspectionReport` should use JSON files in `~/Library/Application Support/MacSoftwareSteward/`.
- Reports should be compact and rotate or cap by count to avoid unbounded growth.
- Network discovery must not upload the full local application list.
- Export should produce local JSON or archive files. Import should validate schema version before applying.

## Testing Strategy

### Unit Tests

- `AutomationProfileStore` defaults, onboarding state and advanced mode persistence.
- `RiskAssessor` rules for low-risk, major version, pinned package, running app, sudo requirement, cleanup conflict and dependency issues.
- `InboxStore` creation, deduplication, status transitions and persistence.
- `InspectionReportStore` report creation and summary aggregation.
- `RegularAppUpdateDiscovery` with fixtures for Sparkle, Chrome, Adobe, JetBrains, Microsoft and unknown updater metadata.
- `RecoveryActionPlanner` for known Homebrew, mas and permission failure classes.
- Notification decision logic: success-only reports stay quiet; pending decisions or failures notify.

### Integration Tests

- Agent scan writes a report and inbox items using fixture scanner output.
- Manual upgrade plan displays risk reasons and selection defaults.
- Advanced mode changes navigation visibility without losing existing state.
- Auto repair allowlist executes only permitted actions.

### UI Checks

- Default mode has inbox, apps, history and settings only.
- Advanced mode exposes updates, sources, rules and jobs.
- Inbox item actions stay readable at supported window sizes.
- Empty states clearly explain when automation has not been enabled.

## Rollout Plan

### M1: Automation Profile, Advanced Mode And Inbox Skeleton

- Add `AutomationProfile`.
- Add onboarding completion and advanced mode setting.
- Add `InboxItem` model and persistence.
- Add default `InboxView`.
- Gate existing detailed pages behind advanced mode.

### M2: Risk-Based Upgrade Plan

- Add `RiskAssessor`.
- Integrate risk decisions into `UpgradePlanner`.
- Adjust manual upgrade selection defaults.
- Create inbox items for high-risk upgrades.
- Add notification decision logic.

### M3: Inspection Reports And History

- Add `InspectionReport`.
- Update Agent to write reports.
- Add `HistoryView`.
- Record automatic upgrades, skipped items and failures.

### M4: Regular App Update Discovery

- Add Sparkle detector first.
- Add vendor detector interfaces and fixtures.
- Add Chrome, Adobe, JetBrains and Microsoft detector rules incrementally.
- Surface ordinary app update actions in inbox and applications list.

### M5: Failure Recovery And Auto Repair

- Add structured `RecoveryAction`.
- Extend existing failure analysis to produce actions.
- Add manual recovery buttons in inbox.
- Add advanced auto-repair allowlist for low-risk actions.

### M6: Rules Console And Import/Export

- Add `RulesView`.
- Show risk rules, network policy and auto-repair policy.
- Add export/import for automation profile, risk policy and report archive.

## Acceptance Criteria

- `npm test` covers new pure logic before each milestone merges.
- A user who has not completed onboarding cannot accidentally enable automatic upgrades.
- A user who enables automation only gets automatic low-risk upgrades by default.
- High-risk upgrades appear in the inbox with clear reasons and actions.
- Successful automatic upgrades appear in history without proactive notification.
- Failures and pending decisions trigger notification and inbox items.
- Default mode hides command logs, detailed source diagnostics and rules.
- Advanced mode exposes full control surfaces.
- Ordinary `.app` update discovery never silently replaces apps.
- All automation data is stored locally and remains usable without network access except for explicit update checks.

## Open Implementation Notes

- Use fixtures for ordinary app update detectors so tests do not rely on installed third-party apps.
- Prefer small helper types over increasing `StewardModel.swift` size.
- Keep the first detector milestone narrow enough to finish with reliable tests before adding more vendor rules.
- Treat import/export as schema-versioned from the start, even if the first version only exports JSON.
