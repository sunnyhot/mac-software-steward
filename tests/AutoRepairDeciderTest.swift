import Foundation

@main
struct AutoRepairDeciderTest {
    static func main() {
        let rescanProgress = PackageUpgradeProgress(
            packageID: "brew:formula:missing",
            packageName: "missing",
            status: .failed,
            detail: "所需的文件或工具未找到。",
            failureSummary: "所需的文件或工具未找到。",
            recoverySuggestion: "请点击「重新扫描」刷新软件列表后再试。",
            recoveryAction: .rescan
        )

        var profile = AutomationProfile.manualDefault
        profile.autoRepairPolicy = .allowLowRisk

        let allowed = AutoRepairDecider.automaticAction(
            for: rescanProgress,
            profile: profile,
            attemptedPackageIDs: []
        )
        precondition(allowed?.kind == .rescan)

        let attempted = AutoRepairDecider.automaticAction(
            for: rescanProgress,
            profile: profile,
            attemptedPackageIDs: [rescanProgress.packageID]
        )
        precondition(attempted == nil)

        profile.autoRepairPolicy = .manualOnly
        precondition(AutoRepairDecider.automaticAction(for: rescanProgress, profile: profile, attemptedPackageIDs: []) == nil)

        let retryProgress = PackageUpgradeProgress(
            packageID: "brew:cask:android-studio",
            packageName: "Android Studio",
            status: .failed,
            detail: "下载失败",
            failureSummary: "下载失败",
            recoverySuggestion: "请重试。",
            recoveryAction: .cleanup
        )
        profile.autoRepairPolicy = .allowLowRisk
        precondition(AutoRepairDecider.automaticAction(for: retryProgress, profile: profile, attemptedPackageIDs: []) == nil)
    }
}
