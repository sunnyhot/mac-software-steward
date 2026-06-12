import Foundation

@main
struct AppTabVisibilityTest {
    static func main() {
        precondition(AppTab.visibleTabs(advancedModeEnabled: false) == [
            .inbox,
            .applications,
            .history,
            .settings
        ])
        precondition(AppTab.visibleTabs(advancedModeEnabled: true) == [
            .inbox,
            .updates,
            .applications,
            .sources,
            .history,
            .jobs,
            .settings
        ])
        precondition(AppTab.inbox.symbol == "tray.and.arrow.down")
        precondition(AppTab.history.symbol == "clock.arrow.circlepath")
        precondition(AppTab.inbox.usesSearch == false)
        precondition(AppTab.updates.usesSearch == true)
    }
}
