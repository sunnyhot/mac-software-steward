import SwiftUI

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
