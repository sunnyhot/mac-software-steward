import Foundation

enum SettingsPageGroup: String, Equatable {
    case general = "通用"
    case appUpdates = "应用更新"

    var title: String {
        rawValue
    }

    var symbol: String {
        switch self {
        case .general:
            return "gearshape"
        case .appUpdates:
            return "arrow.down.app"
        }
    }
}

enum SettingsPagePresenter {
    static let visibleGroups: [SettingsPageGroup] = [.general, .appUpdates]
    static let automationPolicyDestination: AppTab = .rules

    private static let automationStrategyOwnedGroupTitles: Set<String> = [
        "自动化管家",
        "扫描与升级策略",
        "每日巡检"
    ]

    static func settingsOwnsGroup(title: String) -> Bool {
        !automationStrategyOwnedGroupTitles.contains(title)
    }
}
