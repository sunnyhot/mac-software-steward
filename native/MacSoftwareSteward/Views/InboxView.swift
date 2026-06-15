import AppKit
import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore
    @EnvironmentObject private var inboxStore: InboxStore
    @State private var kindFilter: InboxKindFilter = .all
    @State private var severityFilter: InboxSeverityFilter = .all

    private var pendingItems: [InboxItem] {
        inboxStore.pendingItems
    }

    private var visibleItems: [InboxItem] {
        guard automationProfile.profile.advancedModeEnabled else { return pendingItems }
        return InboxFilterPresenter.items(from: pendingItems, kind: kindFilter, severity: severityFilter)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !automationProfile.profile.onboardingCompleted {
                AutomationOnboardingCard()
                    .environmentObject(automationProfile)
            }

            AutomationSummaryCard()
                .environmentObject(model)
                .environmentObject(automationProfile)
                .environmentObject(inboxStore)

            if automationProfile.profile.advancedModeEnabled && !pendingItems.isEmpty {
                InboxFilterBar(kindFilter: $kindFilter, severityFilter: $severityFilter)
            }

            if pendingItems.isEmpty {
                EmptyStateView(
                    symbol: "checkmark.circle",
                    title: "暂无待处理事项",
                    text: "需要确认的升级、失败恢复和来源异常会出现在这里。"
                )
            } else if visibleItems.isEmpty {
                EmptyStateView(
                    symbol: "line.3.horizontal.decrease.circle",
                    title: "当前筛选暂无事项",
                    text: "调整类型或严重级别筛选后再查看。"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(visibleItems) { item in
                            InboxItemRow(item: item)
                                .environmentObject(model)
                                .environmentObject(automationProfile)
                                .environmentObject(inboxStore)
                        }
                    }
                }
            }
        }
    }
}

private struct InboxFilterBar: View {
    @Binding var kindFilter: InboxKindFilter
    @Binding var severityFilter: InboxSeverityFilter

    var body: some View {
        HStack(spacing: 10) {
            Picker("类型", selection: $kindFilter) {
                ForEach(InboxKindFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.menu)

            Picker("严重级别", selection: $severityFilter) {
                ForEach(InboxSeverityFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct AutomationOnboardingCard: View {
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: "wand.and.stars")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("开启自动化管家")
                    .font(.system(.headline, design: .rounded))
                Text("默认只自动处理低风险升级；需要确认或失败时再提醒。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("保持手动") {
                automationProfile.completeOnboarding(enableAutomation: false)
            }
            .buttonStyle(.bordered)

            Button("开启") {
                automationProfile.completeOnboarding(enableAutomation: true)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct AutomationSummaryCard: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore
    @EnvironmentObject private var inboxStore: InboxStore

    var body: some View {
        HStack(spacing: 10) {
            SummaryPill(
                title: "自动化",
                value: automationProfile.profile.automationEnabled ? "已开启" : "手动模式",
                symbol: automationProfile.profile.automationEnabled ? "checkmark.shield" : "hand.raised"
            )
            SummaryPill(
                title: "待处理",
                value: "\(inboxStore.pendingItems.count)",
                symbol: "tray.and.arrow.down"
            )
            SummaryPill(
                title: "可操作升级",
                value: "\(model.availableUpdates.count)",
                symbol: "arrow.down.circle"
            )
            SummaryPill(
                title: "高级模式",
                value: automationProfile.profile.advancedModeEnabled ? "已开启" : "已关闭",
                symbol: "slider.horizontal.3"
            )
        }
    }
}

private struct SummaryPill: View {
    var title: String
    var value: String
    var symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.callout)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.headline, design: .rounded))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct InboxItemRow: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore
    @EnvironmentObject private var inboxStore: InboxStore
    var item: InboxItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: severitySymbol(item.severity))
                    .font(.title3)
                    .foregroundStyle(severityColor(item.severity))
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(.headline, design: .rounded))
                    Text(item.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Badge(text: severityTitle(item.severity), color: severityColor(item.severity))
            }

            HStack(spacing: 8) {
                ForEach(item.actions, id: \.self) { action in
                    Button {
                        perform(action.kind)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                Button {
                    inboxStore.updateStatus(id: item.id, status: .resolved)
                } label: {
                    Label("完成", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderless)

                Button {
                    inboxStore.updateStatus(id: item.id, status: .ignored)
                } label: {
                    Label("忽略", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(severityColor(item.severity).opacity(0.18), lineWidth: 1)
        )
    }

    private func perform(_ kind: InboxActionKind) {
        switch kind {
        case .openUpdates:
            open(tab: .updates)
        case .openApplications:
            open(tab: .applications)
        case .openSources:
            open(tab: .sources)
        case .openJobs:
            open(tab: .jobs)
        case .openSettings:
            open(tab: .settings)
        case .rescan:
            Task {
                await model.scanSoftware(
                    regularAppNetworkPolicy: automationProfile.profile.regularAppNetworkPolicy,
                    notificationPolicy: automationProfile.profile.notificationPolicy,
                    inboxStore: inboxStore
                )
            }
        case .retryPackage:
            guard let packageID = item.sourceID else { return }
            Task {
                await model.retryPackage(packageID, inboxStore: inboxStore)
            }
        case .copyRecoveryCommand:
            guard
                let packageID = item.sourceID,
                let progress = model.packageProgress[packageID]
            else { return }
            let command = progress.lastFailedCommand.isEmpty ? progress.copyText : progress.lastFailedCommand
            guard !command.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            open(tab: .jobs)
        case .openStorageSettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func open(tab: AppTab) {
        let visibleTabs = AppTab.visibleTabs(advancedModeEnabled: automationProfile.profile.advancedModeEnabled)
        if !visibleTabs.contains(tab) {
            automationProfile.setAdvancedMode(true)
        }
        model.selectedTab = tab
    }
}

private func severityTitle(_ severity: InboxSeverity) -> String {
    switch severity {
    case .info: return "信息"
    case .warning: return "需确认"
    case .critical: return "严重"
    }
}

private func severitySymbol(_ severity: InboxSeverity) -> String {
    switch severity {
    case .info: return "info.circle"
    case .warning: return "exclamationmark.triangle"
    case .critical: return "xmark.octagon"
    }
}

private func severityColor(_ severity: InboxSeverity) -> Color {
    switch severity {
    case .info: return .blue
    case .warning: return .orange
    case .critical: return .red
    }
}
