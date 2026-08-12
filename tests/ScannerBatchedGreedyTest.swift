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
