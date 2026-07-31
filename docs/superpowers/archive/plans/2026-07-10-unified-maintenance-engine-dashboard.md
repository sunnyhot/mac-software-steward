# 实施计划：统一维护引擎与维护总览页

> 配套设计：`docs/superpowers/specs/2026-07-10-unified-maintenance-engine-dashboard-design.md`
>
> 目标：把扫描→评估→计划→执行→校验→报告 收敛为一个 Foundation-only 工作流核心，新增「维护总览」默认页，并让手动维护、升级页、每日巡检共用同一套计划分类与执行规则。
>
> 拆分原则：**每个子任务独立可编译、可测试、可提交**。任何一步结束时 `npm test && npm run build` 必须通过。不把"未验证的引擎重写"和"整块 UI 迁移"塞进同一个提交。

---

## 现状关键事实（影响拆分）

1. `StewardModel.swift` 已 1628 行。执行相关逻辑约 680 行（`command(for:)` 到 `applyHomebrewDownloadSnapshot`），外加 14 个执行状态字段。
2. 执行链路对 `StewardModel` 有两处**反向依赖**：
   - `runJob` 结束调 `scheduleRescanAfterJobCompletion`（读 `hasRunningJob`+`pendingJobQueue`，再调 `scanSoftware`）。
   - `performAutomaticRepairIfAllowed` 的 `.rescan` 分支调 `scanSoftware`。
   抽 Executor 时这两处必须改成事件/回调，不能让 Executor 反向持有扫描入口。
3. `strategiesForStep`(StewardModel.swift:1206) 硬调 `DownloadAccelerationPolicy.defaultStrategies()`，**忽略了注入的 `downloadStrategiesProvider`**——抽出时修正。
4. `lowRiskAutoUpgradeEnabled`（AutomationProfile 字段）在 planner/agent 链中**完全没被读取**，profile 开关形同虚设。统一 Planner 时补齐。
5. `AppTab` 的 `.inbox/.sources/.history/.performance` case 存在但**未被任何 sidebar 分区接线**。新增 `.overview` 时注意 `symbol`/`usesSearch` 的 exhaustive switch 都要补 case。
6. 持久化 store 统一写法见 `InspectionReportStore.swift`（含 sortedKeys/trimToLimit/reload，最完整），新 store 照搬。
7. Agent（`MacSoftwareStewardAgent/AgentMain.swift`）当前自己调 `UpgradePlanner.makePlan → DailyUpgradePolicy.automaticPackages`，是独立第二条链路，第 6 步接入引擎。

---

## 阶段总览

| 阶段 | 对应设计迁移步 | 子任务数 | 产物 |
|------|---------------|---------|------|
| Phase 1 | 步 1 | T1–T4 | Foundation-only 状态机、计划分类、协议边界 + 单测 |
| Phase 2 | 步 2 | T5–T7 | MaintenanceExecutor（执行逻辑搬离 StewardModel）|
| Phase 3 | 步 3 | T8–T9 | Verifier/Recovery 协调 + 跨进程租约 |
| Phase 4 | 步 4 | T10–T11 | MaintenanceRunStore + 双写 + bundle 兼容 |
| Phase 5 | 步 5 | T12 | 升级页与前台巡检接入引擎 |
| Phase 6 | 步 6 | T13 | 后台 Agent 接入 Foundation-only 核心 |
| Phase 7 | 步 7 | T14–T16 | Dashboard presenter + overview 导航 + Dashboard UI |
| Phase 8 | 步 8 | T17 | 全局视觉收口 + 移除 StewardModel 重复执行代码 |

每个 Phase 完成后建议单独提交 + 版本号递增发布（patch），降低回滚成本。

---

## Phase 1 — Foundation-only 工作流核心（不改现有调用方）

目标：建立纯 Foundation 的类型与协议，加单测，**StewardModel 完全不动**。这一阶段产物不接入 UI，纯粹是"地基"。

### T1. 工作流状态机与转换规则

**新增文件**：`native/MacSoftwareSteward/MaintenanceWorkflowState.swift`

**内容**：
- `enum MaintenanceWorkflowPhase`：`idle / scanning / assessing / executingAutomatic / awaitingConfirmation / executingConfirmed / verifying / completed(MaintenanceRunOutcome) / cancelled(MaintenanceRunOutcome) / failed(String)`。
  - 注意 `completed/cancelled/failed` 携带关联值，需 `Equatable`（`MaintenanceRunOutcome` 也要 `Equatable`）。
- `struct MaintenanceRunOutcome`：`runID / trigger / startedAt / finishedAt / terminalStatus / summary(MaintenanceRunSummary)`。
- `enum MaintenanceRunTrigger`：`smartMaintenance / detailedUpgrade / dailyInspection`。
- `struct MaintenanceRunSummary`：各类计数（automatic/confirmation/reminder/blocked、succeeded/failed/cancelled/timedOut/neverStarted）。
- `enum MaintenanceWorkflowCore`（无状态命名空间，纯函数）：`static func transition(from:by:) -> MaintenanceWorkflowPhase?`，编码所有合法/非法转换；`awaitingConfirmation` 在无待确认项时跳过；`executingAutomatic` 在无 automatic 项时跳过。
- 约束：包级失败是 run 内的 outcome，不把整条 workflow 推到 `failed`；只有 workflow 级错误（如扫描彻底失败）才 `failed`。

**测试** `tests/MaintenanceWorkflowStateTest.swift`：合法转换推进、非法转换返回 nil、跳过空阶段、终态不可再转。

**验收**：`npm test` 通过；不触碰任何现有文件。

### T2. 统一计划分类（MaintenancePlanner + MaintenancePlanDisposition）

**新增文件**：`native/MacSoftwareSteward/MaintenancePlanner.swift`（注意：与现有 `UpgradePlanner.swift` **并存**，不删旧的）。

**内容**：
- `enum MaintenancePlanDisposition`：`automatic / confirmationRequired / reminderOnly / blocked`，各带 `title` 与是否可执行。
- `struct MaintenancePlanItem`：`packageID / packageName / package: UpdatablePackage? / disposition / riskLevel / automationDecision / effectivePolicy / reasons([String]) / commandDisplay`。派生 `isExecutable`。
- `struct MaintenancePlan`：`items([MaintenancePlanItem])` + 分组计算属性（`automaticItems/confirmationItems/reminderItems/blockedItems`）。
- `enum MaintenancePlanner`（纯静态）：`static func makePlan(scan:policyStore:riskAssessor:includeGreedy:profile:) -> MaintenancePlan`。
  - **复用** 现有 `RiskAssessor.assess` 与 `UpgradePolicyStore.effectivePolicy`，不重写风险评估。
  - 分类规则严格按设计「Confirmed Product Decisions」：
    - `automatic` = 可执行 ∧ level==low ∧ decision==allowAutomatic ∧ policy==automatic ∧ **profile.lowRiskAutoUpgradeEnabled**（补齐第 4 点缺口）。
    - `confirmationRequired` = 可执行 ∧ (需确认 ∨ policy==askFirst)。
    - `reminderOnly` = policy==remindOnly ∨ 普通 App 有手动 checker 但无安全命令。
    - `blocked` = policy==skip ∨ 源不可用 ∨ pinned ∨ 不可升级 ∨ decision==blockExecution。
  - blocked 项 `package=nil`，UI 无法把它变可执行。

**测试** `tests/MaintenancePlannerTest.swift`：覆盖 policy×risk×automationDecision×sourceAvailability×pinned×executable 的全部组合；blocked 永不进 automatic；confirmation 永不进 automatic；`lowRiskAutoUpgradeEnabled=false` 时 automatic 为空。

**验收**：`npm test` 通过；现有 `UpgradePlanner` 仍被 StewardModel/Agent 使用，行为不变。

### T3. 执行/校验/恢复协议边界（仅协议，无实现）

**新增文件**：`native/MacSoftwareSteward/MaintenanceProtocols.swift`

**内容**：定义后续 Phase 2/3 要实现的协议，**此任务只写协议 + 文档注释，不写实现**。
- `protocol MaintenanceExecuting`：`func execute(plan:autoRepairProfile:inboxStore:) async -> MaintenanceExecutionResult`、`var executionSnapshot: MaintenanceExecutionSnapshot { get }`、`func cancel() async`。
- `protocol MaintenanceVerifying`：`func verify(executedPackageIDs:scan:) async -> MaintenanceVerificationResult`。
- `protocol MaintenanceRecovering`：`func recoveryActions(for:PackageUpgradeProgress) -> [FailureActionType]`。
- `protocol MaintenanceRunLeasing`：`func acquire(trigger:) -> MaintenanceLease?`、`func release(_:)`、`func currentLease() -> MaintenanceLease?`。
- 配套值类型：`MaintenanceExecutionResult / MaintenanceExecutionSnapshot / MaintenanceVerificationResult / MaintenanceLease`。

**验收**：`npm test && npm run build` 通过（协议无实现方也能编译，因为没人 conform）。

### T4. 跨进程维护租约 MaintenanceRunLease

**新增文件**：`native/MacSoftwareSteward/MaintenanceRunLease.swift`

**内容**：Foundation-only，实现 `MaintenanceRunLeasing`（T3 的协议）。
- 原子获取锁文件 `~/Library/Application Support/MacSoftwareSteward/maintenance.lock`（`FileHandle` 独占或 `open(O_EXLOCK)`）。
- lease 记录：`runID(UUID) / pid / processStartTime / trigger / createdAt`，写 JSON 到锁文件旁。
- PID 复用防护：校验 `pid` 当前存活且启动时间与记录一致；不一致视为 stale。
- stale lease：标记关联的非终态 run 为 `interrupted`，再回收。
- 释放：终态完成或有序取消时释放。

**测试** `tests/MaintenanceRunLeaseTest.swift`：获取/冲突/有序释放/stale-owner 检测/PID 复用保护（用临时目录注入 fileURL）。

**验收**：`npm test` 通过；此阶段 lease 尚未接入任何调用方。

> ⚠️ Phase 1 结束检查点：`npm test && npm run build` 全绿；StewardModel/Agent/Views **零改动**。建议提交 + 发 patch 版本。

---

## Phase 2 — MaintenanceExecutor（执行逻辑搬离 StewardModel）

目标：把 StewardModel 里约 680 行执行逻辑搬进独立的 `MaintenanceExecutor`（实现 T3 的 `MaintenanceExecuting`），StewardModel 降级为门面委托给它。

### T5. MaintenanceExecutor 骨架 + 状态搬移

**新增文件**：`native/MacSoftwareSteward/MaintenanceExecutor.swift`

**搬移的状态字段**（来自 StewardModel）：`jobs / activeJobCount / pendingJobQueue / activeCancellationTokens / downloadMonitorTasks / downloadSizeTasks / downloadExpectedSizes / downloadAccelerationStrategies / downloadAccelerationAttempts / downloadAccelerationRetryRequests / downloadAccelerationTokens / downloadAccelerationCleanups / downloadSlowSampleState / autoRepairAttemptedPackageIDs`。

**搬移的方法**：`command(for:) / enqueueJob / startJob(×2) / dequeueNext / runJob / runPackageStepsConcurrently / handleStepResult / prepareStepExecution / runCommand / cleanupStaleBrewCaskIfNeeded / 所有 mark* / 所有 Homebrew 下载监控 / updateJob / appendLog / updateUpgradeProgress / failureAnalysis / firstErrorLine / currentCommandText / failureSummary / prunePackageProgress`，私有类型 `StepExecutionOutcome / FailureAnalysis`，`JobRescanPolicy`。

**依赖注入**（解决第 2 点反向依赖）：
- Executor 不持有 scanner。改为暴露事件：`var onAllJobsCompleted: ((MaintenanceExecutionSnapshot) -> Void)?`，由 StewardModel 订阅后驱动重扫。
- `performAutomaticRepairIfAllowed` 的 `.rescan` 分支改为 `onRescanRequested: (() async -> Void)?` 回调，由 StewardModel 提供真正的 `scanSoftware`。

**修正**（第 3 点）：`strategiesForStep` 改为走注入的 `downloadStrategiesProvider`，不再硬调 default。

**StewardModel 改动**（最小）：
- 新增 `let executor: MaintenanceExecutor`。
- `upgrade/retryPackage/upgradeAll/confirmUpgradePlan/upgradeSelectedPlanRows/installMasCLI/runDailyInspectionNow` 改为委托 executor（签名对外不变）。
- `packageProgress / upgradeProgress / jobs / hasRunningJob / cancelJob` 改为转发到 executor（或保留为计算属性转发）。
- 订阅 `executor.onAllJobsCompleted` → 触发 `scheduleRescanAfterJobCompletion` 逻辑（留在 StewardModel）。

**测试** `tests/MaintenanceExecutorTest.swift`：并发上限、独立包失败隔离、超时隔离、用户取消（停止入队 + cancel 活跃 token）、onAllJobsCompleted 触发时机。

**风险**：这是最大的一步，搬移面广。建议**先全量复制到 Executor、StewardModel 内部改为转发**（行为等价），跑通全测后再在后续任务优化边界。不要在这一步同时改语义。

**验收**：`npm test && npm run build` 全绿；现有升级/取消/重试/巡检行为完全不变（人工 QA 一遍升级流程）。

### T6. Executor 接入工作流状态机与租约

**改动**：`MaintenanceExecutor` 在 `execute(...)` 开始时 `acquire(trigger:)`，结束（终态/取消/失败）时 `release`。冲突时返回"已有活跃 run"结果，由调用方决定展示。

**测试**：扩展 T5 测试，覆盖租约冲突时不重复执行、取消时释放、异常路径释放。

### T7. 删除 StewardModel 中的执行重复代码

**改动**：确认所有调用方都走 executor 后，删除 StewardModel 里已搬走的字段与方法实体（保留门面转发）。

**验收**：`StewardModel.swift` 行数显著下降；测试与构建通过。

> ⚠️ Phase 2 结束检查点：升级/取消/重试/巡检行为完全等价；提交 + 发 patch。

---

## Phase 3 — Verifier / Recovery 协调（接入引擎）

### T8. MaintenanceVerifier（实现 T3 协议）

**新增文件**：`native/MacSoftwareSteward/MaintenanceVerifier.swift`

**内容**：实现 `MaintenanceVerifying`，封装现有 `UpgradeVerifier.remainingOutdatedIDs/verify` 行为，对完成的包集合做重扫后校验。校验不一致 → 标记为失败 outcome（即使命令退出码为 0）。

**测试**：校验成功 / 不一致（命令成功但版本仍 outdated→warning）/ 包不在新扫描结果中。

### T9. MaintenanceRecoveryCoordinator

**新增文件**：`native/MacSoftwareSteward/MaintenanceRecoveryCoordinator.swift`

**内容**：实现 `MaintenanceRecovering`，复用 `RecoveryActionPlanner` + `UpgradeFailureAnalyzer`，输出重试/重扫/看日志/复制终端命令/开系统设置的恢复动作。自动修复仍由现有 `AutomationProfile.autoRepairPolicy` + allowlist 控制（复用 `AutoRepairDecider`）。

**测试**：各失败类型的恢复动作映射；allowlist 门控。

> ⚠️ Phase 3 结束：提交 + patch。

---

## Phase 4 — MaintenanceRunStore + 双写 + bundle 兼容

### T10. MaintenanceRunRecord + Store

**新增文件**：`native/MacSoftwareSteward/MaintenanceRunStore.swift`

**内容**（照搬 InspectionReportStore 写法）：
- `struct MaintenanceRunRecord: Codable`：schemaVersion / runID / trigger / 起止时间 / terminalStatus / scan 摘要与每源可用性 / 每个 item 的 disposition / 每个执行包的命令+校验+失败+恢复 outcome / dashboard 计数。
- `final class MaintenanceRunStore: ObservableObject`：`init(fileURL:limit:)`、`append/reload/clear/replaceRecords`、`static let currentSchemaVersion`、有界历史（limit=50）、原子写、iso8601、`[.prettyPrinted,.sortedKeys]`、损坏文件不阻塞启动（返回空）。
- 存储路径：`~/Library/Application Support/MacSoftwareSteward/maintenance-runs.json`。

**测试**：round trip / 有界历史 / interrupted-run 处理 / 损坏输入返回空 / legacy projection（空 store 时投影最新 legacy 巡检+升级记录为只读摘要）。

### T11. 双写 + AutomationDataBundle schema v3

**改动**：
- 工作流终态时**同时**写 legacy `inspection-reports.json` + `upgrade-history.json`（保证现有页面/导出不变）和新 `maintenance-runs.json`。
- `AutomationDataBundle`：`currentSchemaVersion` 2→3；新增可选字段 `maintenanceRunRecords`，`init(from:)` 用 `decodeIfPresent ?? []`；`AutomationDataBundleSummary` 加对应 count；导入校验区间改 `[1...3]`。

**测试**：扩展 `AutomationDataBundleTest`，v2 导入到 v3（新字段空）、v3 导出/导入 round trip。

> ⚠️ Phase 4 结束：提交 + patch。

---

## Phase 5 — 升级页与前台巡检接入引擎

### T12. 升级页 + 前台巡检走引擎

**改动**：
- 升级页（`UpdatesView` + `StewardModel.prepareUpgradePlan`）改为消费 `MaintenancePlan`（来自统一 Planner），执行走 Executor + 同一全局租约。
- 前台手动触发巡检（`runDailyInspectionNow`）走引擎，但只执行 `automatic` 组。
- 跨进程租约保证升级页与总览页/巡检不会重复执行。

**验收**：升级页与总览页不能同时跑（租约互斥）；升级计划分类与总览一致。

> ⚠️ 提交 + patch。

---

## Phase 6 — 后台 Agent 接入 Foundation-only 核心

### T13. AgentMain 走引擎核心

**改动** `native/MacSoftwareStewardAgent/AgentMain.swift`：
- 用 Foundation-only 核心（不引入 SwiftUI/AppKit/Combine）。
- 只执行 `automatic` 组，永不弹确认框。
- 获取租约冲突时记日志并成功退出（不重复干活）。
- confirmation/reminder/blocked/failed 通过持久化 run + inbox + 通知策略暴露。
- 编译约束：Agent 编译时只能链接共享的 Foundation 文件（参照现有 build-native.sh 的 Agent 编译文件清单）。

**风险**：Agent 编译文件清单在 `scripts/build-native.sh`，新增核心文件要同步加入清单，否则 Agent 链接报错。

**验收**：Agent 单独运行测试；租约冲突时正确退出。

> ⚠️ 提交 + patch。

---

## Phase 7 — Dashboard Presenter + Overview 导航 + UI

### T14. MaintenanceDashboardPresenter

**新增文件**：`native/MacSoftwareSteward/MaintenanceDashboardPresenter.swift`

**内容**：把引擎状态 + 持久化 run 映射为稳定 UI 模型（纯 Foundation，可单测）：健康标题/支撑文案、维护轨道四阶段、4 项 metric、优先任务行、当前包进度、巡检摘要、最近一次 run 结果、各空/部分源/失败/取消/完成态。无命令执行。

**测试** `tests/MaintenanceDashboardPresenterTest.swift`：ready/scanning/automatic 执行/等待确认/部分成功/失败/取消/全清 各态。

### T15. overview 导航接入

**改动**：
- `Models.swift` `AppTab`：新增 `case overview = "维护总览"`，补 `symbol`/`usesSearch` switch。
- `StewardModel.swift:6`：默认 `selectedTab = .overview`。
- `AppTabNavigationPresenter`：`overview` 放进 `primaryTabs` 的**标准与高级模式都显示**，且作为首项；`fallbackTab` 改回 `.overview`。
- `ContentView.swift` `MainPanel` switch：`case .overview: MaintenanceOverviewView()`。

**测试**：扩展 `AppTabVisibilityTest`，覆盖标准/高级模式 overview 可见与默认值。

### T16. MaintenanceOverviewView

**新增文件**：`native/MacSoftwareSteward/Views/MaintenanceOverviewView.swift`

**内容**：按设计「Dashboard layout」单页滚动：页头+重扫 / 健康面+`开始智能维护` / 四阶段维护轨道 / 4 metric / 优先任务 / 自动化与最近 run 摘要。复用 `SharedComponents` 的 surface/token，不引新框架。窄窗单列，metric 先两列再塌缩。无嵌套滚动视图。

**验收**：标准/高级模式都默认进总览；首启无扫描时显示 ready 态 + 单按钮，不显示"零值健康评估"。`npm test && npm run build` 通过。

> ⚠️ 提交 + patch（或 minor）。

---

## Phase 8 — 全局视觉收口 + 清理

### T17. 视觉对齐 + 移除残留

**改动**：
- 统一 sidebar、页头、section spacing、filter bar、列表行、空态、badge、进度面到共享 spacing/surface token。
- 复用共享 SwiftUI modifier，移除页体内的裸色/裸圆角。
- 移除 StewardModel 中已完全迁移的重复执行代码（若 Phase 2 未清完）。
- reduced-motion / 键盘焦点 / 浅深色对比检查。

**验收**：设计 Acceptance Criteria 全部满足；`npm test && npm run build` 通过；人工 QA 清单（设计文档「Manual QA」节）过一遍。

> ⚠️ 提交 + 发 minor 版本（如 0.14.0）。

---

## 跨阶段约束（始终生效）

- 每个子任务结束：`npm test && npm run build` 必须通过。
- 每个 Phase 结束：提交 + 发 patch（Phase 8 发 minor）。
- 不删 legacy `inspection-reports.json` / `upgrade-history.json`。
- 不改自更新安全与安装行为。
- 不改生成的图标与 release 资产。
- 中文 UI / 英文代码标识符。
- Foundation-only 核心文件不 import SwiftUI/AppKit/Combine（Agent 可编译）。
- 版本号双写：`package.json` 与 `native/Info.plist` 同步。

## 建议执行顺序与依赖

```
T1 → T2 → T3 → T4        (Phase 1，互不依赖可顺序快做)
       ↓
T5 → T6 → T7              (Phase 2，T5 是最大单步，需重点 review)
       ↓
T8, T9                    (Phase 3，可并行)
       ↓
T10 → T11                 (Phase 4)
       ↓
T12                       (Phase 5)
       ↓
T13                       (Phase 6，注意 Agent 编译清单)
       ↓
T14 → T15 → T16           (Phase 7)
       ↓
T17                       (Phase 8)
```

## 风险登记

| 风险 | 缓解 |
|------|------|
| T5 搬移面广，易引入回归 | 先"复制+转发"保证行为等价，跑全测后再优化；不在此步改语义 |
| Executor↔StewardModel 反向依赖（重扫/修复） | 用 `onAllJobsCompleted`/`onRescanRequested` 回调拆开，不互相持有 |
| Agent 编译文件清单遗漏新核心文件 | 改 build-native.sh 时同步更新；Agent 单独跑一遍 |
| Dashboard 语义复杂（部分成功/取消/中断） | Presenter 先纯函数化 + 全态单测，再接 UI |
| `lowRiskAutoUpgradeEnabled` 接入后行为变化 | T2 单测显式覆盖开关 true/false 两态；文档标注语义变化 |
