import Foundation

enum DailyUpgradePolicy {
    static func automaticPackages(from rows: [UpgradePlanRow]) -> [UpdatablePackage] {
        rows.compactMap { row in
            guard row.policy == .automatic,
                  row.canExecute,
                  row.automationDecision == .allowAutomatic else {
                return nil
            }
            return row.package
        }
    }
}
