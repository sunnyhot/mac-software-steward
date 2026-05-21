import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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
}

@main
struct MacSoftwareStewardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage("dockIconVisible") private var dockIconVisible = true
    @StateObject private var model = StewardModel()
    @StateObject private var updater = AppUpdateModel()
    @StateObject private var launchAtLogin = LaunchAtLoginModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(updater)
                .environmentObject(launchAtLogin)
                .preferredColorScheme(currentAppearanceMode.colorScheme)
                .frame(minWidth: 1120, minHeight: 720)
                .task {
                    applyDockIconPolicy()
                    if model.scan == nil {
                        await model.scanSoftware()
                    }
                    await updater.autoCheckIfNeeded()
                }
                .onChange(of: dockIconVisible) {
                    applyDockIconPolicy()
                }
        }
        .windowStyle(.titleBar)

        MenuBarExtra(menuBarTitle, systemImage: menuBarSymbol) {
            MenuBarUpgradeMenu()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(after: .newItem) {
                Button("扫描软件") {
                    Task { await model.scanSoftware() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("一键升级可管理软件") {
                    Task { await model.upgradeAll() }
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(model.availableUpdates.isEmpty || model.hasRunningJob)

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
        return totalCount > 0 ? "\(totalCount) 个更新" : "已最新"
    }

    private var menuBarSymbol: String {
        if model.isScanning { return "magnifyingglass" }
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
            Task { await model.upgradeAll() }
        } label: {
            Label("一键升级", systemImage: "bolt.fill")
        }
        .disabled(model.availableUpdates.isEmpty || model.hasRunningJob)

        if model.hasRunningJob {
            Text("升级任务运行中")
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
        let totalCount = model.allUpgradeablePackages.count
        return totalCount == 0
            ? "当前没有可升级软件"
            : "发现 \(totalCount) 个可升级软件"
    }
}
