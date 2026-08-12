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
