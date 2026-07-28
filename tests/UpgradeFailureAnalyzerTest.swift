import Foundation

@main
struct UpgradeFailureAnalyzerTest {
    static func main() {
        let lockedOutput = """
        [stderr] Error: A `brew upgrade --cask --greedy android-studio` process has already locked /Users/xufan65/Library/Caches/Homebrew/downloads/a3c4--android-studio.dmg.incomplete.
        [stderr] Please wait for it to finish or terminate it to continue.
        """
        let lockedHint = UpgradeFailureAnalyzer.knownFailureHint(in: lockedOutput)
        precondition(lockedHint?.summary == "已有 Homebrew 任务正在占用下载缓存。", "Expected Homebrew lock conflict summary")
        precondition(lockedHint?.suggestion.contains("等待原任务结束") == true, "Expected wait-and-retry guidance")
        precondition(lockedHint?.action == .retry, "Expected retry action after the lock is released")

        let interruptedOutput = """
        [stderr] Error: Download failed on Cask 'android-studio' with message: Download incomplete
        """
        let interruptedHint = UpgradeFailureAnalyzer.knownFailureHint(in: interruptedOutput)
        precondition(interruptedHint?.summary == "下载过程中被中断，文件不完整。", "Generic incomplete downloads should keep the retryable download hint")

        // --- requiresSudo ---
        let sudoRequired = "Error: sudo: a password is required"
        precondition(UpgradeFailureAnalyzer.requiresSudo(in: sudoRequired) == true, "sudo + 'a password is required' must be detected")

        let sudoTerminal = "sudo: terminal is required to read the password"
        precondition(UpgradeFailureAnalyzer.requiresSudo(in: sudoTerminal) == true, "'terminal is required' sudo variant must be detected")

        let sudoRead = "Error: sudo: read the password"
        precondition(UpgradeFailureAnalyzer.requiresSudo(in: sudoRead) == true, "'read the password' sudo variant must be detected")

        let sudoPlain = "sudo: password is required"
        precondition(UpgradeFailureAnalyzer.requiresSudo(in: sudoPlain) == true, "'password is required' sudo variant must be detected")

        // 非 sudo 失败不应命中
        let permDenied = "curl: (18) permission denied"
        precondition(UpgradeFailureAnalyzer.requiresSudo(in: permDenied) == false, "permission denied must NOT be treated as sudo")

        let checksumFail = "Error: SHA256 mismatch"
        precondition(UpgradeFailureAnalyzer.requiresSudo(in: checksumFail) == false, "checksum mismatch must NOT be treated as sudo")

        let networkFail = "curl: (28) connection timed out"
        precondition(UpgradeFailureAnalyzer.requiresSudo(in: networkFail) == false, "network error must NOT be treated as sudo")
    }
}
