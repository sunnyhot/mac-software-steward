import Foundation

/// 无论本次是否允许或成功自动清理，都为仍存在的残留记录保留可处理入口。
enum StaleCaskInboxFactory {
    static func items(from scan: ScanResult) -> [InboxItem] {
        scan.brew.casks
            .filter { $0.hasStaleInstallRecord }
            .map { cask in
                InboxItem(
                    kind: .failureRecovery,
                    severity: .warning,
                    title: "\(cask.name) 残留记录待清理",
                    summary: "App 文件已不存在，Homebrew 仍保留安装记录。可在升级页确认后清理；不会使用 --zap 删除个人配置。",
                    sourceID: cask.id,
                    actions: [
                        InboxAction(title: "前往清理", systemImage: "trash", kind: .openUpdates)
                    ]
                )
            }
    }
}
