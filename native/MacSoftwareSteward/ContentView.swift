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
                .disabled(model.availableUpdates.isEmpty || model.hasRunningJob)
                .help(model.upgradeAllHelpText)
            }

            if !model.errorMessage.isEmpty {
                Label(model.errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
            Button {
                model.selectedTab = .jobs
            } label: {
                Label("查看日志", systemImage: "terminal")
            }
        }
        .padding(10)
        .foregroundStyle(notice.isFailure ? .red : .accentColor)
        .background((notice.isFailure ? Color.red : Color.accentColor).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
                Text("这里汇总 Homebrew 与 Mac App Store 中可直接执行的升级；扫描和升级策略可在设置中调整。")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.selectedTab = .settings
                } label: {
                    Label("升级设置", systemImage: "gearshape")
                }
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

    var progress: PackageUpgradeProgress? {
        model.packageProgress[package.id]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: package.source.contains("Brew") ? "shippingbox" : "bag")
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(package.name)
                        .font(.headline)
                    Text("\(package.source) · 当前 \(versionText(package.installedVersion)) · 可升级版本 \(availableVersionText(for: package))")
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

                if let progress {
                    PackageProgressBadge(progress: progress)
                } else {
                    PackageStatusBadge(package: package)
                }

                Button {
                    Task { await model.upgrade(package) }
                } label: {
                    Label("升级", systemImage: "play")
                }
                .disabled(!package.upgradeable || model.hasRunningJob)
            }

            if let progress {
                PackageProgressDetail(progress: progress)
            }
        }
        .padding(12)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(rowBorder)
        )
    }

    private var rowBackground: Color {
        switch progress?.status {
        case .running, .queued: return Color.accentColor.opacity(0.08)
        case .succeeded: return Color.green.opacity(0.08)
        case .failed: return Color.red.opacity(0.08)
        case nil: return package.outdated ? Color.orange.opacity(0.08) : Color(nsColor: .controlBackgroundColor)
        }
    }

    private var rowBorder: Color {
        switch progress?.status {
        case .running, .queued: return Color.accentColor.opacity(0.25)
        case .succeeded: return Color.green.opacity(0.25)
        case .failed: return Color.red.opacity(0.25)
        case nil: return package.outdated ? Color.orange.opacity(0.25) : Color.gray.opacity(0.12)
        }
    }
}

private struct PackageStatusBadge: View {
    var package: UpdatablePackage

    var body: some View {
        Badge(text: text, color: color)
    }

    private var text: String {
        if package.upgradeable { return "可升级" }
        if package.outdated && package.isPinned { return "已固定" }
        if package.outdated { return "需手动" }
        return "已最新"
    }

    private var color: Color {
        if package.upgradeable { return .orange }
        if package.outdated { return .secondary }
        return .green
    }
}

private struct PackageProgressBadge: View {
    var progress: PackageUpgradeProgress

    var body: some View {
        HStack(spacing: 6) {
            if progress.status == .running {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            } else {
                Image(systemName: symbol)
            }
            Text(progress.status.rawValue)
                .font(.caption.bold())
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color)
    }

    private var symbol: String {
        switch progress.status {
        case .queued: return "clock"
        case .running: return "hourglass"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch progress.status {
        case .queued, .running: return .accentColor
        case .succeeded: return .green
        case .failed: return .red
        }
    }
}

private struct PackageProgressDetail: View {
    var progress: PackageUpgradeProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if progress.status == .queued {
                ProgressView(value: 0.15)
                    .progressViewStyle(.linear)
            } else if progress.status == .running {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            if progress.status == .failed && !progress.failureSummary.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("失败原因：\(progress.failureSummary)")
                        .foregroundStyle(.red)
                    if !progress.recoverySuggestion.isEmpty {
                        Text("解决方案：\(progress.recoverySuggestion)")
                    }
                    Button {
                        copyToPasteboard(progress.copyText)
                    } label: {
                        Label("复制原因", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .disabled(progress.copyText.isEmpty)
                }
                .font(.caption)
                .textSelection(.enabled)
                .padding(10)
                .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.18))
                )
            } else {
                Text(progress.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .padding(.leading, 46)
    }

    private func copyToPasteboard(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private enum SourcePane: String, CaseIterable, Identifiable {
    case homebrew = "Homebrew"
    case appStore = "App Store"

    var id: String { rawValue }
}

private struct SourcesView: View {
    @State private var selectedPane: SourcePane = .homebrew

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text("管理来源负责执行升级；本机应用页只展示实际安装的 .app 和来源关系。")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("管理来源", selection: $selectedPane) {
                    ForEach(SourcePane.allCases) { pane in
                        Text(pane.rawValue).tag(pane)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }

            switch selectedPane {
            case .homebrew:
                BrewSourceView()
            case .appStore:
                AppStoreSourceView()
            }
        }
    }
}

private struct BrewSourceView: View {
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
            Text("本机应用是实际安装的 .app；安装位置说明 App 文件在哪，管理方式说明由 Homebrew、App Store、系统或手动维护。")
                .foregroundStyle(.secondary)
            if let scan = model.scan?.applications, !scan.error.isEmpty {
                WarningLine(text: scan.error)
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(apps) { app in
                        ApplicationRow(app: app)
                    }
                }
            }
        }
    }
}

private struct ApplicationRow: View {
    @EnvironmentObject private var model: StewardModel
    var app: AppItem

    var progress: PackageUpgradeProgress? {
        app.relatedPackageID.isEmpty ? nil : model.packageProgress[app.relatedPackageID]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                VersionColumn(title: "当前", value: app.version)
                VersionColumn(title: "可升级", value: app.availableVersion)
                Badge(text: appLocationText(app), color: .secondary)
                if let progress {
                    PackageProgressBadge(progress: progress)
                } else {
                    ManagementBadge(app: app)
                }
                Button {
                    model.reveal(app)
                } label: {
                    Label("Finder", systemImage: "arrow.up.forward.app")
                }
            }

            if let progress {
                PackageProgressDetail(progress: progress)
            }
        }
        .padding(10)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    private var rowBackground: Color {
        if progress != nil { return Color.accentColor.opacity(0.08) }
        if app.updateState == "outdated" { return Color.orange.opacity(0.08) }
        return Color(nsColor: .controlBackgroundColor)
    }
}

private struct VersionColumn: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(versionText(value))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: 92, alignment: .leading)
    }
}

private struct AppStoreSourceView: View {
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

private struct SettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsBlockHeader(
                    title: "外观",
                    text: "默认跟随系统，也可以手动固定为浅色或深色。",
                    symbol: "circle.lefthalf.filled"
                )
                AppearanceSettingsView()

                SettingsBlockHeader(
                    title: "扫描与升级",
                    text: "这些选项影响顶部扫描按钮、一键升级和每日巡检里的自动升级行为。",
                    symbol: "slider.horizontal.3"
                )
                ScanUpgradeSettingsView()

                SettingsBlockHeader(
                    title: "每日巡检",
                    text: "定时扫描可管理来源，并在发现可操作升级时自动执行。",
                    symbol: "calendar.badge.clock"
                )
                DailyInspectionView()

                SettingsBlockHeader(
                    title: "应用与启动",
                    text: "配置 Mac 软件管家本身的更新检查和开机启动。",
                    symbol: "arrow.down.app"
                )
                AppUpdateView()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SettingsBlockHeader: View {
    var title: String
    var text: String
    var symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct AppearanceSettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("外观", selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 360)

            Text("深色模式会使用系统窗口、控件和文本颜色，升级状态仍保留红、绿、橙等语义提示。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ScanUpgradeSettingsView: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("扫描 Homebrew 时包含 greedy cask", isOn: $model.includeGreedy)
                .toggleStyle(.switch)
            Toggle("一键升级和自动升级前先执行 brew update", isOn: $model.runBrewUpdate)
                .toggleStyle(.switch)

            HStack(spacing: 10) {
                Button {
                    Task { await model.scanSoftware() }
                } label: {
                    Label(model.isScanning ? "扫描中" : "立即扫描", systemImage: model.isScanning ? "hourglass" : "arrow.clockwise")
                }
                .disabled(model.isScanning)

                Button {
                    Task { await model.upgradeAll() }
                } label: {
                    Label(model.hasRunningJob ? "升级中" : "一键升级", systemImage: model.hasRunningJob ? "hourglass" : "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.availableUpdates.isEmpty || model.hasRunningJob)
                .help(model.upgradeAllHelpText)
            }

            Text("Homebrew Cask 的 auto_updates 或 version :latest 软件默认不会进入可操作升级；开启 greedy 后会一起纳入扫描和升级候选。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
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

                Spacer()
            }

            InfoLine(text: "每日巡检会使用上方“扫描与升级”的 greedy cask 和 brew update 设置。")

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
    @EnvironmentObject private var launchAtLogin: LaunchAtLoginModel

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

            if updater.automaticChecksEnabled {
                Toggle("自动下载并安装更新", isOn: $updater.automaticDownloadsEnabled)
                    .toggleStyle(.switch)
            }

            HStack(spacing: 12) {
                Toggle("开机自动启动", isOn: Binding(
                    get: { launchAtLogin.enabled },
                    set: { enabled in
                        Task { await launchAtLogin.setEnabled(enabled) }
                    }
                ))
                .toggleStyle(.switch)
                .disabled(launchAtLogin.isChanging)

                Text(launchAtLogin.status)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    launchAtLogin.refresh()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }

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

private struct ManagementBadge: View {
    var app: AppItem

    var body: some View {
        if app.managedBy == "brew-cask" {
            Badge(text: "管理方式：Homebrew Cask", color: app.updateState == "outdated" ? .orange : .green)
        } else if app.managedBy == "mas" {
            Badge(text: "管理方式：App Store", color: app.updateState == "outdated" ? .orange : .green)
        } else if app.source == "Apple" || app.path.hasPrefix("/System/") {
            Badge(text: "管理方式：系统", color: .secondary)
        } else {
            Badge(text: "管理方式：手动", color: .secondary)
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

private func versionText(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "-" : value
}

private func availableVersionText(for package: UpdatablePackage) -> String {
    if !package.currentVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return package.currentVersion
    }
    if package.outdated && package.source == "Mac App Store" {
        return "待 App Store 确认"
    }
    return "-"
}

private func appLocationText(_ app: AppItem) -> String {
    if app.path.hasPrefix("/Applications/") {
        return "安装位置：/Applications"
    }
    if app.path.contains("/Applications/") {
        return "安装位置：用户应用目录"
    }
    if app.path.hasPrefix("/System/") {
        return "安装位置：系统目录"
    }
    return app.source.isEmpty ? "安装位置：未知" : "安装位置：\(app.source)"
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
