import Foundation

@main
struct AutomationMaintenanceAccessTest {
    static func main() {
        let defaultAccess = AutomationMaintenanceAccessPresenter.dailyInspectionAccess(for: .manualDefault)
        precondition(defaultAccess.canEnable == false)
        precondition(defaultAccess.caption == "先开启自动化管家后再启用每日巡检")
        precondition(defaultAccess.disabledReason == "自动化引导未完成")

        var manualProfile = AutomationProfile.manualDefault
        manualProfile.onboardingCompleted = true
        manualProfile.automationEnabled = false

        let manualAccess = AutomationMaintenanceAccessPresenter.dailyInspectionAccess(for: manualProfile)
        precondition(manualAccess.canEnable == false)
        precondition(manualAccess.caption == "自动化管家关闭时不会启用每日巡检")
        precondition(manualAccess.disabledReason == "自动化管家已关闭")

        var enabledProfile = manualProfile
        enabledProfile.automationEnabled = true
        enabledProfile.dailyInspectionEnabled = true

        let enabledAccess = AutomationMaintenanceAccessPresenter.dailyInspectionAccess(for: enabledProfile)
        precondition(enabledAccess.canEnable == true)
        precondition(enabledAccess.caption == "定时扫描可管理来源，发现可升级项后自动执行低风险升级")
        precondition(enabledAccess.disabledReason == nil)
    }
}
