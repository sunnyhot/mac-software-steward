import SwiftUI

struct UpdatesView: View {
    @EnvironmentObject private var model: StewardModel

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
                scanningView
            } else if updates.isEmpty {
                EmptyStateView(symbol: "checkmark.circle", title: "没有发现可操作升级", text: "如果需要包含自动更新类 cask，请打开 greedy cask 后重新扫描。")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(updates) { package in
                            UpdateRow(package: package)
                        }
                    }
                }
            }
        }
    }

    private var scanningView: some View {
        VStack(spacing: 16) {
            scanningIcon
            Text("正在扫描本机软件")
                .font(.headline)
            if let phase = model.scanPhase {
                Text(phase.rawValue)
                    .foregroundStyle(.secondary)
                ProgressView(value: phase.progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 280)
            } else {
                Text("准备中...")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    /// macOS 15+ uses rotate symbolEffect; macOS 14 falls back to static icon.
    @ViewBuilder
    private var scanningIcon: some View {
        if #available(macOS 15.0, *) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .symbolEffect(.rotate, options: .repeating)
        } else {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - UpdateRow

struct UpdateRow: View {
    @EnvironmentObject private var model: StewardModel
    var package: UpdatablePackage

    var progress: PackageUpgradeProgress? {
        model.packageProgress[package.id]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 主行：图标 + 名称 + 标签 + 操作
            HStack(spacing: 10) {
                Image(systemName: package.source.contains("Brew") ? "shippingbox" : "bag")
                    .font(.callout)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

                CopyableText(text: package.name)

                Spacer()

                if package.isPinned {
                    Badge(text: "固定", color: .red)
                }
                if package.autoUpdates {
                    Badge(text: "自更新", color: .blue)
                }

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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.08), in: Capsule())

                VersionChangeLabel(
                    current: package.installedVersion,
                    available: availableVersionText(for: package)
                )
            }
            .padding(.leading, 38)

            if let progress {
                PackageProgressDetail(progress: progress)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(rowBorder)
        )
    }

    @ViewBuilder
    private var actionButton: some View {
        if progress?.status == .failed {
            Button {
                Task { await model.retryPackage(package.id) }
            } label: {
                Label("重试", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(model.isPackageActive(package.id))
        } else {
            Button {
                Task { await model.upgrade(package) }
            } label: {
                Label("升级", systemImage: "play")
            }
            .buttonStyle(.borderless)
            .disabled(!package.upgradeable || model.isPackageActive(package.id))
        }
    }

    private var rowBackground: Color {
        switch progress?.status {
        case .running, .queued: return Color.accentColor.opacity(0.06)
        case .succeeded: return Color.green.opacity(0.06)
        case .failed: return Color.red.opacity(0.06)
        case nil: return package.outdated ? Color.orange.opacity(0.05) : Color(nsColor: .controlBackgroundColor)
        }
    }

    private var rowBorder: Color {
        switch progress?.status {
        case .running, .queued: return Color.accentColor.opacity(0.2)
        case .succeeded: return Color.green.opacity(0.2)
        case .failed: return Color.red.opacity(0.2)
        case nil: return package.outdated ? Color.orange.opacity(0.15) : Color.gray.opacity(0.1)
        }
    }
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
                    .scaleEffect(0.65)
            } else {
                Image(systemName: symbol)
                    .font(.caption)
            }
            Text(progress.status.rawValue)
                .font(.caption.bold())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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

// MARK: - Progress Detail

struct PackageProgressDetail: View {
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
                runningProgress
            } else if progress.status == .succeeded {
                ProgressView(value: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.green)
                Text("升级完成")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if progress.status == .failed && !progress.failureSummary.isEmpty {
                failureDetail
            } else if progress.status != .queued {
                Text(progress.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .padding(.leading, 38)
    }

    @ViewBuilder
    private var runningProgress: some View {
        if let fraction = progress.downloadFraction, fraction > 0 {
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
        .padding(10)
        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red.opacity(0.15))
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
}
