import Foundation

@main
struct RecoveryInboxFactoryTest {
    static func main() {
        let failed = PackageUpgradeProgress(
            packageID: "brew:cask:android-studio",
            packageName: "Android Studio",
            status: .failed,
            detail: "下载的文件校验不通过",
            failureSummary: "下载的文件校验不通过，可能是缓存损坏。",
            recoverySuggestion: "请点击「重试」，系统会自动清理缓存后重新下载。",
            copyText: "命令：brew upgrade --cask android-studio",
            recoveryAction: .cleanup,
            lastFailedCommand: "brew upgrade --cask android-studio"
        )

        let items = RecoveryInboxFactory.items(from: [failed])
        precondition(items.count == 1)
        precondition(items[0].kind == .failureRecovery)
        precondition(items[0].severity == .critical)
        precondition(items[0].sourceID == failed.packageID)
        precondition(items[0].title == "Android Studio 升级失败")
        precondition(items[0].summary.contains("下载的文件校验不通过"))
        precondition(items[0].actions.map(\.kind) == [.retryPackage, .openUpdates, .openJobs])

        let permissionFailure = PackageUpgradeProgress(
            packageID: "brew:cask:secured-app",
            packageName: "Secured App",
            status: .failed,
            detail: "Permission denied",
            failureSummary: "没有写入权限，无法完成安装。",
            recoverySuggestion: "请尝试点击「重试」。如果仍然失败，可在「系统设置 > 隐私与安全性」中检查 Homebrew 的磁盘访问权限。",
            recoveryAction: .repairPerms,
            lastFailedCommand: "brew upgrade --cask secured-app"
        )

        let permissionItems = RecoveryInboxFactory.items(from: [permissionFailure])
        precondition(permissionItems.count == 1)
        precondition(permissionItems[0].kind == .permissionIssue)
        precondition(permissionItems[0].severity == .critical)
        precondition(permissionItems[0].sourceID == permissionFailure.packageID)
        precondition(permissionItems[0].actions.map(\.kind) == [.retryPackage, .openUpdates, .openJobs])

        let running = PackageUpgradeProgress(
            packageID: "brew:formula:jq",
            packageName: "jq",
            status: .running,
            detail: "执行命令"
        )
        precondition(RecoveryInboxFactory.items(from: [running]).isEmpty)

        let cleanupFailure = PackageUpgradeProgress(
            packageID: "brew:cask:bartender",
            packageName: "bartender",
            status: .failed,
            detail: "管理员授权脚本存在语法错误，命令未执行。",
            failureSummary: "管理员授权脚本存在语法错误，命令未执行。",
            recoveryAction: .openLog,
            lastFailedCommand: "brew uninstall --cask --force bartender",
            purpose: .staleCaskCleanup
        )
        let cleanupItems = RecoveryInboxFactory.items(from: [cleanupFailure])
        precondition(cleanupItems.count == 1)
        precondition(cleanupItems[0].title == "bartender 清理失败")
        precondition(cleanupItems[0].actions.map(\.kind).contains(.openJobs))

        let partialCleanup = PackageUpgradeProgress(
            packageID: "brew:cask:partial",
            packageName: "partial",
            status: .warning,
            detail: "receipt 已移除，但命令返回非零",
            failureSummary: "receipt 已移除，但清理部分阶段失败",
            recoverySuggestion: "查看日志，无需重复卸载",
            recoveryAction: .openLog,
            lastFailedCommand: "brew uninstall --cask --force partial",
            purpose: .staleCaskCleanup
        )
        let partialItems = RecoveryInboxFactory.items(from: [partialCleanup])
        precondition(partialItems.count == 1)
        precondition(partialItems[0].title == "partial 清理失败")
        precondition(partialItems[0].status == .pending)
    }
}
