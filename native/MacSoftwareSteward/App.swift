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

        MenuBarExtra {
            MenuBarUpgradeMenu()
                .environmentObject(model)
        } label: {
            MenuBarUpgradeLabel(
                count: model.availableUpdates.count,
                isScanning: model.isScanning,
                hasRunningJob: model.hasRunningJob
            )
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
}

private struct MenuBarUpgradeLabel: View {
    var count: Int
    var isScanning: Bool
    var hasRunningJob: Bool

    var body: some View {
        HStack(spacing: 3) {
            MenuBarGlyph(count: count, isScanning: isScanning, hasRunningJob: hasRunningJob)
                .frame(width: 16, height: 16)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
    }
}

private struct MenuBarGlyph: View {
    var count: Int
    var isScanning: Bool
    var hasRunningJob: Bool

    var body: some View {
        Canvas { context, size in
            let stroke = Color.primary.opacity(0.88)
            let line = max(1.25, size.width * 0.09)
            let cube = CGRect(x: size.width * 0.20, y: size.height * 0.19, width: size.width * 0.52, height: size.height * 0.52)
            var path = Path()
            path.move(to: CGPoint(x: cube.midX, y: cube.minY))
            path.addLine(to: CGPoint(x: cube.maxX, y: cube.minY + cube.height * 0.28))
            path.addLine(to: CGPoint(x: cube.maxX, y: cube.maxY - cube.height * 0.26))
            path.addLine(to: CGPoint(x: cube.midX, y: cube.maxY))
            path.addLine(to: CGPoint(x: cube.minX, y: cube.maxY - cube.height * 0.26))
            path.addLine(to: CGPoint(x: cube.minX, y: cube.minY + cube.height * 0.28))
            path.closeSubpath()
            path.move(to: CGPoint(x: cube.minX, y: cube.minY + cube.height * 0.28))
            path.addLine(to: CGPoint(x: cube.midX, y: cube.midY))
            path.addLine(to: CGPoint(x: cube.maxX, y: cube.minY + cube.height * 0.28))
            path.move(to: CGPoint(x: cube.midX, y: cube.midY))
            path.addLine(to: CGPoint(x: cube.midX, y: cube.maxY))
            context.stroke(path, with: .color(stroke), style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))

            let badge = Path(ellipseIn: CGRect(x: size.width * 0.61, y: size.height * 0.07, width: size.width * 0.34, height: size.height * 0.34))
            context.fill(badge, with: .color(Color.primary.opacity(count > 0 || hasRunningJob || isScanning ? 0.88 : 0.16)))

            var mark = Path()
            if isScanning || hasRunningJob {
                mark.move(to: CGPoint(x: size.width * 0.70, y: size.height * 0.24))
                mark.addLine(to: CGPoint(x: size.width * 0.78, y: size.height * 0.13))
                mark.addLine(to: CGPoint(x: size.width * 0.86, y: size.height * 0.24))
            } else if count > 0 {
                mark.move(to: CGPoint(x: size.width * 0.78, y: size.height * 0.12))
                mark.addLine(to: CGPoint(x: size.width * 0.78, y: size.height * 0.29))
                mark.move(to: CGPoint(x: size.width * 0.70, y: size.height * 0.22))
                mark.addLine(to: CGPoint(x: size.width * 0.78, y: size.height * 0.31))
                mark.addLine(to: CGPoint(x: size.width * 0.86, y: size.height * 0.22))
            } else {
                mark.move(to: CGPoint(x: size.width * 0.70, y: size.height * 0.23))
                mark.addLine(to: CGPoint(x: size.width * 0.76, y: size.height * 0.30))
                mark.addLine(to: CGPoint(x: size.width * 0.88, y: size.height * 0.14))
            }
            context.stroke(mark, with: .color(Color(nsColor: .controlBackgroundColor)), style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
        }
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if isScanning { return "正在扫描软件更新" }
        if hasRunningJob { return "正在升级软件" }
        return count > 0 ? "发现 \(count) 个可升级软件" : "没有可升级软件"
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
