import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsGroupBox {
                    SettingsGroupHeader(title: "自动维护", symbol: "bolt.badge.checkmark")
                    AutomaticMaintenanceRow()
                    SettingsDivider()
                    NotificationPolicyRow()
                }

                SettingsGroupBox {
                    SettingsGroupHeader(title: "运行状态", symbol: "clock.badge.checkmark")
                    DailyInspectionHealthRow()
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
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
            Toggle("", isOn: Binding(
                get: { model.includeGreedy },
                set: { enabled in
                    model.includeGreedy = enabled
                    if model.dailyInspectionEnabled {
                        Task { await model.enableDailyInspection() }
                    }
                }
            ))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(model.isUpdatingDailyInspection)
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
                Text("维护计划和自动升级执行前先运行 brew update")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { model.runBrewUpdate },
                set: { enabled in
                    model.runBrewUpdate = enabled
                    if model.dailyInspectionEnabled {
                        Task { await model.enableDailyInspection() }
                    }
                }
            ))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(model.isUpdatingDailyInspection)
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

struct AutomaticMaintenanceRow: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    private var isEnabled: Bool {
        model.dailyInspectionEnabled
            && automationProfile.profile.lowRiskAutoUpgradeEnabled
            && automationProfile.profile.autoRepairPolicy == .allowLowRisk
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("自动维护")
                    .font(.body)
                Text("每天自动扫描，安全升级并清理可确认的残留；高风险操作仍需确认")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { enabled in
                    Task {
                        if enabled {
                            automationProfile.setLowRiskAutoUpgradeEnabled(true)
                            automationProfile.setAutoRepairPolicy(.allowLowRisk)
                            automationProfile.setDailyInspectionEnabled(true)
                            await model.enableDailyInspection()
                        } else {
                            automationProfile.setDailyInspectionEnabled(false)
                            automationProfile.setLowRiskAutoUpgradeEnabled(false)
                            automationProfile.setAutoRepairPolicy(.manualOnly)
                            await model.disableDailyInspection()
                            model.refreshDailyInspectionStatus(preference: false)
                        }
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(model.isUpdatingDailyInspection)
        }
    }
}

struct DailyInspectionToggleRow: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("启用每日巡检")
                    .font(.body)
                Text(model.dailyInspectionEnabled
                    ? (automationProfile.profile.lowRiskAutoUpgradeEnabled
                        ? "按计划扫描，并自动处理符合条件的更新"
                        : "按计划扫描；当前仅提醒，不会自动升级")
                    : "开启后按计划扫描；自动升级由下方设置独立控制")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { model.dailyInspectionEnabled },
                set: { enabled in
                    Task {
                        if enabled {
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
            .disabled(model.isUpdatingDailyInspection)
            .help("启用或停用每日后台巡检")
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
                Text(model.isUpdatingDailyInspection ? "保存中…" : "保存")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut(.defaultAction)
        }
        .disabled(model.isUpdatingDailyInspection)
    }
}

struct DailyInspectionHealthRow: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusSymbol)
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.body)
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if case .needsRepair = model.dailyInspectionHealth {
                Button(automationProfile.profile.dailyInspectionEnabled ? "一键修复" : "重试停用") {
                    Task {
                        if automationProfile.profile.dailyInspectionEnabled {
                            await model.repairDailyInspection()
                        } else {
                            await model.repairDailyInspectionIfNeeded(dailyInspectionPreference: false)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("重新安装并加载当前版本的每日巡检后台程序")
            } else if presentation.tone == .warning {
                Button("查看日志") {
                    model.openDailyInspectionLog()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("打开每日巡检日志查看失败原因")
            }
        }
        .disabled(model.isUpdatingDailyInspection)
    }

    private var presentation: DailyInspectionStatusPresentation {
        DailyInspectionStatusPresenter.make(
            health: model.dailyInspectionHealth,
            runtime: model.dailyInspectionRuntime,
            latestReport: model.inspectionReportStore.reports.first { $0.trigger == .dailyAgent },
            automaticUpgradeEnabled: automationProfile.profile.lowRiskAutoUpgradeEnabled,
            hour: model.dailyHour,
            minute: model.dailyMinute
        )
    }

    private var statusTitle: String { presentation.title }
    private var statusDetail: String { presentation.detail }
    private var statusSymbol: String { presentation.symbol }

    private var statusColor: Color {
        if presentation.tone == .warning { return .orange }
        return model.dailyInspectionHealth == .disabled ? .secondary : .green
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

            if updater.updateAvailable && HomebrewSelfInstallDetector.isManaged() && !updater.isInstalling {
                Label("由 Homebrew 管理，请用 brew upgrade 更新", systemImage: "terminal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if (updater.updateAvailable || updater.updateErrorMessage != nil) && !updater.isInstalling {
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

struct LowRiskHandlingRow: View {
    @EnvironmentObject private var automationProfile: AutomationProfileStore

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("自动升级")
                    .font(.body)
                Text("选择每日巡检发现更新后的处理方式")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { automationProfile.profile.lowRiskAutoUpgradeEnabled },
                set: { automationProfile.setLowRiskAutoUpgradeEnabled($0) }
            )) {
                Text("仅提醒").tag(false)
                Text("自动处理").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
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
                get: {
                    // 历史遗留的 everyInspection/everyAction 已从 UI 移除；显示时归一为最接近的可见项。
                    NotificationPolicy.visibleCases.contains(automationProfile.profile.notificationPolicy)
                        ? automationProfile.profile.notificationPolicy
                        : .decisionsAndFailures
                },
                set: { automationProfile.setNotificationPolicy($0) }
            )) {
                ForEach(NotificationPolicy.visibleCases) { policy in
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
                get: {
                    // aggressive 是历史遗留值，UI 不再展示；显示时归一为等效的默认项。
                    automationProfile.profile.regularAppNetworkPolicy == .aggressive
                        ? .declaredSourcesOnly
                        : automationProfile.profile.regularAppNetworkPolicy
                },
                set: { automationProfile.setRegularAppNetworkPolicy($0) }
            )) {
                ForEach(RegularAppNetworkPolicy.visibleCases) { policy in
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
