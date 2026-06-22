import Foundation

@main
struct AppTabVisibilityTest {
    static func main() {
        precondition(AppTab.visibleTabs(advancedModeEnabled: false) == [
            .applications,
            .history,
            .settings
        ])
        precondition(AppTab.visibleTabs(advancedModeEnabled: true) == [
            .updates,
            .applications,
            .sources,
            .rules,
            .history,
            .performance,
            .jobs,
            .settings
        ])
        precondition(!AppTab.visibleTabs(advancedModeEnabled: false).contains(.inbox))
        precondition(!AppTab.visibleTabs(advancedModeEnabled: true).contains(.inbox))
        precondition(AppTabNavigationPresenter.primaryTabs(advancedModeEnabled: true) == [.updates, .applications])
        precondition(AppTabNavigationPresenter.primaryTabs(advancedModeEnabled: false) == [.applications, .history])
        precondition(AppTabNavigationPresenter.advancedTabs(advancedModeEnabled: true) == [.sources, .rules, .history, .performance, .jobs])
        precondition(AppTabNavigationPresenter.advancedTabs(advancedModeEnabled: false).isEmpty)
        precondition(AppTabNavigationPresenter.footerTabs == [.settings])
        precondition(AppTabNavigationPresenter.fallbackTab(for: .inbox, advancedModeEnabled: true) == .applications)
        precondition(AppTabNavigationPresenter.fallbackTab(for: .sources, advancedModeEnabled: false) == .applications)
        precondition(AppTabNavigationPresenter.isAdvancedTool(.jobs, advancedModeEnabled: true))
        precondition(!AppTabNavigationPresenter.isAdvancedTool(.updates, advancedModeEnabled: true))
        precondition(SidebarRowInteractionState.hovered != SidebarRowInteractionState.selected)
        precondition(SidebarRowInteractionState.selected.showsSelectionIndicator)
        precondition(!SidebarRowInteractionState.hovered.showsSelectionIndicator)
        precondition(AppTab.inbox.symbol == "tray.and.arrow.down")
        precondition(AppTab.rules.symbol == "list.bullet.clipboard")
        precondition(AppTab.history.symbol == "clock.arrow.circlepath")
        precondition(AppTab.performance.symbol == "speedometer")
        precondition(AppTab.inbox.usesSearch == false)
        precondition(AppTab.rules.usesSearch == false)
        precondition(AppTab.performance.usesSearch == false)
        precondition(AppTab.updates.usesSearch == true)
    }
}
