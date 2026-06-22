import Foundation

struct AutomationMaintenanceAccess: Equatable {
    var canEnable: Bool
    var caption: String
    var disabledReason: String?
}

enum AutomationMaintenanceAccessPresenter {
    static func dailyInspectionAccess(for profile: AutomationProfile) -> AutomationMaintenanceAccess {
        guard profile.onboardingCompleted else {
            return AutomationMaintenanceAccess(
                canEnable: false,
                caption: "先开启自动化管家后再启用每日巡检",
                disabledReason: "自动化引导未完成"
            )
        }

        guard profile.automationEnabled else {
            return AutomationMaintenanceAccess(
                canEnable: false,
                caption: "自动化管家关闭时不会启用每日巡检",
                disabledReason: "自动化管家已关闭"
            )
        }

        return AutomationMaintenanceAccess(
            canEnable: true,
            caption: "定时扫描可升级项，发现低风险项目后自动处理",
            disabledReason: nil
        )
    }
}
