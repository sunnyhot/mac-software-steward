import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: StewardModel

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

    /// 显示所有可升级包（包含正在升级中的，以显示进度）
    var updates: [UpdatablePackage] {
        filter(model.allUpgradeablePackages, query: model.query) { package in
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
                    CopyableText(text: package.name)
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

                if progress?.status == .failed {
                    Button {
                        Task { await model.retryPackage(package.id) }
                    } label: {
                        Label("重试", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isPackageActive(package.id))
                } else {
                    Button {
                        Task { await model.upgrade(package) }
                    } label: {
                        Label("升级", systemImage: "play")
                    }
                    .disabled(!package.upgradeable || model.isPackageActive(package.id))
                }
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
        if package.outdated && package.autoUpdates { return "自更新" }
        if package.outdated && package.isPinned { return "已固定" }
        if package.outdated { return "需手动" }
        return "已最新"
    }

    private var color: Color {
        if package.upgradeable { return .orange }
        if package.outdated && package.autoUpdates { return .blue }
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
    @EnvironmentObject private var model: StewardModel
    var progress: PackageUpgradeProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if progress.status == .queued {
                ProgressView(value: 0.15)
                    .progressViewStyle(.linear)
                Text("等待升级")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if progress.status == .running {
                if let fraction = progress.downloadFraction, fraction > 0 {
                    // Determinate progress bar with download info
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                        HStack(spacing: 12) {
                            Text("\(Int(fraction * 100))%")
                                .font(.caption.bold())
                                .monospacedDigit()
                                .foregroundStyle(Color.accentColor)
                            if let sizeText = progress.downloadSizeText {
                                Label(sizeText, systemImage: "arrow.down.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let speedText = progress.downloadSpeedText {
                                Label(speedText, systemImage: "gauge.with.dots.needle.33percent")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    // Indeterminate progress (no download info yet)
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView()
                            .progressViewStyle(.linear)
                        Text(progress.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
            } else if progress.status == .succeeded {
                ProgressView(value: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.green)
                Text("升级完成")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if progress.status == .failed && !progress.failureSummary.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    // 失败原因
                    Label {
                        Text(progress.failureSummary)
                            .fontWeight(.medium)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(.red)

                    // 恢复建议
                    if !progress.recoverySuggestion.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(.yellow)
                                .font(.caption)
                            Text(progress.recoverySuggestion)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // 操作按钮
                    HStack(spacing: 10) {
                        if let action = progress.recoveryAction {
                            actionButton(for: action)
                        }
                        Button {
                            copyToPasteboard(progress.copyText)
                        } label: {
                            Label("复制详情", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .disabled(progress.copyText.isEmpty)
                    }
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

    // MARK: - Action Buttons

    @ViewBuilder
    private func actionButton(for action: FailureActionType) -> some View {
        switch action {
        case .retry, .quitAndRetry, .reimport, .cleanup, .repairPerms:
            Button {
                Task { await model.retryPackage(progress.packageID) }
            } label: {
                Label(actionLabel(for: action), systemImage: actionIcon(for: action))
            }
            .buttonStyle(.borderless)
            .font(.caption)

        case .rescan:
            Button {
                Task { await model.scanSoftware() }
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .font(.caption)

        case .openLog:
            Button {
                model.selectedTab = .jobs
            } label: {
                Label("查看日志", systemImage: "terminal")
            }
            .buttonStyle(.borderless)
            .font(.caption)

        case .checkNetwork:
            Button {
                Task { await model.retryPackage(progress.packageID) }
            } label: {
                Label("重试", systemImage: "wifi")
            }
            .buttonStyle(.borderless)
            .font(.caption)

        case .freeDisk:
            if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
                Link(destination: url) {
                    Label("清理空间", systemImage: "arrow.forward.circle")
                }
                .font(.caption)
            }

        case .retryInTerminal:
            Button {
                // Copy just the command to clipboard, then open Terminal.app
                let cmd = progress.lastFailedCommand.isEmpty ? progress.copyText : progress.lastFailedCommand
                copyToPasteboard(cmd)
                if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                    NSWorkspace.shared.open(terminalURL)
                }
            } label: {
                Label("在终端运行", systemImage: "terminal")
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }

    private func actionLabel(for action: FailureActionType) -> String {
        switch action {
        case .retry: return "重试"
        case .quitAndRetry: return "关闭后重试"
        case .reimport: return "覆盖重装"
        case .cleanup: return "清理并重试"
        case .repairPerms: return "重试"
        default: return "重试"
        }
    }

    private func actionIcon(for action: FailureActionType) -> String {
        switch action {
        case .retry: return "arrow.clockwise"
        case .quitAndRetry: return "xmark.circle"
        case .reimport: return "square.and.arrow.down.on.square"
        case .cleanup: return "trash.circle"
        case .repairPerms: return "lock.shield"
        default: return "arrow.clockwise"
        }
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
                    CopyableText(text: app.name)
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
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var updater: AppUpdateModel
    @EnvironmentObject private var launchAtLogin: LaunchAtLoginModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                SettingsGroupBox {
                    SettingsGroupHeader(title: "通用", symbol: "gearshape")
                    AppearanceRow()
                    Divider().padding(.vertical, 2)
                    LaunchAtLoginRow()
                    Divider().padding(.vertical, 2)
                    DockIconRow()
                }

                SettingsGroupBox {
                    SettingsGroupHeader(title: "扫描与升级策略", symbol: "slider.horizontal.3")
                    GreedyCaskRow()
                    Divider().padding(.vertical, 2)
                    BrewUpdateRow()
                    Divider().padding(.vertical, 2)
                    MaxConcurrentUpgradesRow()
                }

                SettingsGroupBox {
                    SettingsGroupHeader(title: "每日巡检", symbol: "calendar.badge.clock")
                    DailyInspectionToggleRow()
                    if model.dailyInspectionEnabled {
                        Divider().padding(.vertical, 2)
                        DailyInspectionTimeRow()
                    }
                }

                SettingsGroupBox {
                    SettingsGroupHeader(title: "应用更新", symbol: "arrow.down.app")
                    AutoCheckUpdateRow()
                    if updater.automaticChecksEnabled {
                        Divider().padding(.vertical, 2)
                        AutoDownloadUpdateRow()
                    }
                    Divider().padding(.vertical, 2)
                    ManualCheckUpdateRow()
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
    }
}

private struct SettingsGroupBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct SettingsGroupHeader: View {
    var title: String
    var symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
        }
    }
}

private struct AppearanceRow: View {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        HStack {
            Text("外观")
            Spacer()
            Picker("", selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .labelsHidden()
        }
    }
}

private struct LaunchAtLoginRow: View {
    @EnvironmentObject private var launchAtLogin: LaunchAtLoginModel

    var body: some View {
        HStack {
            Text("开机自动启动")
            Spacer()
            Toggle("", isOn: Binding(
                get: { launchAtLogin.enabled },
                set: { enabled in
                    Task { await launchAtLogin.setEnabled(enabled) }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(launchAtLogin.isChanging)
        }
    }
}

private struct DockIconRow: View {
    @AppStorage("dockIconVisible") private var dockIconVisible = true

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("在 Dock 中显示")
                Text("关闭后应用只在菜单栏运行，不占用 Dock 位置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $dockIconVisible)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

private struct GreedyCaskRow: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("包含 greedy cask")
                Text("auto_updates 或 :latest 的 Cask 也纳入扫描")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $model.includeGreedy)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

private struct BrewUpdateRow: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("升级前 brew update")
                Text("一键升级和自动升级前先执行 brew update")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $model.runBrewUpdate)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

private struct MaxConcurrentUpgradesRow: View {
    @EnvironmentObject private var model: StewardModel
    private let options = [1, 2, 3, 5, 10, 0] // 0 = unlimited

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("并行升级数量")
                Text("同时执行的最大升级任务数，超出自动排队")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $model.maxConcurrentUpgrades) {
                ForEach(options, id: \.self) { value in
                    Text(value == 0 ? "不限" : "\(value)").tag(value)
                }
            }
            .frame(width: 100)
            .labelsHidden()
        }
    }
}

private struct DailyInspectionToggleRow: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("启用每日巡检")
                Text("定时扫描可管理来源，发现可升级项后自动执行升级")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { model.dailyInspectionEnabled },
                set: { enabled in
                    Task {
                        if enabled {
                            await model.enableDailyInspection()
                        } else {
                            await model.disableDailyInspection()
                        }
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
    }
}

private struct DailyInspectionTimeRow: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        HStack {
            Text("巡检时间")
            Spacer()
            Picker("时", selection: $model.dailyHour) {
                ForEach(0..<24) { hour in
                    Text(String(format: "%02d", hour)).tag(hour)
                }
            }
            .frame(width: 80)
            .labelsHidden()
            Text(":")
            Picker("分", selection: $model.dailyMinute) {
                ForEach(0..<60) { minute in
                    Text(String(format: "%02d", minute)).tag(minute)
                }
            }
            .frame(width: 80)
            .labelsHidden()
            Button {
                Task { await model.enableDailyInspection() }
            } label: {
                Text("保存")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}

private struct AutoCheckUpdateRow: View {
    @EnvironmentObject private var updater: AppUpdateModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("启动时自动检查更新")
                Text("每次启动应用时从 GitHub Release 检查新版本")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $updater.automaticChecksEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

private struct ManualCheckUpdateRow: View {
    @EnvironmentObject private var updater: AppUpdateModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("手动检查更新")
                if updater.isInstalling {
                    // 下载进度显示
                    if let fraction = updater.downloadFraction {
                        ProgressView(value: fraction) {
                            Text("正在下载 v\(updater.latestVersion)...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } currentValueLabel: {
                            HStack(spacing: 4) {
                                Text("\(Int(fraction * 100))%")
                                if let size = updater.downloadedSizeText {
                                    Text("·")
                                    Text(size)
                                }
                                if let speed = updater.downloadSpeedText {
                                    Text("·")
                                    Text(speed)
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 260)
                    } else {
                        Text(updater.progress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if updater.updateAvailable {
                    Text("发现新版本 \(updater.latestVersion)，可前往下载安装")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("当前版本 \(updater.currentVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await updater.checkForUpdates() }
            } label: {
                Label(updater.isChecking ? "检查中" : "立即检查", systemImage: updater.isChecking ? "hourglass" : "arrow.clockwise")
            }
            .disabled(updater.isChecking || updater.isInstalling)

            if updater.updateAvailable && !updater.isInstalling {
                Button {
                    Task { await updater.downloadInstallAndRestart() }
                } label: {
                    Label("下载安装", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(updater.isInstalling)
            }

            if updater.isInstalling {
                // 安装中显示取消按钮（实际无法取消下载，但可显示进度）
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}

private struct AutoDownloadUpdateRow: View {
    @EnvironmentObject private var updater: AppUpdateModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("自动下载并安装更新")
                Text("发现新版本后自动下载、覆盖安装并重启")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $updater.automaticDownloadsEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
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

private struct CopyableText: View {
    var text: String
    var font: Font = .headline
    @State private var didCopy = false

    var body: some View {
        Text(text)
            .font(font)
            .help("点击复制名称")
            .onTapGesture {
                copyToPasteboard(text)
                didCopy = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    didCopy = false
                }
            }
            .overlay(alignment: .top) {
                if didCopy {
                    Text("已复制")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 4))
                        .offset(y: -20)
                        .transition(.opacity)
                }
            }
    }
}

private func copyToPasteboard(_ text: String) {
    guard !text.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
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

private struct UpgradeProgressBar: View {
    var progress: UpgradeProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .symbolEffect(.pulse, options: .repeating)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("正在升级 \(progress.completed)/\(progress.total)")
                            .font(.subheadline.bold())
                        if let current = progress.currentPackage {
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(current)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if progress.failed > 0 {
                        Text("\(progress.failed) 个失败")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
                Text("\(Int(progress.fraction * 100))%")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
            }

            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)
                .tint(progress.failed > 0 && !progress.isRunning ? .orange : .accentColor)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.15))
        )
    }
}
