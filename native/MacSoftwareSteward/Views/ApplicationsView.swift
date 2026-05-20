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

struct ApplicationRow: View {
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

struct VersionColumn: View {
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

struct ManagementBadge: View {
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
