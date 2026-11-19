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

        // mas：商店目录已见新版本，但购买/重下后端尚未向本机账户放行
        let noDownloadsOutput = """
        [stderr] Error: No downloads initiated for ADAM ID 6471391855
        """
        let noDownloadsHint = UpgradeFailureAnalyzer.knownFailureHint(in: noDownloadsOutput)
        precondition(noDownloadsHint != nil, "'No downloads initiated' must be classified instead of falling to the generic error-line hint")
        precondition(noDownloadsHint?.summary.contains("尚未向本机") == true, "Expected store-side rollout-lag summary")
        precondition(noDownloadsHint?.suggestion.contains("稍后") == true, "Expected wait-and-retry guidance, not immediate retry")
        precondition(noDownloadsHint?.action == .retry, "Expected retry action for a later attempt")

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

        let multipleVersions = UpgradeFailureAnalyzer.knownFailureHint(
            in: "Error: /opt/homebrew/Cellar/merve/1.2.2_5 is not a directory"
        )
        precondition(multipleVersions?.action == .reinstall)
        precondition(multipleVersions?.summary.contains("多个已安装版本") == true)
        precondition(multipleVersions?.suggestion.contains("修复并重装") == true)

        let explicitMultiple = UpgradeFailureAnalyzer.knownFailureHint(
            in: "Error: merve has multiple installed versions"
        )
        precondition(explicitMultiple?.action == .reinstall)

        let cacheRename = UpgradeFailureAnalyzer.knownFailureHint(
            in: "Error: No such file or directory @ rb_file_s_rename - (/tmp/mongosh.bottle_manifest.json.incomplete, /tmp/mongosh.bottle_manifest.json)"
        )
        precondition(cacheRename?.action == .cleanup)
        precondition(cacheRename?.summary.contains("下载缓存重命名失败") == true)
        precondition(cacheRename?.suggestion.contains(".incomplete") == true)
        precondition(cacheRename?.suggestion.contains("不需要重新扫描") == true)

        let mixedCacheLog = """
        Error: dependency conflict detected
        Error: No such file or directory @ rb_file_s_rename - (/tmp/mongosh.json.incomplete, /tmp/mongosh.json)
        """
        let mixedHint = UpgradeFailureAnalyzer.knownFailureHint(in: mixedCacheLog)
        precondition(mixedHint?.action == .cleanup, "cache rename must win over dependency/rescan classification")

        let nodeLog = """
        ==> Downloading bottle manifests
        ✘ Bottle Manifest node (26.13.1_2)
        Error: No such file or directory @ rb_file_s_rename - (/Users/xufan65/Library/Caches/Homebrew/downloads/a1e1582ede418458db7223233e613bc9e06740b02baf9de9673bd06016c899f5--node-26.13.1_2.bottle_manifest.json.incomplete, /Users/xufan65/Library/Caches/Homebrew/downloads/a1e1582ede418458db7223233e613bc9e06740b02baf9de9673bd06016c899f5--node-26.13.1_2.bottle_manifest.json)
        """
        let nodeHint = UpgradeFailureAnalyzer.knownFailureHint(in: nodeLog)
        precondition(nodeHint?.action == .cleanup)
        precondition(nodeHint?.summary.contains("下载缓存重命名失败") == true)
        precondition(nodeHint?.suggestion.contains("不需要重新扫描") == true)

        let notInstalled = UpgradeFailureAnalyzer.knownFailureHint(
            command: "brew upgrade merve",
            output: "Error: merve not installed"
        )
        precondition(notInstalled?.action == .reinstall)
        precondition(notInstalled?.summary.contains("当前未安装") == true)
        precondition(notInstalled?.suggestion.contains("不再回退到 brew upgrade") == true)

        let caskNotInstalled = UpgradeFailureAnalyzer.knownFailureHint(
            command: "brew upgrade --cask some-app",
            output: "Error: some-app not installed"
        )
        precondition(caskNotInstalled?.action != .reinstall, "cask failures must not enter formula repair")
    }
}
