import SwiftUI

@main
struct MacSoftwareStewardApp: App {
    @StateObject private var model = StewardModel()
    @StateObject private var updater = AppUpdateModel()
    @StateObject private var launchAtLogin = LaunchAtLoginModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(updater)
                .environmentObject(launchAtLogin)
                .frame(minWidth: 1120, minHeight: 720)
                .task {
                    if model.scan == nil {
                        await model.scanSoftware()
                    }
                    await updater.autoCheckIfNeeded()
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
        if model.hasRunningJob {
            return "升级中 \(model.availableUpdates.count)"
        }
        let count = model.availableUpdates.count
        return count > 0 ? "\(count) 个更新" : "已最新"
    }

    private var menuBarSymbol: String {
        if model.isScanning { return "magnifyingglass" }
        if model.hasRunningJob { return "arrow.triangle.2.circlepath" }
        return model.availableUpdates.isEmpty ? "checkmark.circle" : "arrow.down.circle.fill"
    }
}

private struct MenuBarUpgradeMenu: View {
    @EnvironmentObject private var model: StewardModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(summaryText)

        Button {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
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

    private var summaryText: String {
        if model.isScanning {
            return "正在扫描软件更新"
        }
        if model.hasRunningJob {
            return "正在升级，剩余可升级 \(model.availableUpdates.count) 项"
        }
        return model.availableUpdates.isEmpty
            ? "当前没有可升级软件"
            : "发现 \(model.availableUpdates.count) 个可升级软件"
    }
}
