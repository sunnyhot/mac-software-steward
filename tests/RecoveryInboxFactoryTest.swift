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

        let running = PackageUpgradeProgress(
            packageID: "brew:formula:jq",
            packageName: "jq",
            status: .running,
            detail: "执行命令"
        )
        precondition(RecoveryInboxFactory.items(from: [running]).isEmpty)
    }
}
