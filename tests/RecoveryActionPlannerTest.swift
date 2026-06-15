import Foundation

@main
struct RecoveryActionPlannerTest {
    static func main() {
        let cleanup = PackageUpgradeProgress(
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

        let cleanupActions = RecoveryActionPlanner.actions(for: cleanup)
        precondition(cleanupActions.map(\.kind) == [.retryPackage, .openUpdates, .openJobs])
        precondition(cleanupActions[0].title == "清理并重试")
        precondition(cleanupActions[0].systemImage == "trash.circle")

        let terminal = PackageUpgradeProgress(
            packageID: "mas:123",
            packageName: "Pages",
            status: .timedOut,
            detail: "升级命令超时。",
            failureSummary: "升级命令超时。",
            recoverySuggestion: "请稍后重试，或在终端中手动运行命令检查。",
            copyText: "命令：mas upgrade 123",
            recoveryAction: .retryInTerminal,
            lastFailedCommand: "mas upgrade 123"
        )

        let terminalActions = RecoveryActionPlanner.actions(for: terminal)
        precondition(terminalActions.map(\.kind) == [.copyTerminalCommand, .openUpdates, .openJobs])
        precondition(terminalActions[0].title == "复制终端命令")

        let running = PackageUpgradeProgress(
            packageID: "brew:formula:jq",
            packageName: "jq",
            status: .running,
            detail: "执行命令"
        )
        precondition(RecoveryActionPlanner.actions(for: running).isEmpty)

        let rescan = PackageUpgradeProgress(
            packageID: "brew:formula:missing",
            packageName: "missing",
            status: .failed,
            detail: "所需的文件或工具未找到。",
            failureSummary: "所需的文件或工具未找到。",
            recoverySuggestion: "请点击「重新扫描」刷新软件列表后再试。",
            recoveryAction: .rescan
        )
        let rescanAction = RecoveryActionPlanner.actions(for: rescan)[0]
        precondition(rescanAction.kind == .rescan)
        precondition(rescanAction.allowsAutomaticRepair == true)
    }
}
