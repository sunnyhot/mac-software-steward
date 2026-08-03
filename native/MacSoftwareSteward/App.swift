import AppKit
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if activateExistingInstanceIfNeeded() {
            return
        }

        // 读取 UserDefaults，注意区分「未设值」和「显式设为 false」
        let dockIconVisible: Bool
        if UserDefaults.standard.object(forKey: "dockIconVisible") == nil {
            dockIconVisible = true  // 首次使用，默认显示
        } else {
            dockIconVisible = UserDefaults.standard.bool(forKey: "dockIconVisible")
        }

        NSApp.setActivationPolicy(dockIconVisible ? .regular : .accessory)
        UNUserNotificationCenter.current().delegate = self

        // 如果 Dock 图标隐藏，延迟隐藏已创建的主窗口
        if !dockIconVisible {
            DispatchQueue.main.async {
                for window in NSApp.windows {
                    if window.styleMask.contains(.titled) && window.styleMask.contains(.resizable) {
                        window.orderOut(nil)
                    }
                }
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.styleMask.contains(.titled) {
            window.makeKeyAndOrderFront(nil)
        }
        completionHandler()
    }

    private func activateExistingInstanceIfNeeded() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let runningApplications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        let runningPIDs = runningApplications.map(\.processIdentifier)
        guard AppSingleInstancePolicy.shouldTerminateCurrent(
            currentProcessIdentifier: currentPID,
            runningProcessIdentifiers: runningPIDs
        ) else {
            return false
        }

        let existingApplication = runningApplications
            .filter { $0.processIdentifier != currentPID }
            .min { $0.processIdentifier < $1.processIdentifier }
        existingApplication?.activate(options: [.activateAllWindows])
        NSApp.terminate(nil)
        return true
    }

}

@main
struct MacSoftwareStewardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage("dockIconVisible") private var dockIconVisible = true
    @StateObject private var model = StewardModel()
    @StateObject private var updater = AppUpdateModel()
    @StateObject private var launchAtLogin = LaunchAtLoginModel()
    @StateObject private var automationProfile = AutomationProfileStore()
    @StateObject private var inboxStore = InboxStore()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(updater)
                .environmentObject(launchAtLogin)
                .environmentObject(automationProfile)
                .environmentObject(inboxStore)
                .preferredColorScheme(AppAppearanceResolver.colorScheme(for: currentAppearanceMode))
                .frame(minWidth: 1120, minHeight: 720)
                .task {
                    applyDockIconPolicy()
                    model.refreshDailyInspectionStatus()
                    publishAutomationIssues()
                    if model.scan == nil {
                        await model.scanSoftware(
                            regularAppNetworkPolicy: automationProfile.profile.regularAppNetworkPolicy,
                            notificationPolicy: automationProfile.profile.notificationPolicy,
                            inboxStore: inboxStore
                        )
                    }
                    await updater.autoCheckIfNeeded()
                }
                .onChange(of: dockIconVisible) {
                    applyDockIconPolicy()
                }
                .onChange(of: scenePhase) {
                    guard scenePhase == .active else { return }
                    refreshForegroundStores()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        MenuBarExtra(menuBarTitle, systemImage: menuBarSymbol) {
            MenuBarUpgradeMenu()
                .environmentObject(model)
                .environmentObject(automationProfile)
                .environmentObject(inboxStore)
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(after: .newItem) {
                Button("扫描软件") {
                    Task {
                        await model.scanSoftware(
                            regularAppNetworkPolicy: automationProfile.profile.regularAppNetworkPolicy,
                            notificationPolicy: automationProfile.profile.notificationPolicy,
                            inboxStore: inboxStore
                        )
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(model.isScanning)

                Button("检查并维护") {
                    Task {
                        await model.checkAndPrepareMaintenance(
                            regularAppNetworkPolicy: automationProfile.profile.regularAppNetworkPolicy,
                            notificationPolicy: automationProfile.profile.notificationPolicy,
                            inboxStore: inboxStore
                        )
                    }
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(model.isScanning || model.hasRunningJob || model.isConfirmingUpgradePlan)

                Button("检查应用更新") {
                    Task { await updater.checkForUpdates() }
                }
                .keyboardShortcut("u", modifiers: [.command, .option])
            }
        }
    }

    private var menuBarTitle: String {
        menuBarPresentation.title
    }

    private var menuBarSymbol: String {
        menuBarPresentation.symbol
    }

    private var menuBarPresentation: MenuBarStatusPresentation {
        MenuBarStatusPresenter.presentation(
            isScanning: model.isScanning,
            isConfirmingUpgradePlan: model.isConfirmingUpgradePlan,
            hasRunningJob: model.hasRunningJob,
            activeUpgradeCount: activeUpgradeCount,
            remainingUpgradeableCount: model.availableUpdates.count,
            totalUpgradeableCount: model.executableUpdates.count
        )
    }

    private var activeUpgradeCount: Int {
        model.packageProgress.values.filter { progress in
            progress.status == .queued || progress.status == .running
        }.count
    }

    private var currentAppearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceMode) ?? .system
    }

    private func refreshForegroundStores() {
        inboxStore.reload()
        model.inspectionReportStore.reload()
        model.refreshDailyInspectionStatus()
        publishAutomationIssues()
    }

    private func publishAutomationIssues() {
        AutomationIssueInboxPublisher.publishDailyInspectionIssue(
            profile: automationProfile.profile,
            dailyInspectionEnabled: model.dailyInspectionEnabled,
            to: inboxStore
        )
    }

    private func applyDockIconPolicy() {
        NSApp.setActivationPolicy(dockIconVisible ? .regular : .accessory)
    }
}

private struct MenuBarUpgradeMenu: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var automationProfile: AutomationProfileStore
    @EnvironmentObject private var inboxStore: InboxStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openMainWindowOnce()
        } label: {
            Label("打开 Mac 软件管家", systemImage: "macwindow")
        }

        Divider()

        Button {
            Task {
                await model.scanSoftware(
                    regularAppNetworkPolicy: automationProfile.profile.regularAppNetworkPolicy,
                    notificationPolicy: automationProfile.profile.notificationPolicy,
                    inboxStore: inboxStore
                )
            }
        } label: {
            Label(model.isScanning ? "扫描中..." : "扫描更新", systemImage: "arrow.clockwise")
        }
        .disabled(model.isScanning)

        Button {
            openMainWindowOnce()
            Task {
                await model.checkAndPrepareMaintenance(
                    regularAppNetworkPolicy: automationProfile.profile.regularAppNetworkPolicy,
                    notificationPolicy: automationProfile.profile.notificationPolicy,
                    inboxStore: inboxStore
                )
            }
        } label: {
            Label(maintenanceActionTitle, systemImage: model.isConfirmingUpgradePlan ? "hourglass" : "bolt.fill")
        }
        .disabled(model.isScanning || model.hasRunningJob || model.isConfirmingUpgradePlan)

        Divider()

        Button("退出") {
            NSApplication.shared.terminate(nil)
        }
    }

    /// 单例打开主窗口：已有窗口时仅前置，避免重复创建
    private func openMainWindowOnce() {
        if let window = NSApp.windows.first(where: {
            $0.styleMask.contains(.titled) &&
            $0.styleMask.contains(.resizable) &&
            ($0.isVisible || $0.isMiniaturized)
        }) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var maintenanceActionTitle: String {
        if model.isScanning { return "检查中..." }
        if model.hasRunningJob { return "维护中" }
        if model.isConfirmingUpgradePlan { return "准备中" }
        return "检查并维护"
    }

    private var menuBarPresentation: MenuBarStatusPresentation {
        MenuBarStatusPresenter.presentation(
            isScanning: model.isScanning,
            isConfirmingUpgradePlan: model.isConfirmingUpgradePlan,
            hasRunningJob: model.hasRunningJob,
            activeUpgradeCount: activeUpgradeCount,
            remainingUpgradeableCount: model.availableUpdates.count,
            totalUpgradeableCount: model.executableUpdates.count
        )
    }

    private var activeUpgradeCount: Int {
        model.packageProgress.values.filter { progress in
            progress.status == .queued || progress.status == .running
        }.count
    }
}
