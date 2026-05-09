import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginModel: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var status = ""
    @Published var isChanging = false

    init() {
        refresh()
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            enabled = true
            status = "开机自动启动已启用。"
        case .requiresApproval:
            enabled = false
            status = "需要在系统设置中批准开机启动。"
        case .notRegistered:
            enabled = false
            status = "开机自动启动未启用。"
        case .notFound:
            enabled = false
            status = "当前应用位置不支持注册开机启动，请先移动到“应用程序”文件夹。"
        @unknown default:
            enabled = false
            status = "无法读取开机启动状态。"
        }
    }

    func setEnabled(_ nextEnabled: Bool) async {
        guard !isChanging else { return }
        isChanging = true
        defer { isChanging = false }

        do {
            if nextEnabled {
                try SMAppService.mainApp.register()
            } else {
                try await SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            refresh()
            status = nextEnabled
                ? "启用开机自动启动失败：\(error.localizedDescription)"
                : "停用开机自动启动失败：\(error.localizedDescription)"
        }
    }
}
