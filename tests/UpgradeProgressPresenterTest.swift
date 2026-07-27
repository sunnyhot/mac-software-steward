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
        let phaseDuration = UpgradeProgressPresenter.phaseDurationText(for: running, now: now)
        precondition(phaseDuration == "下载中持续 2 分钟", "Unexpected phase duration: \(phaseDuration)")

        let lastUpdate = UpgradeProgressPresenter.lastUpdateText(for: running, now: now)
        precondition(lastUpdate == "最近输出 2 分钟前", "Unexpected last update: \(lastUpdate)")

        let staleHint = UpgradeProgressPresenter.staleHint(for: running, now: now)
        precondition(staleHint == "超过 2 分钟没有新输出，可能在等待下载、安装或系统授权。", "Unexpected stale hint: \(String(describing: staleHint))")

        let accelerating = PackageUpgradeProgress(
            packageID: "brew:cask:warp",
            packageName: "warp",
            status: .running,
            detail: "正在下载",
            phaseText: "下载中",
            updatedAt: now,
            accelerationStatusText: "下载速度持续偏低，正在自动加速",
            accelerationStrategyText: "系统代理",
            accelerationAttemptText: "第 2/3 次"
        )
        let accelerationHint = UpgradeProgressPresenter.accelerationHint(for: accelerating)
        precondition(accelerationHint == "下载速度持续偏低，正在自动加速：系统代理（第 2/3 次）", "Unexpected acceleration hint: \(String(describing: accelerationHint))")
        precondition(UpgradeProgressPresenter.staleHint(for: accelerating, now: now.addingTimeInterval(300)) == nil)

        let freshHint = UpgradeProgressPresenter.staleHint(for: queued, now: now)
        precondition(freshHint == nil, "Queued packages should not show stale running hints")
    }
}
