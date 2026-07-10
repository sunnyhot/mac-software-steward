import Foundation

// MARK: - Maintenance Recovery Coordinator
//
// 复用现有 RecoveryActionPlanner，为失败/超时的包推导恢复动作。
// 输出重试/重扫/看日志/复制终端命令/开系统设置等动作。
// 自动修复仍由 AutomationProfile.autoRepairPolicy + allowlist 控制（复用 AutoRepairDecider）。
// 设计依据：docs/superpowers/specs/2026-07-10-unified-maintenance-engine-dashboard-design.md

struct MaintenanceRecoveryCoordinator: MaintenanceRecovering {
    func recoveryActions(for progress: PackageUpgradeProgress) -> [RecoveryAction] {
        RecoveryActionPlanner.actions(for: progress)
    }
}
