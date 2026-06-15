import Foundation

@main
struct AutomationIssueInboxFactoryTest {
    static func main() {
        var profile = AutomationProfile.manualDefault
        profile.onboardingCompleted = true
        profile.automationEnabled = true
        profile.dailyInspectionEnabled = true

        let healthyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("automation-issue-healthy-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: healthyURL) }
        let healthyStore = InboxStore(fileURL: healthyURL)
        let healthyPublished = AutomationIssueInboxPublisher.publishDailyInspectionIssue(
            profile: profile,
            dailyInspectionEnabled: true,
            to: healthyStore
        )
        precondition(healthyPublished == false)
        precondition(healthyStore.items.isEmpty)

        let issueURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("automation-issue-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: issueURL) }
        let issueStore = InboxStore(fileURL: issueURL)
        let firstPublished = AutomationIssueInboxPublisher.publishDailyInspectionIssue(
            profile: profile,
            dailyInspectionEnabled: false,
            to: issueStore
        )
        precondition(firstPublished == true)
        precondition(issueStore.pendingItems.count == 1)
        precondition(issueStore.pendingItems[0].kind == .automationIssue)
        precondition(issueStore.pendingItems[0].sourceID == AutomationIssueInboxFactory.dailyInspectionSourceID)
        precondition(issueStore.pendingItems[0].actions.map(\.kind) == [.openSettings])

        let secondPublished = AutomationIssueInboxPublisher.publishDailyInspectionIssue(
            profile: profile,
            dailyInspectionEnabled: false,
            to: issueStore
        )
        precondition(secondPublished == false)
        precondition(issueStore.items.count == 1)

        let resolvedPublished = AutomationIssueInboxPublisher.publishDailyInspectionIssue(
            profile: profile,
            dailyInspectionEnabled: true,
            to: issueStore
        )
        precondition(resolvedPublished == false)
        precondition(issueStore.pendingItems.isEmpty)
        precondition(issueStore.items[0].status == .resolved)
    }
}
