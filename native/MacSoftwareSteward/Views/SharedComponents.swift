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

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            metadataRow
            releaseNotesPanel
            statusArea
            actionRow
        }
        .padding(30)
        .frame(width: 760)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: 72, height: 72)
                Image(systemName: "arrow.down")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("发现新版本")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                Text("\(updater.appDisplayName) v\(updater.latestVersion)")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("当前 \(updater.currentVersion) · 最新 \(updater.latestVersion)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 12) {
            UpdateMetaPill(text: updater.releaseAssetName.isEmpty ? "MacSoftwareSteward.zip" : updater.releaseAssetName, isPrimary: true)
            if !updater.releaseAssetSizeText.isEmpty {
                UpdateMetaPill(text: updater.releaseAssetSizeText)
            }
            if !updater.releasePublishedAtText.isEmpty {
                UpdateMetaPill(text: updater.releasePublishedAtText)
            }
        }
    }

    private var releaseNotesPanel: some View {
        ScrollView {
            Text(updater.releaseNotes.isEmpty ? "暂无更新说明。" : updater.releaseNotes)
                .font(.system(size: 17, weight: .regular))
                .lineSpacing(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(minHeight: 190, maxHeight: 260)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
    }

    @ViewBuilder
    private var statusArea: some View {
        if updater.isInstalling {
            VStack(alignment: .leading, spacing: 12) {
                if let fraction = updater.downloadFraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(Color.accentColor)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(Color.accentColor)
                }
                Text(updater.downloadStatusText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        } else if let errorMessage = updater.updateErrorMessage {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("更新失败")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.red.opacity(0.18), lineWidth: 1)
            )
        } else {
            Divider().opacity(0.5)
        }
    }

    private var actionRow: some View {
        HStack {
            Button("稍后") {
                updater.showUpdateDialog = false
            }
            .buttonStyle(.bordered)
            .disabled(updater.isInstalling)
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                if let url = URL(string: updater.releaseURL) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("查看发布页")
            }
            .buttonStyle(.bordered)
            .disabled(updater.releaseURL.isEmpty)

            Button {
                Task { await updater.downloadInstallAndRestart() }
            } label: {
                if updater.isInstalling {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("安装中...")
                    }
                } else if updater.updateErrorMessage != nil {
                    Label("重试下载", systemImage: "arrow.clockwise")
                } else {
                    Label("立即安装", systemImage: "square.and.arrow.down")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(updater.isInstalling)
            .keyboardShortcut(.defaultAction)
        }
    }
}

private struct UpdateMetaPill: View {
    var text: String
    var isPrimary = false

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isPrimary ? Color.accentColor : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isPrimary ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isPrimary ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.18), lineWidth: 1)
            )
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
    case .failed, .cancelled, .timedOut: return .red
    case .warning: return .yellow
    }
}

func logLineColor(_ stream: String) -> Color {
    switch stream {
    case "stdout": return .green
    case "stderr": return .red
    default: return .secondary
    }
}

// MARK: - 管理来源错误恢复卡片

struct ErrorRecoveryCard: View {
    var diagnosis: SourceDiagnosis
    var onAction: (SourceRecoveryAction) -> Void
    var isProcessing: Bool = false

    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 原因
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                Text(diagnosis.reason)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            // 建议
            Text(diagnosis.suggestion)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 终端命令提示（如果有）
            if let cmd = diagnosis.terminalCommand {
                TerminalCommandHint(command: cmd, hint: diagnosis.terminalHint)
            }

            // 操作按钮
            if let action = diagnosis.action, let label = diagnosis.actionLabel {
                HStack(spacing: 10) {
                    Button {
                        onAction(action)
                    } label: {
                        HStack(spacing: 6) {
                            if isProcessing {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(label)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isProcessing)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.orange.opacity(0.25), lineWidth: 1)
        )
    }
}

/// 可复制的终端命令提示条
struct TerminalCommandHint: View {
    var command: String
    var hint: String?

    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    copyToPasteboard(command)
                    withAnimation(.spring(response: 0.3)) {
                        showCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.spring(response: 0.3)) {
                            showCopied = false
                        }
                    }
                } label: {
                    if showCopied {
                        Label("已复制", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else {
                        Label("复制", systemImage: "doc.on.doc")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
