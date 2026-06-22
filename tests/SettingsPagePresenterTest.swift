import Foundation

@main
struct SettingsPagePresenterTest {
    static func main() {
        precondition(SettingsPagePresenter.visibleGroups == [.general, .appUpdates])
        precondition(SettingsPagePresenter.visibleGroups.map(\.title) == ["通用", "应用更新"])
        precondition(SettingsPagePresenter.automationPolicyDestination == .rules)
        precondition(!SettingsPagePresenter.settingsOwnsGroup(title: "自动化管家"))
        precondition(!SettingsPagePresenter.settingsOwnsGroup(title: "扫描与升级策略"))
        precondition(!SettingsPagePresenter.settingsOwnsGroup(title: "每日巡检"))
    }
}
