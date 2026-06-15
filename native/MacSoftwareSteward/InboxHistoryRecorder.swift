import Foundation

enum InboxHistoryRecorder {
    static func record(
        for item: InboxItem,
        status: InboxStatus,
        handledAt: Date = Date()
    ) -> UpgradeHistoryRecord {
        UpgradeHistoryRecord(
            id: UUID(),
            label: "处理待办：\(item.title)",
            status: statusTitle(for: status),
            startedAt: handledAt,
            finishedAt: handledAt,
            commands: [],
            exitCode: nil,
            summary: "收件箱事项已\(actionText(for: status))：\(item.summary)"
        )
    }

    private static func statusTitle(for status: InboxStatus) -> String {
        switch status {
        case .resolved:
            return "完成"
        case .ignored:
            return "已忽略"
        case .pending:
            return "待处理"
        }
    }

    private static func actionText(for status: InboxStatus) -> String {
        switch status {
        case .resolved:
            return "完成"
        case .ignored:
            return "忽略"
        case .pending:
            return "保留"
        }
    }
}
