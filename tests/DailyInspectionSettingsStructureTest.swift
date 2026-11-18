import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let settingsURL = root.appendingPathComponent("native/MacSoftwareSteward/Views/SettingsView.swift")
let appURL = root.appendingPathComponent("native/MacSoftwareSteward/App.swift")
let settings = try String(contentsOf: settingsURL, encoding: .utf8)
let app = try String(contentsOf: appURL, encoding: .utf8)
let modelURL = root.appendingPathComponent("native/MacSoftwareSteward/StewardModel.swift")
let model = try String(contentsOf: modelURL, encoding: .utf8)
let policyURL = root.appendingPathComponent("native/MacSoftwareSteward/DailyInspectionRepairPolicy.swift")
let policy = try String(contentsOf: policyURL, encoding: .utf8)

func component(named name: String, in source: String) -> String {
    guard let start = source.range(of: "struct \(name): View") else {
        preconditionFailure("Missing component \(name)")
    }
    let remainder = source[start.lowerBound...]
    let end = remainder.dropFirst().range(of: "\nstruct ")?.lowerBound ?? remainder.endIndex
    return String(remainder[..<end])
}

let masterSource = component(named: "AutomaticMaintenanceRow", in: settings)
precondition(masterSource.contains("await model.enableDailyInspection()"), "The master switch must install LaunchAgent")
precondition(masterSource.contains("await model.disableDailyInspection()"), "The master switch must uninstall LaunchAgent")
precondition(masterSource.contains("setLowRiskAutoUpgradeEnabled(true)"))
precondition(masterSource.contains("setAutoRepairPolicy(.allowLowRisk)"))
precondition(masterSource.contains("setLowRiskAutoUpgradeEnabled(false)"))
precondition(masterSource.contains("setAutoRepairPolicy(.manualOnly)"))
precondition(masterSource.contains("model.isUpdatingDailyInspection"), "The master switch must prevent concurrent configuration writes")

precondition(settings.contains("latestReport: model.inspectionReportStore.reports.first"), "Daily status must use persisted reports")
precondition(app.contains("dailyInspectionPreference: automationProfile.profile.dailyInspectionEnabled"), "Missing plist recovery must honor the saved preference")
precondition(model.contains("func repairDailyInspectionIfNeeded(dailyInspectionPreference: Bool = false) async {\n        guard !isUpdatingDailyInspection"), "Automatic repair must be serialized")
precondition(model.contains("func disableDailyInspection() async {\n        guard !isUpdatingDailyInspection"), "Disable must be serialized with install and repair")
precondition(policy.contains("(config.enabled || isLoaded) ? .uninstall : .none"), "Disabled preference must remove a leftover agent instead of repairing it")
precondition(policy.contains("config.hour != DailyAutomationDefaults.hour"), "Legacy schedules must normalize to the new default")
precondition(policy.contains("config.includeGreedy != DailyAutomationDefaults.includeGreedy"), "Greedy must use the new default")
precondition(policy.contains("config.runBrewUpdate != DailyAutomationDefaults.runBrewUpdate"), "Brew update must use the new default")
precondition(model.contains("DailyInspectionRepairPolicy.action"), "Repair flow must evaluate preference before installation")
