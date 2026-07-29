import SwiftUI

struct RulesView: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore
    @State private var showsAdvancedUpgradeOptions = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                automationPolicyControls
                riskRuleControls
                recoveryRuleControls

                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var automationPolicyControls: some View {
        SettingsGroupBox {
            SettingsGroupHeader(title: "自动化策略", symbol: "switch.2")
            DailyInspectionToggleRow()
            if model.dailyInspectionEnabled {
                SettingsDivider()
                DailyInspectionTimeRow()
            }
            SettingsDivider()
            RegularAppNetworkPolicyRow()
            SettingsDivider()
            LowRiskHandlingRow()
            SettingsDivider()
            NotificationPolicyRow()
        }
    }

    private var riskRuleControls: some View {
        SettingsGroupBox {
            DisclosureGroup(isExpanded: $showsAdvancedUpgradeOptions) {
                VStack(alignment: .leading, spacing: 12) {
                    GreedyCaskRow()
                    SettingsDivider()
                    BrewUpdateRow()
                    SettingsDivider()
                    MaxConcurrentUpgradesRow()
                }
                .padding(.top, 8)
            } label: {
                SettingsGroupHeader(title: "高级升级选项", symbol: "gearshape.2")
            }
        }
    }

    private var recoveryRuleControls: some View {
        SettingsGroupBox {
            SettingsGroupHeader(title: "恢复规则", symbol: "cross.case")
            AutoRepairPolicyRow()
        }
    }
}
