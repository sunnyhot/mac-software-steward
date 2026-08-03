import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var updater: AppUpdateModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore
    @EnvironmentObject private var inboxStore: InboxStore

    var body: some View {
        NavigationSplitView {
            TaskFirstSidebar()
                .environmentObject(model)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230)
        } detail: {
            MainPanel()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(StewardCanvasBackground().ignoresSafeArea())
                .animation(.easeInOut(duration: 0.2), value: model.selectedTab)
        }
        .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task {
                        await model.scanSoftware(
                            regularAppNetworkPolicy: automationProfile.profile.regularAppNetworkPolicy,
                            notificationPolicy: automationProfile.profile.notificationPolicy,
                            inboxStore: inboxStore
                        )
                    }
                } label: {
                    Label(model.isScanning ? "扫描中" : "扫描软件", systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanning)

                Button {
                    Task {
                        await model.checkAndPrepareMaintenance(
                            regularAppNetworkPolicy: automationProfile.profile.regularAppNetworkPolicy,
                            notificationPolicy: automationProfile.profile.notificationPolicy,
                            inboxStore: inboxStore
                        )
                    }
                } label: {
                    Label(
                        maintenanceActionTitle,
                        systemImage: model.hasRunningJob ? "hourglass" : "bolt.fill"
                    )
                }
                .disabled(model.isScanning || model.hasRunningJob || model.isConfirmingUpgradePlan)
                .help("重新扫描软件并生成可确认的维护计划")
            }
        }
        .sheet(isPresented: $updater.showUpdateDialog) {
            AppUpdateDialog()
                .environmentObject(updater)
        }
        .sheet(isPresented: $model.showingUpgradePlan) {
            UpgradePlanView()
                .environmentObject(model)
        }
    }

    private var maintenanceActionTitle: String {
        if model.isScanning { return "检查中" }
        if model.hasRunningJob { return "维护中" }
        if model.isConfirmingUpgradePlan { return "准备中" }
        return "检查并维护"
    }
}

// MARK: - Task First Sidebar

private struct TaskFirstSidebar: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sidebarHeader

            SidebarSection(title: "日常维护") {
                ForEach(AppTabNavigationPresenter.primaryTabs, id: \.rawValue) { tab in
                    SidebarRow(
                        tab: tab,
                        isSelected: model.selectedTab == tab,
                        action: { select(tab) }
                    )
                }
            }

            Spacer(minLength: 12)

            VStack(spacing: 4) {
                ForEach(AppTabNavigationPresenter.footerTabs, id: \.rawValue) { tab in
                    SidebarRow(
                        tab: tab,
                        isSelected: model.selectedTab == tab,
                        isUtility: true,
                        action: { select(tab) }
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .stewardSurface(role: .sidebar, cornerRadius: 0)
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.14))
                        .frame(width: 30, height: 30)
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Mac 软件管家")
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                    Text("本机维护控制台")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            SidebarStatusChip()
                .environmentObject(model)
        }
        .padding(.bottom, 4)
    }

    private func select(_ tab: AppTab) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            model.selectedTab = tab
        }
    }
}

private struct SidebarSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .padding(.horizontal, 9)
            content
        }
    }
}

private struct SidebarStatusChip: View {
    @EnvironmentObject private var model: StewardModel

    private var presentation: MaintenanceStatusPresentation {
        MaintenanceStatusPresenter.presentation(
            isScanning: model.isScanning,
            scanPhaseText: model.scanPhase?.rawValue,
            scanProgress: model.scanPhase?.progress,
            hasRunningJob: model.hasRunningJob,
            upgradeProgress: model.upgradeProgress,
            updateCount: model.executableUpdates.count,
            failedPackageCount: model.packageProgress.values.filter { progress in
                [
                    PackageUpgradeStatus.failed,
                    PackageUpgradeStatus.timedOut,
                    PackageUpgradeStatus.cancelled
                ].contains(progress.status)
            }.count
        )
    }

    private var tint: Color {
        tintColor(for: presentation.tintRole)
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: presentation.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
                .stewardSymbolPulse(active: presentation.isActive)

            VStack(alignment: .leading, spacing: 1) {
                Text(presentation.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(presentation.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .polishedTaskSurface(tint: tint, isActive: presentation.isActive)
        .animation(.easeOut(duration: 0.18), value: presentation)
    }
}

private struct SidebarRow: View {
    var tab: AppTab
    var isSelected: Bool
    var isCompact = false
    var isUtility = false
    var action: () -> Void
    @State private var isHovered = false

    private var rowState: SidebarRowInteractionState {
        isSelected ? .selected : (isHovered ? .hovered : .normal)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: tab.symbol)
                    .font(.system(size: isCompact ? 12 : 14, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 18)

                Text(tab.rawValue)
                    .font(.system(size: isCompact ? 13 : 14, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(textColor)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, isCompact ? 6 : 8)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(rowBorderColor, lineWidth: rowState == .selected ? 1 : 0.5)
            )
            .overlay(alignment: .leading) {
                if rowState.showsSelectionIndicator {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 3)
                        .padding(.vertical, 8)
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(rowState == .hovered ? 1.012 : 1.0)
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: rowState)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var iconColor: Color {
        switch rowState {
        case .normal:
            return isUtility || isCompact ? .secondary : Color.accentColor.opacity(0.82)
        case .hovered, .selected:
            return Color.accentColor
        }
    }

    private var textColor: Color {
        switch rowState {
        case .normal:
            return isCompact || isUtility ? .secondary : .primary
        case .hovered:
            return .primary
        case .selected:
            return Color.accentColor
        }
    }

    private var rowBackground: Color {
        switch rowState {
        case .normal:
            return Color.clear
        case .hovered:
            return Color.primary.opacity(0.06)
        case .selected:
            return Color.accentColor.opacity(0.14)
        }
    }

    private var rowBorderColor: Color {
        switch rowState {
        case .normal:
            return Color.clear
        case .hovered:
            return Color.primary.opacity(0.08)
        case .selected:
            return Color.accentColor.opacity(0.22)
        }
    }
}

// MARK: - Main Panel

private struct MainPanel: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore
    @EnvironmentObject private var inboxStore: InboxStore

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text(model.selectedTab.rawValue)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .id(model.selectedTab.rawValue)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                Spacer()
                if model.selectedTab.usesSearch {
                    searchField
                }
            }

            if !model.errorMessage.isEmpty {
                AppErrorBanner()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if model.shouldShowUpgradeReminder {
                UpgradeReminderBanner()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let notice = model.jobNotice {
                JobNoticeView(notice: notice)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }

            Group {
                switch model.selectedTab {
                case .updates:
                    UpdatesView()
                case .applications:
                    ApplicationsView()
                case .settings:
                    SettingsView()
                }
            }
            .id(model.selectedTab)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.easeOut(duration: 0.18), value: model.selectedTab)
        }
        .padding(18)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("搜索名称、版本、路径", text: $model.query)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minWidth: 200, idealWidth: 320, maxWidth: 400)
        .stewardSurface(cornerRadius: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct UpgradeReminderBanner: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore
    @EnvironmentObject private var inboxStore: InboxStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("发现 \(model.availableUpdates.count) 个可升级项目")
                    .font(.headline)
                Text("可前往升级列表查看，或直接一键升级全部可执行项目。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button("查看升级") {
                model.selectedTab = .updates
            }
            .buttonStyle(.bordered)

            Button {
                Task {
                    await model.upgradeAllExecutable(
                        inboxStore: inboxStore,
                        autoRepairProfile: automationProfile.profile
                    )
                }
            } label: {
                Label("一键升级", systemImage: "arrow.up.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isScanning || model.hasRunningJob || model.isConfirmingUpgradePlan)

            Button {
                model.dismissUpgradeReminder()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("关闭升级提醒")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stewardSurface(cornerRadius: 10, tint: .orange)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.orange.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct AppErrorBanner: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(model.errorMessage)
                .font(.subheadline)
            Spacer()
            Button {
                model.errorMessage = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭错误提示")
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stewardSurface(cornerRadius: 10, tint: .red)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.red.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Job Notice View

private struct JobNoticeView: View {
    @EnvironmentObject private var model: StewardModel
    var notice: JobNotice

    var body: some View {
        HStack(spacing: 10) {
            JobNoticeIcon(symbol: notice.symbol, isActive: !notice.isFailure)

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(notice.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer()

            if notice.isFailure {
                Button {
                    model.dismissFailureNotice()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .foregroundStyle(notice.isFailure ? .red : Color.accentColor)
        .stewardSurface(cornerRadius: 10, tint: notice.isFailure ? .red : Color.accentColor)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke((notice.isFailure ? Color.red : Color.accentColor).opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Job Notice Icon (macOS 15+ symbol effect guard)

private struct JobNoticeIcon: View {
    var symbol: String
    var isActive: Bool

    var body: some View {
        if #available(macOS 15.0, *) {
            Image(systemName: symbol)
                .font(.title3)
                .symbolEffect(.pulse, options: .repeating, isActive: isActive)
        } else {
            Image(systemName: symbol)
                .font(.title3)
        }
    }
}
