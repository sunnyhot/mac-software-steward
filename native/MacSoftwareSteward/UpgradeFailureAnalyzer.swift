import Foundation

struct FailureHint {
    var summary: String
    var suggestion: String
    var action: FailureActionType
}

enum UpgradeFailureAnalyzer {
    static func knownFailureHint(in output: String) -> FailureHint? {
        let lowercased = output.lowercased()

        if isHomebrewDownloadLockConflict(lowercased) {
            return FailureHint(
                summary: "已有 Homebrew 任务正在占用下载缓存。",
                suggestion: "请等待原任务结束后点击「重试」。如果长时间没有进展，请确认没有其他 Mac 软件管家或 brew upgrade 进程仍在运行，再重新升级。",
                action: .retry
            )
        }

        if lowercased.contains("is currently running") || lowercased.contains("app is running") || lowercased.contains("application is running") {
            return FailureHint(
                summary: "该应用正在运行中，无法被替换。",
                suggestion: "请先关闭该应用（可在 Dock 栏右键退出，或按 ⌘+Q），然后点击「重试」。",
                action: .quitAndRetry
            )
        }

        if lowercased.contains("app source") && lowercased.contains("is not there") {
            return FailureHint(
                summary: "Homebrew 中保留了已不存在的 Cask 记录。",
                suggestion: "系统会自动尝试从 Homebrew Cask 中移除该残留记录；如果仍失败，请在终端运行对应的 brew uninstall --cask --force 命令。",
                action: .cleanup
            )
        }

        if BrewCaskCleanupDetector.isCaskroomAppConflict(lowercased) {
            return FailureHint(
                summary: "Homebrew Caskroom 中存在旧版本 App 残留。",
                suggestion: "系统会自动尝试执行 brew uninstall --cask --force 清理该残留记录；如果仍失败，请在终端运行对应命令后重新扫描。",
                action: .cleanup
            )
        }

        if lowercased.contains("already exists") || lowercased.contains("it seems there is already an app") || lowercased.contains("app already exists") {
            return FailureHint(
                summary: "目标位置已存在同名应用，无法直接覆盖安装。",
                suggestion: "请先关闭该应用，然后点击「重试」重新覆盖安装。",
                action: .reimport
            )
        }

        if lowercased.contains("permission denied") || lowercased.contains("operation not permitted") || lowercased.contains("eacces") {
            return FailureHint(
                summary: "没有写入权限，无法完成安装。",
                suggestion: "请尝试点击「重试」。如果仍然失败，可在「系统设置 > 隐私与安全性」中检查 Homebrew 的磁盘访问权限。",
                action: .repairPerms
            )
        }

        if lowercased.contains("checksum mismatch") || lowercased.contains("sha256 mismatch") {
            return FailureHint(
                summary: "下载的文件校验不通过，可能是缓存损坏。",
                suggestion: "请点击「重试」，系统会自动清理缓存后重新下载。",
                action: .cleanup
            )
        }

        if lowercased.contains("timeout") || lowercased.contains("timed out") || lowercased.contains("connection refused") || lowercased.contains("could not resolve") || lowercased.contains("network") || (lowercased.contains("curl") && lowercased.contains("error")) {
            return FailureHint(
                summary: "网络连接出现问题，下载失败。",
                suggestion: "请检查网络连接是否正常，然后点击「重试」。如果使用代理，请确认代理配置正确。",
                action: .checkNetwork
            )
        }

        if lowercased.contains("no space left") || lowercased.contains("disk full") || lowercased.contains("not enough space") || lowercased.contains("enospc") {
            return FailureHint(
                summary: "磁盘空间不足，无法完成下载和安装。",
                suggestion: "请清理磁盘空间后再试。可以在「系统设置 > 通用 > 储存空间」中查看和清理。",
                action: .freeDisk
            )
        }

        if lowercased.contains("version conflict") || lowercased.contains("conflicting") || (lowercased.contains("depends on") && lowercased.contains("not installed")) || lowercased.contains("broken") || lowercased.contains("dependency") {
            return FailureHint(
                summary: "存在依赖关系问题，无法直接升级。",
                suggestion: "请点击「重试」。如果持续失败，可以先在「管理来源」页面更新 Homebrew 本身，再重新扫描。",
                action: .rescan
            )
        }

        if lowercased.contains("no such file or directory") || lowercased.contains("not found") {
            return FailureHint(
                summary: "所需的文件或工具未找到。",
                suggestion: "请点击「重新扫描」刷新软件列表后再试。如果仍然失败，该软件可能已被卸载。",
                action: .rescan
            )
        }

        if lowercased.contains("signal") || lowercased.contains("sigsegv") || lowercased.contains("sigabrt") || lowercased.contains("崩溃") {
            return FailureHint(
                summary: "命令进程崩溃，可能是工具与当前系统版本不兼容。",
                suggestion: "请尝试在终端手动运行该命令检查，然后点击「重试」。如果是 mas CLI 崩溃，可能需要在 App Store 中登录，或更新 mas 到最新版本。",
                action: .retry
            )
        }

        if lowercased.contains("download") && (lowercased.contains("interrupted") || lowercased.contains("failed") || lowercased.contains("incomplete")) {
            return FailureHint(
                summary: "下载过程中被中断，文件不完整。",
                suggestion: "请点击「重试」重新下载。",
                action: .retry
            )
        }

        if lowercased.contains("sudo") && (lowercased.contains("password is required") || lowercased.contains("terminal is required") || lowercased.contains("a password is required") || lowercased.contains("read the password")) {
            return FailureHint(
                summary: "系统需要管理员密码才能完成安装，但当前环境无法输入密码。",
                suggestion: "请打开「终端」App，手动运行上方命令并输入密码完成升级。也可以在「系统设置 > App Store」中检查是否已登录，然后点击「重试」。",
                action: .retryInTerminal
            )
        }

        return nil
    }

    private static func isHomebrewDownloadLockConflict(_ lowercasedOutput: String) -> Bool {
        lowercasedOutput.contains("already locked")
            && lowercasedOutput.contains(".incomplete")
            && lowercasedOutput.contains("please wait for it to finish or terminate it")
    }
}
