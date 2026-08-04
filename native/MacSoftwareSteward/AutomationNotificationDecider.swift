import Foundation

struct AutomationNotificationDecision: Equatable {
    var title: String
    var body: String
    var isUrgent: Bool
}

enum AutomationNotificationDecider {
    static func failureDecision(
        policy: NotificationPolicy,
        failures: [InspectionFailureRecord]
    ) -> AutomationNotificationDecision? {
        guard policy != .silent, !failures.isEmpty else { return nil }

        let firstCommand = failures[0].commandDisplay
        let body: String
        if failures.count == 1 {
            body = "\(firstCommand) 执行失败，其他项目已继续处理。"
        } else {
            body = "共有 \(failures.count) 项执行失败，其他项目已继续处理。"
        }
        return AutomationNotificationDecision(
            title: "每日巡检有失败项目",
            body: body,
            isUrgent: true
        )
    }

    static func decision(
        policy: NotificationPolicy,
        newInboxItems: [InboxItem],
        automaticUpgradeCount: Int,
        availableUpgradeCount: Int = 0
    ) -> AutomationNotificationDecision? {
        let actionableItems = newInboxItems.filter { item in
            item.status == .pending && (item.severity != .info || !item.actions.isEmpty)
        }

        switch policy {
        case .silent:
            return nil

        case .decisionsAndFailures:
            guard !actionableItems.isEmpty || availableUpgradeCount > 0 else { return nil }
            return pendingDecision(
                actionableCount: actionableItems.count,
                availableUpgradeCount: availableUpgradeCount
            )

        case .everyInspection:
            if !actionableItems.isEmpty || availableUpgradeCount > 0 {
                return pendingDecision(
                    actionableCount: actionableItems.count,
                    availableUpgradeCount: availableUpgradeCount
                )
            }
            return AutomationNotificationDecision(
                title: "巡检完成",
                body: automaticUpgradeCount > 0 ? "已自动处理 \(automaticUpgradeCount) 项。" : "没有需要处理的事项。",
                isUrgent: false
            )

        case .everyAction:
            if !actionableItems.isEmpty || availableUpgradeCount > 0 {
                return pendingDecision(
                    actionableCount: actionableItems.count,
                    availableUpgradeCount: availableUpgradeCount
                )
            }
            guard automaticUpgradeCount > 0 else { return nil }
            return AutomationNotificationDecision(
                title: "自动维护完成",
                body: "已自动处理 \(automaticUpgradeCount) 项。",
                isUrgent: false
            )
        }
    }

    private static func pendingDecision(
        actionableCount: Int,
        availableUpgradeCount: Int
    ) -> AutomationNotificationDecision {
        if actionableCount == 0 {
            return AutomationNotificationDecision(
                title: "发现 \(availableUpgradeCount) 个可升级项目",
                body: "打开“可升级”页面可查看并一键升级。",
                isUrgent: true
            )
        }

        if availableUpgradeCount > 0 {
            return AutomationNotificationDecision(
                title: "有 \(actionableCount + availableUpgradeCount) 项需要处理",
                body: "包含 \(availableUpgradeCount) 个可升级项目和 \(actionableCount) 个其他事项。",
                isUrgent: true
            )
        }

        return AutomationNotificationDecision(
            title: "有 \(actionableCount) 项需要处理",
            body: "打开 Mac 软件管家可查看详情并处理。",
            isUrgent: true
        )
    }
}
