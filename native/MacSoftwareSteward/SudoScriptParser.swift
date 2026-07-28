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
        if count == 0 { return [] }

        // 先按出现顺序收集所有标记及其位置。标记形如 __RC_2_1__
        var found: [(index: Int, code: Int32, range: Range<String.Index>)] = []
        let pattern = "__RC_(\\d+)_(\\d+)__"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        regex.enumerateMatches(in: output, range: NSRange(location: 0, length: (output as NSString).length)) { match, _, _ in
            guard let match = match, match.numberOfRanges == 3,
                  let indexRange = Range(match.range(at: 1), in: output),
                  let codeRange = Range(match.range(at: 2), in: output),
                  let idx = Int(output[indexRange]),
                  let code = Int32(output[codeRange]),
                  let r = Range(match.range, in: output) else { return }
            found.append((index: idx, code: code, range: r))
        }

        // 按下标建查找表（同下标取第一个出现的）。
        var byIndex: [Int: (code: Int32, range: Range<String.Index>)] = [:]
        for item in found {
            if byIndex[item.index] == nil { byIndex[item.index] = (item.code, item.range) }
        }

        // 1...count 顺序产出；缺失用哨兵。
        // 按标记在原文中的出现顺序排好，用于切分「片段 = 上一个标记之后 → 本标记之前」。
        let ordered = found.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var results: [Outcome] = []
        for i in 1...count {
            if let entry = byIndex[i] {
                // 片段：上一个标记结束（或文本开头）→ 本标记开始。
                let segmentStart = previousMarkerUpperBound(before: entry.range.lowerBound, in: ordered) ?? output.startIndex
                let segmentEnd = entry.range.lowerBound
                let segment = segmentStart <= segmentEnd ? String(output[segmentStart..<segmentEnd]) : ""
                results.append(Outcome(packageIndex: i, exitCode: entry.code, outputSegment: segment))
            } else {
                results.append(Outcome(packageIndex: i, exitCode: -1, outputSegment: ""))
            }
        }
        return results
    }

    /// 在已按位置排序的标记里，找 position 之前最近的那个标记的结束位置（用于切分片段起点）。
    private static func previousMarkerUpperBound(
        before position: String.Index,
        in ordered: [(index: Int, code: Int32, range: Range<String.Index>)]
    ) -> String.Index? {
        var last: String.Index?
        for item in ordered {
            if item.range.lowerBound >= position { break }
            last = item.range.upperBound
        }
        return last
    }
}
