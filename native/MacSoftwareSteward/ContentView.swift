import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var updater: AppUpdateModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    var body: some View {
        NavigationSplitView {
            TaskFirstSidebar()
                .environmentObject(model)
                .environmentObject(automationProfile)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230)
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(StewardCanvasBackground().ignoresSafeArea())
                .animation(.easeInOut(duration: 0.2), value: model.selectedTab)
        }
        .sheet(isPresented: $updater.showUpdateDialog) {
            AppUpdateDialog()
                .environmentObject(updater)
        }
        .sheet(isPresented: $model.showingUpgradePlan) {
            UpgradePlanView()
                .environmentObject(model)
        }
        .onAppear {
            normalizeSelectedTab()
        }
        .onChange(of: automationProfile.profile.advancedModeEnabled) {
            normalizeSelectedTab()
        }
    }

    private func normalizeSelectedTab() {
        let fallbackTab = AppTabNavigationPresenter.fallbackTab(
            for: model.selectedTab,
            advancedModeEnabled: automationProfile.profile.advancedModeEnabled
        )
        if model.selectedTab != fallbackTab {
            model.selectedTab = fallbackTab
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if model.selectedTab == .settings {
            MainPanel()
        } else {
            VStack(spacing: 0) {
                HeaderView()
                Divider().opacity(0.5)
                MainPanel()
            }
        }
    }
}

// MARK: - Task First Sidebar

private struct TaskFirstSidebar: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    private var advancedModeEnabled: Bool {
        automationProfile.profile.advancedModeEnabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sidebarHeader

            SidebarSection(title: "日常维护") {
                ForEach(AppTabNavigationPresenter.primaryTabs(advancedModeEnabled: advancedModeEnabled), id: \.rawValue) { tab in
                    SidebarRow(
                        tab: tab,
                        isSelected: model.selectedTab == tab,
                        action: { select(tab) }
                    )
                }
            }

            if advancedModeEnabled {
                SidebarSection(title: "诊断与控制") {
                    ForEach(AppTabNavigationPresenter.controlTabs(advancedModeEnabled: advancedModeEnabled), id: \.rawValue) { tab in
                        SidebarRow(
                            tab: tab,
                            isSelected: model.selectedTab == tab,
                            action: { select(tab) }
                        )
                    }
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
        .padding(.top, 54)
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
            updateCount: model.allUpgradeablePackages.count,
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

// MARK: - Header View

private struct HeaderView: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore
    @EnvironmentObject private var inboxStore: InboxStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Toolbar row: title + actions
            toolbarRow

            MaintenanceStatusBand(
                presentation: statusPresentation,
                updateCount: model.allUpgradeablePackages.count,
                failedCount: failedPackageCount
            )

            // Conditional banners
            VStack(spacing: 8) {
                if !model.errorMessage.isEmpty {
                    errorBanner
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                }
                if let progress = model.upgradeProgress, progress.total > 0 {
                    UpgradeProgressBar(
                        progress: progress,
                        packageProgress: Array(model.packageProgress.values)
                    )
                        .transition(.opacity)
                }
            }

            // Metrics cards
            metricsRow
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(headerBackground)
    }

    // MARK: Header Background

    @ViewBuilder
    private var headerBackground: some View {
        if #available(macOS 15.0, *) {
            // 使用系统背景 + subtle bottom border
            ZStack {
                Color.clear
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.03),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        } else {
            Color.clear
        }
    }

    // MARK: Toolbar Row

    private var toolbarRow: some View {
        HStack(alignment: .center, spacing: 12) {
            // App icon + title
            HStack(spacing: 8) {
                Image(systemName: "shield.checkered")
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Mac 软件管家")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Text("本机软件汇总可人工维护的 App、Homebrew 和 App Store 软件。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(0)

            Spacer(minLength: 16)

            HeaderButton(
                title: model.isScanning ? "扫描中" : "扫描",
                icon: model.isScanning ? "hourglass" : "arrow.clockwise",
                isProminent: false,
                isLoading: model.isScanning
            ) {
                Task {
                    await model.scanSoftware(
                        regularAppNetworkPolicy: automationProfile.profile.regularAppNetworkPolicy,
                        notificationPolicy: automationProfile.profile.notificationPolicy,
                        inboxStore: inboxStore
                    )
                }
            }
            .disabled(model.isScanning)

            HeaderButton(
                title: model.hasRunningJob ? "升级中" : (model.isConfirmingUpgradePlan ? "准备中" : "一键升级"),
                icon: model.hasRunningJob || model.isConfirmingUpgradePlan ? "hourglass" : "bolt.fill",
                isProminent: true,
                isLoading: model.hasRunningJob || model.isConfirmingUpgradePlan
            ) {
                model.prepareUpgradePlan(inboxStore: inboxStore)
            }
            .disabled(model.availableUpdates.isEmpty || model.hasRunningJob || model.isConfirmingUpgradePlan)
            .help(model.upgradeAllHelpText)
        }
    }

    // MARK: Error Banner

    private var errorBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.callout)
            Text(model.errorMessage)
                .font(.subheadline)
            Spacer()
            Button {
                model.errorMessage = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.6))
            }
            .buttonStyle(.plain)
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

    // MARK: Metrics Row

    private var metricsRow: some View {
        HStack(spacing: 10) {
            MetricCard(title: "本机软件", value: localSoftwareSummary?.total, symbol: "macwindow", accent: .blue)
            MetricCard(title: "App", value: localSoftwareSummary?.app, symbol: "app", accent: .green)
            MetricCard(title: "Brew", value: localSoftwareSummary?.brew, symbol: "shippingbox", accent: .orange)
            MetricCard(title: "App Store", value: localSoftwareSummary?.appStore, symbol: "bag", accent: .purple)
        }
    }

    private var localSoftwareSummary: LocalSoftwareSummary? {
        guard let scan = model.scan else { return nil }
        return LocalSoftwarePresenter.summary(for: LocalSoftwarePresenter.rows(from: scan))
    }

    private var failedPackageCount: Int {
        model.packageProgress.values.filter { progress in
            [
                PackageUpgradeStatus.failed,
                PackageUpgradeStatus.timedOut,
                PackageUpgradeStatus.cancelled
            ].contains(progress.status)
        }.count
    }

    private var statusPresentation: MaintenanceStatusPresentation {
        MaintenanceStatusPresenter.presentation(
            isScanning: model.isScanning,
            scanPhaseText: model.scanPhase?.rawValue,
            scanProgress: model.scanPhase?.progress,
            hasRunningJob: model.hasRunningJob,
            upgradeProgress: model.upgradeProgress,
            updateCount: model.allUpgradeablePackages.count,
            failedPackageCount: failedPackageCount
        )
    }
}

private struct MaintenanceStatusBand: View {
    var presentation: MaintenanceStatusPresentation
    var updateCount: Int
    var failedCount: Int

    private var tint: Color {
        tintColor(for: presentation.tintRole)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                StatusIconPlate(symbol: presentation.symbol, tint: tint, isActive: presentation.isActive)

                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(presentation.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                statusMetric(title: "可升级", value: updateCount, tint: .orange)
                statusMetric(title: "需处理", value: failedCount, tint: failedCount > 0 ? .red : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if let progress = presentation.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(tint)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            FlowingAccentLine(tint: tint, isActive: presentation.isActive)
        }
        .polishedTaskSurface(tint: tint, isActive: presentation.isActive)
        .animation(.easeOut(duration: 0.18), value: presentation)
    }

    private func statusMetric(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 52, alignment: .trailing)
    }
}

// MARK: - Header Button

private struct HeaderButton: View {
    var title: String
    var icon: String
    var isProminent: Bool
    var isLoading: Bool
    var action: () -> Void

    var body: some View {
        Group {
            if isProminent {
                Button(action: action) {
                    buttonLabel
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: action) {
                    buttonLabel
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.small)
    }

    private var buttonLabel: some View {
        HStack(spacing: 5) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            } else {
                Image(systemName: icon)
                    .font(.caption)
            }
            Text(title)
                .font(.system(.callout, weight: .medium))
        }
    }
}

// MARK: - Metric Card

private struct MetricCard: View {
    var title: String
    var value: Int?
    var symbol: String
    var accent: Color

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Icon with gradient background
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.15), accent.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 34)

                Image(systemName: symbol)
                    .font(.system(.callout, weight: .medium))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(value.map(String.init) ?? "–")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 58)
        .stewardSurface(cornerRadius: 12, tint: accent)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? accent.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
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

            if let notice = model.jobNotice {
                JobNoticeView(notice: notice)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }

            Group {
                switch model.selectedTab {
                case .inbox:
                    InboxView()
                case .updates:
                    UpdatesView()
                case .applications:
                    ApplicationsView()
                case .sources:
                    SourcesView()
                case .rules:
                    RulesView()
                case .history:
                    HistoryView()
                case .performance:
                    PerformanceView()
                case .settings:
                    SettingsView()
                case .jobs:
                    JobsView()
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

            Button {
                model.selectedTab = .jobs
            } label: {
                Label("查看日志", systemImage: "terminal")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
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
