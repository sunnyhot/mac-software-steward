import Foundation

enum DailyInspectionRepairAction {
    case uninstall
    case restore
    case normalize
    case repairExisting
    case none
}

/// 启动/前台恢复前先看用户授权，再看现有安装与新默认值是否一致。
enum DailyInspectionRepairPolicy {
    static func action(
        preferenceEnabled: Bool,
        config: DailyInspectionConfig,
        isLoaded: Bool = false,
        expectedHour: Int = DailyAutomationDefaults.hour,
        expectedMinute: Int = DailyAutomationDefaults.minute
    ) -> DailyInspectionRepairAction {
        guard preferenceEnabled else {
            return (config.enabled || isLoaded) ? .uninstall : .none
        }
        guard config.enabled else { return .restore }
        if config.hour != expectedHour
            || config.minute != expectedMinute
            || config.includeGreedy != DailyAutomationDefaults.includeGreedy
            || config.runBrewUpdate != DailyAutomationDefaults.runBrewUpdate {
            return .normalize
        }
        return .repairExisting
    }
}
