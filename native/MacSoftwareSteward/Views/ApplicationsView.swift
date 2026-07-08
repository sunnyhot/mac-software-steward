import SwiftUI

struct ApplicationsView: View {
    @EnvironmentObject private var model: StewardModel
    @State private var selectedFilter: LocalSoftwareFilter = .all

    var rows: [LocalSoftwareRow] {
        guard let scan = model.scan else { return [] }
        let queried = filter(LocalSoftwarePresenter.rows(from: scan), query: model.query) { row in
            row.searchText
        }
        return LocalSoftwarePresenter.filteredRows(queried, filter: selectedFilter)
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                filterHeader
                applicationContent
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, 4)
        }
    }

    private var filterHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("汇总电脑里可人工维护的软件，包括普通 App、Homebrew Formula、Homebrew Cask 和 App Store 应用。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Picker("筛选", selection: $selectedFilter) {
                ForEach(LocalSoftwareFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 520)
        }
    }

    @ViewBuilder
    private var applicationContent: some View {
        if let scan = model.scan?.applications, !scan.error.isEmpty {
            WarningLine(text: scan.error)
        }
        if rows.isEmpty {
            EmptyStateView(
                symbol: "checkmark.seal",
                title: "暂无可维护软件",
                text: "扫描完成后，这里会列出可人工升级或检查更新的软件。"
            )
        } else {
            LazyVStack(spacing: 8) {
                ForEach(rows) { row in
                    LocalSoftwareRowView(row: row)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                }
            }
        }
    }
}

// MARK: - LocalSoftwareRowView

private struct LocalSoftwareRowView: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var inboxStore: InboxStore
    @EnvironmentObject private var automationProfile: AutomationProfileStore
    var row: LocalSoftwareRow

    @State private var isHovered = false

    private var progress: PackageUpgradeProgress? {
        guard let package = row.package else { return nil }
        return model.packageProgress[package.id]
    }

    var body: some View {
        if let app = row.app {
            ApplicationRow(app: app)
        } else {
            packageRow
        }
    }

    private var packageRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(kindColor.opacity(0.12))
                        .frame(width: 30, height: 30)
                    Image(systemName: row.kind.symbol)
                        .font(.system(.callout, weight: .medium))
                        .foregroundStyle(kindColor)
                }

                CopyableText(text: row.name)

                Spacer()

                if row.isPinned {
                    Badge(text: "固定", color: .red)
                }
                if row.autoUpdates {
                    Badge(text: "自更新", color: .blue)
                }

                Badge(text: row.kind.title, color: kindColor)

                if let progress {
                    PackageProgressBadge(progress: progress)
                } else {
                    Badge(text: statusTitle, color: statusColor)
                }

                if row.isOutdated, let package = row.package {
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
                    .buttonStyle(.borderless)
                    .disabled(!row.isUpgradeable || model.isPackageActive(package.id))
                }
            }

            HStack(spacing: 8) {
                Text(row.source)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.08), in: Capsule())

                VersionChangeLabel(
                    current: row.installedVersion,
                    available: row.currentVersion
                )

                if !row.detail.isEmpty {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(row.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
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
                .stroke(isHovered ? kindColor.opacity(0.20) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .scaleEffect(isHovered && progress == nil ? 1.005 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var kindColor: Color {
        switch row.kind {
        case .app: return .blue
        case .brewFormula: return .orange
        case .brewCask: return .purple
        case .appStore: return .blue
        }
    }

    private var statusTitle: String {
        if row.isUpgradeable { return "可升级" }
        if row.isOutdated { return "需确认" }
        if row.isCheckable { return "可手动检查" }
        return "已安装"
    }

    private var statusColor: Color {
        if row.isUpgradeable { return .orange }
        if row.isOutdated { return .secondary }
        if row.isCheckable { return .blue }
        return .green
    }

    private var rowTint: Color {
        switch progress?.status {
        case .running, .queued: return Color.accentColor.opacity(0.04)
        case .succeeded: return Color.green.opacity(0.04)
        case .failed, .cancelled, .timedOut: return Color.red.opacity(0.04)
        case .warning: return Color.yellow.opacity(0.04)
        case nil: return row.isOutdated ? Color.orange.opacity(0.03) : .clear
        }
    }
}

// MARK: - ApplicationRow

struct ApplicationRow: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore
    var app: AppItem

    @State private var isHovered = false

    var progress: PackageUpgradeProgress? {
        app.relatedPackageID.isEmpty ? nil : model.packageProgress[app.relatedPackageID]
    }

    private var updatePresentation: AppManualUpdatePresentation {
        AppManualUpdatePresenter.presentation(for: app)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 主行：图标 + 名称 + 管理方式 + 操作
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.10))
                        .frame(width: 30, height: 30)
                    Image(systemName: "macwindow")
                        .font(.system(.callout, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }

                CopyableText(text: app.name)

                Spacer()

                if let progress {
                    PackageProgressBadge(progress: progress)
                } else if let statusTitle = updatePresentation.statusTitle {
                    Badge(text: statusTitle, color: statusColor)
                }

                ManagementBadge(app: app)

                if let primaryAction = updatePresentation.primaryAction {
                    Button {
                        model.performUpdateAction(primaryAction, for: app)
                    } label: {
                        Label(updatePresentation.primaryTitle, systemImage: primaryAction.systemImage)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(updatePresentation.primaryTitle)

                    ForEach(updatePresentation.secondaryActions.filter { $0.kind != .directReplace }, id: \.self) { action in
                        Button {
                            model.performUpdateAction(action, for: app)
                        } label: {
                            Image(systemName: action.systemImage)
                        }
                        .buttonStyle(.borderless)
                        .help(action.title)
                    }
                }

                if updatePresentation.primaryAction == nil {
                    Button {
                        model.reveal(app)
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderless)
                    .help("在 Finder 中显示")
                }
            }

            // 次行：路径 + 版本 + 位置
            HStack(spacing: 6) {
                Text(app.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !app.version.isEmpty {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    VersionChangeLabel(current: app.version, available: app.availableVersion)
                }

                Spacer()

                Text(appLocationText(app))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 40)

            if app.updateCapability.hasManualAction && app.managedBy == "manual" {
                AppUpdateCapabilityLine(capability: app.updateCapability)
                    .padding(.leading, 40)
                ManualUpdateActionCallout(app: app, presentation: updatePresentation)
                    .padding(.leading, 40)
            }

            if automationProfile.profile.advancedModeEnabled,
               let diagnostic = AppDiagnosticsPresenter.row(from: app) {
                AppDiagnosticDetail(row: diagnostic)
                    .padding(.leading, 40)
            }

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
                .stroke(isHovered ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.005 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var rowTint: Color {
        if progress != nil { return Color.accentColor.opacity(0.04) }
        if app.updateState == "outdated" { return Color.orange.opacity(0.03) }
        if app.updateState == "checkable" { return Color.blue.opacity(0.03) }
        return .clear
    }

    private var statusColor: Color {
        if app.updateState == "outdated" { return .orange }
        if app.updateState == "checkable" { return .blue }
        return .secondary
    }
}

private struct ManualUpdateActionCallout: View {
    @EnvironmentObject private var model: StewardModel
    var app: AppItem
    var presentation: AppManualUpdatePresentation

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.point.up.left.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(width: 16)

            Text(presentation.guidanceText)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer(minLength: 12)

            if let primaryAction = presentation.primaryAction {
                Button {
                    model.performUpdateAction(primaryAction, for: app)
                } label: {
                    Label(presentation.primaryTitle, systemImage: primaryAction.systemImage)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Button {
                    model.reveal(app)
                } label: {
                    Label("在 Finder 中显示", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let directReplaceAction {
                Button {
                    model.performUpdateAction(directReplaceAction, for: app)
                } label: {
                    Label(directReplaceAction.title, systemImage: directReplaceAction.systemImage)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.orange)
                .help("下载更新包并直接覆盖当前 App，风险自负")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
    }

    private var directReplaceAction: AppUpdateAction? {
        presentation.secondaryActions.first { $0.kind == .directReplace }
    }
}

private struct AppDiagnosticDetail: View {
    var row: AppDiagnosticRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .opacity(0.35)

            HStack(spacing: 6) {
                Image(systemName: "stethoscope")
                    .font(.caption)
                    .foregroundStyle(diagnosticColor(row.severity))
                Text("诊断详情")
                    .font(.caption)
                    .fontWeight(.semibold)
                Badge(text: row.reasonTitle, color: diagnosticColor(row.severity))
                Badge(text: row.detectorTitle, color: .blue)
                Badge(text: row.stateTitle, color: diagnosticColor(row.severity))
                Spacer(minLength: 0)
            }

            Text(row.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(row.actionHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(row.detailItems, id: \.self) { item in
                    HStack(spacing: 5) {
                        Image(systemName: item.symbol)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(width: 14)
                        Text(item.title)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Text(item.value)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            if !row.feedURLString.isEmpty {
                HStack(spacing: 6) {
                    Text("Feed")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text(row.feedURLString)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Text(row.diagnostic)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(3)
        }
    }
}

private func diagnosticColor(_ severity: InboxSeverity) -> Color {
    switch severity {
    case .critical:
        return .red
    case .warning:
        return .orange
    case .info:
        return .blue
    }
}

private struct AppUpdateCapabilityLine: View {
    var capability: AppUpdateCapability

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.app")
                .font(.caption)
                .foregroundStyle(.blue)
            Text(capability.detector.title)
                .font(.caption)
                .fontWeight(.semibold)
            Text(capability.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !capability.feedURLString.isEmpty {
                Text(capability.feedURLString)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }
}

// MARK: - ManagementBadge

struct ManagementBadge: View {
    var app: AppItem

    var body: some View {
        let label: String = {
            if app.managedBy == "brew-cask" { return "Homebrew" }
            if app.managedBy == "mas" { return "App Store" }
            if app.source == "Apple" || app.path.hasPrefix("/System/") { return "系统" }
            return "手动"
        }()

        let color: Color = {
            if app.managedBy == "brew-cask" || app.managedBy == "mas" {
                return app.updateState == "outdated" ? .orange : .green
            }
            return .secondary
        }()

        Badge(text: label, color: color)
    }
}
