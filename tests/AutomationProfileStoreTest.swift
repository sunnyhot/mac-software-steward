import Foundation

@main
struct AutomationProfileStoreTest {
    static func main() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("automation-profile-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = AutomationProfileStore(fileURL: url)
        precondition(store.profile == .manualDefault)
        precondition(store.profile.dailyInspectionEnabled == false)
        precondition(store.profile.lowRiskAutoUpgradeEnabled == false)
        precondition(store.profile.notificationPolicy == .decisionsAndFailures)
        precondition(store.profile.regularAppNetworkPolicy == .declaredSourcesOnly)
        precondition(store.profile.autoRepairPolicy == .manualOnly)

        store.setDailyInspectionEnabled(true)
        store.setLowRiskAutoUpgradeEnabled(true)
        precondition(store.profile.dailyInspectionEnabled == true)
        precondition(store.profile.lowRiskAutoUpgradeEnabled == true)

        store.setNotificationPolicy(.everyInspection)
        store.setRegularAppNetworkPolicy(.localOnly)
        store.setAutoRepairPolicy(.allowLowRisk)

        let reloaded = AutomationProfileStore(fileURL: url)
        precondition(reloaded.profile.dailyInspectionEnabled == true)
        precondition(reloaded.profile.lowRiskAutoUpgradeEnabled == true)
        precondition(reloaded.profile.notificationPolicy == .decisionsAndFailures)
        precondition(reloaded.profile.regularAppNetworkPolicy == .declaredSourcesOnly)
        precondition(reloaded.profile.autoRepairPolicy == .allowLowRisk)

        var importedProfile = AutomationProfile.manualDefault
        importedProfile.notificationPolicy = .silent
        importedProfile.regularAppNetworkPolicy = .aggressive
        importedProfile.autoRepairPolicy = .allowLowRisk
        reloaded.replace(with: importedProfile)

        let importedReloaded = AutomationProfileStore(fileURL: url)
        precondition(importedReloaded.profile.notificationPolicy == .silent)
        precondition(importedReloaded.profile.regularAppNetworkPolicy == .declaredSourcesOnly)
        precondition(importedReloaded.profile.autoRepairPolicy == .manualOnly)

        reloaded.setLowRiskAutoUpgradeEnabled(false)
        precondition(reloaded.profile.lowRiskAutoUpgradeEnabled == false)

        let legacyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("automation-profile-legacy-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: legacyURL) }
        let legacyJSON = """
        {
          "onboardingCompleted": true,
          "automationEnabled": true,
          "dailyInspectionEnabled": true,
          "lowRiskAutoUpgradeEnabled": true,
          "notificationPolicy": "silent",
          "regularAppNetworkPolicy": "localOnly",
          "autoRepairPolicy": "allowLowRisk"
        }
        """
        try! Data(legacyJSON.utf8).write(to: legacyURL)
        let migrated = AutomationProfileStore(fileURL: legacyURL)
        precondition(migrated.profile.dailyInspectionEnabled == true)
        precondition(migrated.profile.lowRiskAutoUpgradeEnabled == true)
        precondition(migrated.profile.notificationPolicy == .silent)
        precondition(migrated.profile.regularAppNetworkPolicy == .declaredSourcesOnly)
        precondition(migrated.profile.autoRepairPolicy == .allowLowRisk)

        let manualURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("automation-manual-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: manualURL) }
        let manualStore = AutomationProfileStore(fileURL: manualURL)
        manualStore.setDailyInspectionEnabled(true)
        manualStore.setLowRiskAutoUpgradeEnabled(true)
        manualStore.setAutoRepairPolicy(.manualOnly)
        let manualReloaded = AutomationProfileStore(fileURL: manualURL)
        precondition(manualReloaded.profile.dailyInspectionEnabled)
        precondition(manualReloaded.profile.lowRiskAutoUpgradeEnabled)
        precondition(manualReloaded.profile.autoRepairPolicy == .manualOnly, "manualOnly must not be silently upgraded to allowLowRisk")
    }
}
