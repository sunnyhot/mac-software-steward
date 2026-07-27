import Foundation

@main
struct AppTabVisibilityTest {
    static func main() {
        precondition(AppTabNavigationPresenter.visibleTabs == [
            .overview,
            .updates,
            .applications,
            .rules,
            .jobs,
            .settings
        ])
        precondition(AppTab.allCases == AppTabNavigationPresenter.visibleTabs)
        precondition(AppTabNavigationPresenter.primaryTabs == [.overview, .updates, .applications])
        precondition(AppTabNavigationPresenter.controlTabs == [.rules, .jobs])
        precondition(AppTabNavigationPresenter.footerTabs == [.settings])
        precondition(SidebarRowInteractionState.hovered != SidebarRowInteractionState.selected)
        precondition(SidebarRowInteractionState.selected.showsSelectionIndicator)
        precondition(!SidebarRowInteractionState.hovered.showsSelectionIndicator)
        precondition(AppTab.applications.rawValue == "本机软件")
        precondition(AppTab.rules.rawValue == "自动化策略")
        precondition(AppTab.rules.symbol == "list.bullet.clipboard")
        precondition(AppTab.rules.usesSearch == false)
        precondition(AppTab.updates.usesSearch == true)
    }
}
