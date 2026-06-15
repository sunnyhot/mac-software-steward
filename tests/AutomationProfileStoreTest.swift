import Foundation

@main
struct AutomationProfileStoreTest {
    static func main() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("automation-profile-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = AutomationProfileStore(fileURL: url)
        precondition(store.profile == .manualDefault)
        precondition(store.profile.onboardingCompleted == false)
        precondition(store.profile.automationEnabled == false)
        precondition(store.profile.advancedModeEnabled == false)
        precondition(store.profile.notificationPolicy == .decisionsAndFailures)
        precondition(store.profile.regularAppNetworkPolicy == .declaredSourcesOnly)
        precondition(store.profile.autoRepairPolicy == .manualOnly)

        store.completeOnboarding(enableAutomation: true)
        precondition(store.profile.onboardingCompleted == true)
        precondition(store.profile.automationEnabled == true)
        precondition(store.profile.dailyInspectionEnabled == true)
        precondition(store.profile.lowRiskAutoUpgradeEnabled == true)

        store.setAdvancedMode(true)
        store.setNotificationPolicy(.everyInspection)
        store.setRegularAppNetworkPolicy(.localOnly)
        store.setAutoRepairPolicy(.allowLowRisk)

        let reloaded = AutomationProfileStore(fileURL: url)
        precondition(reloaded.profile.onboardingCompleted == true)
        precondition(reloaded.profile.automationEnabled == true)
        precondition(reloaded.profile.advancedModeEnabled == true)
        precondition(reloaded.profile.notificationPolicy == .everyInspection)
        precondition(reloaded.profile.regularAppNetworkPolicy == .localOnly)
        precondition(reloaded.profile.autoRepairPolicy == .allowLowRisk)

        var importedProfile = AutomationProfile.manualDefault
        importedProfile.onboardingCompleted = true
        importedProfile.advancedModeEnabled = true
        importedProfile.notificationPolicy = .silent
        importedProfile.regularAppNetworkPolicy = .aggressive
        importedProfile.autoRepairPolicy = .allowLowRisk
        reloaded.replace(with: importedProfile)

        let importedReloaded = AutomationProfileStore(fileURL: url)
        precondition(importedReloaded.profile == importedProfile)

        reloaded.setAutomationEnabled(false)
        precondition(reloaded.profile.automationEnabled == false)
        precondition(reloaded.profile.lowRiskAutoUpgradeEnabled == false)
    }
}
