import Foundation

/// 流式保留每个 sudo 命令的结果标记及有界错误上下文。
/// CommandRunner 的 recentOutput 只有 40 行，不能用于批次结果判定。
final class SudoScriptOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let perCommandLineLimit = 40
    private var currentCommandIndex = 1
    private var segments: [Int: [String]] = [:]

    func append(stream: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }
        var lines = segments[currentCommandIndex, default: []]
        lines.append(trimmed)
        if lines.count > perCommandLineLimit {
            lines.removeFirst(lines.count - perCommandLineLimit)
        }
        segments[currentCommandIndex] = lines

        if let markerIndex = Self.markerIndex(in: trimmed) {
            currentCommandIndex = markerIndex + 1
        }
    }

    var containsResultMarker: Bool {
        lock.lock()
        defer { lock.unlock() }
        return segments.keys.contains { Self.markerIndex(in: segments[$0]?.last ?? "") != nil }
    }

    /// 输出仍交给 SudoScriptParser 做统一解析；与 recentOutput 不同，
    /// 这里不会丢失较早命令的 __RC__ 标记。
    func text() -> String {
        lock.lock()
        defer { lock.unlock() }
        return segments.keys.sorted().flatMap { segments[$0] ?? [] }.joined(separator: "\n")
    }

    private static func markerIndex(in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: "__RC_(\\d+)_\\d+__") else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let indexRange = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[indexRange])
    }
}
