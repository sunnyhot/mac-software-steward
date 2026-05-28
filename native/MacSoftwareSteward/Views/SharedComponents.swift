import SwiftUI

// MARK: - Shared Views

struct Badge: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text.isEmpty ? "-" : text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .lineLimit(1)
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
}

/// 紧凑的版本变化标签：显示 "1.0 → 2.0"，无可用版本时只显示当前版本
struct VersionChangeLabel: View {
    var current: String
    var available: String

    private var displayCurrent: String { versionText(current) }
    private var displayAvailable: String { versionText(available) }

    var body: some View {
        HStack(spacing: 3) {
            Text(displayCurrent)
            if displayAvailable != "-" {
                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.orange.opacity(0.7))
                Text(displayAvailable)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
    }
}

struct InfoLine: View {
    var text: String

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WarningLine: View {
    var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.callout)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.red.opacity(0.2), lineWidth: 1)
        )
    }
}

struct InstallToolPrompt: View {
    var title: String
    var text: String
    var symbol: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 40, height: 40)

                Image(systemName: symbol)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var text: String

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )

                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.primary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}

struct CopyableText: View {
    var text: String
    var font: Font = .system(.headline, design: .rounded)
    @State private var didCopy = false

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.primary)
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
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                        Text("已复制")
                            .font(.caption2)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green, in: RoundedRectangle(cornerRadius: 6))
                    .offset(y: -22)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .animation(.spring(response: 0.3), value: didCopy)
    }
}

struct UpgradeProgressBar: View {
    var progress: UpgradeProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.15), lineWidth: 2.5)
                        .frame(width: 28, height: 28)

                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("正在升级 \(progress.completed)/\(progress.total)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        if let current = progress.currentPackage {
                            Text("·")
                                .foregroundStyle(.tertiary)
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
                    .font(.system(.callout, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)
                .tint(progress.failed > 0 && !progress.isRunning ? .orange : .accentColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor.opacity(0.15), lineWidth: 1)
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
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 56, height: 56)
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("发现新版本")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    HStack(spacing: 6) {
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
                            .font(.system(.headline, design: .rounded))
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.3)) { releaseNotesCollapsed.toggle() }
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
            } else if let errorMessage = updater.updateErrorMessage {
                // 下载/安装失败：显示错误信息和重试入口
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                        Text("更新失败")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.red)
                        Spacer()
                    }
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.red.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.red.opacity(0.2), lineWidth: 1)
                        )
                )
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
                        if updater.updateErrorMessage != nil {
                            Label("重试下载", systemImage: "arrow.clockwise")
                        } else {
                            Label("立即下载安装", systemImage: "square.and.arrow.down")
                        }
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
        return "/Applications"
    }
    if app.path.contains("/Applications/") {
        return "用户应用目录"
    }
    if app.path.hasPrefix("/System/") {
        return "系统"
    }
    return app.source.isEmpty ? "未知" : app.source
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
