import Foundation

@main
struct AppTabVisibilityTest {
    static func main() {
        precondition(AppTabNavigationPresenter.visibleTabs == [.updates, .settings])
        precondition(AppTab.allCases == AppTabNavigationPresenter.visibleTabs)
        precondition(AppTab.allCases.count == 2)
        precondition(AppTabNavigationPresenter.primaryTabs == [.updates])
        precondition(AppTabNavigationPresenter.footerTabs == [.settings])
        precondition(SidebarRowInteractionState.hovered != SidebarRowInteractionState.selected)
        precondition(SidebarRowInteractionState.selected.showsSelectionIndicator)
        precondition(!SidebarRowInteractionState.hovered.showsSelectionIndicator)
        precondition(AppTab.updates.rawValue == "可升级")
        precondition(AppTab.settings.rawValue == "设置")
        precondition(AppTab.settings.symbol == "gearshape")
        precondition(AppTab.settings.usesSearch == false)
        precondition(AppTab.updates.usesSearch == true)
    }
}
