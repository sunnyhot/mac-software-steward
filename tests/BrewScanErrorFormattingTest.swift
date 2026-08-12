import Foundation

@main
struct BrewScanErrorFormattingTest {
    static func main() {
        testBrewCommandErrorSignalAware()
        testDiagnoseBrewTimeoutBranch()
        testDiagnoseBrewPartialBranch()
        print("BrewScanErrorFormattingTest passed")
    }

    /// brewCommandError 对被信号终止（超时 SIGTERM）的命令返回友好文案，
    /// 不再把 Ruby SIGTERM 栈原样透传给用户。
    static func testBrewCommandErrorSignalAware() {
        // 场景 A：brew 被 OS 级 SIGTERM 杀死。macOS 上 Foundation 返回原始信号号 15
        // （不是 shell 的 128+15=143），terminationReason == .uncaughtSignal。
        let sigterm = CommandResult(
            ok: false,
            code: 15,
            stdout: "",
            stderr: "Error: SIGTERM\n/opt/homebrew/Library/Homebrew/system_command.rb:370:in `join'",
            terminationReason: .uncaughtSignal
        )
        let msg = SoftwareScanner.brewCommandError(tagged: "brew outdated", sigterm)
        precondition(msg.contains("brew outdated"), "错误文案应包含命令名")
        precondition(msg.contains("被终止") || msg.contains("SIGTERM") || msg.contains("中断"), "SIGTERM 应翻译为友好信号描述")
        precondition(!msg.contains("system_command.rb"), "不应透传 Ruby 栈给用户")

        // 场景 B：Homebrew 的 Ruby 自己捕获了 SIGTERM，把 "Error: SIGTERM" + 栈打到 stderr 后
        // 以普通失败码（exit 1）退出，terminationReason == .exit。仅靠 wasSignaled 抓不到，
        // 必须靠 stderr 内容兜底识别（这正是用户截图里的现场）。
        let rubyCaught = CommandResult(
            ok: false,
            code: 1,
            stdout: "",
            stderr: "Error: SIGTERM\n/opt/homebrew/Library/Homebrew/system_command.rb:370:in `Thread#join'",
            terminationReason: .exit
        )
        let rubyMsg = SoftwareScanner.brewCommandError(tagged: "brew outdated", rubyCaught)
        precondition(rubyMsg.contains("brew outdated"), "Ruby 捕获场景文案应包含命令名")
        precondition(rubyMsg.contains("被终止") || rubyMsg.contains("SIGTERM") || rubyMsg.contains("中断"), "Ruby 捕获的 SIGTERM 也应翻译为友好文案")
        precondition(!rubyMsg.contains("system_command.rb"), "不应透传 Ruby 栈给用户")

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

    /// diagnoseBrew 对"部分完成"（error 空 + 有未检 cask）给出软诊断，
    /// 不建议 brew doctor、不当作整盘失败；error 非空时仍优先走 error 分支。
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
}
