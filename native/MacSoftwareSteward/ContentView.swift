import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        NavigationSplitView {
            List(AppTab.allCases, selection: $model.selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.symbol)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            VStack(spacing: 0) {
                HeaderView()
                Divider()
                MainPanel()
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

private struct HeaderView: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mac 软件管家")
                        .font(.system(size: 34, weight: .bold))
                    Text("扫描本机应用、Homebrew 与可选的 Mac App Store 应用，集中处理可升级项。")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("包含 greedy cask", isOn: $model.includeGreedy)
                    .toggleStyle(.switch)

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
                    Label("一键升级", systemImage: "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.availableUpdates.isEmpty || model.hasRunningJob)
            }

            if !model.errorMessage.isEmpty {
                Label(model.errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 12) {
                MetricView(title: "应用程序", value: model.scan?.summary.applications, symbol: "macwindow")
                MetricView(title: "Brew Formula", value: model.scan?.summary.brewFormulae, symbol: "cube")
                MetricView(title: "Brew Cask", value: model.scan?.summary.brewCasks, symbol: "slider.horizontal.3")
                MetricView(title: "可操作升级", value: model.scan?.summary.actionable, symbol: "checkmark.shield")
            }
        }
        .padding(22)
    }
}

private struct MetricView: View {
    var title: String
    var value: Int?
    var symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value.map(String.init) ?? "-")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 78)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MainPanel: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text(model.selectedTab.rawValue)
                    .font(.title2.bold())
                Spacer()
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("搜索名称、版本、路径", text: $model.query)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(width: 360, height: 36)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }

            switch model.selectedTab {
            case .updates:
                UpdatesView()
            case .brew:
                BrewView()
            case .applications:
                ApplicationsView()
            case .mas:
                MasView()
            case .daily:
                DailyInspectionView()
            case .appUpdate:
                AppUpdateView()
            case .jobs:
                JobsView()
            }
        }
        .padding(18)
    }
}

private struct UpdatesView: View {
    @EnvironmentObject private var model: StewardModel

    var updates: [UpdatablePackage] {
        filter(model.availableUpdates, query: model.query) { package in
            "\(package.name) \(package.source) \(package.installedVersion) \(package.currentVersion)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Homebrew 与 Mac App Store 支持自动执行升级；普通 .app 会在应用程序列表中供手动处理。")
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("一键升级前先 brew update", isOn: $model.runBrewUpdate)
                    .toggleStyle(.switch)
            }

            if model.isScanning {
                EmptyStateView(symbol: "hourglass", title: "正在扫描本机软件", text: "system_profiler 与 brew outdated 可能需要一点时间。")
            } else if updates.isEmpty {
                EmptyStateView(symbol: "checkmark.circle", title: "没有发现可操作升级", text: "如果需要包含自动更新类 cask，请打开 greedy cask 后重新扫描。")
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(updates) { package in
                            UpdateRow(package: package)
                        }
                    }
                }
            }
        }
    }
}

private struct UpdateRow: View {
    @EnvironmentObject private var model: StewardModel
    var package: UpdatablePackage

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: package.source.contains("Brew") ? "shippingbox" : "bag")
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(package.name)
                    .font(.headline)
                Text("\(package.source) · \(package.installedVersion.isEmpty ? "-" : package.installedVersion) → \(package.currentVersion.isEmpty ? "-" : package.currentVersion)")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if package.isPinned {
                Badge(text: "pinned", color: .red)
            }
            if package.autoUpdates {
                Badge(text: "auto_updates", color: .secondary)
            }
            Badge(text: "可升级", color: .orange)

            Button {
                Task { await model.upgrade(package) }
            } label: {
                Label("升级", systemImage: "play")
            }
            .disabled(!package.upgradeable || model.hasRunningJob)
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.25))
        )
    }
}

private struct BrewView: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let brew = model.scan?.brew {
                    InfoLine(text: brew.available ? "\(brew.version) · \(brew.prefix)" : "未检测到 Homebrew")
                    if !brew.error.isEmpty {
                        WarningLine(text: brew.error)
                    }
                    PackageSection(title: "Formula", packages: filteredBrew(brew.formulae))
                    PackageSection(title: "Cask", packages: filteredBrew(brew.casks))
                } else {
                    EmptyStateView(symbol: "shippingbox", title: "等待扫描", text: "点击扫描后会显示 Homebrew 软件。")
                }
            }
        }
    }

    private func filteredBrew(_ packages: [BrewPackage]) -> [BrewPackage] {
        filter(packages, query: model.query) { "\($0.name) \($0.kind) \($0.installedVersion) \($0.currentVersion)" }
    }
}

private struct PackageSection: View {
    @EnvironmentObject private var model: StewardModel
    var title: String
    var packages: [BrewPackage]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            ForEach(packages) { package in
                UpdateRow(package: .brew(package))
            }
        }
    }
}

private struct ApplicationsView: View {
    @EnvironmentObject private var model: StewardModel

    var apps: [AppItem] {
        filter(model.scan?.applications.items ?? [], query: model.query) {
            "\($0.name) \($0.version) \($0.source) \($0.managedBy) \($0.path)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let scan = model.scan?.applications, !scan.error.isEmpty {
                WarningLine(text: scan.error)
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(apps) { app in
                        HStack(spacing: 12) {
                            Image(systemName: "macwindow")
                                .frame(width: 32, height: 32)
                                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.name)
                                    .font(.headline)
                                Text(app.path)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text(app.version.isEmpty ? "-" : app.version)
                                .foregroundStyle(.secondary)
                                .frame(width: 130, alignment: .leading)
                            Badge(text: app.source, color: .secondary)
                            ManagedBadge(app: app)
                            Button {
                                model.reveal(app)
                            } label: {
                                Label("Finder", systemImage: "arrow.up.forward.app")
                            }
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

private struct MasView: View {
    @EnvironmentObject private var model: StewardModel

    var apps: [MasApp] {
        filter(model.scan?.mas.apps ?? [], query: model.query) {
            "\($0.name) \($0.appId) \($0.installedVersion) \($0.currentVersion)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let mas = model.scan?.mas {
                HStack(spacing: 12) {
                    InfoLine(text: mas.available ? "通过 mas CLI 扫描与升级" : "未检测到 mas CLI")
                    Spacer()
                    if !mas.available {
                        Button {
                            Task { await model.installMasCLI() }
                        } label: {
                            Label("安装 mas CLI", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canInstallMasCLI || model.hasRunningJob)
                    }
                }
                if !mas.error.isEmpty {
                    WarningLine(text: mas.error)
                }
                if !mas.available {
                    InstallToolPrompt(
                        title: model.canInstallMasCLI ? "可通过 Homebrew 自动安装" : "需要先安装 Homebrew",
                        text: model.canInstallMasCLI
                            ? "点击安装会执行 brew install mas，完成后自动重新扫描 App Store 应用。"
                            : "当前未检测到可用的 Homebrew，无法自动安装 mas CLI。",
                        symbol: model.canInstallMasCLI ? "terminal" : "exclamationmark.lock"
                    )
                }
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(apps) { app in
                        UpdateRow(package: .mas(app))
                    }
                }
            }
        }
    }
}

private struct JobsView: View {
    @EnvironmentObject private var model: StewardModel
    @State private var selectedJobId: UUID?

    var selectedJob: UpgradeJob? {
        let id = selectedJobId ?? model.jobs.first?.id
        return model.jobs.first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 14) {
            List(selection: $selectedJobId) {
                ForEach(model.jobs) { job in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.label)
                            .font(.headline)
                        Text(job.status.rawValue)
                            .foregroundStyle(statusColor(job.status))
                            .font(.caption.bold())
                    }
                    .tag(job.id)
                }
            }
            .frame(width: 280)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "terminal")
                    Text(selectedJob?.label ?? "任务日志")
                        .font(.headline)
                    Spacer()
                    if let selectedJob {
                        Badge(text: selectedJob.status.rawValue, color: statusColor(selectedJob.status))
                    }
                }

                ScrollView {
                    Text(selectedJob?.log.map { "[\($0.stream)] \($0.text)" }.joined(separator: "\n") ?? "等待任务输出...")
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct DailyInspectionView: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.dailyInspectionEnabled ? "每日巡检已启用" : "每日巡检未启用")
                        .font(.headline)
                    Text("每天按设定时间扫描 Homebrew 与可用的 Mac App Store 软件，发现可升级项后自动执行升级。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Badge(text: model.dailyInspectionEnabled ? "ACTIVE" : "OFF", color: model.dailyInspectionEnabled ? .green : .secondary)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 12) {
                Picker("小时", selection: $model.dailyHour) {
                    ForEach(0..<24) { hour in
                        Text(String(format: "%02d", hour)).tag(hour)
                    }
                }
                .frame(width: 130)

                Picker("分钟", selection: $model.dailyMinute) {
                    ForEach(0..<60) { minute in
                        Text(String(format: "%02d", minute)).tag(minute)
                    }
                }
                .frame(width: 130)

                Toggle("包含 greedy cask", isOn: $model.includeGreedy)
                    .toggleStyle(.switch)

                Toggle("自动升级前先 brew update", isOn: $model.runBrewUpdate)
                    .toggleStyle(.switch)

                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    Task { await model.enableDailyInspection() }
                } label: {
                    Label(model.dailyInspectionEnabled ? "更新巡检计划" : "启用每日巡检", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await model.disableDailyInspection() }
                } label: {
                    Label("停用", systemImage: "xmark.circle")
                }
                .disabled(!model.dailyInspectionEnabled)

                Button {
                    model.runDailyInspectionNow()
                } label: {
                    Label("立即巡检一次", systemImage: "play.circle")
                }
                .disabled(model.hasRunningJob)

                Button {
                    model.refreshDailyInspectionStatus()
                } label: {
                    Label("刷新状态", systemImage: "arrow.clockwise")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("调度文件")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(model.dailyLaunchAgentPath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Text("日志文件")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                Text(model.dailyLogPath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                Text("最近巡检日志")
                    .font(.headline)
                ScrollView {
                    Text(model.dailyLog.isEmpty ? "暂无后台巡检日志。" : model.dailyLog)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct AppUpdateView: View {
    @EnvironmentObject private var updater: AppUpdateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: updater.updateAvailable ? "arrow.down.app.fill" : "arrow.down.app")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(updater.updateAvailable ? "发现可用更新" : "应用更新")
                        .font(.headline)
                    Text("当前版本 \(updater.currentVersion)，更新源 \(updater.repositoryName)。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Badge(text: updater.updateAvailable ? "UPDATE" : "CURRENT", color: updater.updateAvailable ? .orange : .green)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            Toggle("启动应用时自动检查更新", isOn: $updater.automaticChecksEnabled)
                .toggleStyle(.switch)

            HStack(spacing: 10) {
                Button {
                    Task { await updater.checkForUpdates() }
                } label: {
                    Label(updater.isChecking ? "检查中" : "手动检查更新", systemImage: updater.isChecking ? "hourglass" : "arrow.clockwise")
                }
                .disabled(updater.isChecking || updater.isInstalling)

                Button {
                    Task { await updater.downloadInstallAndRestart() }
                } label: {
                    Label(updater.isInstalling ? "安装中" : "下载并安装，重启应用", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!updater.updateAvailable || updater.isInstalling)

                if !updater.releaseURL.isEmpty {
                    Link("打开 Release", destination: URL(string: updater.releaseURL)!)
                }
            }

            InfoLine(text: updater.status)
            if !updater.progress.isEmpty {
                InfoLine(text: updater.progress)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Release Notes")
                    .font(.headline)
                ScrollView {
                    Text(updater.releaseNotes.isEmpty ? "暂无 release notes。" : updater.releaseNotes)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct Badge: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text.isEmpty ? "-" : text)
            .font(.caption.bold())
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct ManagedBadge: View {
    var app: AppItem

    var body: some View {
        if app.managedBy == "brew-cask" {
            Badge(text: "Brew Cask", color: app.updateState == "outdated" ? .orange : .green)
        } else if app.managedBy == "mas" {
            Badge(text: "App Store", color: app.updateState == "outdated" ? .orange : .green)
        } else {
            Badge(text: "手动", color: .secondary)
        }
    }
}

private struct InfoLine: View {
    var text: String

    var body: some View {
        Label(text, systemImage: "info.circle")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WarningLine: View {
    var text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct InstallToolPrompt: View {
    var title: String
    var text: String
    var symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct EmptyStateView: View {
    var symbol: String
    var title: String
    var text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }
}

private func filter<T>(_ items: [T], query: String, text: (T) -> String) -> [T] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !needle.isEmpty else { return items }
    return items.filter { text($0).lowercased().contains(needle) }
}

private func statusColor(_ status: JobStatus) -> Color {
    switch status {
    case .queued, .running: return .orange
    case .succeeded: return .green
    case .failed: return .red
    }
}
