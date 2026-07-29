import Foundation

enum MaintenanceStatusTintRole: String, Equatable {
    case neutral
    case accent
    case scanning
    case attention
    case success
    case failure
}

struct MaintenanceStatusPresentation: Equatable {
    var title: String
    var detail: String
    var symbol: String
    var tintRole: MaintenanceStatusTintRole
    var isActive: Bool
    var progress: Double?
}

enum MaintenanceStatusPresenter {
    static func presentation(
        isScanning: Bool,
        scanPhaseText: String?,
        scanProgress: Double?,
        hasRunningJob: Bool,
        upgradeProgress: UpgradeProgress?,
        updateCount: Int,
        failedPackageCount: Int
    ) -> MaintenanceStatusPresentation {
        if isScanning {
            return MaintenanceStatusPresentation(
                title: "正在扫描本机软件",
                detail: scanPhaseText ?? "准备刷新软件状态",
                symbol: "magnifyingglass",
                tintRole: .scanning,
                isActive: true,
                progress: scanProgress
            )
        }

        if hasRunningJob {
            let detail: String
            if let upgradeProgress {
                if let currentPackage = upgradeProgress.currentPackage, !currentPackage.isEmpty {
                    detail = "已完成 \(upgradeProgress.completed)/\(upgradeProgress.total) · 当前 \(currentPackage)"
                } else {
                    detail = "已完成 \(upgradeProgress.completed)/\(upgradeProgress.total)"
                }
            } else {
                detail = "升级任务正在执行"
            }
            return MaintenanceStatusPresentation(
                title: "正在执行升级",
                detail: detail,
                symbol: "bolt.circle",
                tintRole: .accent,
                isActive: true,
                progress: upgradeProgress?.fraction
            )
        }

        if failedPackageCount > 0 {
            return MaintenanceStatusPresentation(
                title: "有 \(failedPackageCount) 个升级需要处理",
                detail: "失败项保留在列表中，可重试或查看日志",
                symbol: "exclamationmark.triangle",
                tintRole: .failure,
                isActive: false,
                progress: nil
            )
        }

        if updateCount > 0 {
            return MaintenanceStatusPresentation(
                title: "发现 \(updateCount) 个可升级项目",
                detail: "使用“检查并维护”生成可确认的维护计划",
                symbol: "arrow.down.circle",
                tintRole: .attention,
                isActive: false,
                progress: nil
            )
        }

        return MaintenanceStatusPresentation(
            title: "维护状态良好",
            detail: "没有发现可操作升级",
            symbol: "checkmark.seal",
            tintRole: .success,
            isActive: false,
            progress: nil
        )
    }
}

struct MenuBarStatusPresentation: Equatable {
    var title: String
    var summary: String
    var symbol: String
}

enum MenuBarStatusPresenter {
    static func presentation(
        isScanning: Bool,
        isConfirmingUpgradePlan: Bool,
        hasRunningJob: Bool,
        activeUpgradeCount: Int,
        remainingUpgradeableCount: Int,
        totalUpgradeableCount: Int
    ) -> MenuBarStatusPresentation {
        if isScanning {
            return MenuBarStatusPresentation(
                title: "扫描中",
                summary: "正在扫描软件更新",
                symbol: "magnifyingglass"
            )
        }

        if hasRunningJob {
            let activeText = activeUpgradeCount > 0 ? "\(activeUpgradeCount) 个执行中" : "正在执行任务"
            let activeSummary = activeUpgradeCount > 0 ? activeText : "任务正在执行"
            var summaryParts = ["正在升级，\(activeSummary)"]
            if remainingUpgradeableCount > 0 {
                summaryParts.append("剩余 \(remainingUpgradeableCount) 项待升级")
            }
            return MenuBarStatusPresentation(
                title: "升级中 · \(activeText)",
                summary: summaryParts.joined(separator: " · "),
                symbol: "arrow.triangle.2.circlepath"
            )
        }

        if isConfirmingUpgradePlan {
            return MenuBarStatusPresentation(
                title: "准备升级中",
                summary: "正在准备升级任务",
                symbol: "hourglass"
            )
        }

        if totalUpgradeableCount > 0 {
            return MenuBarStatusPresentation(
                title: "\(totalUpgradeableCount) 个更新",
                summary: "发现 \(totalUpgradeableCount) 个可升级软件",
                symbol: "arrow.down.circle.fill"
            )
        }

        return MenuBarStatusPresentation(
            title: "已最新",
            summary: "当前没有可升级软件",
            symbol: "checkmark.circle"
        )
    }
}
