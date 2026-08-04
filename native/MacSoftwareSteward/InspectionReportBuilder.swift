import Foundation

enum InspectionReportBuilder {
    static func makeReport(
        trigger: InspectionReportTrigger,
        startedAt: Date,
        finishedAt: Date,
        scan: ScanResult,
        rows: [UpgradePlanRow],
        automaticPackages: [UpdatablePackage],
        inboxItemIDs: [UUID] = [],
        failures: [InspectionFailureRecord] = []
    ) -> InspectionReportRecord {
        let automaticIDs = Set(automaticPackages.map(\.id))
        let skippedItems = rows
            .filter { row in
                !automaticIDs.contains(row.packageID)
                    && (!row.canExecute || row.selection != .selected || !row.skipReason.isEmpty)
            }
            .map { row in
                InspectionSkippedRecord(
                    packageID: row.packageID,
                    packageName: row.packageName,
                    reason: skipReason(for: row)
                )
            }

        return InspectionReportRecord(
            id: UUID(),
            trigger: trigger,
            startedAt: startedAt,
            finishedAt: finishedAt,
            status: failures.isEmpty ? .succeeded : .failed,
            scanSummary: InspectionScanSummary(
                applications: scan.summary.applications,
                brewFormulae: scan.summary.brewFormulae,
                brewCasks: scan.summary.brewCasks,
                masApps: scan.summary.masApps,
                outdated: scan.summary.outdated,
                actionable: scan.summary.actionable
            ),
            automaticUpgrades: automaticPackages.map(packageRecord),
            skippedItems: skippedItems,
            failures: failures,
            inboxItemIDs: inboxItemIDs
        )
    }

    private static func packageRecord(for package: UpdatablePackage) -> InspectionPackageRecord {
        InspectionPackageRecord(
            packageID: package.id,
            packageName: package.name,
            source: package.source
        )
    }

    private static func skipReason(for row: UpgradePlanRow) -> String {
        if !row.skipReason.isEmpty {
            return row.skipReason
        }
        if !row.riskSummary.isEmpty {
            return row.riskSummary
        }
        return row.policy.title
    }
}
