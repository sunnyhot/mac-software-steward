import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var updater: AppUpdateModel

    var body: some View {
        NavigationSplitView {
            List(AppTab.allCases, selection: $model.selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.symbol)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            detailContent
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

// MARK: - Header View

private struct HeaderView: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Toolbar row: title + actions
            toolbarRow

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
                    UpgradeProgressBar(progress: progress)
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

            Text("本机应用是实际安装的 .app；Homebrew / App Store 是可执行升级的管理来源。")
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
                Task { await model.scanSoftware() }
            }
            .disabled(model.isScanning)

            HeaderButton(
                title: model.hasRunningJob ? "升级中" : (model.isConfirmingUpgradePlan ? "准备中" : "一键升级"),
                icon: model.hasRunningJob || model.isConfirmingUpgradePlan ? "hourglass" : "bolt.fill",
                isProminent: true,
                isLoading: model.hasRunningJob || model.isConfirmingUpgradePlan
            ) {
                model.prepareUpgradePlan()
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.red.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: Metrics Row

    private var metricsRow: some View {
        HStack(spacing: 10) {
            MetricCard(title: "本机应用", value: model.scan?.summary.applications, symbol: "macwindow", accent: .blue)
            MetricCard(title: "Brew Formula", value: model.scan?.summary.brewFormulae, symbol: "cube.box", accent: .orange)
            MetricCard(title: "Brew Cask", value: model.scan?.summary.brewCasks, symbol: "shippingbox", accent: .purple)
            MetricCard(title: "可操作升级", value: model.scan?.summary.actionable, symbol: "checkmark.shield", accent: .green)
        }
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text(model.selectedTab.rawValue)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
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
                case .updates:
                    UpdatesView()
                case .applications:
                    ApplicationsView()
                case .sources:
                    SourcesView()
                case .settings:
                    SettingsView()
                case .jobs:
                    JobsView()
                }
            }
            .animation(.easeInOut(duration: 0.15), value: model.selectedTab)
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
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
