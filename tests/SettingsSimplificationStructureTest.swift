import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let settingsURL = root.appendingPathComponent("native/MacSoftwareSteward/Views/SettingsView.swift")
let source = try String(contentsOf: settingsURL, encoding: .utf8)
let layout = source.components(separatedBy: "// MARK: - Settings Group Box").first ?? ""

for required in ["AutomaticMaintenanceRow", "DailyInspectionTimeRow", "NotificationPolicyRow", "DailyInspectionHealthRow", "DockIconRow"] {
    precondition(layout.contains("\(required)()"), "\(required) must remain on the automation-only settings page")
}
for removed in [
    "LowRiskHandlingRow", "LaunchAtLoginRow", "AppearanceRow",
    "AutoCheckUpdateRow", "AutoDownloadUpdateRow", "ManualCheckUpdateRow",
    "RegularAppNetworkPolicyRow", "AutoRepairPolicyRow", "GreedyCaskRow",
    "BrewUpdateRow", "MaxConcurrentUpgradesRow"
] {
    precondition(!layout.contains("\(removed)()"), "\(removed) must use a default instead of a setting")
}
precondition(!layout.contains("showsAdvancedUpgradeOptions"), "The settings page must not retain the old advanced section")

let master = source.components(separatedBy: "struct AutomaticMaintenanceRow: View").last ?? ""
precondition(master.contains("setLowRiskAutoUpgradeEnabled(true)"))
precondition(master.contains("setAutoRepairPolicy(.allowLowRisk)"))
precondition(master.contains("autoRepairPolicy == .allowLowRisk"), "The master state must include low-risk repair authorization")
precondition(master.contains("setDailyInspectionEnabled(true)"))
precondition(master.contains("setLowRiskAutoUpgradeEnabled(false)"))
precondition(master.contains("setAutoRepairPolicy(.manualOnly)"))
precondition(master.contains("setDailyInspectionEnabled(false)"))
precondition(master.contains("model.isUpdatingDailyInspection"))
