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
    static let primaryTabs: [AppTab] = [.overview, .updates, .applications]
    static let controlTabs: [AppTab] = [.rules, .jobs]
    static let footerTabs: [AppTab] = [.settings]
    static let visibleTabs = primaryTabs + controlTabs + footerTabs
}
