# greedy 扫描分批增量 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `Scanner.scanBrew` 的单发 `brew outdated --greedy`（120s 全有或全无）改成按 cask 分批 + 总预算 180s，慢批超时只丢该批、返回部分结果，未扫到的 cask 进 `uncheckedCasks` 并在 UI 给软诊断。

**Architecture:** 纯逻辑（切批 + 归集）抽到独立的 `BrewBatchedGreedy.swift`（仅依赖 Foundation，单测友好）；`Scanner.scanBrew` 负责串行调度 + 预算 + 调用纯函数；`SourceDiagnostics.diagnoseBrew` 新增"部分完成"分支；`BrewScan` 新增 `uncheckedCasks` 字段驱动该分支。

**Tech Stack:** Swift（macOS 14+），Foundation `Process`，现有 `scripts/test-native.sh`（每个测试单独 `xcrun swiftc` 编译）。

**Spec:** `docs/superpowers/specs/2026-08-12-greedy-scan-batched-incremental-design.md`

## Global Constraints

- 常量（最终值，逐字照抄）：`greedyBatchSize = 5`、`greedyTotalBudget = 180`s、`greedyPerBatchCap = 60`s、`greedyBudgetFloor = 5`s。
- 正确性红线：unchecked 的 cask **不得**被当作"最新"（不进 outdated 条目 → `mergeBrew` 不会标 outdated，但名字必须进 `uncheckedCasks`）。
- error 契约：零批成功 → `error` 写含 "被终止/SIGTERM/超时" 关键字的友好串；至少一批成功 → `error` 留空，由 `uncheckedCasks` 驱动软诊断。
- 向后兼容：新字段/新参数一律带默认值，不破坏既有构造点与调用点。
- 本机构建需 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`（GUI 用 SwiftUIMacros）。

## File Structure

- **Create** `native/MacSoftwareSteward/BrewBatchedGreedy.swift` — 纯逻辑：`splitIntoBatches`、`BatchOutcome`、`accumulate`。仅 Foundation，无 brew 依赖。
- **Create** `tests/ScannerBatchedGreedyTest.swift` — 上述纯函数的单测。
- **Modify** `native/MacSoftwareSteward/Models.swift` — `BrewScan` 增 `uncheckedCasks`。
- **Modify** `native/MacSoftwareSteward/SourceDiagnostics.swift` — `diagnoseBrew` 增 `uncheckedCasks` 参数 + "部分完成"分支。
- **Modify** `native/MacSoftwareSteward/Scanner.swift` — 常量、`scanCasksGreedyBatched`、`scanBrew` 拆分与重排、删除无用的 `outdatedTimeout`。
- **Modify** `native/MacSoftwareSteward/Views/UpdatesView.swift` — 传 `uncheckedCasks` 给 `diagnoseBrew`。
- **Modify** `tests/BrewScanErrorFormattingTest.swift` — 新增 `testDiagnoseBrewPartialBranch`。
- **Modify** `scripts/test-native.sh` — 注册 `ScannerBatchedGreedyTest`。

---

### Task 1: 纯分批逻辑（`BrewBatchedGreedy.swift`）+ 单测

**Files:**
- Create: `native/MacSoftwareSteward/BrewBatchedGreedy.swift`
- Create: `tests/ScannerBatchedGreedyTest.swift`
- Modify: `scripts/test-native.sh`

**Interfaces:**
- Produces: `BrewBatchedGreedy.splitIntoBatches(_ items: [String], size: Int) -> [[String]]`、`BrewBatchedGreedy.BatchOutcome`（`.succeeded([[String: Any]])` / `.failed`）、`BrewBatchedGreedy.accumulate(installedCasks: [String], batchResults: [(batch: [String], outcome: BatchOutcome)]) -> (outdated: [[String: Any]], unchecked: [String])`。Task 3 的 `scanCasksGreedyBatched` 消费这些。

- [ ] **Step 1: 写失败测试**

创建 `tests/ScannerBatchedGreedyTest.swift`：

```swift
import Foundation

@main
struct ScannerBatchedGreedyTest {
    static func main() {
        testSplitIntoBatches()
        testAccumulateAllSucceeded()
        testAccumulateOneBatchFailed()
        testAccumulateBudgetExhausted()
        testAccumulateAllFailed()
        print("ScannerBatchedGreedyTest passed")
    }

    static func testSplitIntoBatches() {
        precondition(BrewBatchedGreedy.splitIntoBatches([], size: 5) == [], "空列表应返回空批")
        precondition(BrewBatchedGreedy.splitIntoBatches(["a","b","c","d","e"], size: 5) == [["a","b","c","d","e"]], "刚好整除")
        precondition(BrewBatchedGreedy.splitIntoBatches(["a","b","c","d","e","f"], size: 5) == [["a","b","c","d","e"], ["f"]], "余数成末批")
        precondition(BrewBatchedGreedy.splitIntoBatches(["a","b"], size: 5) == [["a","b"]], "size 大于总数应整批")
        precondition(BrewBatchedGreedy.splitIntoBatches(["a","b","c"], size: 1) == [["a"],["b"],["c"]], "size=1 逐个成批")
        precondition(BrewBatchedGreedy.splitIntoBatches(["a","b"], size: 0) == [["a","b"]], "size<=0 视为整批")
    }

    static func testAccumulateAllSucceeded() {
        let r = BrewBatchedGreedy.accumulate(
            installedCasks: ["a","b","c"],
            batchResults: [
                (["a","b"], .succeeded([["name":"a","current_version":"2"]])),
                (["c"], .succeeded([]))
            ]
        )
        precondition(r.outdated.count == 1, "应合并 1 条 outdated，实际 \(r.outdated.count)")
        precondition((r.outdated[0]["name"] as? String) == "a", "outdated 名应为 a")
        precondition(r.unchecked.isEmpty, "全成功时 unchecked 应为空")
    }

    static func testAccumulateOneBatchFailed() {
        let r = BrewBatchedGreedy.accumulate(
            installedCasks: ["a","b","c","d","e"],
            batchResults: [
                (["a","b","c","d","e"], .failed),
            ]
        )
        precondition(r.outdated.isEmpty, "失败批不应产出 outdated")
        precondition(r.unchecked == ["a","b","c","d","e"], "整批失败时全部 unchecked")
    }

    static func testAccumulateBudgetExhausted() {
        // 第二批因预算耗尽没跑 → 不在 batchResults 中 → 计入 unchecked
        let r = BrewBatchedGreedy.accumulate(
            installedCasks: ["a","b","c","d","e","f","g","h","i","j"],
            batchResults: [
                (["a","b","c","d","e"], .succeeded([["name":"a"]])),
                // 第二批 ["f","g","h","i","j"] 未跑
            ]
        )
        precondition(r.outdated.count == 1, "应仅 1 条 outdated")
        precondition(r.unchecked == ["f","g","h","i","j"], "未跑批次应进 unchecked，实际 \(r.unchecked)")
    }

    static func testAccumulateAllFailed() {
        let r = BrewBatchedGreedy.accumulate(
            installedCasks: ["a","b","c"],
            batchResults: [
                (["a","b"], .failed),
                (["c"], .failed),
            ]
        )
        precondition(r.outdated.isEmpty, "全失败应无 outdated")
        precondition(Set(r.unchecked) == Set(["a","b","c"]), "全失败应全部 unchecked")
    }
}
```

- [ ] **Step 2: 注册到测试脚本**

在 `scripts/test-native.sh` 中，紧挨 `run_test BrewScanErrorFormattingTest ...` 块之后追加（依赖列表只含纯逻辑文件 + Foundation）：

```bash
run_test ScannerBatchedGreedyTest \
  "$SRC/BrewBatchedGreedy.swift" \
  "$TESTS/ScannerBatchedGreedyTest.swift"
```

- [ ] **Step 3: 运行测试，确认失败**

Run: `bash scripts/test-native.sh 2>&1 | grep -A3 ScannerBatchedGreedyTest`
Expected: 编译失败，`cannot find 'BrewBatchedGreedy' in scope`（实现尚未创建）。

- [ ] **Step 4: 写实现**

创建 `native/MacSoftwareSteward/BrewBatchedGreedy.swift`：

```swift
import Foundation

/// Homebrew greedy cask 扫描的分批增量纯逻辑（无 brew 依赖，便于单测）。
/// 调度与超时由 `Scanner.scanCasksGreedyBatched` 负责；本类型只做切批与归集。
enum BrewBatchedGreedy {
    /// 一批 greedy 检查的结果：成功（带回该批的 outdated cask 条目）或失败（超时/出错）。
    enum BatchOutcome {
        case succeeded([[String: Any]])
        case failed
    }

    /// 把列表切成固定大小的批。`size <= 0` 视为整批（不切）。
    static func splitIntoBatches(_ items: [String], size: Int) -> [[String]] {
        guard size > 0 else { return items.isEmpty ? [] : [items] }
        guard !items.isEmpty else { return [] }
        var batches: [[String]] = []
        var idx = 0
        while idx < items.count {
            let end = min(idx + size, items.count)
            batches.append(Array(items[idx..<end]))
            idx = end
        }
        return batches
    }

    /// 归集各批结果为 (outdated 条目, 未完成 cask 名单)。
    /// - 失败批的 cask → unchecked
    /// - 未在 batchResults 中出现的 cask（预算耗尽、未跑到）→ unchecked
    /// - 一个 cask 只会在一个批次里（由调用方保证），故两来源不会重复。
    static func accumulate(
        installedCasks: [String],
        batchResults: [(batch: [String], outcome: BatchOutcome)]
    ) -> (outdated: [[String: Any]], unchecked: [String]) {
        var outdated: [[String: Any]] = []
        var unchecked: [String] = []
        let covered = Set(batchResults.flatMap { $0.batch })
        for name in installedCasks where !covered.contains(name) {
            unchecked.append(name)
        }
        for entry in batchResults {
            switch entry.outcome {
            case .succeeded(let entries):
                outdated.append(contentsOf: entries)
            case .failed:
                unchecked.append(contentsOf: entry.batch)
            }
        }
        return (outdated, unchecked)
    }
}
```

- [ ] **Step 5: 运行测试，确认通过**

Run: `bash scripts/test-native.sh 2>&1 | tail -3`
Expected: `All native tests passed.`（含 `ScannerBatchedGreedyTest passed`）

- [ ] **Step 6: 提交**

```bash
git add native/MacSoftwareSteward/BrewBatchedGreedy.swift tests/ScannerBatchedGreedyTest.swift scripts/test-native.sh
git commit -m "feat(scan): 抽出 greedy 分批纯逻辑 BrewBatchedGreedy + 单测"
```

---

### Task 2: 诊断"部分完成"分支

**Files:**
- Modify: `native/MacSoftwareSteward/SourceDiagnostics.swift`（`diagnoseBrew`）
- Modify: `tests/BrewScanErrorFormattingTest.swift`（新增 `testDiagnoseBrewPartialBranch`）

**Interfaces:**
- Produces: `SourceDiagnosticEngine.diagnoseBrew(available:error:uncheckedCasks:)`（新参 `uncheckedCasks: [String] = []`，默认空，向后兼容）。Task 3 的 `UpdatesView` 调用点传入 `brew.uncheckedCasks`。

- [ ] **Step 1: 写失败测试**

在 `tests/BrewScanErrorFormattingTest.swift` 的 `main()` 里加一行调用，并新增测试方法：

```swift
    static func main() {
        testBrewCommandErrorSignalAware()
        testDiagnoseBrewTimeoutBranch()
        testDiagnoseBrewPartialBranch()      // 新增
        print("BrewScanErrorFormattingTest passed")
    }
```

新增方法（与 `testDiagnoseBrewTimeoutBranch` 同级）：

```swift
    /// diagnoseBrew 对"部分完成"（error 空 + 有未检 cask）给出软诊断，
    /// 不建议 brew doctor、不当作整盘失败。
    static func testDiagnoseBrewPartialBranch() {
        // error 空 + uncheckedCasks 非空 → 部分完成
        let partial = SourceDiagnosticEngine.diagnoseBrew(
            available: true, error: "", uncheckedCasks: ["microsoft-word", "microsoft-excel", "foo"]
        )
        guard let d = partial else { preconditionFailure("部分完成应产出诊断") }
        precondition(d.reason.contains("未完成"), "reason 应点明未完成，实际：\(d.reason)")
        precondition(d.terminalCommand == nil, "部分完成不应建议 brew doctor")
        precondition(!d.suggestion.contains("brew doctor"), "部分完成建议不应含 brew doctor")

        // error 非空（整盘超时）时，uncheckedCasks 不改变优先级：仍走 error 分支
        let timeout = SourceDiagnosticEngine.diagnoseBrew(
            available: true,
            error: "brew outdated 进程被终止 (SIGTERM)，可能是命令耗时过长被中断，请稍后重试。",
            uncheckedCasks: ["microsoft-word"]
        )
        precondition(timeout?.reason.contains("超时") == true, "error 非空时应优先走超时分支")

        // 全成功（error 空 + uncheckedCasks 空）→ 无诊断
        let ok = SourceDiagnosticEngine.diagnoseBrew(available: true, error: "", uncheckedCasks: [])
        precondition(ok == nil, "全成功应无诊断")
    }
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `bash scripts/test-native.sh 2>&1 | grep -A2 BrewScanErrorFormattingTest`
Expected: 编译失败，`Incorrect argument label` / `extraneous argument 'uncheckedCasks'`（签名尚未加）。

- [ ] **Step 3: 改签名 + 加分支**

`native/MacSoftwareSteward/SourceDiagnostics.swift`：把 `diagnoseBrew` 第一行签名改为：

```swift
    static func diagnoseBrew(available: Bool, error: String, uncheckedCasks: [String] = []) -> SourceDiagnosis? {
```

并把 `if !available { ... }` 之后那条 `if error.isEmpty { return nil }`（约第 44 行）替换为：

```swift
        if error.isEmpty {
            // 全成功：无诊断；部分完成（有未检 cask）：软诊断，不建议 brew doctor。
            guard !uncheckedCasks.isEmpty else { return nil }
            let preview = uncheckedCasks.prefix(3).joined(separator: "、")
            return SourceDiagnosis(
                reason: "Homebrew 部分检查未完成",
                suggestion: "另有 \(uncheckedCasks.count) 个 cask（如 \(preview)）未完成更新检查，通常是一次性网络拉取较慢。已扫到的结果仍可用；建议稍后重新扫描补齐。",
                technicalDetails: "未完成检查的 cask：\(uncheckedCasks.sorted().joined(separator: ", "))",
                action: .rescan,
                actionLabel: "重新扫描",
                terminalCommand: nil,
                terminalHint: nil
            )
        }
```

（`error` 非空时继续走下方既有的 timeout/connection/permission/notfound/sigterm/通用分支——保持不变。）

- [ ] **Step 4: 运行测试，确认通过**

Run: `bash scripts/test-native.sh 2>&1 | tail -3`
Expected: `All native tests passed.`（含 `BrewScanErrorFormattingTest passed`）

- [ ] **Step 5: 提交**

```bash
git add native/MacSoftwareSteward/SourceDiagnostics.swift tests/BrewScanErrorFormattingTest.swift
git commit -m "feat(scan): diagnoseBrew 增“部分完成”软诊断分支"
```

---

### Task 3: 接入 scanBrew（拆分 / 串行分批 / 预算 / error 契约）

**Files:**
- Modify: `native/MacSoftwareSteward/Models.swift`（`BrewScan` 增字段）
- Modify: `native/MacSoftwareSteward/Scanner.swift`（常量 + `scanCasksGreedyBatched` + `scanBrew` 重排 + 删 `outdatedTimeout`）
- Modify: `native/MacSoftwareSteward/Views/UpdatesView.swift`（传 `uncheckedCasks`）

**Interfaces:**
- Consumes: Task 1 的 `BrewBatchedGreedy`、Task 2 的 `diagnoseBrew(uncheckedCasks:)`。
- Produces: `BrewScan.uncheckedCasks: [String]`（默认 `[]`）。

- [ ] **Step 1: Models 增字段**

`native/MacSoftwareSteward/Models.swift` 的 `struct BrewScan`（约 192 行），在 `var casks: [BrewPackage]` 之后加：

```swift
    /// greedy 分批检查中未完成（超时/失败/预算耗尽未跑）的 cask 名。
    /// 不能被当作"最新"——否则等于漏报。供 UI 诊断"部分完成，建议重试"。
    var uncheckedCasks: [String] = []
```

（默认值 `[]`，现有所有 `BrewScan(...)` 构造点无须改动。）

- [ ] **Step 2: Scanner 增常量与 greedy 分批调度器**

在 `Scanner.swift` 的 `enum SoftwareScanner {` 内（`scanBrew` 之前）加常量与私有调度方法：

```swift
    // MARK: - greedy cask 分批常量
    private static let greedyBatchSize = 5
    private static let greedyTotalBudget: TimeInterval = 180
    private static let greedyPerBatchCap: TimeInterval = 60
    private static let greedyBudgetFloor: TimeInterval = 5

    /// greedy cask 检查：按已装 cask 分批、串行、在总预算内跑。
    /// 返回 (outdated 条目, 未完成 cask 名单, 是否至少有一批成功)。
    /// 至少一批成功 → 上层 error 留空、由 unchecked 驱动软诊断；
    /// 零批成功 → 上层 error 写友好超时串。
    private static func scanCasksGreedyBatched(
        brewPath: String,
        installedCasks: [String]
    ) async -> (outdated: [[String: Any]], unchecked: [String], anySucceeded: Bool) {
        let batches = BrewBatchedGreedy.splitIntoBatches(installedCasks, size: greedyBatchSize)
        var batchResults: [(batch: [String], outcome: BrewBatchedGreedy.BatchOutcome)] = []
        let start = Date()
        var anySucceeded = false
        for batch in batches {
            let remaining = greedyTotalBudget - Date().timeIntervalSince(start)
            if remaining < greedyBudgetFloor {
                break  // 预算耗尽：剩余批次不跑，其 cask 由 accumulate 计入 unchecked
            }
            let batchTimeout = min(greedyPerBatchCap, remaining)
            let r = await CommandRunner.run(
                brewPath,
                arguments: ["outdated", "--greedy", "--json=v2", "--cask"] + batch,
                timeout: batchTimeout
            )
            if r.ok {
                anySucceeded = true
                batchResults.append((batch, .succeeded(parseBrewOutdated(r.stdout).casks)))
            } else {
                batchResults.append((batch, .failed))
            }
        }
        let acc = BrewBatchedGreedy.accumulate(installedCasks: installedCasks, batchResults: batchResults)
        return (acc.outdated, acc.unchecked, anySucceeded)
    }
```

- [ ] **Step 3: 改 scanBrew —— outdated 任务按 includeGreedy 分叉**

`Scanner.swift` 的 `scanBrew`：删掉这两行（约 217-220）：

```swift
        let timeout: TimeInterval = 30
        // outdated --greedy 会联网逐个检查每个 cask 的最新版，耗时远超本地命令，
        // 单独给足时间，避免 30s 超时把 brew 进程中途 SIGTERM（这正是"Homebrew 扫描遇到错误"的根因）。
        let outdatedTimeout: TimeInterval = 120
```

替换为（保留 `timeout`，删 `outdatedTimeout` 及其注释）：

```swift
        let timeout: TimeInterval = 30
```

把任务组里的 `outdated` 任务（约 235-241 行）：

```swift
            group.addTask {
                BrewTaskOutput(tag: "outdated", result: await CommandRunner.run(
                    brewPath,
                    arguments: ["outdated", "--json=v2"] + (includeGreedy ? ["--greedy"] : []),
                    timeout: outdatedTimeout
                ))
            }
```

替换为按 `includeGreedy` 分叉（greedy 只查 formulae，casks 留给阶段二的分批）：

```swift
            if includeGreedy {
                // casks 走阶段二分批（scanCasksGreedyBatched）；这里只查 formulae（本地比对，快）。
                group.addTask {
                    BrewTaskOutput(tag: "formulaOutdated", result: await CommandRunner.run(
                        brewPath,
                        arguments: ["outdated", "--json=v2", "--formula"],
                        timeout: timeout
                    ))
                }
            } else {
                // 非 greedy：formulae + casks 一次本地比对即可，不分批。
                group.addTask {
                    BrewTaskOutput(tag: "outdated", result: await CommandRunner.run(
                        brewPath,
                        arguments: ["outdated", "--json=v2"],
                        timeout: timeout
                    ))
                }
            }
```

- [ ] **Step 4: 改 scanBrew —— 解析与 greedy 分批阶段、error 契约**

把这段（约 261-289 行）：

```swift
        let formulaListResult = installedBrewPackages(primary: formulaList)
        let caskListResult = installedBrewPackages(primary: caskList, fallback: caskNameList)
        let installedFormulae = formulaListResult.packages
        let installedCasks = caskListResult.packages
        let outdatedPayload = parseBrewOutdated(outdated.stdout)
        let formulae = mergeBrew(installed: installedFormulae, outdated: outdatedPayload.formulae, kind: "formula")
        let caskMetadataByName = await scanCaskMetadata(
            brewPath: brewPath,
            installedCasks: installedCasks
        )
        let caskAdvisoriesByName = await caskUpdateAdvisories(
            installedCasks: installedCasks,
            outdated: outdatedPayload.casks,
            metadataByName: caskMetadataByName,
            networkPolicy: regularAppNetworkPolicy
        )
        let casks = mergeBrew(
            installed: installedCasks,
            outdated: outdatedPayload.casks,
            kind: "cask",
            caskMetadataByName: caskMetadataByName,
            caskAdvisoriesByName: caskAdvisoriesByName
        )

        let errors = [
            formulaListResult.error,
            caskListResult.error,
            brewCommandError(tagged: "brew outdated", outdated)
        ]
            .filter { !$0.isEmpty }
```

替换为：

```swift
        let formulaListResult = installedBrewPackages(primary: formulaList)
        let caskListResult = installedBrewPackages(primary: caskList, fallback: caskNameList)
        let installedFormulae = formulaListResult.packages
        let installedCasks = caskListResult.packages

        // formulae/casks 的 outdated 来源按 includeGreedy 分叉：
        //  - greedy：formulae 来自 --formula 调用；casks 来自阶段二分批（部分结果 + unchecked）
        //  - 非 greedy：一次 --json=v2 同时给 formulae 和 casks
        let formulaeOutdatedEntries: [[String: Any]]
        let casksOutdatedEntries: [[String: Any]]
        var uncheckedCasks: [String] = []
        var outdatedError: String

        if includeGreedy {
            let fo = results["formulaOutdated"] ?? missingResult
            formulaeOutdatedEntries = parseBrewOutdated(fo.stdout).formulae
            let greedy = await scanCasksGreedyBatched(
                brewPath: brewPath,
                installedCasks: installedCasks.map(\.name)
            )
            casksOutdatedEntries = greedy.outdated
            uncheckedCasks = greedy.unchecked
            // 契约：零批成功才警报（走"更新检查超时"诊断）；至少一批成功 → 留空，由 unchecked 驱动软诊断。
            outdatedError = greedy.anySucceeded
                ? ""
                : "brew outdated --greedy 进程被终止 (SIGTERM)，可能是命令耗时过长被中断，请稍后重试。"
        } else {
            let o = results["outdated"] ?? missingResult
            let p = parseBrewOutdated(o.stdout)
            formulaeOutdatedEntries = p.formulae
            casksOutdatedEntries = p.casks
            outdatedError = brewCommandError(tagged: "brew outdated", o)
        }

        let formulae = mergeBrew(installed: installedFormulae, outdated: formulaeOutdatedEntries, kind: "formula")
        let caskMetadataByName = await scanCaskMetadata(
            brewPath: brewPath,
            installedCasks: installedCasks
        )
        let caskAdvisoriesByName = await caskUpdateAdvisories(
            installedCasks: installedCasks,
            outdated: casksOutdatedEntries,
            metadataByName: caskMetadataByName,
            networkPolicy: regularAppNetworkPolicy
        )
        let casks = mergeBrew(
            installed: installedCasks,
            outdated: casksOutdatedEntries,
            kind: "cask",
            caskMetadataByName: caskMetadataByName,
            caskAdvisoriesByName: caskAdvisoriesByName
        )

        let errors = [
            formulaListResult.error,
            caskListResult.error,
            outdatedError
        ]
            .filter { !$0.isEmpty }
```

- [ ] **Step 5: scanBrew 返回 uncheckedCasks**

把 `scanBrew` 末尾的 `return BrewScan(...)`（约 292-301 行）加一个字段：

```swift
        return BrewScan(
            available: true,
            path: brewPath,
            prefix: results["prefix"]?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            version: results["version"]?.stdout.components(separatedBy: .newlines).first ?? "",
            error: errors.joined(separator: "\n"),
            includeGreedy: includeGreedy,
            formulae: formulae,
            casks: casks,
            uncheckedCasks: uncheckedCasks
        )
```

（注：`results["version"]` / `results["prefix"]` 仍在阶段一任务组里，未改动。）

- [ ] **Step 6: UpdatesView 传 uncheckedCasks**

`native/MacSoftwareSteward/Views/UpdatesView.swift`（约 58-61 行）：

```swift
           let diagnosis = SourceDiagnosticEngine.diagnoseBrew(
               available: brew.available,
               error: brew.error,
               uncheckedCasks: brew.uncheckedCasks
           ) {
```

- [ ] **Step 7: 全量测试**

Run: `bash scripts/test-native.sh 2>&1 | tail -5`
Expected: `All native tests passed.`（60+ 项全过，含新增 2 项）。

- [ ] **Step 8: 构建 app**

Run: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && bash scripts/build-native.sh 2>&1 | tail -5`
Expected: 末行打印 `.../build/MacSoftwareSteward.app`，签名 OK。

- [ ] **Step 9: 提交**

```bash
git add native/MacSoftwareSteward/Models.swift native/MacSoftwareSteward/Scanner.swift native/MacSoftwareSteward/Views/UpdatesView.swift
git commit -m "feat(scan): scanBrew greedy 改分批增量，部分超时返回部分结果"
```

---

## Self-Review（写完后自查结果）

**Spec coverage：**
- 拆分 formulae(--formula) + cask 分批 → Task 3 Step 3/4。✓
- 总预算 180s / 单批 60s / 批大小 5 / floor 5s → Task 3 Step 2 常量。✓
- 串行 + 预算耗尽停止 → Task 3 Step 2 (`if remaining < floor { break }`)。✓
- `brew update` 60s 保留、独立于预算 → 不在本次改动范围（既有代码，未触碰）。✓
- `BrewScan.uncheckedCasks` → Task 3 Step 1。✓
- 正确性红线（unchecked 不进 outdated）→ Task 3 Step 4 只把 `greedy.outdated` 喂给 mergeBrew，unchecked 仅进字段。✓
- error 契约（零批成功警报 / 部分成功留空）→ Task 3 Step 4。✓
- 诊断"部分完成"分支 → Task 2。✓
- 纯函数单测（全成功/某批失败/预算耗尽/全失败 + 切批）→ Task 1。✓

**Placeholder scan：** 无 TBD/TODO；每步均含可执行代码或命令。✓

**Type consistency：**
- `BrewBatchedGreedy.BatchOutcome` 在 Task 1 定义，Task 3 Step 2 使用 `.succeeded/.failed`——一致。✓
- `scanCasksGreedyBatched` 返回 `(outdated, unchecked, anySucceeded)`，Task 3 Step 4 解构同名——一致。✓
- `diagnoseBrew(uncheckedCasks:)` Task 2 定义默认 `[]`，Task 3 Step 6 传 `brew.uncheckedCasks`——一致。✓
- `BrewScan.uncheckedCasks` Task 3 Step 1 定义，Step 5 构造、Step 6 读取——一致。✓

**遗留验证（非阻塞，运行时确认）：** 实现完成后，建议在真机触发一次 greedy 扫描（或临时把 `greedyPerBatchCap` 调到 1s）观察：慢批进 unchecked、UI 出"部分完成"卡片。位置过滤器 `--greedy --cask <name>` 对已知 greedy-outdated cask 的命中已在 spec 标注为实现时复核项。
