import SwiftUI

struct UpdatesView: View {
    @EnvironmentObject private var model: StewardModel
    @State private var selectedFilter: UpdateFilter = .all

    var updates: [UpdatablePackage] {
        let base = filter(model.allUpgradeablePackages, query: model.query) { package in
            "\(package.name) \(package.source) \(package.installedVersion) \(package.currentVersion)"
        }
        return base.filter { package in
            switch selectedFilter {
            case .all:
                return true
            case .homebrew:
                return package.source.contains("Brew")
            case .appStore:
                return package.source.contains("App Store")
            case .risk:
                return package.autoUpdates || package.isPinned
            case .failed:
                let status = model.packageProgress[package.id]?.status
                return status == .failed || status == .timedOut || status == .cancelled
            case .skipped:
                return model.policyStore.effectivePolicy(for: package, includeGreedy: model.includeGreedy) == .skip
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("这里汇总 Homebrew 与 Mac App Store 中可直接执行的升级；扫描和升级策略可在设置中调整。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("筛选", selection: $selectedFilter) {
                    ForEach(UpdateFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 420)
                Button {
                    model.selectedTab = .settings
                } label: {
                    Label("升级设置", systemImage: "gearshape")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            if model.isScanning {
                scanningView
            } else if updates.isEmpty {
                EmptyStateView(symbol: "checkmark.circle", title: "没有发现可操作升级", text: "如果需要包含自动更新类 cask，请打开 greedy cask 后重新扫描。")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(updates) { package in
                            UpdateRow(package: package)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity
                                ))
                        }
                    }
                }
            }
        }
    }

    private var scanningView: some View {
        VStack(spacing: 20) {
            scanningIcon

            VStack(spacing: 8) {
                Text("正在扫描本机软件")
                    .font(.system(.headline, design: .rounded))
                if let phase = model.scanPhase {
                    Text(phase.rawValue)
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    ProgressView(value: phase.progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 280)
                } else {
                    Text("准备中...")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    /// macOS 15+ uses rotate symbolEffect; macOS 14 falls back to static icon.
    @ViewBuilder
    private var scanningIcon: some View {
        if #available(macOS 15.0, *) {
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .stroke(Color.accentColor.opacity(0.15), lineWidth: 1)
                    )
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.rotate, options: .repeating)
            }
        } else {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - UpdateRow

struct UpdateRow: View {
    @EnvironmentObject private var model: StewardModel
    var package: UpdatablePackage

    @State private var isHovered = false

    var progress: PackageUpgradeProgress? {
        model.packageProgress[package.id]
    }

    private var packageActionDisabled: Bool {
        model.isConfirmingUpgradePlan || model.isPackageActive(package.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 主行：图标 + 名称 + 标签 + 操作
            HStack(spacing: 10) {
                // Source icon with styled background
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(sourceIconBackground)
                        .frame(width: 30, height: 30)

                    Image(systemName: package.source.contains("Brew") ? "shippingbox" : "bag")
                        .font(.system(.callout, weight: .medium))
                        .foregroundStyle(sourceIconColor)
                }

                CopyableText(text: package.name)

                Spacer()

                if package.isPinned {
                    Badge(text: "固定", color: .red)
                }
                if package.autoUpdates {
                    Badge(text: "自更新", color: .blue)
                }

                Picker("", selection: Binding(
                    get: { model.policyStore.effectivePolicy(for: package, includeGreedy: model.includeGreedy) },
                    set: { model.policyStore.set($0, forPackageID: package.id) }
                )) {
                    ForEach(UpgradePolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .labelsHidden()
                .frame(width: 116)

                if let progress {
                    PackageProgressBadge(progress: progress)
                } else {
                    PackageStatusBadge(package: package)
                }

                actionButton
            }

            // 次行：来源 + 版本变化
            HStack(spacing: 8) {
                Text(package.source)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.08), in: Capsule())

                VersionChangeLabel(
                    current: package.installedVersion,
                    available: availableVersionText(for: package)
                )
            }
            .padding(.leading, 40)

            if let progress {
                PackageProgressDetail(progress: progress)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .background(rowTint, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(rowBorder, lineWidth: 1)
        )
        .scaleEffect(isHovered && progress == nil ? 1.005 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    // MARK: Source Icon Colors

    private var sourceIconBackground: Color {
        package.source.contains("Brew") ? Color.orange.opacity(0.12) : Color.blue.opacity(0.12)
    }

    private var sourceIconColor: Color {
        package.source.contains("Brew") ? .orange : .blue
    }

    // MARK: Action Button

    @ViewBuilder
    private var actionButton: some View {
        if progress?.status == .failed {
            Button {
                Task { await model.retryPackage(package.id) }
            } label: {
                Label("重试", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(packageActionDisabled)
        } else {
            Button {
                Task { await model.upgrade(package) }
            } label: {
                Label("升级", systemImage: "play")
            }
            .buttonStyle(.borderless)
            .disabled(!package.upgradeable || packageActionDisabled)
        }
    }

    // MARK: Row Style

    private var rowTint: Color {
        switch progress?.status {
        case .running, .queued: return Color.accentColor.opacity(0.04)
        case .succeeded: return Color.green.opacity(0.04)
        case .failed, .cancelled, .timedOut: return Color.red.opacity(0.04)
        case .warning: return Color.yellow.opacity(0.04)
        case nil: return package.outdated ? Color.orange.opacity(0.03) : .clear
        }
    }

    private var rowBorder: Color {
        switch progress?.status {
        case .running, .queued: return Color.accentColor.opacity(0.2)
        case .succeeded: return Color.green.opacity(0.2)
        case .failed, .cancelled, .timedOut: return Color.red.opacity(0.2)
        case .warning: return Color.yellow.opacity(0.2)
        case nil: return package.outdated ? Color.orange.opacity(0.15) : Color.primary.opacity(0.06)
        }
    }
}

private enum UpdateFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case homebrew = "Homebrew"
    case appStore = "App Store"
    case risk = "高风险"
    case failed = "失败"
    case skipped = "已跳过"

    var id: String { rawValue }
}

// MARK: - Status Badges

struct PackageStatusBadge: View {
    var package: UpdatablePackage

    var body: some View {
        Badge(text: text, color: color)
    }

    private var text: String {
        if package.upgradeable { return "可升级" }
        if package.outdated { return "需手动" }
        return "已最新"
    }

    private var color: Color {
        if package.upgradeable { return .orange }
        if package.outdated { return .secondary }
        return .green
    }
}

struct PackageProgressBadge: View {
    var progress: PackageUpgradeProgress

    var body: some View {
        HStack(spacing: 5) {
            if progress.status == .running {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(statusText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke(color.opacity(0.15), lineWidth: 0.5)
                )
        )
        .foregroundStyle(color)
    }

    private var symbol: String {
        switch progress.status {
        case .queued: return "clock"
        case .running: return "hourglass"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        case .timedOut: return "timer"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch progress.status {
        case .queued, .running: return .accentColor
        case .succeeded: return .green
        case .failed, .cancelled, .timedOut: return .red
        case .warning: return .yellow
        }
    }

    private var statusText: String {
        guard progress.status == .running else { return progress.status.rawValue }
        if progress.phaseText == "下载中", let fraction = progress.downloadFraction {
            return "下载中 \(Int(fraction * 100))%"
        }
        return progress.phaseText.isEmpty ? progress.status.rawValue : progress.phaseText
    }
}

// MARK: - Progress Detail

struct PackageProgressDetail: View {
    @EnvironmentObject private var model: StewardModel
    var progress: PackageUpgradeProgress

    private var packageActionDisabled: Bool {
        model.isConfirmingUpgradePlan || model.isPackageActive(progress.packageID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if progress.status == .queued {
                ProgressView(value: 0.15)
                    .progressViewStyle(.linear)
                HStack(spacing: 10) {
                    Label("等待升级", systemImage: "clock")
                    Text(UpgradeProgressPresenter.lastUpdateText(for: progress))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if progress.status == .running {
                runningProgress
            } else if progress.status == .succeeded {
                ProgressView(value: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.green)
                Text("升级完成")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if (progress.status == .failed || progress.status == .timedOut) && !progress.failureSummary.isEmpty {
                failureDetail
            } else if progress.status != .queued && progress.status != .running {
                Text(progress.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .padding(.leading, 40)
    }

    @ViewBuilder
    private var runningProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(phaseText, systemImage: phaseSymbol)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text(UpgradeProgressPresenter.phaseDurationText(for: progress))
                Text(UpgradeProgressPresenter.lastUpdateText(for: progress))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            if let staleHint = UpgradeProgressPresenter.staleHint(for: progress) {
                Label(staleHint, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let fraction = progress.downloadFraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                downloadMetricRow(percentText: "\(Int(fraction * 100))%")
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                if progress.downloadSizeText != nil || progress.downloadSpeedText != nil {
                    downloadMetricRow(percentText: nil)
                }
            }

            Text(progress.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func downloadMetricRow(percentText: String?) -> some View {
        HStack(spacing: 12) {
            if let percentText {
                Text(percentText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
            }
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
            if let remainingText = progress.downloadTimeRemainingText {
                Label(remainingText, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var failureDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(progress.failureSummary)
                    .fontWeight(.medium)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(.red)

            if !progress.recoverySuggestion.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text(progress.recoverySuggestion)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

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
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.red.opacity(0.15), lineWidth: 1)
        )
    }

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
            .disabled(packageActionDisabled)

        case .rescan:
            Button {
                Task { await model.scanSoftware() }
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .disabled(model.isConfirmingUpgradePlan)

        case .openLog:
            Button {
                model.selectedTab = .jobs
            } label: {
                Label("查看日志", systemImage: "terminal")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .disabled(packageActionDisabled)

        case .checkNetwork:
            Button {
                Task { await model.retryPackage(progress.packageID) }
            } label: {
                Label("重试", systemImage: "wifi")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .disabled(packageActionDisabled)

        case .freeDisk:
            if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
                Link(destination: url) {
                    Label("清理空间", systemImage: "arrow.forward.circle")
                }
                .font(.caption)
            }

        case .retryInTerminal:
            Button {
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

    private var phaseText: String {
        progress.phaseText.isEmpty ? "执行中" : progress.phaseText
    }

    private var phaseSymbol: String {
        switch phaseText {
        case "准备下载": return "arrow.down.circle"
        case "下载中": return "arrow.down.circle.fill"
        case "下载完成": return "checkmark.circle"
        case "校验下载": return "checkmark.shield"
        case "安装中": return "square.and.arrow.down"
        case "替换应用": return "arrow.triangle.2.circlepath"
        case "链接命令": return "link"
        case "移除旧链接": return "link.badge.minus"
        case "清理中": return "trash"
        case "执行命令": return "terminal"
        default: return "gearshape"
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
}
