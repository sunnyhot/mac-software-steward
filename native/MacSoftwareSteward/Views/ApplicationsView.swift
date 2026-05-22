import SwiftUI

struct ApplicationsView: View {
    @EnvironmentObject private var model: StewardModel

    var apps: [AppItem] {
        filter(model.scan?.applications.items ?? [], query: model.query) {
            "\($0.name) \($0.version) \($0.source) \($0.managedBy) \($0.path)"
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
                }

                ManagementBadge(app: app)

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
        return .clear
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
