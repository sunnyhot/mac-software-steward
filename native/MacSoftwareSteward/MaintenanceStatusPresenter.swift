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
                detail: "可先检查策略，再执行一键升级",
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
