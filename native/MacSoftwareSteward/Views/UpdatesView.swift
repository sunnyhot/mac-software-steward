import SwiftUI

struct UpdatesView: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore
    @EnvironmentObject private var inboxStore: InboxStore
    @State private var selectedFilter: UpdateFilter = .all

    var updates: [UpdatablePackage] {
        let base = filter(model.allUpgradeablePackages, query: model.query) { package in
            "\(package.name) \(package.source) \(package.installedVersion) \(package.currentVersion)"
        }
        return base.filter { package in
            // 只保留真能升级的包；正在进行（有进度记录）的也保留以展示进度。
            // “需手动”的包（upgradeable=false 且无进度）不属此页，归本机软件页。
            guard package.upgradeable || model.packageProgress[package.id] != nil else { return false }
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
        .sorted { lhs, rhs in
            // 正在处理（下载中/升级中/排队）的排最前，其次是失败/需关注，其余按名字。
            let lr = UpdateRowSort.priority(for: model.packageProgress[lhs.id]?.status)
            let rr = UpdateRowSort.priority(for: model.packageProgress[rhs.id]?.status)
            if lr != rr { return lr < rr }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                sourceDiagnostics
                filterHeader
                updateContent
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private var sourceDiagnostics: some View {
        if let brew = model.scan?.brew,
           let diagnosis = SourceDiagnosticEngine.diagnoseBrew(
               available: brew.available,
               error: brew.error,
               hasScan: model.scan != nil
           ) {
            ErrorRecoveryCard(
                diagnosis: diagnosis,
                onAction: { action in
                    Task { await model.performSourceRecovery(action: action) }
                },
                isProcessing: model.isScanning
            )
        }

        if let mas = model.scan?.mas,
           let diagnosis = SourceDiagnosticEngine.diagnoseMas(
               available: mas.available,
               error: mas.error,
               canInstallMas: model.canInstallMasCLI
           ) {
            ErrorRecoveryCard(
                diagnosis: diagnosis,
                onAction: { action in
                    Task { await model.performSourceRecovery(action: action) }
                },
                isProcessing: model.isScanning || model.hasRunningJob
            )
        }
    }

    private var filterHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("可执行升级")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Homebrew 与 Mac App Store 中可直接执行的升级会出现在这里。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button {
                Task {
                    await model.upgradeAllExecutable(
                        inboxStore: inboxStore,
                        autoRepairProfile: automationProfile.profile
                    )
                }
            } label: {
                Label("一键升级 \(upgradableCount) 项", systemImage: "arrow.up.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(upgradableCount == 0 || model.isScanning || model.hasRunningJob || model.isConfirmingUpgradePlan)

            Picker("", selection: $selectedFilter) {
                ForEach(UpdateFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 420)
            Button {
                model.selectedTab = .settings
            } label: {
                Label("设置", systemImage: "gearshape")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .polishedTaskSurface(tint: .accentColor, isActive: false)
    }

    /// 全机可执行升级项的数量（不受当前筛选/搜索影响），用于「一键升级」按钮计数。
    private var upgradableCount: Int {
        model.availableUpdates.count
    }

    @ViewBuilder
    private var updateContent: some View {
        if model.isScanning {
            scanningView
        } else {
            VStack(spacing: 8) {
                if updates.isEmpty {
                    EmptyStateView(symbol: "checkmark.circle", title: "没有发现可操作升级", text: "如果需要包含自动更新类 cask，请打开 greedy cask 后重新扫描。")
                } else {
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

                orphanedFailedSection
            }
        }
    }

    /// 失败孤儿：升级失败后重新扫描，包已不在可升级集合里，但失败记录仍残留。
    /// 单独成区展示，避免顶部状态横幅计数与列表对不上，用户能看到原因并重试或清除。
    @ViewBuilder
    private var orphanedFailedSection: some View {
        let orphans = model.orphanedFailedProgresses
        if !orphans.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("\(orphans.count) 个失败项不在当前可升级列表中")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Spacer(minLength: 8)
                    Button {
                        for progress in orphans {
                            model.clearPackageFailure(progress.packageID)
                        }
                    } label: {
                        Label("全部清除", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)

                LazyVStack(spacing: 8) {
                    ForEach(orphans) { progress in
                        OrphanedFailedRow(progress: progress)
                    }
                }
            }
            .polishedTaskSurface(tint: .red, isActive: false)
        }
    }

    private var scanningView: some View {
        VStack(spacing: 18) {
            StatusIconPlate(symbol: "arrow.triangle.2.circlepath", tint: .cyan, isActive: true)
                .scaleEffect(1.2)

            VStack(spacing: 8) {
                Text("正在扫描本机软件")
                    .font(.system(.headline, design: .rounded))
                if let phase = model.scanPhase {
                    Text(phase.rawValue)
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    ProgressView(value: phase.progress)
                        .progressViewStyle(.linear)
                        .tint(.cyan)
                        .frame(maxWidth: 320)
                    FlowingAccentLine(tint: .cyan, isActive: true)
                        .frame(maxWidth: 320)
                } else {
                    Text("准备刷新软件状态")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .polishedTaskSurface(tint: .cyan, isActive: true)
    }
}

// MARK: - UpdateRow

struct UpdateRow: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var inboxStore: InboxStore
    @EnvironmentObject private var automationProfile: AutomationProfileStore
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
            // 主行：图标 + 名称 + 状态 + 操作
            HStack(spacing: 10) {
                StatusIconPlate(
                    symbol: package.source.contains("Brew") ? "shippingbox" : "bag",
                    tint: sourceIconColor,
                    isActive: progress?.status == .running
                )

                CopyableText(text: package.name)

                Spacer()

                if let progress {
                    PackageProgressBadge(progress: progress)
                } else {
                    PackageStatusBadge(package: package)
                }

                actionButton
            }

            // 次行：版本变化
            HStack(spacing: 8) {
                VersionChangeLabel(
                    current: package.installedVersion,
                    available: availableVersionText(for: package)
                )
            }
            .padding(.leading, 40)

            if let progress {
                PackageProgressDetail(progress: progress)
            }

            if isActiveRow {
                FlowingAccentLine(tint: rowAccent, isActive: true)
                    .padding(.leading, 40)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .polishedTaskSurface(tint: rowAccent, isActive: isActiveRow)
        .scaleEffect(isHovered && progress == nil ? 1.005 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    // MARK: Source Icon Colors

    private var sourceIconColor: Color {
        package.source.contains("Brew") ? .orange : .blue
    }

    // MARK: Action Button

    @ViewBuilder
    private var actionButton: some View {
        if progress?.status == .failed {
            Button {
                Task { await model.retryPackage(package.id, inboxStore: inboxStore) }
            } label: {
                Label("重试", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(packageActionDisabled)
        } else {
            Button {
                Task {
                    await model.upgrade(
                        package,
                        inboxStore: inboxStore,
                        autoRepairProfile: automationProfile.profile
                    )
                }
            } label: {
                Label("升级", systemImage: "play")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(packageActionDisabled)
        }
    }

    // MARK: Row Style

    private var isActiveRow: Bool {
        progress?.status == .running || progress?.status == .queued
    }

    private var rowAccent: Color {
        switch progress?.status {
        case .running, .queued, .needsSudo:
            return .accentColor
        case .succeeded:
            return .green
        case .failed, .cancelled, .timedOut:
            return .red
        case .warning:
            return .yellow
        case nil:
            return package.outdated ? .orange : .secondary
        }
    }
}

// MARK: - Orphaned Failed Row

/// 失败孤儿行：升级失败后重新扫描，包已不在可升级集合里，但失败记录仍残留。
/// 复用普通失败行的视觉（红色强调 + 重试/清除按钮 + 失败详情），数据来自 PackageUpgradeProgress。
private struct OrphanedFailedRow: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var inboxStore: InboxStore
    @EnvironmentObject private var automationProfile: AutomationProfileStore
    var progress: PackageUpgradeProgress

    private var packageActionDisabled: Bool {
        model.isConfirmingUpgradePlan || model.isPackageActive(progress.packageID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                StatusIconPlate(symbol: "exclamationmark.triangle.fill", tint: .red, isActive: false)
                CopyableText(text: progress.packageName.isEmpty ? progress.packageID : progress.packageName)
                Spacer()
                PackageProgressBadge(progress: progress)
                Button {
                    Task { await model.retryPackage(progress.packageID, inboxStore: inboxStore) }
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(packageActionDisabled)
                Button {
                    model.clearPackageFailure(progress.packageID)
                } label: {
                    Label("清除", systemImage: "xmark")
                }
                .buttonStyle(.borderless)
                .disabled(packageActionDisabled)
            }

            PackageProgressDetail(progress: progress)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .polishedTaskSurface(tint: .red, isActive: false)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.red.opacity(0.15), lineWidth: 1)
        )
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

/// 可升级列表排序优先级：正在处理的排最前，其次是失败/需关注，其余最后。
private enum UpdateRowSort {
    static func priority(for status: PackageUpgradeStatus?) -> Int {
        switch status {
        case .running, .queued, .needsSudo:
            return 0
        case .failed, .timedOut, .cancelled, .warning:
            return 1
        case .succeeded, nil:
            return 2
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
        package.upgradeable ? "可升级" : "已最新"
    }

    private var color: Color {
        package.upgradeable ? .orange : .green
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
        case .needsSudo: return "lock.shield"
        }
    }

    private var color: Color {
        switch progress.status {
        case .queued, .running, .needsSudo: return .accentColor
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
    @EnvironmentObject private var automationProfile: AutomationProfileStore
    @EnvironmentObject private var inboxStore: InboxStore
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

            if let accelerationHint = UpgradeProgressPresenter.accelerationHint(for: progress) {
                Label(accelerationHint, systemImage: "bolt.horizontal.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                FlowingAccentLine(tint: .accentColor, isActive: true)
                downloadMetricRow(percentText: "\(Int(fraction * 100))%")
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                FlowingAccentLine(tint: .accentColor, isActive: true)
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
        .stewardSurface(cornerRadius: 10, tint: .red)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.red.opacity(0.15), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func actionButton(for action: FailureActionType) -> some View {
        switch action {
        case .retry, .quitAndRetry, .reimport, .cleanup, .repairPerms, .promptAdminPassword, .openLog:
            Button {
                Task { await model.retryPackage(progress.packageID, inboxStore: inboxStore) }
            } label: {
                Label(actionLabel(for: action), systemImage: actionIcon(for: action))
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .disabled(packageActionDisabled)

        case .rescan:
            Button {
                Task {
                    await model.scanSoftware(
                        regularAppNetworkPolicy: automationProfile.profile.regularAppNetworkPolicy,
                        notificationPolicy: automationProfile.profile.notificationPolicy,
                        inboxStore: inboxStore
                    )
                }
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .disabled(model.isScanning || model.isConfirmingUpgradePlan)

        case .checkNetwork:
            Button {
                Task { await model.retryPackage(progress.packageID, inboxStore: inboxStore) }
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
