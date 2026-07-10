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
        advancedModeEnabled ? [.overview, .updates, .applications] : [.overview, .applications]
    }

    static func controlTabs(advancedModeEnabled: Bool) -> [AppTab] {
        advancedModeEnabled ? [.rules, .jobs] : []
    }

    static func advancedTabs(advancedModeEnabled: Bool) -> [AppTab] {
        []
    }

    static let footerTabs: [AppTab] = [.settings]

    static func visibleTabs(advancedModeEnabled: Bool) -> [AppTab] {
        primaryTabs(advancedModeEnabled: advancedModeEnabled)
            + controlTabs(advancedModeEnabled: advancedModeEnabled)
            + advancedTabs(advancedModeEnabled: advancedModeEnabled)
            + footerTabs
    }

    static func fallbackTab(for selectedTab: AppTab, advancedModeEnabled: Bool) -> AppTab {
        visibleTabs(advancedModeEnabled: advancedModeEnabled).contains(selectedTab)
            ? selectedTab
            : .overview
    }

    static func isAdvancedTool(_ tab: AppTab, advancedModeEnabled: Bool) -> Bool {
        advancedTabs(advancedModeEnabled: advancedModeEnabled).contains(tab)
    }
}
