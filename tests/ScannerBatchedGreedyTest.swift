import Foundation

@main
struct ScannerBatchedGreedyTest {
    static func main() {
        testSplitIntoBatches()
        testAccumulateAllSucceeded()
        testAccumulateOneBatchFailed()
        testAccumulateBudgetExhausted()
        testAccumulateAllFailed()
        testGreedyBatchSucceededOutdatedFound()
        testGreedyBatchSucceededNothingOutdated()
        testGreedyBatchSucceededSignaled()
        testGreedyBatchSucceededEmptyStdout()
        testGreedyBatchSucceededGarbage()
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

    // MARK: - greedyBatchSucceeded
    // `brew outdated` 在发现可升级项时会以 exit code 1 退出（正常结果，非错误），
    // JSON 仍完整输出到 stdout。判定"一批是否成功"必须据此，而非 `code == 0`。

    static func testGreedyBatchSucceededOutdatedFound() {
        // 核心回归点：exit 1 + 合法 JSON（含可升级 cask）必须判为成功。
        // 旧实现按 r.ok(code==0) 判定，会把含可升级项的整批误判失败 → 系统性漏报。
        let json = #"{"formulae":[],"casks":[{"name":"1password","current_version":"2"}]}"#
        let r = CommandResult(ok: false, code: 1, stdout: json, stderr: "")
        precondition(BrewBatchedGreedy.greedyBatchSucceeded(r), "exit 1 + 合法 JSON（有可升级项）应为成功")
    }

    static func testGreedyBatchSucceededNothingOutdated() {
        let json = #"{"formulae":[],"casks":[]}"#
        let r = CommandResult(ok: true, code: 0, stdout: json, stderr: "")
        precondition(BrewBatchedGreedy.greedyBatchSucceeded(r), "exit 0 + 合法 JSON（无可升级项）应为成功")
    }

    static func testGreedyBatchSucceededSignaled() {
        // 超时被 SIGTERM 杀死：即便 stdout 有半截内容也必须判失败。
        let r = CommandResult(ok: false, code: 15, stdout: "", stderr: "", terminationReason: .uncaughtSignal)
        precondition(!BrewBatchedGreedy.greedyBatchSucceeded(r), "被信号杀死应判失败")
    }

    static func testGreedyBatchSucceededEmptyStdout() {
        // 真正失败（如 cask 名错误）：错误在 stderr，stdout 为空、无 JSON。
        let r = CommandResult(ok: false, code: 1, stdout: "", stderr: "Error: Cask 'foo' is unavailable")
        precondition(!BrewBatchedGreedy.greedyBatchSucceeded(r), "stdout 空（无 JSON）应判失败")
    }

    static func testGreedyBatchSucceededGarbage() {
        let r = CommandResult(ok: false, code: 1, stdout: "Error: something broke", stderr: "Error: something broke")
        precondition(!BrewBatchedGreedy.greedyBatchSucceeded(r), "stdout 非 JSON 应判失败")
    }
}
