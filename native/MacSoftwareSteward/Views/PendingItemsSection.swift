import AppKit
import SwiftUI

struct PendingItemsSection: View {
    @EnvironmentObject private var inboxStore: InboxStore

    var body: some View {
        if !inboxStore.pendingItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("待处理")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Badge(text: "\(inboxStore.pendingItems.count)", color: .orange)
                }
                .padding(.horizontal, 4)

                LazyVStack(spacing: 8) {
                    ForEach(inboxStore.pendingItems) { item in
                        PendingItemRow(item: item)
                    }
                }
            }
        }
    }
}

private struct PendingItemRow: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore
    @EnvironmentObject private var inboxStore: InboxStore
    var item: InboxItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: severitySymbol)
                    .font(.title3)
                    .foregroundStyle(severityColor)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(.headline, design: .rounded))
                    Text(item.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Badge(text: severityTitle, color: severityColor)
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
                    mark(status: .resolved)
                } label: {
                    Label("完成", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderless)

                Button {
                    mark(status: .ignored)
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
                .stroke(severityColor.opacity(0.18), lineWidth: 1)
        )
    }

    private func perform(_ kind: InboxActionKind) {
        switch kind {
        case .openUpdates, .openSources:
            model.selectedTab = .updates
        case .openApplications:
            model.selectedTab = .applications
        case .openJobs:
            model.selectedTab = .jobs
        case .openRules:
            model.selectedTab = .rules
        case .openSettings:
            model.selectedTab = .settings
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
            model.selectedTab = .jobs
        case .openStorageSettings:
            guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") else { return }
            NSWorkspace.shared.open(url)
        }
    }

    private func mark(status: InboxStatus) {
        inboxStore.updateStatus(id: item.id, status: status)
        model.historyStore.append(InboxHistoryRecorder.record(for: item, status: status))
    }

    private var severityTitle: String {
        switch item.severity {
        case .info: return "信息"
        case .warning: return "需确认"
        case .critical: return "严重"
        }
    }

    private var severitySymbol: String {
        switch item.severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .critical: return "xmark.octagon"
        }
    }

    private var severityColor: Color {
        switch item.severity {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
