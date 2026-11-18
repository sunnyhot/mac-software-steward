import Foundation

/// 本地、可测试的智能维护决策：避免重复更新，并限定可自动清理的安全边界。
enum SmartMaintenancePolicy {
    static func canReconcileStaleRecords(scan: ScanResult) -> Bool {
        scan.brew.available
            && scan.brew.error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && scan.brew.uncheckedCasks.isEmpty
            && scan.brew.metadataComplete
    }

    static func shouldDeferToSelfUpdater(_ package: UpdatablePackage) -> Bool {
        guard case .brew(let brew) = package else { return false }
        return brew.kind == "cask" && brew.autoUpdates && !brew.hasStaleInstallRecord
    }

    /// 自动清理同时受三个既有授权约束：启用每日巡检、允许自动处理、允许低风险修复。
    /// 只返回元数据标记为残留的 cask；执行前还必须再次检查真实 App 路径。
    static func automaticStaleCleanupCandidates(
        scan: ScanResult,
        profile: AutomationProfile
    ) -> [BrewPackage] {
        guard profile.dailyInspectionEnabled,
              profile.lowRiskAutoUpgradeEnabled,
              profile.autoRepairPolicy == .allowLowRisk else { return [] }
        return scan.brew.casks
            .filter { $0.kind == "cask" && $0.hasStaleInstallRecord && !$0.expectedAppPaths.isEmpty }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func removingCasks(packageIDs: Set<String>, from scan: ScanResult) -> ScanResult {
        guard !packageIDs.isEmpty else { return scan }
        var updated = scan
        let removed = updated.brew.casks.filter { packageIDs.contains($0.id) }
        guard !removed.isEmpty else { return scan }
        updated.brew.casks.removeAll { packageIDs.contains($0.id) }
        let removedNames = Set(removed.map(\.name))
        updated.brew.uncheckedCasks.removeAll { removedNames.contains($0) }
        updated.summary.brewCasks = updated.brew.casks.count
        for cask in removed {
            if cask.outdated {
                updated.summary.outdated = max(0, updated.summary.outdated - 1)
            }
            if cask.upgradeable {
                updated.summary.actionable = max(0, updated.summary.actionable - 1)
            }
        }
        updated.performance.brewCasks = updated.summary.brewCasks
        updated.performance.outdated = updated.summary.outdated
        updated.performance.actionable = updated.summary.actionable
        return updated
    }
}
