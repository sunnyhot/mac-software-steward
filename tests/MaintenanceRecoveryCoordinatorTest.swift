import Foundation

@main
struct MaintenanceRecoveryCoordinatorTest {
    static func main() {
        let coordinator = MaintenanceRecoveryCoordinator()

        // MARK: failed 包应产生恢复动作
        let failedProgress = PackageUpgradeProgress(
            packageID: "brew:formula:jq",
            packageName: "jq",
            status: .failed,
            detail: "升级失败",
            failureSummary: "升级失败",
            recoveryAction: .retry,
            lastFailedCommand: "brew upgrade jq"
        )
        let failedActions = coordinator.recoveryActions(for: failedProgress)
        precondition(!failedActions.isEmpty, "failed 包应有恢复动作")
        precondition(failedActions.contains { $0.kind == .retryPackage }, "retry 进程应包含 retryPackage")

        // MARK: timedOut 包也应产生恢复动作
        let timedOutProgress = PackageUpgradeProgress(
            packageID: "brew:formula:slow",
            packageName: "slow",
            status: .timedOut,
            detail: "超时",
            failureSummary: "超时",
            recoveryAction: .retryInTerminal,
            lastFailedCommand: "brew upgrade slow"
        )
        let timedOutActions = coordinator.recoveryActions(for: timedOutProgress)
        precondition(!timedOutActions.isEmpty, "timedOut 包应有恢复动作")
        precondition(timedOutActions.contains { $0.kind == .copyTerminalCommand }, "retryInTerminal 应映射到 copyTerminalCommand")

        // MARK: succeeded 包不应产生恢复动作
        let succeededProgress = PackageUpgradeProgress(
            packageID: "brew:formula:ok",
            packageName: "ok",
            status: .succeeded,
            detail: "完成"
        )
        let succeededActions = coordinator.recoveryActions(for: succeededProgress)
        precondition(succeededActions.isEmpty, "succeeded 包不应有恢复动作")

        // MARK: 无 recoveryAction 的 failed 包仍应有支撑动作（查看升级/日志）
        let noActionProgress = PackageUpgradeProgress(
            packageID: "brew:formula:mystery",
            packageName: "mystery",
            status: .failed,
            detail: "未知错误"
        )
        let noActionsResult = coordinator.recoveryActions(for: noActionProgress)
        precondition(!noActionsResult.isEmpty, "无 recoveryAction 的 failed 包仍应有支撑动作")
        precondition(noActionsResult.contains { $0.kind == .openJobs }, "应包含查看日志")

        print("MaintenanceRecoveryCoordinatorTest passed")
    }
}
