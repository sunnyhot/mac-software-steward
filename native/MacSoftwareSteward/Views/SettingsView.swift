import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var updater: AppUpdateModel
    @EnvironmentObject private var launchAtLogin: LaunchAtLoginModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                SettingsGroupBox {
                    SettingsGroupHeader(title: "通用", symbol: "gearshape")
                    AppearanceRow()
                    Divider()
                    LaunchAtLoginRow()
                    Divider()
                    DockIconRow()
                }

                SettingsGroupBox {
                    SettingsGroupHeader(title: "扫描与升级策略", symbol: "slider.horizontal.3")
                    GreedyCaskRow()
                    Divider()
                    BrewUpdateRow()
                    Divider()
                    MaxConcurrentUpgradesRow()
                }

                SettingsGroupBox {
                    SettingsGroupHeader(title: "每日巡检", symbol: "calendar.badge.clock")
                    DailyInspectionToggleRow()
                    if model.dailyInspectionEnabled {
                        Divider()
                        DailyInspectionTimeRow()
                    }
                }

                SettingsGroupBox {
                    SettingsGroupHeader(title: "应用更新", symbol: "arrow.down.app")
                    AutoCheckUpdateRow()
                    if updater.automaticChecksEnabled {
                        Divider()
                        AutoDownloadUpdateRow()
                    }
                    Divider()
                    ManualCheckUpdateRow()
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: 600, alignment: .leading)
        }
    }
}

struct SettingsGroupBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        )
    }
}

struct SettingsGroupHeader: View {
    var title: String
    var symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
        }
    }
}

struct AppearanceRow: View {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        HStack {
            Text("外观")
            Spacer()
            Picker("", selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .labelsHidden()
        }
    }
}

struct LaunchAtLoginRow: View {
    @EnvironmentObject private var launchAtLogin: LaunchAtLoginModel

    var body: some View {
        HStack {
            Text("开机自动启动")
            Spacer()
            Toggle("", isOn: Binding(
                get: { launchAtLogin.enabled },
                set: { enabled in
                    Task { await launchAtLogin.setEnabled(enabled) }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(launchAtLogin.isChanging)
        }
    }
}

struct DockIconRow: View {
    @AppStorage("dockIconVisible") private var dockIconVisible = true

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("在 Dock 中显示")
                Text("关闭后应用只在菜单栏运行，不占用 Dock 位置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $dockIconVisible)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

struct GreedyCaskRow: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("包含 greedy cask")
                Text("auto_updates 或 :latest 的 Cask 也纳入扫描")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $model.includeGreedy)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

struct BrewUpdateRow: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("升级前 brew update")
                Text("一键升级和自动升级前先执行 brew update")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $model.runBrewUpdate)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

struct MaxConcurrentUpgradesRow: View {
    @EnvironmentObject private var model: StewardModel
    private let options = [1, 2, 3, 5, 10, 0]

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("并行升级数量")
                Text("同时执行的最大升级任务数，超出自动排队")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $model.maxConcurrentUpgrades) {
                ForEach(options, id: \.self) { value in
                    Text(value == 0 ? "不限" : "\(value)").tag(value)
                }
            }
            .frame(width: 100)
            .labelsHidden()
        }
    }
}

struct DailyInspectionToggleRow: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("启用每日巡检")
                Text("定时扫描可管理来源，发现可升级项后自动执行升级")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { model.dailyInspectionEnabled },
                set: { enabled in
                    Task {
                        if enabled {
                            await model.enableDailyInspection()
                        } else {
                            await model.disableDailyInspection()
                        }
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
    }
}

struct DailyInspectionTimeRow: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        HStack {
            Text("巡检时间")
            Spacer()
            Picker("时", selection: $model.dailyHour) {
                ForEach(0..<24) { hour in
                    Text(String(format: "%02d", hour)).tag(hour)
                }
            }
            .frame(width: 80)
            .labelsHidden()
            Text(":")
            Picker("分", selection: $model.dailyMinute) {
                ForEach(0..<60) { minute in
                    Text(String(format: "%02d", minute)).tag(minute)
                }
            }
            .frame(width: 80)
            .labelsHidden()
            Button {
                Task { await model.enableDailyInspection() }
            } label: {
                Text("保存")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}

struct AutoCheckUpdateRow: View {
    @EnvironmentObject private var updater: AppUpdateModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("启动时自动检查更新")
                Text("每次启动应用时从 GitHub Release 检查新版本")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $updater.automaticChecksEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

struct ManualCheckUpdateRow: View {
    @EnvironmentObject private var updater: AppUpdateModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("手动检查更新")
                if updater.isInstalling {
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
                        .frame(maxWidth: 260)
                    } else {
                        Text(updater.progress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if updater.updateAvailable {
                    Text("发现新版本 \(updater.latestVersion)，可前往下载安装")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("当前版本 \(updater.currentVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await updater.checkForUpdates() }
            } label: {
                Label(updater.isChecking ? "检查中" : "立即检查", systemImage: updater.isChecking ? "hourglass" : "arrow.clockwise")
            }
            .disabled(updater.isChecking || updater.isInstalling)

            if updater.updateAvailable && !updater.isInstalling {
                Button {
                    Task { await updater.downloadInstallAndRestart() }
                } label: {
                    Label("下载安装", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(updater.isInstalling)
            }

            if updater.isInstalling {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}

struct AutoDownloadUpdateRow: View {
    @EnvironmentObject private var updater: AppUpdateModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("自动下载并安装更新")
                Text("发现新版本后自动下载、覆盖安装并重启")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $updater.automaticDownloadsEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}
