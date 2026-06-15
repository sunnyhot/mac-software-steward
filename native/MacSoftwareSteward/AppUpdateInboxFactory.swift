import Foundation

enum AppUpdateInboxFactory {
    static func items(from apps: [AppItem]) -> [InboxItem] {
        apps
            .filter { app in
                app.managedBy == "manual"
                    && app.updateState == "outdated"
                    && !app.availableVersion.isEmpty
                    && app.updateCapability.hasManualAction
            }
            .map { app in
                InboxItem(
                    kind: .appUpdate,
                    severity: .info,
                    title: "\(app.name) 可更新",
                    summary: "当前 \(versionText(app.version))，可用 \(app.availableVersion)。\(app.updateCapability.detector.title) 需要手动打开应用或更新器处理。",
                    sourceID: app.id,
                    actions: [
                        InboxAction(title: "查看应用", systemImage: "macwindow", kind: .openApplications),
                        InboxAction(title: "重新扫描", systemImage: "arrow.clockwise", kind: .rescan)
                    ]
                )
            }
    }

    private static func versionText(_ version: String) -> String {
        version.isEmpty ? "未知版本" : version
    }
}
