# Sudo Cask Auto-Elevation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `brew upgrade --cask` 卡 sudo 时，把同批次所有需要 sudo 的 cask 合并成一条 `osascript ... with administrator privileges`，弹一次系统原生密码框串行跑完，消除「打开终端手动跑命令输密码」的体验。

**Architecture:** 正常并发批不动。并发批跑完后，收集所有命中 sudo 的 cask（挂起为 `needsSudo`，不计失败），用纯函数 `SudoScriptBuilder` 拼一条 osascript 脚本（`;` 分隔 + `__RC_<i>_$?__` 标记），经 `CommandRunner.runStreamingDetailed` 跑，再用纯函数 `SudoScriptParser` 切分输出回填每个包状态。密码全程由 macOS SecurityServer 处理，app 不持有。

**Tech Stack:** Swift（纯 `swiftc` 命令行构建）、AppKit/Foundation、osascript、Homebrew Cask。测试沿用项目 `scripts/test-native.sh` 的 `@main struct` + `precondition` 风格。

**Spec:** `docs/superpowers/specs/2026-07-28-sudo-cask-auto-elevation-design.md`

---

## File Structure

| 文件 | 责任 | 动作 |
|---|---|---|
| `native/MacSoftwareSteward/SudoScriptBuilder.swift` | 纯函数：把 `[包名]` 拼成 osascript 脚本 + `-e` 参数 | 新增 |
| `native/MacSoftwareSteward/SudoScriptParser.swift` | 纯函数：解析 `__RC_<i>_<n>__` 标记，切分每段输出与退出码 | 新增 |
| `native/MacSoftwareSteward/UpgradeFailureAnalyzer.swift` | 新增 `requiresSudo(in:)` 静态识别 | 修改 |
| `native/MacSoftwareSteward/Models.swift` | `PackageUpgradeStatus` 加 `needsSudo`；`FailureActionType` 加 `promptAdminPassword`；新增 `SudoRetryBatch` | 修改 |
| `native/MacSoftwareSteward/MaintenanceExecutor.swift` | `handleStepResult` 命中 sudo 挂起；新增 `runSudoRetryBatch`；`runJob` 编排 sudo 批 | 修改 |
| `scripts/build-native.sh` | 主 app 编译列表加入两个新源文件 | 修改 |
| `tests/SudoScriptBuilderTest.swift` | builder 单测 | 新增 |
| `tests/SudoScriptParserTest.swift` | parser 单测 | 新增 |
| `tests/UpgradeFailureAnalyzerTest.swift` | 加 `requiresSudo` 用例 | 修改 |
| `scripts/test-native.sh` | 注册两个新测试 | 修改 |
| `scripts/test-sudo-retry.sh` | 手测脚本（非 CI） | 新增 |
| `docs/superpowers/specs/2026-06-12-automation-steward-major-enhancement-design.md` | 第 100 行规则补「风险 sudo ≠ 执行 sudo」澄清 | 修改 |

**关键设计决策（影响任务粒度）：**

- 可测核心全部抽成**纯函数**（`SudoScriptBuilder` / `SudoScriptParser`），无 IO 无异步，单测覆盖率最大化。
- `MaintenanceExecutor` 是 `@MainActor ObservableObject`、内部状态重，从未在 tests/ 被实例化——**执行器不做集成测试**，编排正确性靠纯函数保证 + `scripts/test-sudo-retry.sh` 手测兜底。
- `CommandRunner.processEnvironment` / `defaultPath` 是 `private static`——builder **不直接碰环境**，由执行器拿 `PATH`/`HOME` 字符串传给 builder 拼进脚本。

---

### Task 1: 新增枚举 case 与 SudoRetryBatch 模型

**Files:**
- Modify: `native/MacSoftwareSteward/Models.swift:69-78`（`PackageUpgradeStatus`）、`325-337`（`FailureActionType`）、`319-323` 附近（`UpgradeStep` 之后）

- [ ] **Step 1: 读现有定义，确认插入点**

Run: `sed -n '69,80p;319,337p' native/MacSoftwareSteward/Models.swift`
Expected: 看到 `PackageUpgradeStatus`（`String` raw value，最后是 `case warning = "需确认"`）和 `FailureActionType`（最后是 `case retryInTerminal`）。

- [ ] **Step 2: 给 PackageUpgradeStatus 加 needsSudo**

在 `case warning = "需确认"` 之后加：

```swift
    case needsSudo = "等待管理员授权"   /// 需要 sudo 密码，等待批量重试（不立即算失败）
```

- [ ] **Step 3: 给 FailureActionType 加 promptAdminPassword**

在 `case retryInTerminal` 之后加：

```swift
    case promptAdminPassword  /// 系统已弹出密码框进行 sudo 升级（失败后允许重试再弹）
```

- [ ] **Step 4: 在 UpgradeStep 之后新增 SudoRetryBatch**

在 `struct UpgradeStep { ... }` 闭合括号之后插入：

```swift
/// sudo 重试批次：一批弹一次密码框，串行跑完同批次所有 needsSudo 的 cask。
struct SudoRetryBatch: Hashable {
    var steps: [UpgradeStep]
}
```

- [ ] **Step 5: 编译验证（不破坏现有构建）**

Run: `bash scripts/build-native.sh 2>&1 | tail -5`
Expected: 构建成功（新 case 暂未被引用，但 Swift 允许未使用的 enum case）。若 `PackageUpgradeStatus` 在别处有 `switch` 缺 case 报错，按编译器提示在那个 switch 里加 `case .needsSudo: break` 或合适分支（仅当编译报错时）。

- [ ] **Step 6: Commit**

```bash
git add native/MacSoftwareSteward/Models.swift
git commit -m "feat(sudo): add needsSudo status, promptAdminPassword action, SudoRetryBatch model"
```

---

### Task 2: UpgradeFailureAnalyzer.requiresSudo 识别（TDD）

**Files:**
- Modify: `tests/UpgradeFailureAnalyzerTest.swift`（加用例）
- Modify: `native/MacSoftwareSteward/UpgradeFailureAnalyzer.swift`（加静态方法）

- [ ] **Step 1: 先写失败测试**

在 `tests/UpgradeFailureAnalyzerTest.swift` 的 `static func main()` 末尾（最后一个 precondition 之后）追加：

```swift
        // --- requiresSudo ---
        let sudoRequired = "Error: sudo: a password is required"
        precondition(UpgradeFailureAnalyzer.requiresSudo(in: sudoRequired) == true, "sudo + 'a password is required' must be detected")

        let sudoTerminal = "sudo: terminal is required to read the password"
        precondition(UpgradeFailureAnalyzer.requiresSudo(in: sudoTerminal) == true, "'terminal is required' sudo variant must be detected")

        let sudoRead = "Error: sudo: read the password"
        precondition(UpgradeFailureAnalyzer.requiresSudo(in: sudoRead) == true, "'read the password' sudo variant must be detected")

        let sudoPlain = "sudo: password is required"
        precondition(UpgradeFailureAnalyzer.requiresSudo(in: sudoPlain) == true, "'password is required' sudo variant must be detected")

        // 非 sudo 失败不应命中
        let permDenied = "curl: (18) permission denied"
        precondition(UpgradeFailureAnalyzer.requiresSudo(in: permDenied) == false, "permission denied must NOT be treated as sudo")

        let checksumFail = "Error: SHA256 mismatch"
        precondition(UpgradeFailureAnalyzer.requiresSudo(in: checksumFail) == false, "checksum mismatch must NOT be treated as sudo")

        let networkFail = "curl: (28) connection timed out"
        precondition(UpgradeFailureAnalyzer.requiresSudo(in: networkFail) == false, "network error must NOT be treated as sudo")
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `bash scripts/test-native.sh 2>&1 | grep -A3 "UpgradeFailureAnalyzerTest"`
Expected: 编译失败 `'requiresSudo' is not a member of 'UpgradeFailureAnalyzer'`。

- [ ] **Step 3: 实现 requiresSudo**

在 `native/MacSoftwareSteward/UpgradeFailureAnalyzer.swift` 的 `enum UpgradeFailureAnalyzer { ... }` 内、`knownFailureHint` 之后加：

```swift
    /// 输出是否表明升级卡在 sudo 密码上（与 knownFailureHint 里 sudo 分支同一组关键词）。
    /// 调用方据此把步骤挂起为 needsSudo，等待批量 osascript 重试，而非直接判失败。
    static func requiresSudo(in output: String) -> Bool {
        let lowercased = output.lowercased()
        guard lowercased.contains("sudo") else { return false }
        return lowercased.contains("password is required")
            || lowercased.contains("terminal is required")
            || lowercased.contains("a password is required")
            || lowercased.contains("read the password")
    }
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `bash scripts/test-native.sh 2>&1 | grep -A2 "UpgradeFailureAnalyzerTest"`
Expected: `==> Running UpgradeFailureAnalyzerTest` 后无 precondition 崩溃，脚本整体退出码 0。

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/UpgradeFailureAnalyzer.swift tests/UpgradeFailureAnalyzerTest.swift
git commit -m "feat(sudo): detect sudo password requirement via UpgradeFailureAnalyzer.requiresSudo"
```

---

### Task 3: SudoScriptBuilder 纯函数（TDD）

**Files:**
- Create: `tests/SudoScriptBuilderTest.swift`
- Create: `native/MacSoftwareSteward/SudoScriptBuilder.swift`
- Modify: `scripts/test-native.sh`（注册新测试）

**脚本格式约定（必须严格遵守，parser 据此解析）：**

- 整条命令：`osascript` 进程，参数 `["-e", script]`。
- `script` 是 AppleScript：`do shell script "<body>" with administrator privileges`。
- `<body>` 里每个 cask 一行：`<brewPath> upgrade --cask <name>; echo "__RC_<i>_$?__"`，行间用 `\n` 分隔。
- `<i>` 从 1 开始，按 `packageNames` 顺序。
- `<brewPath>` 必须是绝对路径（避免 root 环境 PATH 缺失）。
- body 前加 `export PATH=<path>; export HOME=<home>;` 透传最小环境。

- [ ] **Step 1: 写失败测试**

创建 `tests/SudoScriptBuilderTest.swift`：

```swift
import Foundation

@main
struct SudoScriptBuilderTest {
    static func main() {
        let brewPath = "/opt/homebrew/bin/brew"

        // --- N=3：分隔符、标记、路径、顺序 ---
        let script3 = SudoScriptBuilder.script(
            brewPath: brewPath,
            packageNames: ["pkgA", "pkgB", "pkgC"],
            pathEnv: "/opt/homebrew/bin:/usr/local/bin",
            homeEnv: "/Users/test"
        )
        precondition(script3.contains("with administrator privileges"), "must request admin privileges")
        precondition(script3.contains("\(brewPath) upgrade --cask pkgA"), "must include pkgA with absolute brew path")
        precondition(script3.contains("\(brewPath) upgrade --cask pkgB"), "must include pkgB")
        precondition(script3.contains("\(brewPath) upgrade --cask pkgC"), "must include pkgC")
        precondition(script3.contains("echo \"__RC_1_$?__\""), "pkgA must carry __RC_1_ marker")
        precondition(script3.contains("echo \"__RC_2_$?__\""), "pkgB must carry __RC_2_ marker")
        precondition(script3.contains("echo \"__RC_3_$?__\""), "pkgC must carry __RC_3_ marker")
        precondition(script3.contains("; echo"), "statements must be ;-separated per cask (failure isolation)")
        precondition(script3.contains("export PATH=/opt/homebrew/bin:/usr/local/bin"), "must export PATH for root shell")
        precondition(script3.contains("export HOME=/Users/test"), "must export HOME for root shell")

        // 顺序：pkgA 标记必须出现在 pkgB 标记之前
        if let aRange = script3.range(of: "__RC_1_"), let bRange = script3.range(of: "__RC_2_") {
            precondition(aRange.lowerBound < bRange.lowerBound, "markers must preserve package order")
        } else {
            preconditionFailure("markers not found for ordering check")
        }

        // --- N=1：单包也要正确 ---
        let script1 = SudoScriptBuilder.script(brewPath: brewPath, packageNames: ["only"], pathEnv: "/x", homeEnv: "/h")
        precondition(script1.contains("\(brewPath) upgrade --cask only"), "single package must appear")
        precondition(script1.contains("__RC_1_$?__"), "single package must carry __RC_1_ marker")

        // --- osaArguments：必须是 ["-e", script] ---
        let args = SudoScriptBuilder.osaArguments(script1)
        precondition(args == ["-e", script1], "osaArguments must wrap script as -e arg, got \(args)")

        // --- N=0：空输入返回空 body（调用方应避免，但函数不得崩溃） ---
        let script0 = SudoScriptBuilder.script(brewPath: brewPath, packageNames: [], pathEnv: "/x", homeEnv: "/h")
        precondition(script0.contains("with administrator privileges"), "even empty batch keeps admin privileges wrapper")
        precondition(!script0.contains("__RC_"), "empty batch must emit no markers")
    }
}
```

- [ ] **Step 2: 注册测试到 test-native.sh**

在 `scripts/test-native.sh` 的 `run_test UpgradeFailureAnalyzerTest \` 块**之前**插入：

```sh
run_test SudoScriptBuilderTest \
  "$SRC/Models.swift" \
  "$SRC/SudoScriptBuilder.swift" \
  "$TESTS/SudoScriptBuilderTest.swift"

```

- [ ] **Step 3: 跑测试，确认失败**

Run: `bash scripts/test-native.sh 2>&1 | grep -A3 "SudoScriptBuilderTest"`
Expected: 编译失败 `cannot find 'SudoScriptBuilder' in scope`。

- [ ] **Step 4: 实现 SudoScriptBuilder**

创建 `native/MacSoftwareSteward/SudoScriptBuilder.swift`：

```swift
import Foundation

/// 把同批次所有需要 sudo 的 cask 拼成一条 osascript 脚本。
///
/// 格式（parser 据此解析，改动需同步 SudoScriptParser）：
///   do shell script "<body>" with administrator privileges
/// body 每行：`<brewPath> upgrade --cask <name>; echo "__RC_<i>_$?__"`
/// body 前置 `export PATH=...; export HOME=...;` 透传最小环境给 root shell。
/// 语句间用 `;`（非 `&&`），单条失败不阻断后续，实现失败隔离。
enum SudoScriptBuilder {
    /// 生成 AppleScript 脚本字符串（osascript -e 的内容）。
    static func script(brewPath: String, packageNames: [String], pathEnv: String, homeEnv: String) -> String {
        var lines: [String] = []
        lines.append("export PATH=\(pathEnv)")
        lines.append("export HOME=\(homeEnv)")
        for (index, name) in packageNames.enumerated() {
            // 标记下标从 1 开始，与 parser 约定一致。
            let markerNumber = index + 1
            lines.append("\(brewPath) upgrade --cask \(name); echo \"__RC_\(markerNumber)_$?__\"")
        }
        let body = lines.joined(separator: "\n")
        return "do shell script \"\(body)\" with administrator privileges"
    }

    /// 把脚本包装成 osascript 的参数列表。
    static func osaArguments(_ script: String) -> [String] {
        ["-e", script]
    }
}
```

- [ ] **Step 5: 跑测试，确认通过**

Run: `bash scripts/test-native.sh 2>&1 | grep -A2 "SudoScriptBuilderTest"`
Expected: `==> Running SudoScriptBuilderTest` 后无崩溃，脚本退出码 0。

- [ ] **Step 6: Commit**

```bash
git add native/MacSoftwareSteward/SudoScriptBuilder.swift tests/SudoScriptBuilderTest.swift scripts/test-native.sh
git commit -m "feat(sudo): add SudoScriptBuilder pure function for osascript command assembly"
```

---

### Task 4: SudoScriptParser 纯函数（TDD）

**Files:**
- Create: `tests/SudoScriptParserTest.swift`
- Create: `native/MacSoftwareSteward/SudoScriptParser.swift`
- Modify: `scripts/test-native.sh`（注册新测试）

**解析约定（与 Task 3 builder 严格对应）：**

- 输出里查找 `__RC_<i>_<n>__`，`<i>` 是包下标（从 1），`<n>` 是退出码。
- 第 i 个包的输出片段 = 第 i 个标记**之后**到第 i+1 个标记**之前**的内容。
- `count` 参数 = 包数量；只返回 packageIndex 1...count 的结果。
- 找不到标记的包：exitCode 用 -1 哨兵，outputSegment 为空（执行器据此判定异常）。

- [ ] **Step 1: 写失败测试**

创建 `tests/SudoScriptParserTest.swift`：

```swift
import Foundation

@main
struct SudoScriptParserTest {
    static func main() {
        // --- 正常三段：成功/失败/成功，输出片段归属正确 ---
        let output = """
        ==> upgrading pkgA
        some brew stdout for A
        __RC_1_0__
        ==> upgrading pkgB
        error line for B
        __RC_2_1__
        ==> upgrading pkgC
        ok line for C
        __RC_3_0__
        """
        let outcomes = SudoScriptParser.outcomes(in: output, count: 3)
        precondition(outcomes.count == 3, "expected 3 outcomes, got \(outcomes.count)")

        precondition(outcomes[0].packageIndex == 1, "first outcome is pkgA (index 1)")
        precondition(outcomes[0].exitCode == 0, "pkgA exit 0")
        precondition(outcomes[0].outputSegment.contains("some brew stdout for A"), "pkgA segment content")
        precondition(!outcomes[0].outputSegment.contains("__RC_"), "segment must not contain its own marker")

        precondition(outcomes[1].packageIndex == 2, "second outcome is pkgB (index 2)")
        precondition(outcomes[1].exitCode == 1, "pkgB exit 1 (failure)")
        precondition(outcomes[1].outputSegment.contains("error line for B"), "pkgB segment content")

        precondition(outcomes[2].packageIndex == 3, "third outcome is pkgC (index 3)")
        precondition(outcomes[2].exitCode == 0, "pkgC exit 0")
        precondition(outcomes[2].outputSegment.contains("ok line for C"), "pkgC segment content")

        // --- 中段失败不影响前后段解析（失败隔离验证） ---
        precondition(outcomes[0].exitCode == 0 && outcomes[2].exitCode == 0, "neighbors of failed pkgB must still parse independently")

        // --- 缺失标记：该包用哨兵值，其余正常 ---
        let partial = """
        __RC_1_0__
        __RC_3_0__
        """
        let partialOutcomes = SudoScriptParser.outcomes(in: partial, count: 3)
        precondition(partialOutcomes.count == 3, "count params dictates result length")
        precondition(partialOutcomes[0].exitCode == 0, "pkg1 parsed normally")
        precondition(partialOutcomes[1].exitCode == -1, "missing pkg2 marker → sentinel -1")
        precondition(partialOutcomes[1].outputSegment.isEmpty, "missing pkg2 → empty segment")
        precondition(partialOutcomes[2].exitCode == 0, "pkg3 parsed normally despite pkg2 missing")

        // --- count=0：空结果 ---
        let empty = SudoScriptParser.outcomes(in: "whatever", count: 0)
        precondition(empty.isEmpty, "count=0 → empty outcomes")
    }
}
```

- [ ] **Step 2: 注册测试到 test-native.sh**

在 `scripts/test-native.sh` 的 `run_test SudoScriptBuilderTest \` 块**之后**插入：

```sh

run_test SudoScriptParserTest \
  "$SRC/Models.swift" \
  "$SRC/SudoScriptParser.swift" \
  "$TESTS/SudoScriptParserTest.swift"
```

- [ ] **Step 3: 跑测试，确认失败**

Run: `bash scripts/test-native.sh 2>&1 | grep -A3 "SudoScriptParserTest"`
Expected: 编译失败 `cannot find 'SudoScriptParser' in scope`。

- [ ] **Step 4: 实现 SudoScriptParser**

创建 `native/MacSoftwareSteward/SudoScriptParser.swift`：

```swift
import Foundation

/// 解析 osascript 批次输出里的 `__RC_<i>_<n>__` 标记，切分每个 cask 的退出码与输出片段。
///
/// 与 SudoScriptBuilder 的标记格式严格对应。packageIndex 从 1 开始。
/// 缺失标记的包：exitCode 用 -1 哨兵、outputSegment 为空，供执行器判定异常。
enum SudoScriptParser {
    struct Outcome: Hashable {
        var packageIndex: Int
        var exitCode: Int32
        var outputSegment: String
    }

    /// - Parameters:
    ///   - output: osascript 进程的完整 stdout+stderr 合并文本。
    ///   - count: 本批 cask 数量；结果长度恒等于 count（缺失标记用哨兵填充）。
    static func outcomes(in output: String, count: Int) -> [Outcome] {
        // 先按出现顺序收集所有标记及其位置。
        // 标记形如 __RC_2_1__
        var found: [(index: Int, code: Int32, range: Range<String.Index>)] = []
        let pattern = "__RC_(\\d+)_(\\d+)__"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = output as NSString
        let full = output.startIndex..<output.endIndex
        regex.enumerateMatches(in: output, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match = match, match.numberOfRanges == 3,
                  let indexRange = Range(match.range(at: 1), in: output),
                  let codeRange = Range(match.range(at: 2), in: output),
                  let idx = Int(output[indexRange]),
                  let code = Int32(output[codeRange]) else { return }
            guard let r = Range(match.range, in: output) else { return }
            found.append((index: idx, code: code, range: r))
        }

        // 按下标建查找表（同下标取第一个出现的）。
        var byIndex: [Int: (code: Int32, range: Range<String.Index>)] = [:]
        for item in found {
            if byIndex[item.index] == nil { byIndex[item.index] = (item.code, item.range) }
        }

        // 1...count 顺序产出；缺失用哨兵。
        var results: [Outcome] = []
        for i in 1...max(1, count) {
            if count == 0 { break }
            if let entry = byIndex[i] {
                // 片段：当前标记之后 → 下一个存在的标记之前。
                let segmentStart = entry.range.upperBound
                let segmentEnd = nextMarkerStart(after: entry.range.upperBound, in: output) ?? output.endIndex
                let segment = String(output[segmentStart..<segmentEnd])
                results.append(Outcome(packageIndex: i, exitCode: entry.code, outputSegment: segment))
            } else {
                results.append(Outcome(packageIndex: i, exitCode: -1, outputSegment: ""))
            }
        }
        return results
    }

    /// 找 from 之后下一个 `__RC_` 标记的起始位置（用于切分输出片段）。
    private static func nextMarkerStart(after from: String.Index, in output: String) -> String.Index? {
        let needle = "__RC_"
        guard from < output.endIndex else { return nil }
        let rest = output[from..<output.endIndex]
        if let r = rest.range(of: needle) { return r.lowerBound }
        return nil
    }
}
```

- [ ] **Step 5: 跑测试，确认通过**

Run: `bash scripts/test-native.sh 2>&1 | grep -A2 "SudoScriptParserTest"`
Expected: `==> Running SudoScriptParserTest` 后无崩溃，脚本退出码 0。

- [ ] **Step 6: Commit**

```bash
git add native/MacSoftwareSteward/SudoScriptParser.swift tests/SudoScriptParserTest.swift scripts/test-native.sh
git commit -m "feat(sudo): add SudoScriptParser pure function for __RC__ marker parsing"
```

---

### Task 5: MaintenanceExecutor 接入 sudo 批编排

**Files:**
- Modify: `native/MacSoftwareSteward/MaintenanceExecutor.swift`：`handleStepResult`（548-622）、`runJob`（298-397）、新增 `runSudoRetryBatch`
- Modify: `scripts/build-native.sh`：主 app 编译列表加入两个新源文件

> **执行器不做集成测试**（`@MainActor ObservableObject`、依赖 `UpgradeHistoryStore`/host/下载监控，从未在 tests/ 实例化）。编排正确性靠 Task 3/4 的纯函数保证，端到端靠 Task 7 手测脚本。

- [ ] **Step 1: 把新源文件加入主 app 编译列表**

在 `scripts/build-native.sh` 的主 app `swiftc` 调用里（`"$ROOT_DIR"/native/MacSoftwareSteward/*.swift` 这一行之前，或紧随其后补一行显式列举）。由于脚本用通配 `*.swift`，新文件**会被自动包含**——确认即可：

Run: `grep "native/MacSoftwareSteward/\*.swift" scripts/build-native.sh`
Expected: 看到 `"$ROOT_DIR"/native/MacSoftwareSteward/*.swift \`。新文件自动编译，无需改脚本。若通配不存在则手动加 `"$ROOT_DIR"/native/MacSoftwareSteward/SudoScriptBuilder.swift \` 和 `SudoScriptParser.swift \` 两行。

- [ ] **Step 2: 在 handleStepResult 里把 sudo 失败挂起而非计失败**

读现有 `handleStepResult`（`MaintenanceExecutor.swift:548-622`）。当前 `code != 0` 分支会先试 `cleanupStaleBrewCaskIfNeeded`，否则 `failedCount += 1` + `markFailed`。

在 `} else {` （即 cleanup 未命中、即将 markFailed 的分支）**之前**插入 sudo 挂起判断。把：

```swift
        } else {
            failedCount += 1
            if firstErrorCode == nil { firstErrorCode = code }
            let analysis = failureAnalysis(command: command.display, code: code, output: result.recentOutput)
            markFailed(step, analysis: analysis)
            host?.executorRequestsDerivedDataRecompute()
            updateJob(id) {
                $0.log.append(LogLine(stream: "system", text: "失败：\(command.display)，退出码 \(code)"))
            }
        }
```

改为：

```swift
        } else if UpgradeFailureAnalyzer.requiresSudo(in: result.recentOutput) {
            // 卡在 sudo 密码：不立即计失败，挂起等待批量 osascript 重试。
            markNeedsSudo(step)
            sudoPendingSteps.append(step)
            host?.executorRequestsDerivedDataRecompute()
            updateJob(id) {
                $0.log.append(LogLine(stream: "system", text: "需要管理员密码：\(command.display)，将批量请求授权后重试"))
            }
        } else {
            failedCount += 1
            if firstErrorCode == nil { firstErrorCode = code }
            let analysis = failureAnalysis(command: command.display, code: code, output: result.recentOutput)
            markFailed(step, analysis: analysis)
            host?.executorRequestsDerivedDataRecompute()
            updateJob(id) {
                $0.log.append(LogLine(stream: "system", text: "失败：\(command.display)，退出码 \(code)"))
            }
        }
```

- [ ] **Step 3: 加 sudoPendingSteps 状态字段与 markNeedsSudo**

在 `MaintenanceExecutor` 类的私有状态区（`private var activeCancellationTokens` 附近，约 `MaintenanceExecutor.swift:43`）加：

```swift
    /// 当前 job 并发批里挂起等待 sudo 重试的步骤（runJob 结束时结算）。
    private var sudoPendingSteps: [UpgradeStep] = []
```

在 `markCancelled`（约 `:877`）之后加：

```swift
    private func markNeedsSudo(_ step: UpgradeStep) {
        guard let packageID = step.packageID, let packageName = step.packageName else { return }
        packageProgress[packageID] = PackageUpgradeProgress(
            packageID: packageID,
            packageName: packageName,
            status: .needsSudo,
            detail: "等待管理员授权升级"
        )
    }
```

- [ ] **Step 4: 新增 runSudoRetryBatch 方法**

在 `cleanupStaleBrewCaskIfNeeded`（约 `:624`）之前插入：

```swift
    /// sudo 批次重试：把所有 needsSudo 的 cask 合并成一条 osascript，
    /// 弹一次系统原生密码框串行跑完，按 __RC__ 标记回填每个包状态。
    /// 密码由 macOS SecurityServer 处理，本进程绝不接触。
    private struct SudoRetryOutcome: Hashable {
        var step: UpgradeStep
        var exitCode: Int32
        var outputSegment: String
    }

    private func runSudoRetryBatch(
        jobID id: UUID,
        steps: [UpgradeStep],
        token: CommandCancellationToken
    ) async {
        guard !steps.isEmpty else { return }

        // 1. 解析 brew 绝对路径与最小环境（CommandRunner.processEnvironment 是 private，
        //    这里只取 PATH/HOME 透传给 root shell）。
        guard let brewPath = try? await requireCommand("brew") else {
            for step in steps {
                markFailed(step, analysis: FailureAnalysis(
                    summary: "未找到 brew 命令，无法请求管理员授权升级。",
                    suggestion: "请确认 Homebrew 已安装，然后重试。",
                    action: .rescan,
                    copyText: "",
                    command: step.command.display
                ))
            }
            return
        }
        let pathEnv = CommandRunner.defaultPath
        let homeEnv = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()

        // 2. 按包名顺序拼脚本。
        let packageNames = steps.compactMap { $0.packageName }
        let script = SudoScriptBuilder.script(brewPath: brewPath, packageNames: packageNames, pathEnv: pathEnv, homeEnv: homeEnv)
        let args = SudoScriptBuilder.osaArguments(script)

        updateJob(id) {
            $0.log.append(LogLine(stream: "system", text: "sudo 批次：osascript 提权执行 \(packageNames.count) 个 cask 升级"))
            $0.log.append(LogLine(stream: "system", text: "正在请求管理员密码…"))
        }
        updateUpgradeProgress(currentPackage: "等待管理员授权升级 \(packageNames.count) 个软件")

        // 3. 流式跑 osascript，实时回传日志。
        appendLog(id: id, stream: "command", text: "$ osascript -e <do shell script ... with administrator privileges>（\(packageNames.joined(separator: ", "))）")
        let result = await CommandRunner.runStreamingDetailed(
            "/usr/bin/osascript",
            arguments: args,
            timeout: 7200,
            cancellationToken: token
        ) { [weak self] stream, text in
            Task { @MainActor in
                self?.appendLog(id: id, stream: stream, text: text)
            }
        }

        // 4. 用户取消密码框 / osascript 整体失败：每个包标失败，允许重试。
        if result.terminationReason == .cancelled {
            for step in steps { markCancelled(step) }
            updateJob(id) { $0.log.append(LogLine(stream: "system", text: "sudo 批次已取消")) }
            return
        }
        if result.code != 0 && !result.recentOutput.contains("__RC_") {
            // 整条 osascript 失败（如用户在密码框点取消、密码错误 3 次），无任何包完成。
            for step in steps {
                markFailed(step, analysis: FailureAnalysis(
                    summary: "管理员授权未完成，sudo 升级被取消。",
                    suggestion: "点击「重试」会再次弹出密码框。若密码错误，请确认管理员密码后重试。",
                    action: .promptAdminPassword,
                    copyText: step.command.display,
                    command: step.command.display
                ))
            }
            updateJob(id) { $0.log.append(LogLine(stream: "system", text: "sudo 批次授权未完成，退出码 \(result.code)")) }
            return
        }

        // 5. 解析 __RC__ 标记，回填每个包。
        let parsed = SudoScriptParser.outcomes(in: result.recentOutput, count: packageNames.count)
        for (index, step) in steps.enumerated() {
            let pkgIndex = index + 1
            let outcome = parsed.first { $0.packageIndex == pkgIndex }
                ?? SudoScriptParser.Outcome(packageIndex: pkgIndex, exitCode: -1, outputSegment: "")

            if outcome.exitCode == 0 {
                markSucceeded(step)
                host?.executorRequestsDerivedDataRecompute()
                updateJob(id) { $0.log.append(LogLine(stream: "system", text: "sudo 升级完成：\(step.packageName ?? "")")) }
            } else {
                // 已 sudo 过仍失败：不是密码问题，走常规失败分析，但 action 降级为可重试。
                var analysis = failureAnalysis(command: step.command.display, code: outcome.exitCode, output: outcome.outputSegment)
                if analysis.action == .retryInTerminal {
                    analysis.action = .promptAdminPassword
                }
                failedCountBuffer += 1
                markFailed(step, analysis: analysis)
                host?.executorRequestsDerivedDataRecompute()
                updateJob(id) { $0.log.append(LogLine(stream: "system", text: "sudo 升级失败：\(step.packageName ?? "")，退出码 \(outcome.exitCode)")) }
            }
        }
    }
```

- [ ] **Step 5: 用 failedCountBuffer 解决作用域——改为返回失败计数**

上一步用了 `failedCountBuffer`，但 `runJob` 的 `failedCount` 是局部 inout。把 `runSudoRetryBatch` 的签名改成返回新增失败数：

把 Step 4 方法签名改为：

```swift
    private func runSudoRetryBatch(
        jobID id: UUID,
        steps: [UpgradeStep],
        token: CommandCancellationToken
    ) async -> Int  // 返回 sudo 批新增的失败数
```

把方法体里所有 `failedCountBuffer += 1` 改为 `failedInSudo += 1`，并在方法开头声明 `var failedInSudo = 0`，末尾 `return failedInSudo`。

把循环里那行 `failedCountBuffer += 1` 替换为：

```swift
                failedInSudo += 1
```

并在方法末尾（最后一个 `}` 之前）加：

```swift
        return failedInSudo
```

- [ ] **Step 6: 在 runJob 里接入 sudo 批**

在 `runJob`（`:298-397`）里，`runPackageStepsConcurrently` 调用块**之后**、`activeCancellationTokens[id] = nil` **之前**插入。把：

```swift
        if !shouldStop {
            shouldStop = await runPackageStepsConcurrently(
                jobID: id,
                steps: packageSteps,
                token: token,
                failedCount: &failedCount,
                firstErrorCode: &firstErrorCode,
                completedSteps: &completedSteps
            )
        }

        activeCancellationTokens[id] = nil
```

改为：

```swift
        if !shouldStop {
            shouldStop = await runPackageStepsConcurrently(
                jobID: id,
                steps: packageSteps,
                token: token,
                failedCount: &failedCount,
                firstErrorCode: &firstErrorCode,
                completedSteps: &completedSteps
            )
        }

        // 并发批结束后：若收集到 needsSudo 步骤，弹一次密码框批量重试。
        // 仅当批未被整体取消时进行（取消时 needsSudo 的包已在 handleStepResult 之外标记 cancelled）。
        if !shouldStop && !sudoPendingSteps.isEmpty {
            let pending = sudoPendingSteps
            sudoPendingSteps.removeAll()
            let sudoFailures = await runSudoRetryBatch(jobID: id, steps: pending, token: token)
            failedCount += sudoFailures
            if sudoFailures > 0 && firstErrorCode == nil {
                firstErrorCode = 1
            }
        } else {
            sudoPendingSteps.removeAll()
        }

        activeCancellationTokens[id] = nil
```

- [ ] **Step 7: 处理并发批取消时 needsSudo 包的标记**

当 `shouldStop`（并发批被取消）时，`sudoPendingSteps` 里可能还有挂起的包——它们应标记为 cancelled 而非留 needsSudo。把上一步的 `else` 分支改为：

```swift
        } else {
            // 批被取消：挂起的 needsSudo 包按取消处理。
            for step in sudoPendingSteps { markCancelled(step) }
            sudoPendingSteps.removeAll()
        }
```

- [ ] **Step 8: 编译验证**

Run: `bash scripts/build-native.sh 2>&1 | tail -8`
Expected: 构建成功，无 error。常见编译问题：
- `PackageUpgradeStatus` 别处的 switch 缺 `.needsSudo` → 按 Task 1 Step 5 处理。
- `FailureActionType` 别处的 switch 缺 `.promptAdminPassword` → 同样补 case。
- `failedInSudo` 未声明 → 确认 Step 5 已加。

- [ ] **Step 9: 跑全部单测，确认无回归**

Run: `bash scripts/test-native.sh 2>&1 | tail -15`
Expected: 全绿，所有现有测试通过（sudo 编排逻辑不进单测，纯函数已由 Task 2-4 覆盖）。

- [ ] **Step 10: Commit**

```bash
git add native/MacSoftwareSteward/MaintenanceExecutor.swift scripts/build-native.sh
git commit -m "feat(sudo): wire sudo retry batch into MaintenanceExecutor (one password prompt per job)"
```

---

### Task 6: 更新设计文档的安全规则澄清

**Files:**
- Modify: `docs/superpowers/specs/2026-06-12-automation-steward-major-enhancement-design.md:100`

- [ ] **Step 1: 读现有规则行**

Run: `sed -n '98,102p' docs/superpowers/specs/2026-06-12-automation-steward-major-enhancement-design.md`
Expected: 看到 `5. IF 升级项需要 \`sudo\`、... THEN 系统 SHALL NOT 自动执行该升级。`

- [ ] **Step 2: 在规则下方追加澄清段**

在该条验收标准（第 100 行那条）之后另起一段插入：

```markdown
> **澄清（2026-07-28 sudo cask auto-elevation 设计补充）：** 本规则的「sudo」指**升级项本身在风险评估阶段需要提权**。对已通过风险评估、被批准执行的升级，若执行阶段因 macOS 密码策略卡住，允许通过 `osascript with administrator privileges` 弹原生密码框提权——这是执行方式，不改变风险评估结论。详见 `docs/superpowers/specs/2026-07-28-sudo-cask-auto-elevation-design.md`。
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-06-12-automation-steward-major-enhancement-design.md
git commit -m "docs(spec): clarify risk-sudo vs execution-sudo boundary for auto-elevation"
```

---

### Task 7: 手测脚本

**Files:**
- Create: `scripts/test-sudo-retry.sh`

> osascript 密码框无法自动化，此脚本为**发布前手测清单**，不进 CI。

- [ ] **Step 1: 创建手测脚本**

创建 `scripts/test-sudo-retry.sh`：

```sh
#!/usr/bin/env bash
# 手测：sudo cask 自动提权。不进 CI（osascript 弹框无法自动化）。
#
# 用途：验证「brew upgrade --cask 卡 sudo 时，app 弹一次密码框批量重试」端到端可用。
#
# 前置：
#   1. 已构建 app：bash scripts/build-native.sh
#   2. 准备至少一个会触发 sudo 的 cask（装到 /usr/local 等需 root 写入位置）。
#
# 步骤：
#   - 打开 Mac 软件管家
#   - 在一键升级里选中会卡 sudo 的 cask，执行
#   - 观察：
#     a) 该包先显示「等待管理员授权」（needsSudo）
#     b) 系统弹出原生密码框（一次）
#     c) 输入密码后升级完成，状态变「完成」
#     d) 日志含「sudo 批次：osascript 提权执行 N 个 cask」与 __RC__ 标记
#   - 负向：在密码框点取消 → 该包失败，action 允许「重试」（再点再弹框），而非「去终端」
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT_DIR/build/MacSoftwareSteward.app"

if [ ! -d "$APP" ]; then
  echo "请先构建：bash scripts/build-native.sh" >&2
  exit 1
fi

echo "==> 启动 $APP 进行手测"
echo "    清单见此脚本顶部注释。"
open "$APP"
```

- [ ] **Step 2: 赋可执行权限**

Run: `chmod +x scripts/test-sudo-retry.sh`

- [ ] **Step 3: Commit**

```bash
git add scripts/test-sudo-retry.sh
git commit -m "test(sudo): add manual test script for sudo cask auto-elevation"
```

---

## Self-Review Notes

**Spec coverage:**
- 目标/Non-Goals → 无对应代码任务（声明性），✓ 不需要任务。
- 触发时机（并发批后收集） → Task 5 Step 2/6 ✓
- 命令拼接（`;` + `__RC__` + 绝对路径 + 环境透传） → Task 3 ✓
- 日志实时回传（复用 runStreamingDetailed + appendLog） → Task 5 Step 4 ✓
- 数据流（needsSudo / promptAdminPassword / SudoRetryBatch） → Task 1 ✓
- requiresSudo 识别 → Task 2 ✓
- runSudoRetryBatch → Task 5 Step 4/5 ✓
- 并发批失败隔离（`;` 非 `&&`） → Task 3 builder + Task 4 parser 双重保证 ✓
- 边界（取消/密码错/超时/空批） → Task 5 Step 4 各分支 ✓
- needsSudo 不计 failedCount → Task 5 Step 2（挂起）+ Step 6（sudo 批返回值才累加） ✓
- 安全边界澄清 → Task 6 ✓
- 测试策略（纯函数单测 + 手测） → Task 2/3/4 + Task 7 ✓

**Type consistency:**
- `SudoScriptBuilder.script(brewPath:packageNames:pathEnv:homeEnv:)` —— Task 3 定义，Task 5 Step 4 调用，签名一致 ✓
- `SudoScriptBuilder.osaArguments(_:)` —— 一致 ✓
- `SudoScriptParser.Outcome(packageIndex:exitCode:outputSegment:)` —— Task 4 定义，Task 5 Step 4 引用 ✓
- `SudoScriptParser.outcomes(in:count:)` —— 一致 ✓
- `UpgradeFailureAnalyzer.requiresSudo(in:)` —— Task 2 定义，Task 5 Step 2 调用 ✓
- `FailureAnalysis(summary:suggestion:action:copyText:command:)` —— 与 `MaintenanceExecutor.swift:1120` 现有定义一致 ✓
- `markNeedsSudo` / `markSucceeded` / `markCancelled` / `markFailed` —— Task 5 引用，与现有 `:827-888` 签名一致 ✓
- `CommandRunner.defaultPath`（public）—— Task 5 Step 4 引用，与 `CommandRunner.swift:94` 一致 ✓
- `CommandRunner.runStreamingDetailed(_:arguments:timeout:cancellationToken:environmentOverlay:onOutput:)` —— 与 `:197` 签名一致 ✓

**无占位符**：所有代码块为完整可编译片段，命令带预期输出。
