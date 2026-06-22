import SwiftUI

struct RulesView: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore

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
            AutomationProfileRow()
            SettingsDivider()
            DailyInspectionToggleRow()
            if model.dailyInspectionEnabled {
                SettingsDivider()
                DailyInspectionTimeRow()
            }
            SettingsDivider()
            RegularAppNetworkPolicyRow()
            SettingsDivider()
            RulesToggleRow(
                title: "低风险自动升级",
                detail: "每日巡检可自动执行低风险升级项。",
                isOn: Binding(
                    get: { automationProfile.profile.lowRiskAutoUpgradeEnabled },
                    set: { automationProfile.setLowRiskAutoUpgradeEnabled($0) }
                )
            )
            SettingsDivider()
            NotificationPolicyRow()
        }
    }

    private var riskRuleControls: some View {
        SettingsGroupBox {
            SettingsGroupHeader(title: "风险规则", symbol: "exclamationmark.shield")
            GreedyCaskRow()
            SettingsDivider()
            BrewUpdateRow()
            SettingsDivider()
            MaxConcurrentUpgradesRow()
        }
    }

    private var recoveryRuleControls: some View {
        SettingsGroupBox {
            SettingsGroupHeader(title: "恢复规则", symbol: "cross.case")
            AutoRepairPolicyRow()
        }
    }
}

private struct RulesToggleRow: View {
    var title: String
    var detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}
