# Sudo Cask Auto-Elevation Design

## Context

Mac 软件管家在执行 `brew upgrade --cask` 时，少数 cask（安装到 `/usr/local` 等需要 root 写入的位置）会触发 Homebrew 的 sudo 密码请求。当前实现中，`MaintenanceExecutor` 全程不带 sudo 地跑 brew，一旦 brew 输出 `password is required` 等，`UpgradeFailureAnalyzer` 会把它判定为 `.retryInTerminal`，让用户打开终端、手动复制命令、手动输入密码——体验割裂。

用户明确希望：「sudo 升级不要手动，留在 app 内完成」。

## 当前现状与硬约束

- 纯 `swiftc` 命令行构建（`scripts/build-native.sh`），**ad-hoc 签名**（`codesign --force --sign -`），**无 sandbox、无 entitlements**。
- 因此 `SMJobBless` / 常驻 `LaunchDaemon` / privileged helper tool 这条「常驻 root helper」路系统会拒绝（要求 Developer ID 签名），与当前签名现状不匹配。
- 唯一可行的提权方式：`osascript ... with administrator privileges`，由 macOS SecurityServer 弹原生密码框，AppleScript 临时持权。密码不落盘、不进 shell 历史、不进 app 内存。
- macOS 无法做到「完全不弹密码框」，只能减少次数。

## 用户决策

- sudo 升级时密码框的弹出频次：**一批弹一次**——把一次「一键升级」里所有需要 sudo 的 cask 合并成一条 `osascript`，只弹一次密码框跑完全部。

## Goals

- 当 `brew upgrade --cask` 因 sudo 密码失败时，app 自动把本批次所有需要 sudo 的 cask 合并成一条 `osascript ... with administrator privileges`，弹一次系统原生密码框串行跑完，实时回传日志与每包状态。
- 整个体验从「打开终端、手动跑命令、输密码」变成「点一个按钮、输一次密码」。

## Non-Goals (YAGNI)

- 不做常驻 root helper / LaunchDaemon / SMJobBless。
- 不持有密码、不缓存密码、不把密码写进任何文件或长期进程内存。
- 不改正常路径：99% 的 cask 装到 `/Applications` 不要 sudo，继续走现有并发 + 下载加速 + 流式日志，完全不介入。
- 不改 `RiskAssessor` 的安全边界：major / 固定 / 依赖异常等高风险项仍不自动执行。

## Architecture

### 触发时机：先正常并发跑，真卡 sudo 才介入

不是「升级前预先提权」，而是「先正常并发跑，只有真卡 sudo 才介入」：

1. 本批次步骤照常并发执行（`runPackageStepsConcurrently`）。
2. 某个 cask 失败后，`handleStepResult` 用现有 `UpgradeFailureAnalyzer.knownFailureHint` 判定输出。
3. 新增识别：命中 sudo 提示 → 该步骤标记为 `needsSudo`（新状态），**不立即归为失败**，而是挂起。
4. 批次跑完后，若挂起的 sudo 需求 ≥ 1，收集所有同批次的 `needsSudo` cask → 进入「sudo 批次重试」。

不在单条命令失败时立即弹框，是因为本批可能并发跑着 5 个 cask，其中 3 个要 sudo——等并发批跑完一次性收集，才能做到「一次密码框搞定全部」。

### 命令拼接：一条 osascript 串行跑完所有 cask

把 N 个需要 sudo 的 cask 合成一条 `osascript`，内部串行：

```applescript
osascript -e 'do shell script "
  /opt/homebrew/bin/brew upgrade --cask pkgA; echo \"__RC_1_$?__\"
  /opt/homebrew/bin/brew upgrade --cask pkgB; echo \"__RC_2_$?__\"
  /opt/homebrew/bin/brew upgrade --cask pkgC; echo \"__RC_3_$?__\"
" with administrator privileges'
```

要点：

- **`;` 分隔，不用 `&&`**：某条失败不阻断后续——每个 cask 独立判定成败，失败隔离。
- **每条后跟 `echo "__RC_<i>_$?__"` 标记**：执行器按标记切分输出，给每个 step 独立回填退出码与输出片段。
- **brew 路径用 `commandPath("brew")` 解析的实际绝对路径**（现有逻辑已做），避免 root 环境下 PATH 缺失导致 `brew: command not found`。
- **不传 `--greedy`**：重试只为通过 sudo，扫描语义不变。
- **环境变量透传**：`osascript` 起 root shell 时会丢掉 app 的 `PATH` / `HOMEBREW_*` 等，需显式带上（现有 `processEnvironment()` 的子集，只带必要的 `PATH`、`HOME`）。

### 日志与进度回传

`osascript` 走 `do shell script` 是阻塞的，但 `osascript` 进程本身边跑边把 brew 的输出吐到 stdout。执行器用现有 `CommandRunner.runStreamingDetailed` 跑 `osascript` 这个普通进程，实时回传到现有 `appendLog(stream:text:)` 与 `updatePackageDetail`，复用现有日志 UI，无需新组件。

### 数据流与新增类型

`Models.swift`：

```swift
/// sudo 重试的批次：一批弹一次密码框，串行跑完。
struct SudoRetryBatch: Hashable {
    var steps: [UpgradeStep]      // 同批次中所有 needsSudo 的 cask
}
```

`PackageUpgradeStatus`（`String` raw value）新增状态：

```swift
case needsSudo = "等待管理员授权"   /// 需要管理员密码，等待批量重试（替代直接 .failed）
```

`FailureActionType` 新增 case（给 UI 用，语义=系统已自动用 sudo 重试）：

```swift
case promptAdminPassword  /// 系统已弹出密码框进行 sudo 升级
```

`UpgradeFailureAnalyzer` 不改已知逻辑，新增静态识别：

```swift
static func requiresSudo(in output: String) -> Bool {
    // 现有 knownFailureHint 里 sudo 分支的同一组关键词
    // （password is required / terminal is required / a password is required / read the password）
}
```

`MaintenanceExecutor.handleStepResult` 的判断改成：命中 sudo → `markNeedsSudo(step)`，**不计入 `failedCount`**（它还没失败，只是挂起）。

`MaintenanceExecutor` 新增执行器方法：

```swift
private struct SudoRetryOutcome: Hashable {
    var step: UpgradeStep          // 对应回填的步骤
    var exitCode: Int32            // 该 cask 的 brew 退出码
    var outputSegment: String      // 两个 __RC__ 标记之间的输出片段
}

private func runSudoRetryBatch(
    jobID id: UUID,
    batch: SudoRetryBatch,
    token: CommandCancellationToken
) async -> [SudoRetryOutcome]
```

职责：

1. 解析 brew 绝对路径（`requireCommand("brew")`）。
2. 拼接 osascript 脚本。
3. 调 `CommandRunner.runStreamingDetailed("osascript", args...)` 跑，实时回传日志。
4. 解析输出里的 `__RC_<n>__` 标记 → 给每个 step 回填成功/失败。

整批编排（伪代码）：

```
runPackageStepsConcurrently(...)           // 现有并发批，正常跑
  → 每条失败时若 needsSudo，挂进 sudoPending[batchID]
并发批结束
if !sudoPending.isEmpty {
    runSudoRetryBatch(...)                  // 新增：一次密码框，串行跑完
    → 把每个 outcome 回填到对应 step（markSucceeded / markFailed）
}
```

### 安全：绝不持有密码

`runSudoRetryBatch` 只发出 `osascript ... with administrator privileges` 这条命令本身。密码框是 macOS SecurityServer 弹的原生 sheet，密码：

- 不进 app 内存（app 只看到 osascript 进程的退出码和 stdout）。
- 不落盘、不进 shell 历史（`do shell script` 不经交互式 shell）。
- 用完即焚，`osascript` 进程结束即失效。

### 并发与失败隔离

sudo 重试批内部**串行，不并发**：

- `do shell script` 是单条阻塞命令，N 条 brew 用 `;` 串到同一条 script 里，天然串行。
- macOS 不支持「一次密码授权给多个并发 root 进程」，要并发就得每个进程单独弹框，违背「一批弹一次」。
- 需要 sudo 的 cask 通常就 1~3 个，串行成本可忽略。

退出码解析规则：

- 标记 `__RC_<i>_<n>__`，第 i 个 cask 退出码 n。
- `n == 0` → `markSucceeded(step_i)`。
- `n != 0` → 走现有 `failureAnalysis(...)`，但 action 从 `.retryInTerminal` 改成 `.promptAdminPassword`（已 sudo 过仍失败，说明不是密码问题，降级为「查看日志/重试」）。
- 输出片段（两个标记之间）作为该 step 的失败输出，喂给 `UpgradeFailureAnalyzer` 做进一步诊断。

两批衔接：并发批先跑，sudo 批后跑，不回灌。

```
并发批（含下载加速/部分下载清理）         sudo 重试批
        │
        ├─ pkgA 成功 → markSucceeded
        ├─ pkgB needsSudo → 挂进 sudoPending ──┐
        ├─ pkgC 成功 → markSucceeded            │
        ├─ pkgD needsSudo → 挂进 sudoPending ──┤
        ├─ pkgE 真·失败（非 sudo）→ markFailed    │
        ▼                                        │
   并发批结束                                    │
        │  ←────────────────────────────────────┘
        ▼
   runSudoRetryBatch（收集到的 needsSudo）
        ├─ 一次密码框
        ├─ 串行跑 B、D
        ├─ B 成功 → markSucceeded
        └─ D 仍失败 → markFailed（走常规失败分析）
```

关键：**真·失败（非 sudo 原因）的 cask 不进 sudo 批**。只有 `UpgradeFailureAnalyzer.requiresSudo` 命中的才挂起，避免对「网络断了」或「校验失败」的包也弹密码框。

### 边界情况兜底

| 场景 | 处理 |
|---|---|
| 用户取消并发批（`token.cancel()`） | `needsSudo` 挂起的包标记 `.cancelled`，**不进 sudo 批** |
| 用户在密码框点「取消」（osascript 返回非 0） | sudo 批整体失败，每个 step 标记「用户取消了管理员授权」，action=`.promptAdminPassword` 允许重试（再点会再弹框） |
| sudo 批里某条 brew 仍报 sudo（applescript 环境异常） | 退化为常规失败，action 降级，提示「管理员授权可能未生效，可重试」 |
| osascript 进程超时 | 现有 `timeout` 机制（7200s）生效，标 `.timedOut` |
| 密码错误 3 次（macOS 限制） | osascript 自然返回非 0，按「用户取消」分支处理，不无限重试 |
| 并发批里 0 个 needsSudo | 不进 sudo 批，零开销，正常路径完全不变 |

`needsSudo` 状态**不计入 `failedCount`**。只有 sudo 批跑完后才结算：

- sudo 批里成功的 → 不影响 failedCount。
- sudo 批里仍失败的 → failedCount +1。

「批次是否成功」的判定口径不变：跑完所有阶段（并发批 + sudo 批）后，`failedCount == 0` 才算全批成功。

## 与 RiskAssessor 安全边界的关系

设计文档 `2026-06-12-automation-steward-major-enhancement-design.md` 第 100 行的规则：

> IF 升级项需要 sudo、运行中应用退出、清理冲突、major 版本、固定版本、依赖异常或开发工具链风险 THEN 系统 SHALL NOT 自动执行该升级。

这里的「sudo」指的是**风险评级维度**——即「这个升级本身是否需要提权」作为是否自动执行的判定条件之一。本设计**不动这条规则**：

- `RiskAssessor` 照常评级，major / 固定 / 依赖异常等高风险项**仍写待处理收件箱、等用户确认**，不会因为 sudo 自动重试而绕过。
- sudo 自动重试只作用于**已被批准执行**（低风险自动 / 用户已点确认）的 cask，在执行阶段卡在密码上时，用 osascript 把「去终端手动」变成「弹框一次」。

语义区别：**「风险维度的 sudo」** ≠ **「执行阶段的 sudo 密码弹框」**。前者是准入判断（是否允许自动跑），后者是已准入命令的提权方式（怎么跑）。本设计只动后者。

对该 SHALL NOT 规则补充澄清：

> 本规则的「sudo」指**升级项本身在风险评估阶段需要提权**。对已通过风险评估、被批准执行的升级，若执行阶段因 macOS 密码策略卡住，允许通过 `osascript with administrator privileges` 弹原生密码框提权——这是执行方式，不改变风险评估结论。

## User Experience

| | 现在 | 本设计后 |
|---|---|---|
| 需要终端 | ✅ 打开终端 App | ❌ 不需要 |
| 手动输命令 | ✅ 复制/粘贴/回车 | ❌ 不需要 |
| 输密码 | ✅ 在终端输 | ✅ 系统原生密码框输一次 |
| 切换上下文 | ✅ 离开 app 去终端 | ❌ 留在 app |
| 步数 | 5 步 | 1 次输密码 |

UI 表现（复用现有，最小新增）：

- 密码框：macOS 原生 SecurityServer sheet，无需自绘——osascript 触发，系统自动弹。
- 状态文案：`needsSudo` 状态下，该包显示「等待管理员授权升级」；sudo 批启动时，进度条顶部提示「正在请求管理员密码以升级 N 个软件」。
- 失败兜底：若用户取消密码框或授权失败，sudo 批里每个包标失败，action=`.promptAdminPassword`（允许「重试」——再点会再弹框），**绝不偷偷改成「去终端」**——那是我们要消除的体验。

日志透明度：osascript 跑的整条命令写进 job 日志（已有 `appendLog(stream:"command", ...)`）。用户可看到：

```
$ sudo 批次：osascript 提权执行 3 个 cask 升级
[系统] 弹出管理员密码框…
[pkgB] brew upgrade --cask pkgB …
[pkgB] __RC_1_0__
[pkgD] brew upgrade --cask pkgD …
[pkgD] __RC_2_0__
```

执行细节完全可审计，不留黑盒。

## Testing Strategy

延续项目现有的 swiftc 编译测试风格（见 `scripts/test-native.sh`），核心逻辑可纯单测，osascript 本身不可控的部分靠接口隔离 + 手测脚本兜底。

### 单元测试（可纯函数验证）

| 测试目标 | 文件 | 验证点 |
|---|---|---|
| sudo 需求识别 | `UpgradeFailureAnalyzerTest`（新增） | `requiresSudo(in:)` 对 4 个关键词变体命中、对非 sudo 失败（权限/校验/网络）不命中 |
| osascript 脚本拼接 | `SudoScriptBuilderTest`（新增） | N=1/N=3/N=0 输入 → 正确的 `;` 分隔、`__RC_<i>_$?__` 标记、brew 绝对路径、环境变量透传 |
| 退出码解析 | `SudoScriptParserTest`（新增） | 把含 3 段 `__RC_1_0__`/`__RC_2_1__`/`__RC_3_0__` 的混合输出切成 3 个 outcome，exit code 与输出片段对应正确 |
| 失败隔离 | 同上 | 中段失败不影响前后段标记，每段独立结算 |

### 脚本拼接/解析——纯函数，易测

把拼接和解析各抽成独立纯函数类型：

```swift
enum SudoScriptBuilder {
    static func script(brewPath: String, packageNames: [String]) -> String  // → applescript 串
    static func osaArguments(_ script: String) -> [String]                  // → ["-e", script]
}

enum SudoScriptParser {
    /// 解析单个 cask 的执行结果。packageIndex 与输入 packageNames 的下标对应。
    struct Outcome { var packageIndex: Int; var exitCode: Int32; var outputSegment: String }
    static func outcomes(in output: String, count: Int) -> [Outcome]
}
```

执行器内部把 `SudoScriptParser.Outcome` 与原 `UpgradeStep` 组合成 `SudoRetryOutcome` 回填——见上方 `runSudoRetryBatch` 签名里的 `private struct SudoRetryOutcome`。`Outcome` 是纯解析结果，`SudoRetryOutcome` 带上 step 引用以便回填，职责不重叠。

这俩无 IO、无异步，单测覆盖率高，是整个特性的可测核心。

### osascript 执行——接口隔离

`CommandRunner.runStreamingDetailed` 已是现成的执行边界。`MaintenanceExecutor.runSudoRetryBatch` 依赖的是「一个能流式跑命令的闭包/协议」，测试时可注入假实现（返回构造好的 `__RC__` 输出），验证：

- 调用了 osascript 且参数含 `with administrator privileges`。
- 把假返回的输出正确解析、回填到各 step 的状态。

### 手测脚本（scripts/ 下新增，非 CI）

`scripts/test-sudo-retry.sh`：用一个故意要 sudo 的 cask 触发，确认弹框 + 升级成功 + 日志含 `__RC__` 标记且解析正确。osascript 弹框无法自动化，作为发布前手测清单项。

### 回归——确保正常路径零影响

- 现有所有 `MaintenanceExecutor` / `UpgradeFailureAnalyzer` 单测必须全绿不改。
- 新增测试只加文件，不动现有测试断言。
- 关键回归点：无 sudo 需求的批次（`sudoPending` 为空）→ `runSudoRetryBatch` 根本不被调用，零开销。加一个执行器级测试覆盖此分支。

### 不测的（承认边界）

- macOS 密码框本身的弹起/输入——系统行为，不可控，靠手测。
- 真实 brew 升级结果——依赖环境，靠手测。
- 并发竞态的极端组合——成本过高，靠代码审查 + 边界注释。

## Implementation Surface (Summary)

涉及改动的文件与新增点：

- `native/MacSoftwareSteward/Models.swift`
  - 新增 `SudoRetryBatch`。
  - `PackageUpgradeStatus` 新增 `needsSudo`。
  - `FailureActionType` 新增 `promptAdminPassword`。
- `native/MacSoftwareSteward/UpgradeFailureAnalyzer.swift`
  - 新增 `requiresSudo(in:)` 静态识别（复用现有 sudo 关键词组）。
- `native/MacSoftwareSteward/MaintenanceExecutor.swift`
  - `handleStepResult`：命中 sudo → `markNeedsSudo`，不计 `failedCount`。
  - 新增 `runSudoRetryBatch(jobID:batch:token:)`。
  - 顶层执行流：并发批跑完 → 收集 `needsSudo` → 调 sudo 批。
- `native/MacSoftwareSteward/SudoScriptBuilder.swift`（新增）
  - 纯函数：脚本拼接 + osa 参数。
- `native/MacSoftwareSteward/SudoScriptParser.swift`（新增）
  - 纯函数：`__RC__` 标记解析。
- `scripts/build-native.sh`、`scripts/test-native.sh`
  - 把新增源文件加入编译/测试列表。
- `tests/UpgradeFailureAnalyzerTest.swift`、`tests/SudoScriptBuilderTest.swift`、`tests/SudoScriptParserTest.swift`（新增）
- `scripts/test-sudo-retry.sh`（新增，手测）。
- `docs/superpowers/specs/2026-06-12-automation-steward-major-enhancement-design.md`
  - 第 100 行规则补充「风险 sudo ≠ 执行 sudo」澄清。
