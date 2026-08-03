import Foundation

@main
struct AppTabVisibilityTest {
    static func main() {
        precondition(AppTabNavigationPresenter.visibleTabs == [
            .updates,
            .applications,
            .settings
        ])
        precondition(AppTab.allCases == AppTabNavigationPresenter.visibleTabs)
        precondition(AppTabNavigationPresenter.primaryTabs == [.updates, .applications])
        precondition(AppTabNavigationPresenter.footerTabs == [.settings])
        precondition(SidebarRowInteractionState.hovered != SidebarRowInteractionState.selected)
        precondition(SidebarRowInteractionState.selected.showsSelectionIndicator)
        precondition(!SidebarRowInteractionState.hovered.showsSelectionIndicator)
        precondition(AppTab.applications.rawValue == "本机软件")
        precondition(AppTab.settings.rawValue == "设置")
        precondition(AppTab.settings.symbol == "gearshape")
        precondition(AppTab.settings.usesSearch == false)
        precondition(AppTab.updates.usesSearch == true)
    }
}
