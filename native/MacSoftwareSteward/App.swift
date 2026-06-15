import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var doubleClickZoomMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if activateExistingInstanceIfNeeded() {
            return
        }

        installDoubleClickZoomMonitor()

        // 读取 UserDefaults，注意区分「未设值」和「显式设为 false」
        let dockIconVisible: Bool
        if UserDefaults.standard.object(forKey: "dockIconVisible") == nil {
            dockIconVisible = true  // 首次使用，默认显示
        } else {
            dockIconVisible = UserDefaults.standard.bool(forKey: "dockIconVisible")
        }

        NSApp.setActivationPolicy(dockIconVisible ? .regular : .accessory)

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

    private func installDoubleClickZoomMonitor() {
        guard doubleClickZoomMonitor == nil else { return }
        doubleClickZoomMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let window = event.window,
                  self?.shouldZoom(window: window, for: event) == true else {
                return event
            }
            window.zoom(nil)
            return nil
        }
    }

    private func shouldZoom(window: NSWindow, for event: NSEvent) -> Bool {
        guard window.styleMask.contains(.titled),
              window.styleMask.contains(.resizable),
              !isStandardWindowButtonHit(event, in: window) else {
            return false
        }
        let contentHeight = window.contentView?.frame.height ?? window.contentLayoutRect.height
        return AppWindowDoubleClickZoomPolicy.shouldZoomOnDoubleClick(
            clickCount: event.clickCount,
            windowLocationY: event.locationInWindow.y,
            contentHeight: contentHeight
        )
    }

    private func isStandardWindowButtonHit(_ event: NSEvent, in window: NSWindow) -> Bool {
        [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton
        ]
        .compactMap { window.standardWindowButton($0) }
        .contains { button in
            guard let superview = button.superview else { return false }
            let buttonFrameInWindow = superview.convert(button.frame, to: nil)
            return buttonFrameInWindow.insetBy(dx: -6, dy: -6).contains(event.locationInWindow)
        }
    }
}

@main
struct MacSoftwareStewardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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
                    AppAppearanceResolver.apply(currentAppearanceMode)
                    applyDockIconPolicy()
                    if model.scan == nil {
                        await model.scanSoftware()
                    }
                    await updater.autoCheckIfNeeded()
                }
                .onAppear {
                    AppAppearanceResolver.apply(currentAppearanceMode)
                }
                .onChange(of: appearanceMode) {
                    AppAppearanceResolver.apply(currentAppearanceMode)
                }
                .onChange(of: dockIconVisible) {
                    applyDockIconPolicy()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))

        MenuBarExtra(menuBarTitle, systemImage: menuBarSymbol) {
            MenuBarUpgradeMenu()
                .environmentObject(model)
                .environmentObject(inboxStore)
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(after: .newItem) {
                Button("扫描软件") {
                    Task { await model.scanSoftware() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(model.isScanning)

                Button("一键升级可管理软件") {
                    model.prepareUpgradePlan(inboxStore: inboxStore)
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(model.availableUpdates.isEmpty || model.hasRunningJob || model.isConfirmingUpgradePlan)

                Button("检查应用更新") {
                    Task { await updater.checkForUpdates() }
                }
                .keyboardShortcut("u", modifiers: [.command, .option])
            }
        }
    }

    private var menuBarTitle: String {
        if model.isScanning {
            return "扫描中"
        }
        let totalCount = model.allUpgradeablePackages.count
        if model.hasRunningJob {
            return "升级中 · 剩余 \(model.availableUpdates.count) 待升级"
        }
        if model.isConfirmingUpgradePlan {
            return "准备升级中"
        }
        return totalCount > 0 ? "\(totalCount) 个更新" : "已最新"
    }

    private var menuBarSymbol: String {
        if model.isScanning { return "magnifyingglass" }
        if model.isConfirmingUpgradePlan { return "hourglass" }
        if model.hasRunningJob { return "arrow.triangle.2.circlepath" }
        return model.allUpgradeablePackages.isEmpty ? "checkmark.circle" : "arrow.down.circle.fill"
    }

    private var currentAppearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceMode) ?? .system
    }

    private func applyDockIconPolicy() {
        NSApp.setActivationPolicy(dockIconVisible ? .regular : .accessory)
    }
}

private struct MenuBarUpgradeMenu: View {
    @EnvironmentObject private var model: StewardModel
    @EnvironmentObject private var inboxStore: InboxStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(summaryText)

        Button {
            openMainWindowOnce()
        } label: {
            Label("打开 Mac 软件管家", systemImage: "macwindow")
        }

        Divider()

        Button {
            Task { await model.scanSoftware() }
        } label: {
            Label(model.isScanning ? "扫描中..." : "扫描更新", systemImage: "arrow.clockwise")
        }
        .disabled(model.isScanning)

        Button {
            openMainWindowOnce()
            model.prepareUpgradePlan(inboxStore: inboxStore)
        } label: {
            Label(model.isConfirmingUpgradePlan ? "准备中" : "一键升级", systemImage: model.isConfirmingUpgradePlan ? "hourglass" : "bolt.fill")
        }
        .disabled(model.availableUpdates.isEmpty || model.hasRunningJob || model.isConfirmingUpgradePlan)

        if model.hasRunningJob {
            Text("升级任务运行中")
        } else if model.isConfirmingUpgradePlan {
            Text("正在准备升级任务")
        }

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

    private var summaryText: String {
        if model.isScanning {
            return "正在扫描软件更新"
        }
        if model.hasRunningJob {
            return "正在升级，剩余 \(model.availableUpdates.count) 项待升级"
        }
        if model.isConfirmingUpgradePlan {
            return "正在准备升级任务"
        }
        let totalCount = model.allUpgradeablePackages.count
        return totalCount == 0
            ? "当前没有可升级软件"
            : "发现 \(totalCount) 个可升级软件"
    }
}
