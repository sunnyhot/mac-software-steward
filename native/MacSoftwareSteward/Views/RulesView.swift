import SwiftUI

struct RulesView: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    private var sections: [RulesConsoleSection] {
        RulesConsolePresenter.sections(
            profile: automationProfile.profile,
            includeGreedy: model.includeGreedy
        )
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                policyControls

                ForEach(sections, id: \.title) { section in
                    RulesSectionView(section: section)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var policyControls: some View {
        SettingsGroupBox {
            SettingsGroupHeader(title: "策略控制", symbol: "slider.horizontal.3")
            RulesPickerRow(
                title: "普通 App 联网策略",
                detail: "控制 Sparkle、声明来源与厂商页面检查范围。",
                selection: Binding(
                    get: { automationProfile.profile.regularAppNetworkPolicy },
                    set: { automationProfile.setRegularAppNetworkPolicy($0) }
                ),
                options: Array(RegularAppNetworkPolicy.allCases),
                optionTitle: { $0.title }
            )
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
            RulesPickerRow(
                title: "自动修复策略",
                detail: "控制失败后的低风险恢复动作是否可自动执行。",
                selection: Binding(
                    get: { automationProfile.profile.autoRepairPolicy },
                    set: { automationProfile.setAutoRepairPolicy($0) }
                ),
                options: Array(AutoRepairPolicy.allCases),
                optionTitle: { $0.title }
            )
            SettingsDivider()
            RulesToggleRow(
                title: "包含 greedy cask",
                detail: "将 auto_updates 或 latest Cask 纳入扫描。",
                isOn: $model.includeGreedy
            )
        }
    }
}

private struct RulesSectionView: View {
    var section: RulesConsoleSection

    var body: some View {
        SettingsGroupBox {
            SettingsGroupHeader(title: section.title, symbol: sectionSymbol)
            Text(section.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    SettingsDivider()
                }
                RulesConsoleRowView(row: row)
            }
        }
    }

    private var sectionSymbol: String {
        switch section.title {
        case "自动化策略": return "switch.2"
        case "风险规则": return "exclamationmark.shield"
        case "恢复规则": return "cross.case"
        default: return "list.bullet.clipboard"
        }
    }
}

private struct RulesConsoleRowView: View {
    var row: RulesConsoleRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(statusColor.opacity(0.12))
                    .frame(width: 32, height: 32)

                Image(systemName: row.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.primary)
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Badge(text: row.status, color: statusColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        switch row.status {
        case "开启", "仅低风险":
            return .green
        case "关闭", "阻止":
            return .red
        case "需确认", "扩大":
            return .orange
        case "标准":
            return .blue
        default:
            return .secondary
        }
    }
}

private struct RulesPickerRow<Option: Identifiable & Hashable>: View {
    var title: String
    var detail: String
    @Binding var selection: Option
    var options: [Option]
    var optionTitle: (Option) -> String

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

            Picker("", selection: $selection) {
                ForEach(options) { option in
                    Text(optionTitle(option)).tag(option)
                }
            }
            .frame(width: 240)
            .labelsHidden()
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
