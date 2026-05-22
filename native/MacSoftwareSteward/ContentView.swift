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
            VStack(spacing: 0) {
                if model.selectedTab != .settings {
                    HeaderView()
                    Divider()
                }
                MainPanel()
            }
        }
        .sheet(isPresented: $updater.showUpdateDialog) {
            AppUpdateDialog()
                .environmentObject(updater)
        }
    }
}

// MARK: - Header View

private struct HeaderView: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title + actions
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mac 软件管家")
                        .font(.title.bold())
                    Text("本机应用是实际安装的 .app，总览其来源；Homebrew/App Store 是可执行升级的管理来源。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 16)

                Button {
                    Task { await model.scanSoftware() }
                } label: {
                    Label(model.isScanning ? "扫描中" : "扫描", systemImage: model.isScanning ? "hourglass" : "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(model.isScanning)

                Button {
                    Task { await model.upgradeAll() }
                } label: {
                    Label(model.hasRunningJob ? "升级中" : "一键升级", systemImage: model.hasRunningJob ? "hourglass" : "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(model.availableUpdates.isEmpty)
                .help(model.upgradeAllHelpText)
            }

            // Error banner
            if !model.errorMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(model.errorMessage)
                        .font(.subheadline)
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.red.opacity(0.25), lineWidth: 1)
                )
            }

            // Upgrade progress
            if let progress = model.upgradeProgress, progress.total > 0 {
                UpgradeProgressBar(progress: progress)
            }

            // Metrics
            HStack(spacing: 12) {
                MetricView(title: "本机应用", value: model.scan?.summary.applications, symbol: "macwindow")
                MetricView(title: "Brew Formula", value: model.scan?.summary.brewFormulae, symbol: "cube")
                MetricView(title: "Brew Cask", value: model.scan?.summary.brewCasks, symbol: "slider.horizontal.3")
                MetricView(title: "可操作升级", value: model.scan?.summary.actionable, symbol: "checkmark.shield")
            }
        }
        .padding(20)
    }
}

// MARK: - Metric View

private struct MetricView: View {
    var title: String
    var value: Int?
    var symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value.map(String.init) ?? "-")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 66)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Main Panel

private struct MainPanel: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text(model.selectedTab.rawValue)
                    .font(.title2.bold())
                Spacer()
                if model.selectedTab.usesSearch {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("搜索名称、版本、路径", text: $model.query)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(minWidth: 200, idealWidth: 320, maxWidth: 400)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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

// MARK: - Job Notice View

private struct JobNoticeView: View {
    @EnvironmentObject private var model: StewardModel
    var notice: JobNotice

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: notice.symbol)
                .symbolEffect(.pulse, options: .repeating, isActive: !notice.isFailure)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.subheadline.bold())
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
                    Image(systemName: "xmark")
                        .font(.caption)
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
        .padding(10)
        .foregroundStyle(notice.isFailure ? .red : Color.accentColor)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke((notice.isFailure ? Color.red : Color.accentColor).opacity(0.25), lineWidth: 1)
        )
    }
}
