import Foundation

@main
struct MaintenanceStatusPresenterTest {
    static func main() {
        let idle = MaintenanceStatusPresenter.presentation(
            isScanning: false,
            scanPhaseText: nil,
            scanProgress: nil,
            hasRunningJob: false,
            upgradeProgress: nil,
            updateCount: 0,
            failedPackageCount: 0
        )
        precondition(idle.title == "维护状态良好", "Unexpected idle title: \(idle.title)")
        precondition(idle.detail == "没有发现可操作升级", "Unexpected idle detail: \(idle.detail)")
        precondition(idle.symbol == "checkmark.seal", "Unexpected idle symbol: \(idle.symbol)")
        precondition(idle.tintRole == .success)
        precondition(!idle.isActive)
        precondition(idle.progress == nil)

        let pending = MaintenanceStatusPresenter.presentation(
            isScanning: false,
            scanPhaseText: nil,
            scanProgress: nil,
            hasRunningJob: false,
            upgradeProgress: nil,
            updateCount: 3,
            failedPackageCount: 0
        )
        precondition(pending.title == "发现 3 个可升级项目", "Unexpected pending title: \(pending.title)")
        precondition(pending.detail == "可先检查策略，再执行一键升级", "Unexpected pending detail: \(pending.detail)")
        precondition(pending.symbol == "arrow.down.circle", "Unexpected pending symbol: \(pending.symbol)")
        precondition(pending.tintRole == .attention)
        precondition(!pending.isActive)

        let scanning = MaintenanceStatusPresenter.presentation(
            isScanning: true,
            scanPhaseText: "正在获取 Homebrew 信息...",
            scanProgress: 0.25,
            hasRunningJob: false,
            upgradeProgress: nil,
            updateCount: 0,
            failedPackageCount: 0
        )
        precondition(scanning.title == "正在扫描本机软件", "Unexpected scanning title: \(scanning.title)")
        precondition(scanning.detail == "正在获取 Homebrew 信息...", "Unexpected scanning detail: \(scanning.detail)")
        precondition(scanning.symbol == "magnifyingglass", "Unexpected scanning symbol: \(scanning.symbol)")
        precondition(scanning.tintRole == .scanning)
        precondition(scanning.isActive)
        precondition(scanning.progress == 0.25)

        let progress = UpgradeProgress(completed: 1, total: 4, failed: 0, currentPackage: "iina")
        let upgrading = MaintenanceStatusPresenter.presentation(
            isScanning: false,
            scanPhaseText: nil,
            scanProgress: nil,
            hasRunningJob: true,
            upgradeProgress: progress,
            updateCount: 4,
            failedPackageCount: 0
        )
        precondition(upgrading.title == "正在执行升级", "Unexpected upgrading title: \(upgrading.title)")
        precondition(upgrading.detail == "已完成 1/4 · 当前 iina", "Unexpected upgrading detail: \(upgrading.detail)")
        precondition(upgrading.symbol == "bolt.circle", "Unexpected upgrading symbol: \(upgrading.symbol)")
        precondition(upgrading.tintRole == .accent)
        precondition(upgrading.isActive)
        precondition(upgrading.progress == 0.25)

        let failed = MaintenanceStatusPresenter.presentation(
            isScanning: false,
            scanPhaseText: nil,
            scanProgress: nil,
            hasRunningJob: false,
            upgradeProgress: nil,
            updateCount: 2,
            failedPackageCount: 2
        )
        precondition(failed.title == "有 2 个升级需要处理", "Unexpected failed title: \(failed.title)")
        precondition(failed.detail == "失败项保留在列表中，可重试或查看日志", "Unexpected failed detail: \(failed.detail)")
        precondition(failed.symbol == "exclamationmark.triangle", "Unexpected failed symbol: \(failed.symbol)")
        precondition(failed.tintRole == .failure)
        precondition(!failed.isActive)
    }
}
