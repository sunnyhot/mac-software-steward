import Foundation

enum RecoveryInboxFactory {
    static func items(from progresses: [PackageUpgradeProgress]) -> [InboxItem] {
        progresses
            .filter { $0.status == .failed || $0.status == .timedOut }
            .filter { !$0.failureSummary.isEmpty || $0.recoveryAction != nil }
            .map { progress in
                InboxItem(
                    kind: kind(for: progress),
                    severity: severity(for: progress),
                    title: "\(progress.packageName) 升级失败",
                    summary: summary(for: progress),
                    sourceID: progress.packageID,
                    actions: RecoveryActionPlanner.actions(for: progress).map(inboxAction)
                )
            }
    }

    private static func inboxAction(from action: RecoveryAction) -> InboxAction {
        InboxAction(title: action.title, systemImage: action.systemImage, kind: inboxActionKind(for: action.kind))
    }

    private static func inboxActionKind(for kind: RecoveryActionKind) -> InboxActionKind {
        switch kind {
        case .retryPackage:
            return .retryPackage
        case .openUpdates:
            return .openUpdates
        case .openJobs:
            return .openJobs
        case .rescan:
            return .rescan
        case .openStorageSettings:
            return .openStorageSettings
        case .copyTerminalCommand:
            return .copyRecoveryCommand
        }
    }

    private static func severity(for progress: PackageUpgradeProgress) -> InboxSeverity {
        progress.status == .timedOut ? .warning : .critical
    }

    private static func kind(for progress: PackageUpgradeProgress) -> InboxItemKind {
        switch progress.recoveryAction {
        case .repairPerms:
            return .permissionIssue
        default:
            return .failureRecovery
        }
    }

    private static func summary(for progress: PackageUpgradeProgress) -> String {
        let suggestion = progress.recoverySuggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suggestion.isEmpty else { return progress.failureSummary }
        return "\(progress.failureSummary) \(suggestion)"
    }
}
