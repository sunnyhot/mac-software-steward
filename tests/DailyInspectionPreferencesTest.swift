import Foundation

@main
struct DailyInspectionPreferencesTest {
    static func main() throws {
        let suiteName = "DailyInspectionPreferencesTest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create test defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        precondition(DailyInspectionPreferences.hour(defaults: defaults) == 9)
        precondition(DailyInspectionPreferences.minute(defaults: defaults) == 0)
        DailyInspectionPreferences.save(hour: 8, minute: 45, defaults: defaults)
        precondition(DailyInspectionPreferences.hour(defaults: defaults) == 8)
        precondition(DailyInspectionPreferences.minute(defaults: defaults) == 45)
        DailyInspectionPreferences.save(hour: 25, minute: 70, defaults: defaults)
        precondition(DailyInspectionPreferences.hour(defaults: defaults) == 23)
        precondition(DailyInspectionPreferences.minute(defaults: defaults) == 59)

        let model = try String(contentsOfFile: "native/MacSoftwareSteward/StewardModel.swift", encoding: .utf8)
        precondition(model.contains("DailyInspectionPreferences.hour()"))
        precondition(model.contains("DailyInspectionPreferences.minute()"))
        precondition(model.contains("func saveDailyInspectionTime()"))
        precondition(!model.contains("dailyHour = DailyAutomationDefaults.hour"))
        precondition(!model.contains("dailyMinute = DailyAutomationDefaults.minute"))
    }
}
