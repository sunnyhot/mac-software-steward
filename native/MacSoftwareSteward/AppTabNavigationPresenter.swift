import Foundation

enum SidebarRowInteractionState: Equatable {
    case normal
    case hovered
    case selected

    var showsSelectionIndicator: Bool {
        self == .selected
    }
}

enum AppTabNavigationPresenter {
    static func primaryTabs(advancedModeEnabled: Bool) -> [AppTab] {
        advancedModeEnabled ? [.updates, .applications] : [.applications, .history]
    }

    static func advancedTabs(advancedModeEnabled: Bool) -> [AppTab] {
        advancedModeEnabled ? [.sources, .rules, .history, .performance, .jobs] : []
    }

    static let footerTabs: [AppTab] = [.settings]

    static func visibleTabs(advancedModeEnabled: Bool) -> [AppTab] {
        primaryTabs(advancedModeEnabled: advancedModeEnabled)
            + advancedTabs(advancedModeEnabled: advancedModeEnabled)
            + footerTabs
    }

    static func fallbackTab(for selectedTab: AppTab, advancedModeEnabled: Bool) -> AppTab {
        visibleTabs(advancedModeEnabled: advancedModeEnabled).contains(selectedTab)
            ? selectedTab
            : .applications
    }

    static func isAdvancedTool(_ tab: AppTab, advancedModeEnabled: Bool) -> Bool {
        advancedTabs(advancedModeEnabled: advancedModeEnabled).contains(tab)
    }

    static func advancedCaption(for selectedTab: AppTab, advancedModeEnabled: Bool) -> String {
        isAdvancedTool(selectedTab, advancedModeEnabled: advancedModeEnabled) ? selectedTab.rawValue : ""
    }
}
