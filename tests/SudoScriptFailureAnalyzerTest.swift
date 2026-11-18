import Foundation

@main
struct SudoScriptFailureAnalyzerTest {
    static func main() {
        let command = "brew uninstall --cask --force bartender"
        let cancelled = SudoScriptFailureAnalyzer.analysis(
            command: command,
            output: "execution error: User canceled. (-128)"
        )
        precondition(cancelled.action == .promptAdminPassword)
        precondition(cancelled.summary.contains("取消管理员授权"))
        precondition(cancelled.copyText.contains("(-128)"))

        for output in [
            "syntax error: A identifier can’t go after this quote. (-2740)",
            "20:26: syntax error: Expected end of line. (-2741)"
        ] {
            let syntax = SudoScriptFailureAnalyzer.analysis(command: command, output: output)
            precondition(syntax.action == .openLog)
            precondition(syntax.summary.contains("语法错误"))
            precondition(!syntax.summary.contains("授权未完成"))
            precondition(!syntax.suggestion.contains("密码错误"))
            precondition(syntax.copyText.contains(command))
            precondition(syntax.copyText.contains("syntax error"))
        }

        let generic = SudoScriptFailureAnalyzer.analysis(
            command: command,
            output: "execution error: unexpected failure (-10004)"
        )
        precondition(generic.action == .openLog)
        precondition(generic.summary.contains("执行失败"))
        precondition(generic.copyText.contains("-10004"))
    }
}
