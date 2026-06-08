import Foundation

@main
struct UpgradeProgressPresenterTest {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_000)
        let running = PackageUpgradeProgress(
            packageID: "brew:cask:iina",
            packageName: "iina",
            status: .running,
            detail: "正在下载 Homebrew 缓存",
            phaseText: "下载中",
            updatedAt: now.addingTimeInterval(-130)
        )
        let queued = PackageUpgradeProgress(
            packageID: "brew:cask:warp",
            packageName: "warp",
            status: .queued,
            detail: "等待升级",
            updatedAt: now.addingTimeInterval(-30)
        )
        let failed = PackageUpgradeProgress(
            packageID: "brew:cask:excel",
            packageName: "excel",
            status: .failed,
            detail: "下载失败",
            updatedAt: now.addingTimeInterval(-15)
        )
        let progress = UpgradeProgress(completed: 1, total: 4, failed: 1, currentPackage: "2 个任务并行中")

        let summary = UpgradeProgressPresenter.summaryText(
            progress: progress,
            packageProgress: [running, queued, failed],
            now: now
        )
        precondition(summary == "1 个执行中 · 1 个排队 · 1 个需处理 · 1 个长时间无输出", "Unexpected summary: \(summary)")

        let phaseDuration = UpgradeProgressPresenter.phaseDurationText(for: running, now: now)
        precondition(phaseDuration == "下载中持续 2 分钟", "Unexpected phase duration: \(phaseDuration)")

        let lastUpdate = UpgradeProgressPresenter.lastUpdateText(for: running, now: now)
        precondition(lastUpdate == "最近输出 2 分钟前", "Unexpected last update: \(lastUpdate)")

        let staleHint = UpgradeProgressPresenter.staleHint(for: running, now: now)
        precondition(staleHint == "超过 2 分钟没有新输出，可能在等待下载、安装或系统授权。", "Unexpected stale hint: \(String(describing: staleHint))")

        let freshHint = UpgradeProgressPresenter.staleHint(for: queued, now: now)
        precondition(freshHint == nil, "Queued packages should not show stale running hints")
    }
}
