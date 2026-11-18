import Foundation

/// 将 osascript 批次启动阶段的错误转换为准确、可操作的反馈。
/// 此阶段没有任何 __RC__ 标记，不能把语法错误等问题误写为密码取消。
enum SudoScriptFailureAnalyzer {
    static func analysis(command: String, output: String) -> FailureAnalysis {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        let isCancellation = lowercased.contains("user canceled")
            || lowercased.contains("user cancelled")
            || lowercased.contains("(-128)")
        let isSyntaxError = lowercased.contains("syntax error")
            || lowercased.contains("(-2740)")
            || lowercased.contains("(-2741)")

        let summary: String
        let suggestion: String
        let action: FailureActionType
        if isCancellation {
            summary = "已取消管理员授权，命令未执行。"
            suggestion = "点击「重试」可重新发起管理员授权。"
            action = .promptAdminPassword
        } else if isSyntaxError {
            summary = "管理员授权脚本存在语法错误，命令未执行。"
            suggestion = "请查看日志并复制详情反馈；这与管理员密码无关。"
            action = .openLog
        } else {
            summary = "管理员授权脚本执行失败，命令未完成。"
            suggestion = "请查看日志确认原因后重试；详细错误已保留。"
            action = .openLog
        }

        var copyText = "失败原因：\(summary)\n解决方案：\(suggestion)\n命令：\(command)"
        if !trimmed.isEmpty {
            copyText += "\n错误输出：\n\(trimmed)"
        }
        return FailureAnalysis(
            summary: summary,
            suggestion: suggestion,
            action: action,
            copyText: copyText,
            command: command
        )
    }
}
