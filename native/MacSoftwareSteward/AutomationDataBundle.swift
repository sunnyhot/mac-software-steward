import Foundation

struct AutomationDataBundle: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var exportedAt: Date
    var automationProfile: AutomationProfile
    var upgradePolicyOverrides: [String: UpgradePolicy]
    var inspectionReports: [InspectionReportRecord]
    var upgradeHistoryRecords: [UpgradeHistoryRecord]

    init(
        schemaVersion: Int,
        exportedAt: Date,
        automationProfile: AutomationProfile,
        upgradePolicyOverrides: [String: UpgradePolicy],
        inspectionReports: [InspectionReportRecord],
        upgradeHistoryRecords: [UpgradeHistoryRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.automationProfile = automationProfile
        self.upgradePolicyOverrides = upgradePolicyOverrides
        self.inspectionReports = inspectionReports
        self.upgradeHistoryRecords = upgradeHistoryRecords
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        automationProfile = try container.decode(AutomationProfile.self, forKey: .automationProfile)
        upgradePolicyOverrides = try container.decode([String: UpgradePolicy].self, forKey: .upgradePolicyOverrides)
        inspectionReports = try container.decode([InspectionReportRecord].self, forKey: .inspectionReports)
        upgradeHistoryRecords = try container.decodeIfPresent([UpgradeHistoryRecord].self, forKey: .upgradeHistoryRecords) ?? []
    }
}

enum AutomationDataBundleError: Error, Equatable, LocalizedError {
    case unsupportedSchemaVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "不支持的导入文件版本：\(version)"
        }
    }
}

struct AutomationDataBundleSummary: Equatable {
    var schemaVersion: Int
    var policyCount: Int
    var inspectionReportCount: Int
    var upgradeHistoryCount: Int
}

enum AutomationDataBundleService {
    static func makeBundle(
        profile: AutomationProfile,
        upgradePolicyOverrides: [String: UpgradePolicy],
        inspectionReports: [InspectionReportRecord],
        upgradeHistoryRecords: [UpgradeHistoryRecord] = [],
        exportedAt: Date = Date()
    ) -> AutomationDataBundle {
        AutomationDataBundle(
            schemaVersion: AutomationDataBundle.currentSchemaVersion,
            exportedAt: exportedAt,
            automationProfile: profile,
            upgradePolicyOverrides: upgradePolicyOverrides,
            inspectionReports: inspectionReports,
            upgradeHistoryRecords: upgradeHistoryRecords
        )
    }

    static func encode(_ bundle: AutomationDataBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(bundle)
    }

    static func decode(_ data: Data) throws -> AutomationDataBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(AutomationDataBundle.self, from: data)
        guard bundle.schemaVersion >= 1,
              bundle.schemaVersion <= AutomationDataBundle.currentSchemaVersion else {
            throw AutomationDataBundleError.unsupportedSchemaVersion(bundle.schemaVersion)
        }
        return bundle
    }

    static func summary(for bundle: AutomationDataBundle) -> AutomationDataBundleSummary {
        AutomationDataBundleSummary(
            schemaVersion: bundle.schemaVersion,
            policyCount: bundle.upgradePolicyOverrides.count,
            inspectionReportCount: bundle.inspectionReports.count,
            upgradeHistoryCount: bundle.upgradeHistoryRecords.count
        )
    }
}
