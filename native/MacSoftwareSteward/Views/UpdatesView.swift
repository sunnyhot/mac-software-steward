import SwiftUI

struct UpdatesView: View {
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

struct UpdateRow: View {
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

struct PackageStatusBadge: View {
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

struct PackageProgressBadge: View {
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
