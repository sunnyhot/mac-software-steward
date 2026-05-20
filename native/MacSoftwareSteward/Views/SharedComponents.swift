import SwiftUI

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
