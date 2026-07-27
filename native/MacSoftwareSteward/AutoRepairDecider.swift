import Foundation

enum AutoRepairDecider {
    static func automaticAction(
        for progress: PackageUpgradeProgress,
        profile: AutomationProfile,
        attemptedPackageIDs: Set<String>
    ) -> RecoveryAction? {
        guard profile.automationEnabled else { return nil }
        guard profile.autoRepairPolicy == .allowLowRisk else { return nil }
        guard !attemptedPackageIDs.contains(progress.packageID) else { return nil }
        return RecoveryActionPlanner.actions(for: progress)
            .first { $0.allowsAutomaticRepair }
    }
}
