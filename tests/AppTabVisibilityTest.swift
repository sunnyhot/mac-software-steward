import Foundation

@main
struct AppTabVisibilityTest {
    static func main() {
        precondition(AppTab.visibleTabs(advancedModeEnabled: false) == [
            .applications,
            .settings
        ])
        precondition(AppTab.visibleTabs(advancedModeEnabled: true) == [
            .updates,
            .applications,
            .rules,
            .jobs,
            .settings
        ])
        precondition(!AppTab.visibleTabs(advancedModeEnabled: false).contains(.inbox))
        precondition(!AppTab.visibleTabs(advancedModeEnabled: true).contains(.inbox))
        precondition(!AppTab.visibleTabs(advancedModeEnabled: true).contains(.sources))
        precondition(!AppTab.visibleTabs(advancedModeEnabled: true).contains(.history))
        precondition(!AppTab.visibleTabs(advancedModeEnabled: true).contains(.performance))
        precondition(AppTabNavigationPresenter.primaryTabs(advancedModeEnabled: true) == [.updates, .applications])
        precondition(AppTabNavigationPresenter.primaryTabs(advancedModeEnabled: false) == [.applications])
        precondition(AppTabNavigationPresenter.controlTabs(advancedModeEnabled: true) == [.rules, .jobs])
        precondition(AppTabNavigationPresenter.controlTabs(advancedModeEnabled: false).isEmpty)
        precondition(AppTabNavigationPresenter.advancedTabs(advancedModeEnabled: true).isEmpty)
        precondition(AppTabNavigationPresenter.advancedTabs(advancedModeEnabled: false).isEmpty)
        precondition(AppTabNavigationPresenter.footerTabs == [.settings])
        precondition(AppTabNavigationPresenter.fallbackTab(for: .inbox, advancedModeEnabled: true) == .applications)
        precondition(AppTabNavigationPresenter.fallbackTab(for: .sources, advancedModeEnabled: false) == .applications)
        precondition(!AppTabNavigationPresenter.isAdvancedTool(.jobs, advancedModeEnabled: true))
        precondition(!AppTabNavigationPresenter.isAdvancedTool(.updates, advancedModeEnabled: true))
        precondition(SidebarRowInteractionState.hovered != SidebarRowInteractionState.selected)
        precondition(SidebarRowInteractionState.selected.showsSelectionIndicator)
        precondition(!SidebarRowInteractionState.hovered.showsSelectionIndicator)
        precondition(AppTab.inbox.symbol == "tray.and.arrow.down")
        precondition(AppTab.applications.rawValue == "本机软件")
        precondition(AppTab.rules.rawValue == "自动化策略")
        precondition(AppTab.rules.symbol == "list.bullet.clipboard")
        precondition(AppTab.history.symbol == "clock.arrow.circlepath")
        precondition(AppTab.performance.symbol == "speedometer")
        precondition(AppTab.inbox.usesSearch == false)
        precondition(AppTab.rules.usesSearch == false)
        precondition(AppTab.performance.usesSearch == false)
        precondition(AppTab.updates.usesSearch == true)
    }
}
