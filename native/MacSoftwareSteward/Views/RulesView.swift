import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RulesView: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore
    @State private var transferMessage: RulesTransferMessage?
    @State private var rulesQuery = ""
    @State private var categoryFilter: RulesConsoleCategory = .all

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private var sections: [RulesConsoleSection] {
        RulesConsolePresenter.sections(
            profile: automationProfile.profile,
            includeGreedy: model.includeGreedy,
            category: categoryFilter,
            query: rulesQuery
        )
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                policyControls
                dataTransferControls
                rulesFilterControls

                if sections.isEmpty {
                    EmptyStateView(
                        symbol: "line.3.horizontal.decrease.circle",
                        title: "没有匹配的规则",
                        text: "调整分类或搜索词后再查看。"
                    )
                } else {
                    ForEach(sections, id: \.title) { section in
                        RulesSectionView(section: section)
                    }
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

    private var dataTransferControls: some View {
        SettingsGroupBox {
            SettingsGroupHeader(title: "导入导出", symbol: "square.and.arrow.up.on.square")
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("自动化数据")
                        .font(.body)
                    Text("包含自动化配置、单包策略、巡检报告和升级/待办历史。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Button {
                    exportAutomationData()
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)

                Button {
                    importAutomationData()
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
            }

            if let transferMessage {
                SettingsDivider()
                RulesTransferMessageView(message: transferMessage)
            }
        }
    }

    private func exportAutomationData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "mac-software-steward-automation-\(Self.exportDateFormatter.string(from: Date())).json"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                let bundle = AutomationDataBundleService.makeBundle(
                    profile: automationProfile.profile,
                    upgradePolicyOverrides: model.policyStore.overrides,
                    inspectionReports: model.inspectionReportStore.reports,
                    upgradeHistoryRecords: model.historyStore.records
                )
                let data = try AutomationDataBundleService.encode(bundle)
                try data.write(to: url, options: .atomic)
                let summary = AutomationDataBundleService.summary(for: bundle)
                transferMessage = .success("已导出 \(summary.policyCount) 条策略、\(summary.inspectionReportCount) 条报告、\(summary.upgradeHistoryCount) 条历史")
            } catch {
                transferMessage = .failure("导出失败：\(error.localizedDescription)")
            }
        }
    }

    private func importAutomationData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                let data = try Data(contentsOf: url)
                let bundle = try AutomationDataBundleService.decode(data)
                guard confirmImport(bundle) else { return }

                automationProfile.replace(with: bundle.automationProfile)
                model.policyStore.replaceOverrides(bundle.upgradePolicyOverrides)
                model.inspectionReportStore.replaceReports(bundle.inspectionReports)
                model.historyStore.replaceRecords(bundle.upgradeHistoryRecords)
                let summary = AutomationDataBundleService.summary(for: bundle)
                transferMessage = .success("已导入 \(summary.policyCount) 条策略、\(summary.inspectionReportCount) 条报告、\(summary.upgradeHistoryCount) 条历史")
            } catch {
                transferMessage = .failure("导入失败：\(error.localizedDescription)")
            }
        }
    }

    private var rulesFilterControls: some View {
        SettingsGroupBox {
            SettingsGroupHeader(title: "规则筛选", symbol: "line.3.horizontal.decrease.circle")
            HStack(spacing: 12) {
                TextField("搜索规则、状态或说明", text: $rulesQuery)
                    .textFieldStyle(.roundedBorder)

                Picker("分类", selection: $categoryFilter) {
                    ForEach(RulesConsoleCategory.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
            }
        }
    }

    private func confirmImport(_ bundle: AutomationDataBundle) -> Bool {
        let alert = NSAlert()
        alert.messageText = "导入自动化数据？"
        let summary = AutomationDataBundleService.summary(for: bundle)
        alert.informativeText = "文件版本 \(summary.schemaVersion)。这会替换本机自动化配置、\(summary.policyCount) 条单包策略、\(summary.inspectionReportCount) 条巡检报告和 \(summary.upgradeHistoryCount) 条升级/待办历史。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "导入")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

private struct RulesTransferMessage {
    var text: String
    var symbol: String
    var color: Color

    static func success(_ text: String) -> RulesTransferMessage {
        RulesTransferMessage(text: text, symbol: "checkmark.circle.fill", color: .green)
    }

    static func failure(_ text: String) -> RulesTransferMessage {
        RulesTransferMessage(text: text, symbol: "exclamationmark.triangle.fill", color: .red)
    }
}

private struct RulesTransferMessageView: View {
    var message: RulesTransferMessage

    var body: some View {
        Label(message.text, systemImage: message.symbol)
            .font(.caption)
            .foregroundStyle(message.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
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
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(row.detailItems, id: \.self) { item in
                    Label(item, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 6)
            .padding(.leading, 44)
        } label: {
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

                Badge(text: row.category.title, color: .blue)
                Badge(text: row.status, color: statusColor)
            }
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
