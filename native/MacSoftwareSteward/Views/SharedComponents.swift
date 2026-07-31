import SwiftUI

// MARK: - Shared Views

func tintColor(for role: MaintenanceStatusTintRole) -> Color {
    switch role {
    case .neutral:
        return .secondary
    case .accent:
        return .accentColor
    case .scanning:
        return .cyan
    case .attention:
        return .orange
    case .success:
        return .green
    case .failure:
        return .red
    }
}

extension View {
    @ViewBuilder
    func stewardSymbolPulse(active: Bool) -> some View {
        if #available(macOS 15.0, *) {
            self.symbolEffect(.pulse, options: .repeating, isActive: active)
        } else {
            self
        }
    }
}

struct FlowingAccentLine: View {
    var tint: Color
    var isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(isActive ? 0.18 : 0.12))

                if isActive && !reduceMotion {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.clear, tint.opacity(0.85), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(80, proxy.size.width * 0.32))
                        .offset(x: offset * proxy.size.width)
                }
            }
        }
        .frame(height: 2)
        .clipShape(Capsule())
        .onAppear {
            guard isActive && !reduceMotion else { return }
            offset = -0.35
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                offset = 1.05
            }
        }
        .onChange(of: isActive) {
            guard isActive && !reduceMotion else {
                offset = -0.35
                return
            }
            offset = -0.35
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                offset = 1.05
            }
        }
    }
}

struct PolishedTaskSurfaceModifier: ViewModifier {
    var tint: Color
    var isActive: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(StewardSurfaceBackground(role: .surface, cornerRadius: 10, tint: tint, isActive: isActive))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(tint.opacity(isActive ? 0.24 : 0.10), lineWidth: 1)
            )
            .shadow(
                color: tint.opacity(!reduceMotion ? AppSurfacePalette.shadowOpacity(isActive: isActive, appearance: appearance) : 0.02),
                radius: isActive ? 10 : 4,
                y: 2
            )
    }

    private var appearance: AppSurfaceAppearance {
        colorScheme == .dark ? .dark : .light
    }
}

extension View {
    func polishedTaskSurface(tint: Color = .accentColor, isActive: Bool = false) -> some View {
        modifier(PolishedTaskSurfaceModifier(tint: tint, isActive: isActive))
    }

    func stewardSurface(role: AppSurfaceRole = .surface, cornerRadius: CGFloat = 10, tint: Color? = nil, isActive: Bool = false) -> some View {
        background(StewardSurfaceBackground(role: role, cornerRadius: cornerRadius, tint: tint, isActive: isActive))
    }
}

struct StewardCanvasBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color(nsColor: AppSurfacePalette.nsColor(for: .canvas, appearance: appearance))
            .opacity(AppSurfacePalette.opacity(for: .canvas, appearance: appearance))
    }

    private var appearance: AppSurfaceAppearance {
        colorScheme == .dark ? .dark : .light
    }
}

struct StewardSurfaceBackground: View {
    var role: AppSurfaceRole
    var cornerRadius: CGFloat
    var tint: Color?
    var isActive: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(nsColor: AppSurfacePalette.nsColor(for: role, appearance: appearance)))
            .opacity(AppSurfacePalette.opacity(for: role, appearance: appearance))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(tintGradient)
            )
    }

    private var tintGradient: LinearGradient {
        let tintColor = tint ?? .clear
        return LinearGradient(
            colors: [
                tintColor.opacity(AppSurfacePalette.tintOpacity(isActive: isActive, appearance: appearance)),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var appearance: AppSurfaceAppearance {
        colorScheme == .dark ? .dark : .light
    }
}

struct StatusIconPlate: View {
    var symbol: String
    var tint: Color
    var isActive = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(isActive ? 0.20 : 0.14), tint.opacity(0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 34, height: 34)

            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .stewardSymbolPulse(active: isActive)
        }
    }
}

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
        .polishedTaskSurface(tint: .red, isActive: false)
    }
}

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var text: String

    var body: some View {
        VStack(spacing: 14) {
            StatusIconPlate(symbol: symbol, tint: .secondary)

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

// MARK: - App Update Dialog

struct AppUpdateDialog: View {
    @EnvironmentObject private var updater: AppUpdateModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppUpdateDialogLayout.sectionSpacing) {
            header
            metadataRow
            releaseNotesPanel
            statusArea
            actionRow
        }
        .padding(AppUpdateDialogLayout.outerPadding)
        .frame(
            width: AppUpdateDialogLayout.dialogWidth,
            height: AppUpdateDialogLayout.dialogHeight,
            alignment: .topLeading
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AppUpdateDialogLayout.headerSpacing) {
            ZStack {
                RoundedRectangle(cornerRadius: AppUpdateDialogLayout.iconCornerRadius)
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: AppUpdateDialogLayout.iconSize, height: AppUpdateDialogLayout.iconSize)
                Image(systemName: "arrow.down")
                    .font(.system(size: AppUpdateDialogLayout.iconSymbolSize, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("发现新版本")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
                Text("\(updater.appDisplayName) v\(updater.latestVersion)")
                    .font(.system(size: AppUpdateDialogLayout.titleSize, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("当前 \(updater.currentVersion) · 最新 \(updater.latestVersion)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 10) {
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
                .font(.system(size: 12, weight: .regular))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: AppUpdateDialogLayout.releaseNotesMaxHeight)
        .padding(AppUpdateDialogLayout.releaseNotesPadding)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
    }

    @ViewBuilder
    private var statusArea: some View {
        if updater.isInstalling {
            VStack(alignment: .leading, spacing: 9) {
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
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
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
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
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

// MARK: - 来源错误恢复卡片

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
        .stewardSurface(cornerRadius: 12, tint: .orange)
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
