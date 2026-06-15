import SwiftUI

struct ApplicationsView: View {
    @EnvironmentObject private var model: StewardModel

    var apps: [AppItem] {
        filter(model.scan?.applications.items ?? [], query: model.query) {
            "\($0.name) \($0.version) \($0.source) \($0.managedBy) \($0.path) \($0.updateCapability.detector.title) \($0.updateCapability.summary)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本机应用是实际安装的 .app；安装位置说明 App 文件在哪，管理方式说明由 Homebrew、App Store、系统或手动维护。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let scan = model.scan?.applications, !scan.error.isEmpty {
                WarningLine(text: scan.error)
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(apps) { app in
                        ApplicationRow(app: app)
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

// MARK: - ApplicationRow

struct ApplicationRow: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore
    var app: AppItem

    @State private var isHovered = false

    var progress: PackageUpgradeProgress? {
        app.relatedPackageID.isEmpty ? nil : model.packageProgress[app.relatedPackageID]
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
                } else if app.updateState == "outdated" {
                    Badge(text: "可升级", color: .orange)
                } else if app.updateState == "checkable" {
                    Badge(text: "可检查", color: .blue)
                }

                ManagementBadge(app: app)

                if app.updateCapability.hasManualAction && app.managedBy == "manual" {
                    ForEach(app.updateCapability.actions, id: \.self) { action in
                        Button {
                            model.performUpdateAction(action, for: app)
                        } label: {
                            Image(systemName: action.systemImage)
                        }
                        .buttonStyle(.borderless)
                        .help(action.title)
                    }
                }

                Button {
                    model.reveal(app)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("在 Finder 中显示")
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
