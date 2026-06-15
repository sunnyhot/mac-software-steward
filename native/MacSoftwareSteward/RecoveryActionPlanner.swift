import Foundation

enum RecoveryActionPlanner {
    static func actions(for progress: PackageUpgradeProgress) -> [RecoveryAction] {
        guard progress.status == .failed || progress.status == .timedOut else { return [] }
        guard let recoveryAction = progress.recoveryAction else {
            return supportingActions()
        }
        return deduplicated([primaryAction(for: recoveryAction)] + supportingActions())
    }

    private static func primaryAction(for action: FailureActionType) -> RecoveryAction {
        switch action {
        case .retry:
            return RecoveryAction(kind: .retryPackage, title: "重试", systemImage: "arrow.clockwise")
        case .quitAndRetry:
            return RecoveryAction(kind: .retryPackage, title: "关闭后重试", systemImage: "xmark.circle")
        case .reimport:
            return RecoveryAction(kind: .retryPackage, title: "覆盖重装", systemImage: "square.and.arrow.down.on.square")
        case .cleanup:
            return RecoveryAction(kind: .retryPackage, title: "清理并重试", systemImage: "trash.circle")
        case .repairPerms:
            return RecoveryAction(kind: .retryPackage, title: "重试", systemImage: "lock.shield")
        case .rescan:
            return RecoveryAction(kind: .rescan, title: "重新扫描", systemImage: "arrow.clockwise")
        case .checkNetwork:
            return RecoveryAction(kind: .retryPackage, title: "重试", systemImage: "wifi")
        case .freeDisk:
            return RecoveryAction(kind: .openStorageSettings, title: "清理空间", systemImage: "internaldrive")
        case .retryInTerminal:
            return RecoveryAction(kind: .copyTerminalCommand, title: "复制终端命令", systemImage: "terminal")
        case .openLog:
            return RecoveryAction(kind: .openJobs, title: "查看日志", systemImage: "terminal")
        }
    }

    private static func supportingActions() -> [RecoveryAction] {
        [
            RecoveryAction(kind: .openUpdates, title: "查看升级", systemImage: "arrow.triangle.2.circlepath"),
            RecoveryAction(kind: .openJobs, title: "查看日志", systemImage: "terminal")
        ]
    }

    private static func deduplicated(_ actions: [RecoveryAction]) -> [RecoveryAction] {
        var seen: Set<RecoveryActionKind> = []
        return actions.filter { action in
            seen.insert(action.kind).inserted
        }
    }
}
