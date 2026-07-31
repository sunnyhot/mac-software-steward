import Foundation

/// 从 `MaintenanceExecutor` 提取的无状态失败分析逻辑。
///
/// 把升级命令的退出码和输出解析成可展示的失败摘要、建议与处理动作。
/// 不持有任何状态，仅依赖 `UpgradeFailureAnalyzer` 与字符串启发式。
struct FailureAnalysis {
    var summary: String
    var suggestion: String
    var action: FailureActionType?
    var copyText: String
    var command: String
}

enum MaintenanceFailureAnalyzer {
    static func failureAnalysis(command: String, code: Int32, output: String) -> FailureAnalysis {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary: String
        let suggestion: String
        let action: FailureActionType?

        let signalNum = code - 128
        if code < 0 || (signalNum > 0 && signalNum < 32) {
            if code < 0 {
                summary = "升级命令超时被终止。"
                suggestion = "请点击「重试」，如果持续超时，可能是网络或依赖问题。"
            } else {
                summary = "升级命令崩溃（信号 \(signalNum)），进程异常退出。"
                suggestion = "请尝试在终端手动运行 `\(command)` 检查具体错误，然后点击「重试」。如果持续崩溃，该工具可能与当前系统版本不兼容。"
            }
            action = .retry
            var copyText = ""
            copyText += "失败原因：\(summary)\n"
            copyText += "解决方案：\(suggestion)\n"
            copyText += "命令：\(command)"
            if !trimmed.isEmpty {
                copyText += "\n最近输出：\n\(trimmed)"
            }
            return FailureAnalysis(summary: summary, suggestion: suggestion, action: action, copyText: copyText, command: command)
        }

        if let hint = UpgradeFailureAnalyzer.knownFailureHint(in: trimmed) {
            summary = hint.summary
            suggestion = hint.suggestion
            action = hint.action
        } else if let errorLine = firstErrorLine(in: trimmed) {
            summary = errorLine
            suggestion = "请点击「查看日志」了解详情，或尝试重新升级。"
            action = .retry
        } else {
            summary = "升级过程中遇到未知错误。"
            suggestion = "请点击「查看日志」查看完整信息，或稍后再试一次。"
            action = .openLog
        }

        var copyText = ""
        copyText += "失败原因：\(summary)\n"
        copyText += "解决方案：\(suggestion)\n"
        copyText += "命令：\(command)"
        if !trimmed.isEmpty {
            copyText += "\n最近输出：\n\(trimmed)"
        }

        return FailureAnalysis(summary: summary, suggestion: suggestion, action: action, copyText: copyText, command: command)
    }

    static func firstErrorLine(in output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                let lowercased = line.lowercased()
                return lowercased.contains("error")
                    || lowercased.contains("failed")
                    || lowercased.contains("failure")
                    || lowercased.contains("permission denied")
                    || lowercased.contains("already exists")
                    || lowercased.contains("checksum")
                    || lowercased.contains("not found")
            }
    }
}
