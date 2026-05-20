import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var updater: AppUpdateModel

    var body: some View {
        NavigationSplitView {
            List(AppTab.allCases, selection: $model.selectedTab) { tab in
                SidebarRow(tab: tab, selectedTab: model.selectedTab)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            VStack(spacing: 0) {
                if model.selectedTab != .settings {
                    HeaderView()
                    Divider()
                }
                MainPanel()
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .sheet(isPresented: $updater.showUpdateDialog) {
            AppUpdateDialog()
                .environmentObject(updater)
        }
    }
}

private struct SidebarRow: View {
    let tab: AppTab
    let selectedTab: AppTab?
    @State private var isHovered = false

    var body: some View {
        Label(tab.rawValue, systemImage: tab.symbol)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .background(
                (isHovered && tab != selectedTab)
                    ? Color.primary.opacity(0.08)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct HeaderView: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mac 软件管家")
                        .font(.system(size: 34, weight: .bold))
                    Text("本机应用是实际安装的 .app，总览其来源；Homebrew/App Store 是可执行升级的管理来源。")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await model.scanSoftware() }
                } label: {
                    Label(model.isScanning ? "扫描中" : "扫描", systemImage: model.isScanning ? "hourglass" : "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(model.isScanning)

                Button {
                    Task { await model.upgradeAll() }
                } label: {
                    Label(model.hasRunningJob ? "升级中" : "一键升级", systemImage: model.hasRunningJob ? "hourglass" : "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.availableUpdates.isEmpty)
                .help(model.upgradeAllHelpText)
            }

            if !model.errorMessage.isEmpty {
                Label(model.errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            if let progress = model.upgradeProgress, progress.total > 0 {
                UpgradeProgressBar(progress: progress)
            }

            HStack(spacing: 12) {
                MetricView(title: "本机应用", value: model.scan?.summary.applications, symbol: "macwindow")
                MetricView(title: "Brew Formula", value: model.scan?.summary.brewFormulae, symbol: "cube")
                MetricView(title: "Brew Cask", value: model.scan?.summary.brewCasks, symbol: "slider.horizontal.3")
                MetricView(title: "可操作升级", value: model.scan?.summary.actionable, symbol: "checkmark.shield")
            }
        }
        .padding(22)
    }
}

struct MainPanel: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text(model.selectedTab.rawValue)
                    .font(.title2.bold())
                Spacer()
                if model.selectedTab.usesSearch {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        TextField("搜索名称、版本、路径", text: $model.query)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .frame(width: 360, height: 36)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            if let notice = model.jobNotice {
                JobNoticeView(notice: notice)
            }

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
        .padding(18)
    }
}
