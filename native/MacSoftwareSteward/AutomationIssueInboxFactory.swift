import Foundation

enum AutomationIssueInboxFactory {
    static let dailyInspectionSourceID = "automation:daily-inspection"

    static func pendingDailyInspectionItem(
        profile: AutomationProfile,
        dailyInspectionEnabled: Bool
    ) -> InboxItem? {
        guard profile.onboardingCompleted,
              profile.automationEnabled,
              profile.dailyInspectionEnabled,
              !dailyInspectionEnabled else {
            return nil
        }

        return dailyInspectionItem(
            title: "每日巡检需要重新启用",
            summary: "自动化配置要求每日巡检，但当前未检测到 LaunchAgent。请打开自动化策略重新启用每日巡检。",
            status: .pending
        )
    }

    static func resolvedDailyInspectionItem() -> InboxItem {
        dailyInspectionItem(
            title: "每日巡检状态已恢复",
            summary: "每日巡检 LaunchAgent 已恢复或当前配置不再要求启用。",
            status: .resolved
        )
    }

    private static func dailyInspectionItem(
        title: String,
        summary: String,
        status: InboxStatus
    ) -> InboxItem {
        InboxItem(
            kind: .automationIssue,
            severity: .warning,
            title: title,
            summary: summary,
            sourceID: dailyInspectionSourceID,
            status: status,
            actions: [
                InboxAction(title: "打开自动化策略", systemImage: "switch.2", kind: .openRules)
            ]
        )
    }
}

enum AutomationIssueInboxPublisher {
    @discardableResult
    static func publishDailyInspectionIssue(
        profile: AutomationProfile,
        dailyInspectionEnabled: Bool,
        to inboxStore: InboxStore
    ) -> Bool {
        if let item = AutomationIssueInboxFactory.pendingDailyInspectionItem(
            profile: profile,
            dailyInspectionEnabled: dailyInspectionEnabled
        ) {
            return inboxStore.add(item)
        }

        let hasPendingIssue = inboxStore.items.contains { item in
            item.kind == .automationIssue
                && item.sourceID == AutomationIssueInboxFactory.dailyInspectionSourceID
                && item.status == .pending
        }
        guard hasPendingIssue else { return false }
        inboxStore.add(AutomationIssueInboxFactory.resolvedDailyInspectionItem())
        return false
    }
}
