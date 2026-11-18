import Foundation

/// 自动化方向的统一默认参数，不再要求普通用户理解并逐项配置。
enum DailyAutomationDefaults {
    static let hour = 9
    static let minute = 0
    static let includeGreedy = true
    static let runBrewUpdate = true
    static let maxConcurrentUpgrades = 3
}
