import Foundation

@main
struct AutomationDataBundleTest {
    static func main() throws {
        var profile = AutomationProfile.manualDefault
        profile.onboardingCompleted = true
        profile.advancedModeEnabled = true
        profile.regularAppNetworkPolicy = .localOnly
        profile.autoRepairPolicy = .allowLowRisk

        let report = InspectionReportRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            trigger: .manualRun,
            startedAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 20),
            status: .succeeded,
            scanSummary: InspectionScanSummary(applications: 1, brewFormulae: 2, brewCasks: 3, masApps: 4, outdated: 5, actionable: 6),
            automaticUpgrades: [
                InspectionPackageRecord(packageID: "brew:formula:jq", packageName: "jq", source: "Brew Formula")
            ],
            skippedItems: [],
            failures: [],
            inboxItemIDs: []
        )
        let history = UpgradeHistoryRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            label: "一键升级",
            status: "完成",
            startedAt: Date(timeIntervalSince1970: 30),
            finishedAt: Date(timeIntervalSince1970: 40),
            commands: ["brew upgrade jq"],
            exitCode: 0,
            summary: "完成"
        )

        let maintenanceRun = MaintenanceRunRecord(
            schemaVersion: 1,
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
            trigger: .smartMaintenance,
            startedAt: Date(timeIntervalSince1970: 50),
            finishedAt: Date(timeIntervalSince1970: 60),
            terminalStatus: .completed,
            scanSummary: InspectionScanSummary(applications: 1, brewFormulae: 2, brewCasks: 3, masApps: 4, outdated: 5, actionable: 6),
            sourceAvailability: MaintenanceRunSourceAvailability(homebrewAvailable: true, masAvailable: false, homebrewError: nil, masError: nil),
            automaticCount: 1,
            confirmationCount: 0,
            reminderCount: 0,
            blockedCount: 0,
            succeededCount: 1,
            failedCount: 0,
            timedOutCount: 0,
            cancelledCount: 0,
            neverStartedCount: 0,
            packages: [
                MaintenanceRunPackageRecord(packageID: "brew:formula:jq", packageName: "jq", disposition: "automatic", outcome: "succeeded", verificationStatus: "verified", failureSummary: nil, commandDisplay: "brew upgrade jq")
            ]
        )

        let bundle = AutomationDataBundleService.makeBundle(
            profile: profile,
            upgradePolicyOverrides: ["brew:formula:jq": .askFirst],
            inspectionReports: [report],
            upgradeHistoryRecords: [history],
            maintenanceRunRecords: [maintenanceRun],
            exportedAt: Date(timeIntervalSince1970: 100)
        )

        let encoded = try AutomationDataBundleService.encode(bundle)
        let decoded = try AutomationDataBundleService.decode(encoded)

        precondition(decoded.schemaVersion == 3)
        precondition(decoded.exportedAt == Date(timeIntervalSince1970: 100))
        precondition(decoded.automationProfile.regularAppNetworkPolicy == .localOnly)
        precondition(decoded.upgradePolicyOverrides["brew:formula:jq"] == .askFirst)
        precondition(decoded.inspectionReports.map(\.id) == [report.id])
        precondition(decoded.upgradeHistoryRecords.map(\.id) == [history.id])
        precondition(decoded.maintenanceRunRecords.map(\.id) == [maintenanceRun.id])

        let summary = AutomationDataBundleService.summary(for: decoded)
        precondition(summary.policyCount == 1)
        precondition(summary.inspectionReportCount == 1)
        precondition(summary.upgradeHistoryCount == 1)
        precondition(summary.maintenanceRunCount == 1)

        // v2 向后兼容：v2 文件没有 maintenanceRunRecords，导入时应回退空数组。
        var legacyObject = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacyObject["schemaVersion"] = 2
        legacyObject.removeValue(forKey: "maintenanceRunRecords")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject, options: [])
        let legacy = try AutomationDataBundleService.decode(legacyData)
        precondition(legacy.schemaVersion == 2)
        precondition(legacy.maintenanceRunRecords.isEmpty)

        let incompatible = AutomationDataBundle(
            schemaVersion: 99,
            exportedAt: Date(timeIntervalSince1970: 100),
            automationProfile: profile,
            upgradePolicyOverrides: [:],
            inspectionReports: [],
            upgradeHistoryRecords: []
        )
        let incompatibleData = try AutomationDataBundleService.encode(incompatible)
        do {
            _ = try AutomationDataBundleService.decode(incompatibleData)
            preconditionFailure("Unsupported schema version should fail")
        } catch let error as AutomationDataBundleError {
            precondition(error == .unsupportedSchemaVersion(99))
        }
    }
}
