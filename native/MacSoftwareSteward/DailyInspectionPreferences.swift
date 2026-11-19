import Foundation

enum DailyInspectionPreferences {
    static let hourKey = "dailyInspectionHour"
    static let minuteKey = "dailyInspectionMinute"

    static func hour(defaults: UserDefaults = .standard) -> Int {
        let value = defaults.object(forKey: hourKey) as? Int ?? DailyAutomationDefaults.hour
        return min(max(value, 0), 23)
    }

    static func minute(defaults: UserDefaults = .standard) -> Int {
        let value = defaults.object(forKey: minuteKey) as? Int ?? DailyAutomationDefaults.minute
        return min(max(value, 0), 59)
    }

    static func save(hour: Int, minute: Int, defaults: UserDefaults = .standard) {
        defaults.set(min(max(hour, 0), 23), forKey: hourKey)
        defaults.set(min(max(minute, 0), 59), forKey: minuteKey)
    }
}
