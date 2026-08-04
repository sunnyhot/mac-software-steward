import Foundation

@main
struct AutomationNotificationDeciderTest {
    static func main() {
        let failures = [
            InspectionFailureRecord(message: "failed", commandDisplay: "brew upgrade jq", exitCode: 1),
            InspectionFailureRecord(message: "failed", commandDisplay: "mas upgrade 1", exitCode: 2)
        ]
        precondition(AutomationNotificationDecider.failureDecision(policy: .silent, failures: failures) == nil)
        let failureDecision = AutomationNotificationDecider.failureDecision(
            policy: .decisionsAndFailures,
            failures: failures
        )
        precondition(failureDecision?.title == "每日巡检有失败项目")
        precondition(failureDecision?.body.contains("2") == true)

        let warning = InboxItem(
            kind: .upgradeDecision,
            severity: .warning,
            title: "Node 需要确认",
            summary: "major version",
            sourceID: "upgrade:node",
            actions: []
        )
        let appUpdate = InboxItem(
            kind: .appUpdate,
            severity: .info,
            title: "Sparkle 可更新",
            summary: "需要手动打开更新器。",
            sourceID: "app:/Applications/Sparkle.app",
            actions: [
                InboxAction(title: "查看应用", systemImage: "macwindow", kind: .openApplications)
            ]
        )

        let appUpdateDecision = AutomationNotificationDecider.decision(
            policy: .decisionsAndFailures,
            newInboxItems: [appUpdate],
            automaticUpgradeCount: 0
        )
        precondition(appUpdateDecision?.title == "有 1 项需要处理")

        precondition(AutomationNotificationDecider.decision(policy: .silent, newInboxItems: [warning], automaticUpgradeCount: 2) == nil)

        let decisions = AutomationNotificationDecider.decision(policy: .decisionsAndFailures, newInboxItems: [warning], automaticUpgradeCount: 2)
        precondition(decisions?.title == "有 1 项需要处理")
        precondition(decisions?.isUrgent == true)

        let quietSuccess = AutomationNotificationDecider.decision(policy: .decisionsAndFailures, newInboxItems: [], automaticUpgradeCount: 2)
        precondition(quietSuccess == nil)

        let upgrades = AutomationNotificationDecider.decision(
            policy: .decisionsAndFailures,
            newInboxItems: [],
            automaticUpgradeCount: 0,
            availableUpgradeCount: 3
        )
        precondition(upgrades?.title == "发现 3 个可升级项目")
        precondition(upgrades?.body.contains("一键升级") == true)
        precondition(upgrades?.isUrgent == true)

        let combined = AutomationNotificationDecider.decision(
            policy: .decisionsAndFailures,
            newInboxItems: [warning],
            automaticUpgradeCount: 0,
            availableUpgradeCount: 2
        )
        precondition(combined?.title == "有 3 项需要处理")
        precondition(combined?.body.contains("2 个可升级项目") == true)

        let everyInspection = AutomationNotificationDecider.decision(policy: .everyInspection, newInboxItems: [], automaticUpgradeCount: 2)
        precondition(everyInspection?.title == "巡检完成")
        precondition(everyInspection?.isUrgent == false)

        let everyAction = AutomationNotificationDecider.decision(policy: .everyAction, newInboxItems: [], automaticUpgradeCount: 1)
        precondition(everyAction?.body.contains("自动处理 1 项") == true)
    }
}
