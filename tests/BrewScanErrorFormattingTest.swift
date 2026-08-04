import Foundation

@main
struct BrewScanErrorFormattingTest {
    static func main() {
        testBrewCommandErrorSignalAware()
        testDiagnoseBrewTimeoutBranch()
        print("BrewScanErrorFormattingTest passed")
    }

    /// brewCommandError 对被信号终止（超时 SIGTERM）的命令返回友好文案，
    /// 不再把 Ruby SIGTERM 栈原样透传给用户。
    static func testBrewCommandErrorSignalAware() {
        // SIGTERM: brew 被 30s 超时打断，退出码 128+15=143，stderr 是一串 Ruby 栈
        let sigterm = CommandResult(
            ok: false,
            code: 143,
            stdout: "",
            stderr: "Error: SIGTERM\n/opt/homebrew/Library/Homebrew/system_command.rb:327:in `join'"
        )
        let msg = SoftwareScanner.brewCommandError(tagged: "brew outdated", sigterm)
        precondition(msg.contains("brew outdated"), "错误文案应包含命令名")
        precondition(msg.contains("被终止") || msg.contains("SIGTERM") || msg.contains("中断"), "SIGTERM 应翻译为友好信号描述")
        precondition(!msg.contains("system_command.rb"), "不应透传 Ruby 栈给用户")

        // 正常失败（非信号）：保留 stderr 原文便于排查
        let normalErr = CommandResult(ok: false, code: 1, stdout: "", stderr: "Error: some brew failure")
        let normalMsg = SoftwareScanner.brewCommandError(tagged: "brew outdated", normalErr)
        precondition(normalMsg == "Error: some brew failure", "非信号失败应保留 stderr 原文")

        // 成功：返回空
        let ok = CommandResult(ok: true, code: 0, stdout: "{}", stderr: "")
        precondition(SoftwareScanner.brewCommandError(tagged: "brew outdated", ok).isEmpty, "成功时应返回空")
    }

    /// diagnoseBrew 对"超时/被终止"类错误给出"更新检查超时"诊断，
    /// 不再误导用户去跑 brew doctor。
    static func testDiagnoseBrewTimeoutBranch() {
        let timeoutError = "brew outdated 进程被终止 (SIGTERM)，可能是命令耗时过长被中断，请稍后重试。"
        guard let d = SourceDiagnosticEngine.diagnoseBrew(available: true, error: timeoutError) else {
            preconditionFailure("超时错误应产出诊断")
        }
        precondition(d.reason.contains("超时"), "reason 应点明超时，实际：\(d.reason)")
        precondition(d.terminalCommand == nil, "超时不应建议 brew doctor（terminalCommand 应为 nil）")
        precondition(!d.suggestion.contains("brew doctor"), "超时建议不应包含 brew doctor")
    }
}
