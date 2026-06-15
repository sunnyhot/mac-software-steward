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

        let bundle = AutomationDataBundleService.makeBundle(
            profile: profile,
            upgradePolicyOverrides: ["brew:formula:jq": .askFirst],
            inspectionReports: [report],
            upgradeHistoryRecords: [history],
            exportedAt: Date(timeIntervalSince1970: 100)
        )

        let encoded = try AutomationDataBundleService.encode(bundle)
        let decoded = try AutomationDataBundleService.decode(encoded)

        precondition(decoded.schemaVersion == 2)
        precondition(decoded.exportedAt == Date(timeIntervalSince1970: 100))
        precondition(decoded.automationProfile.regularAppNetworkPolicy == .localOnly)
        precondition(decoded.upgradePolicyOverrides["brew:formula:jq"] == .askFirst)
        precondition(decoded.inspectionReports.map(\.id) == [report.id])
        precondition(decoded.upgradeHistoryRecords.map(\.id) == [history.id])

        let summary = AutomationDataBundleService.summary(for: decoded)
        precondition(summary.policyCount == 1)
        precondition(summary.inspectionReportCount == 1)
        precondition(summary.upgradeHistoryCount == 1)

        var legacyObject = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacyObject["schemaVersion"] = 1
        legacyObject.removeValue(forKey: "upgradeHistoryRecords")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject, options: [])
        let legacy = try AutomationDataBundleService.decode(legacyData)
        precondition(legacy.schemaVersion == 1)
        precondition(legacy.upgradeHistoryRecords.isEmpty)

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
