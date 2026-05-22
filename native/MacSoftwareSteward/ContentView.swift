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
        }
        .sheet(isPresented: $updater.showUpdateDialog) {
            AppUpdateDialog()
                .environmentObject(updater)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if model.selectedTab == .settings {
            MainPanel()
        } else {
            VStack(spacing: 0) {
                HeaderView()
                Divider()
                MainPanel()
            }
        }
    }
}

// MARK: - Header View

private struct HeaderView: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Toolbar row: subtitle + actions
            toolbarRow

            // Conditional banners
            VStack(spacing: 8) {
                if !model.errorMessage.isEmpty {
                    errorBanner
                }
                if let progress = model.upgradeProgress, progress.total > 0 {
                    UpgradeProgressBar(progress: progress)
                }
            }

            // Metrics
            metricsRow
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: Toolbar Row

    private var toolbarRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Mac 软件管家")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("本机应用是实际安装的 .app；Homebrew / App Store 是可执行升级的管理来源。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(0)

            Spacer(minLength: 16)

            Button {
                Task { await model.scanSoftware() }
            } label: {
                Label(model.isScanning ? "扫描中" : "扫描", systemImage: model.isScanning ? "hourglass" : "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isScanning)

            Button {
                Task { await model.upgradeAll() }
            } label: {
                Label(model.hasRunningJob ? "升级中" : "一键升级", systemImage: model.hasRunningJob ? "hourglass" : "bolt.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(model.availableUpdates.isEmpty)
            .help(model.upgradeAllHelpText)
        }
    }

    // MARK: Error Banner

    private var errorBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(model.errorMessage)
                .font(.subheadline)
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Metrics Row

    private var metricsRow: some View {
        HStack(spacing: 10) {
            MetricView(title: "本机应用", value: model.scan?.summary.applications, symbol: "macwindow")
            MetricView(title: "Brew Formula", value: model.scan?.summary.brewFormulae, symbol: "cube")
            MetricView(title: "Brew Cask", value: model.scan?.summary.brewCasks, symbol: "slider.horizontal.3")
            MetricView(title: "可操作升级", value: model.scan?.summary.actionable, symbol: "checkmark.shield")
        }
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
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(value.map(String.init) ?? "-")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
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
                    searchField
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

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索名称、版本、路径", text: $model.query)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minWidth: 200, idealWidth: 320, maxWidth: 400)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
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
