import Foundation

struct AutomationNotificationDecision: Equatable {
    var title: String
    var body: String
    var isUrgent: Bool
}

enum AutomationNotificationDecider {
    static func decision(
        policy: NotificationPolicy,
        newInboxItems: [InboxItem],
        automaticUpgradeCount: Int
    ) -> AutomationNotificationDecision? {
        let actionableItems = newInboxItems.filter { item in
            item.status == .pending && (item.severity != .info || !item.actions.isEmpty)
        }

        switch policy {
        case .silent:
            return nil

        case .decisionsAndFailures:
            guard !actionableItems.isEmpty else { return nil }
            return pendingDecision(count: actionableItems.count)

        case .everyInspection:
            if !actionableItems.isEmpty {
                return pendingDecision(count: actionableItems.count)
            }
            return AutomationNotificationDecision(
                title: "巡检完成",
                body: automaticUpgradeCount > 0 ? "已自动处理 \(automaticUpgradeCount) 项。" : "没有需要处理的事项。",
                isUrgent: false
            )

        case .everyAction:
            if !actionableItems.isEmpty {
                return pendingDecision(count: actionableItems.count)
            }
            guard automaticUpgradeCount > 0 else { return nil }
            return AutomationNotificationDecision(
                title: "自动维护完成",
                body: "已自动处理 \(automaticUpgradeCount) 项。",
                isUrgent: false
            )
        }
    }

    private static func pendingDecision(count: Int) -> AutomationNotificationDecision {
        AutomationNotificationDecision(
            title: "有 \(count) 项需要处理",
            body: "需要确认的升级或失败恢复已显示在维护总览。",
            isUrgent: true
        )
    }
}
