import Foundation

enum DailyInspectionInboxPublisher {
    static func publish(scan: ScanResult, rows: [UpgradePlanRow], to inboxStore: InboxStore) -> [UUID] {
        if SmartMaintenancePolicy.canReconcileStaleRecords(scan: scan) {
            let presentStaleIDs = Set(scan.brew.casks.filter { $0.hasStaleInstallRecord }.map(\.id))
            inboxStore.retireStaleCaskRecoveryItems(notPresentIn: presentStaleIDs)
        }
        let items = SourceIssueInboxFactory.items(from: scan)
            + StaleCaskInboxFactory.items(from: scan)
            + RiskInboxFactory.items(from: rows)
            + AppUpdateInboxFactory.items(from: scan.applications.items)

        return items.map { item in
            inboxStore.add(item)
            return item.id
        }
    }
}
