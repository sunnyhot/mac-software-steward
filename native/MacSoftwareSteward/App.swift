import SwiftUI

@main
struct MacSoftwareStewardApp: App {
    @StateObject private var model = StewardModel()
    @StateObject private var updater = AppUpdateModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(updater)
                .frame(minWidth: 1120, minHeight: 720)
                .task {
                    if model.scan == nil {
                        await model.scanSoftware()
                    }
                    await updater.autoCheckIfNeeded()
                }
        }
        .windowStyle(.titleBar)
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
}
