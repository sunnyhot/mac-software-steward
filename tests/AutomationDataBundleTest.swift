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

        let bundle = AutomationDataBundleService.makeBundle(
            profile: profile,
            upgradePolicyOverrides: ["brew:formula:jq": .askFirst],
            inspectionReports: [report],
            exportedAt: Date(timeIntervalSince1970: 100)
        )

        let encoded = try AutomationDataBundleService.encode(bundle)
        let decoded = try AutomationDataBundleService.decode(encoded)

        precondition(decoded.schemaVersion == 1)
        precondition(decoded.exportedAt == Date(timeIntervalSince1970: 100))
        precondition(decoded.automationProfile.regularAppNetworkPolicy == .localOnly)
        precondition(decoded.upgradePolicyOverrides["brew:formula:jq"] == .askFirst)
        precondition(decoded.inspectionReports.map(\.id) == [report.id])

        let incompatible = AutomationDataBundle(
            schemaVersion: 99,
            exportedAt: Date(timeIntervalSince1970: 100),
            automationProfile: profile,
            upgradePolicyOverrides: [:],
            inspectionReports: []
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
