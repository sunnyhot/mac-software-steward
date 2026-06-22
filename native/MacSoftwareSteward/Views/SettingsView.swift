import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var updater: AppUpdateModel
    @EnvironmentObject private var launchAtLogin: LaunchAtLoginModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsGroupBox {
                    SettingsGroupHeader(
                        title: SettingsPageGroup.general.title,
                        symbol: SettingsPageGroup.general.symbol
                    )
                    AppearanceRow()
                    SettingsDivider()
                    LaunchAtLoginRow()
                    SettingsDivider()
                    DockIconRow()
                    SettingsDivider()
                    AdvancedModeRow()
                }

                SettingsGroupBox {
                    SettingsGroupHeader(
                        title: SettingsPageGroup.appUpdates.title,
                        symbol: SettingsPageGroup.appUpdates.symbol
                    )
                    AutoCheckUpdateRow()
                    if updater.automaticChecksEnabled {
                        SettingsDivider()
                        AutoDownloadUpdateRow()
                    }
                    SettingsDivider()
                    ManualCheckUpdateRow()
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
    }
}

// MARK: - Settings Group Box

struct SettingsGroupBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .opacity(0.5)
            .padding(.vertical, 2)
    }
}

struct SettingsGroupHeader: View {
    var title: String
    var symbol: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 26, height: 26)

                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            Text(title)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.primary)
        }
    }
}

struct AppearanceRow: View {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        HStack {
            Text("外观")
                .font(.body)
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
                .font(.body)
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
                    .font(.body)
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

struct PolicyHelpRow: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("单包升级策略")
                    .font(.body)
                Text("在可升级列表中可为每个软件设置自动升级、确认后升级、仅提醒或跳过；每日巡检只执行自动升级项。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct GreedyCaskRow: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("包含 greedy cask")
                    .font(.body)
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
                    .font(.body)
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
                    .font(.body)
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
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    private var access: AutomationMaintenanceAccess {
        AutomationMaintenanceAccessPresenter.dailyInspectionAccess(for: automationProfile.profile)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("启用每日巡检")
                    .font(.body)
                Text(access.caption)
                    .font(.caption)
                    .foregroundStyle(access.canEnable || model.dailyInspectionEnabled ? Color.secondary : .orange)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { model.dailyInspectionEnabled },
                set: { enabled in
                    Task {
                        if enabled {
                            guard access.canEnable else { return }
                            automationProfile.setDailyInspectionEnabled(true)
                            await model.enableDailyInspection()
                        } else {
                            automationProfile.setDailyInspectionEnabled(false)
                            await model.disableDailyInspection()
                        }
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(!access.canEnable && !model.dailyInspectionEnabled)
            .help(access.disabledReason ?? access.caption)
        }
    }
}

struct DailyInspectionTimeRow: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        HStack {
            Text("巡检时间")
                .font(.body)
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
                    .font(.body)
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
                    .font(.body)
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
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(updater.downloadStatusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if updater.updateAvailable {
                    Text("发现新版本 \(updater.latestVersion)，可前往下载安装")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let errorMessage = updater.updateErrorMessage {
                    // 下载失败时在设置页展示错误信息
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text(errorMessage)
                            .lineLimit(2)
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
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

            if (updater.updateAvailable || updater.updateErrorMessage != nil) && !updater.isInstalling {
                Button {
                    Task { await updater.downloadInstallAndRestart() }
                } label: {
                    if updater.updateErrorMessage != nil {
                        Label("重试", systemImage: "arrow.clockwise")
                    } else {
                        Label("下载安装", systemImage: "square.and.arrow.down")
                    }
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
                    .font(.body)
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

struct AutomationProfileRow: View {
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("自动化管家")
                    .font(.body)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if automationProfile.profile.onboardingCompleted {
                Toggle("", isOn: Binding(
                    get: { automationProfile.profile.automationEnabled },
                    set: { automationProfile.setAutomationEnabled($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            } else {
                Button("开启") {
                    automationProfile.completeOnboarding(enableAutomation: true)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("保持手动") {
                    automationProfile.completeOnboarding(enableAutomation: false)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var statusText: String {
        if !automationProfile.profile.onboardingCompleted {
            return "首次开启后只自动处理低风险维护事项"
        }
        return automationProfile.profile.automationEnabled ? "低风险维护可自动处理" : "当前保持手动维护"
    }
}

struct AdvancedModeRow: View {
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("高级模式")
                    .font(.body)
                Text("显示可升级、任务日志和高级策略")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { automationProfile.profile.advancedModeEnabled },
                set: { automationProfile.setAdvancedMode($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
    }
}

struct NotificationPolicyRow: View {
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    var body: some View {
        HStack {
            Text("通知")
                .font(.body)
            Spacer()
            Picker("", selection: Binding(
                get: { automationProfile.profile.notificationPolicy },
                set: { automationProfile.setNotificationPolicy($0) }
            )) {
                ForEach(NotificationPolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .frame(width: 220)
            .labelsHidden()
        }
    }
}

struct RegularAppNetworkPolicyRow: View {
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("普通 App 联网检查")
                    .font(.body)
                Text("控制 Sparkle 和厂商更新源检查范围")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { automationProfile.profile.regularAppNetworkPolicy },
                set: { automationProfile.setRegularAppNetworkPolicy($0) }
            )) {
                ForEach(RegularAppNetworkPolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .frame(width: 220)
            .labelsHidden()
        }
    }
}

struct AutoRepairPolicyRow: View {
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("失败恢复")
                    .font(.body)
                Text("控制是否允许低风险恢复动作自动执行")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { automationProfile.profile.autoRepairPolicy },
                set: { automationProfile.setAutoRepairPolicy($0) }
            )) {
                ForEach(AutoRepairPolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .frame(width: 220)
            .labelsHidden()
        }
    }
}
