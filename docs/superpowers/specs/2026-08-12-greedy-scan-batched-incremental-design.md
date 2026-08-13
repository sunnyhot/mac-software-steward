# greedy 扫描分批增量（partial results）设计

- 日期：2026-08-12
- 状态：已确认，待出实现计划
- 关联：`Scanner.scanBrew`；上一轮修复 `brewCommandError`/`wasSignaled`（信号死亡判定）；`homebrew-auto-updates-cask-detection`（greedy 漏报根因）

## 背景

`Scanner.scanBrew` 用单发 `brew outdated --greedy --json=v2`（`outdatedTimeout = 120s`）一次性检查所有已装 cask。`--greedy` 会为每个 cask（尤其 `auto_updates` 类，如 Microsoft Office）做联网版本检查（appcast / Sparkle / livecheck）。网络慢时整次调用超过 120s 被 `CommandRunner` 的定时器 `SIGTERM`，于是：

- 整盘失败，拿不到任何 cask 的 outdated 信息；
- 定时巡检拿不到结果 → 无法规划升级（漏报死循环的温床）；
- 即便上一轮已把错误文案改友好，仍是"全成功或全失败"。

## 目标

greedy cask 检查慢时**返回已扫到的部分结果**，未扫到的 cask 标记为"待重试"，而非整盘失败。把"一个慢 cask 拖垮整次扫描"的爆炸半径限制在单批内。GUI 手动扫描与定时巡检同时受益（共用 `scanBrew`）。

## 非目标（YAGNI，本次不做）

- 后台异步刷新（扫描秒回非 greedy 结果，greedy 后台补）：改动过大，且定时巡检需要即时结果。
- 调高单次阈值：已被"分批 + 总预算"替代。
- 行级 UI 标记（某 cask 行显示"未知"）：避免动 UI 数据流；用诊断卡片 + 重新扫描兜底。

## 方案

### 核心拆分

把单发 `brew outdated --greedy --json=v2` 拆成：

- **formulae**：`brew outdated --json=v2 --formula`（**不含** `--greedy`；`--greedy` 只影响 cask——`auto_updates` / `:latest`，formulae 无此概念）。本地版本比对，快。逻辑等价于原先 greedy 调用里的 formulae 部分。
- **casks**：按已装 cask 列表分批，逐批 `brew outdated --greedy --json=v2 --cask <批内名字>`。`--greedy`（纳入条件）与位置参数 `[cask ...]`（作用域）正交，组合后仅对批内 cask 做 greedy 检查。

已验证（本机）：`brew outdated --greedy --json=v2 --cask <name>` 返回有效（空）结果而非报错，说明位置过滤器生效。实现时再用一个已知 greedy-outdated 的 cask 复核过滤器确能命中（当前本机各 cask 均为最新，无法直接验证命中分支）。

### 执行模型：总预算 + 串行

`scanBrew` 现为两阶段（任务组 → caskNameList 兜底）。改为：

- **阶段一（任务组，并行）**：`version` / `prefix` / `formulaList` / `caskList` / **formula outdated**（新增 `--formula` 调用）。均为本地/快命令，沿用各自 30s 超时。
- **阶段二（caskList 就绪后，串行 + 预算）**：把已装 cask 名按 `batchSize` 分批，在总预算内逐批跑 greedy。

预算规则：

- `totalBudget = 180s`（用户确认放宽，原 120s）。
- `perBatchCap = 60s`。
- 每批跑前：`remaining = totalBudget - elapsed`。若 `remaining < 5s`（floor），停止，剩余 cask 全部进 `unchecked`。否则 `batchTimeout = min(perBatchCap, remaining)`。
- 批次成功 → 合并其 cask outdated 条目；超时/失败 → 该批 cask 进 `unchecked`，继续下一批。
  - **"成功"的判定（关键，曾出 bug）**：`brew outdated` 发现可升级项时以 **exit code 1** 退出（Homebrew 既定约定，非错误），JSON 仍完整在 stdout。故判定标准是「进程未被信号杀死 且 stdout 可解析为 brew outdated JSON」（`BrewBatchedGreedy.greedyBatchSucceeded`），**不是** `code == 0`。若按非零退出码判失败，会把含可升级 cask 的整批误判失败——恰好在能发现更新时丢弃更新。
- 串行而非并发：避免多个 brew 进程争用 API 缓存，deadline 账目简单；快批次本就几乎不耗时（主要是 ~0.8s brew 启动）。

最坏情况：`batchSize=5`、15 cask → 3 批 × 60s = 180s 恰等总预算（第 3 批后预算耗尽）。正常情况多数批次秒级完成。

`brew update`（刷新元数据，60s）保留在阶段一之前串行执行——它是上一版本修漏报的关键，分批方案仍依赖新鲜元数据。该 60s **独立于** greedy 的 180s 预算，故整次扫描最坏墙钟约 60s + 180s + 快命令。仅在所有批次都触顶 60s 的病态情况才会接近，正常为几秒。

### 数据模型（`native/MacSoftwareSteward/Models.swift`）

`BrewScan` 增字段：

```swift
/// greedy 分批检查中未完成（超时/失败/预算耗尽未跑）的 cask 名。
/// 不能被当作"最新"——否则等于漏报。供上层诊断提示"部分完成，建议重试"。
var uncheckedCasks: [String] = []
```

默认空，向后兼容（现有构造点无须改）。

**正确性红线**：unchecked 的 cask 不出现在 outdated 条目里 → `mergeBrew` 不会把它们标 `outdated`，但必须把名字收进 `uncheckedCasks`。UI/诊断据此提示，**绝不在无信息时默认"最新"**。

### `error` 与 `uncheckedCasks` 的契约（避免歧义）

分批后没有"单一的 outdated 命令结果"，因此 `BrewScan.error` 的组装规则定为：

- 每批失败**不**各自往 `error` 里堆（避免噪音）；统一只计数、把该批 cask 名收进 `uncheckedCasks`。
- **零个 cask 批次成功**（全部超时/失败，或预算耗尽前一个都没跑完）→ `error` 写入友好超时串（含 "被终止"/"SIGTERM"/"超时" 关键字，复用 `brewCommandError` 文案风格），使现有"Homebrew 更新检查超时"诊断命中。formulae 结果仍照常返回（不丢失）。
- **至少一个 cask 批次成功**（部分成功）→ `error` **留空**（不警报），改由 `uncheckedCasks` 驱动下方"部分完成"软诊断。

`diagnoseBrew` 判定顺序随之明确：

1. `!error.isEmpty` → 走现有分支（更新检查超时 / 连接失败 / 通用错误）。
2. `error.isEmpty && !uncheckedCasks.isEmpty` → 新增"部分完成"分支。
3. 否则 → `nil`（全成功）。

### 部分结果的呈现（`native/MacSoftwareSteward/SourceDiagnostics.swift`）

`diagnoseBrew` 增"**部分完成**"分支（在上面的判定顺序第 2 步）：

- 触发：`error.isEmpty && uncheckedCasks.count > 0`。
- 文案：`reason = "Homebrew 部分检查未完成"`；`suggestion = "另有 N 个 cask（如 X、Y）未完成更新检查，通常是一次性网络拉取较慢。已扫到的结果仍可用；建议稍后重新扫描补齐。"`；`action = .rescan`；`terminalCommand = nil`（**不**建议 brew doctor）。
- `technicalDetails`：列出 unchecked 名单（去重、按字母序，超长截断）。

**简化假设**（v1）：批失败一律按"超时/未完成"处理，不在 `error` 里区分非超时的 brew 报错；罕见情况下可后续细化。

### 常量（`Scanner.swift`）

```swift
private static let greedyBatchSize = 5
private static let greedyTotalBudget: TimeInterval = 180
private static let greedyPerBatchCap: TimeInterval = 60
private static let greedyBudgetFloor: TimeInterval = 5   // 剩余不足此时停止再开新批
```

## 测试

把"分批 → 累积 → unchecked 归集"抽成**纯函数**，便于单测（brew 调用本身仍是集成层）：

```swift
// 输入：已装 cask 名 + 每批的结果（成功则 outdated 条目，失败则该批 cask 名）
// 输出：合并后的 outdated 条目 + unchecked 名单
static func accumulateBatchedCaskOutdated(
    installedCasks: [String],
    batchResults: [(batch: [String], result: BatchOutcome)]
) -> (outdated: [[String: Any]], unchecked: [String])
```

`BatchOutcome` = `.succeeded([[String: Any]])` | `.failed`。

`tests/` 覆盖：

1. 全成功：所有批 `.succeeded` → outdated 合并、unchecked 空。
2. 某批超时：该批 cask 进 unchecked，其余合并。
3. 预算耗尽：模拟"第 2 批后预算用完"→ 第 3 批 cask 进 unchecked（即便没跑）。
4. 全部失败：unchecked 覆盖全部，outdated 空（上层落回"更新检查超时"诊断）。
5.（纯函数）批次切分：`splitIntoBatches(["a","b","c","d","e","f"], size: 5)` → `[["a".."e"], ["f"]]`。

诊断分支新增 `testDiagnoseBrewPartialBranch`：构造 unchecked 非空 + 有结果的错误串，断言 reason 含"未完成"、`terminalCommand == nil`、suggestion 不含 "brew doctor"。

## 实现备注 / 验证点

- **位置过滤器 + greedy 命中**：实现时找一个已知 greedy-outdated 的 cask（或临时 `brew install --cask` 旧版）复核 `--greedy --cask <name>` 能命中。当前本机各 cask 均最新，无法直接验证命中分支（只验证了过滤器作用域不报错）。
- **brew 启动开销**：每批 ~0.8s 启动；`batchSize=5` 在 15 cask 下为 3 批 ≈ 2.4s 额外开销，可接受。cask 多时勿把 `batchSize` 调太小（避免启动开销主导）。
- `parseBrewOutdated` 已能解析单次 JSON 的 `formulae`/`casks`；分批后对每批 JSON 解析 `casks` 并拼接即可，formulae 来自阶段一的 `--formula` 调用。
- 阶段一任务组里用 `brew outdated --json=v2 --formula` 取 formulae；其超时沿用 30s（formulae outdated 为本地比对，足够）。

## 不在本次范围

后台异步刷新、调高单次阈值、per-row "未知" UI、把 `brew update` 并行化或计入 greedy 预算。
