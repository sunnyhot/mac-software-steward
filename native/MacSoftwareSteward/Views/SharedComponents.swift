import SwiftUI

// MARK: - Shared Views

struct Badge: View {
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

struct InfoLine: View {
    var text: String

    var body: some View {
        Label(text, systemImage: "info.circle")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WarningLine: View {
    var text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct InstallToolPrompt: View {
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

struct EmptyStateView: View {
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

struct CopyableText: View {
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

struct UpgradeProgressBar: View {
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

// MARK: - App Update Dialog

struct AppUpdateDialog: View {
    @EnvironmentObject private var updater: AppUpdateModel
    @State private var releaseNotesCollapsed = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 6) {
                    Text("发现新版本")
                        .font(.title2.bold())
                    HStack(spacing: 4) {
                        Text("v\(updater.currentVersion)")
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("v\(updater.latestVersion)")
                            .foregroundStyle(Color.accentColor)
                            .bold()
                    }
                    .font(.subheadline)
                }
                Spacer()
            }

            Divider()

            if !updater.releaseNotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("更新内容")
                            .font(.headline)
                        Spacer()
                        Button {
                            withAnimation { releaseNotesCollapsed.toggle() }
                        } label: {
                            Image(systemName: releaseNotesCollapsed ? "chevron.right" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if !releaseNotesCollapsed {
                        ScrollView {
                            Text(updater.releaseNotes)
                                .font(.system(.callout, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 200)
                    }
                }
            }

            if updater.isInstalling {
                VStack(alignment: .leading, spacing: 8) {
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
                    } else {
                        ProgressView {
                            Text(updater.progress.isEmpty ? "正在准备..." : updater.progress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .progressViewStyle(.linear)
                    }
                }
            }

            Divider()

            HStack {
                if !updater.releaseURL.isEmpty {
                    Button {
                        if let url = URL(string: updater.releaseURL) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("在 GitHub 查看")
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                Button("稍后提醒") {
                    updater.showUpdateDialog = false
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                if !updater.isInstalling {
                    Button {
                        Task { await updater.downloadInstallAndRestart() }
                    } label: {
                        Label("立即下载安装", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

// MARK: - Utility Functions

func copyToPasteboard(_ text: String) {
    guard !text.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

func versionText(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "-" : value
}

func availableVersionText(for package: UpdatablePackage) -> String {
    if !package.currentVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return package.currentVersion
    }
    if package.outdated && package.source == "Mac App Store" {
        return "待 App Store 确认"
    }
    return "-"
}

func appLocationText(_ app: AppItem) -> String {
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

func filter<T>(_ items: [T], query: String, text: (T) -> String) -> [T] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !needle.isEmpty else { return items }
    return items.filter { text($0).lowercased().contains(needle) }
}

func statusColor(_ status: JobStatus) -> Color {
    switch status {
    case .queued, .running: return .orange
    case .succeeded: return .green
    case .failed: return .red
    }
}

func logLineColor(_ stream: String) -> Color {
    switch stream {
    case "stdout": return .green
    case "stderr": return .red
    default: return .secondary
    }
}
