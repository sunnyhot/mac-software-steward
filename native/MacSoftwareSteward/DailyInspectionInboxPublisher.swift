import Foundation

enum DailyInspectionInboxPublisher {
    static func publish(scan: ScanResult, rows: [UpgradePlanRow], to inboxStore: InboxStore) -> [UUID] {
        let items = SourceIssueInboxFactory.items(from: scan)
            + RiskInboxFactory.items(from: rows)
            + AppUpdateInboxFactory.items(from: scan.applications.items)

        return items.map { item in
            inboxStore.add(item)
            return item.id
        }
    }
}
