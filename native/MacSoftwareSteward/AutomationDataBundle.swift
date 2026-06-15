import Foundation

struct AutomationDataBundle: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var exportedAt: Date
    var automationProfile: AutomationProfile
    var upgradePolicyOverrides: [String: UpgradePolicy]
    var inspectionReports: [InspectionReportRecord]
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

enum AutomationDataBundleService {
    static func makeBundle(
        profile: AutomationProfile,
        upgradePolicyOverrides: [String: UpgradePolicy],
        inspectionReports: [InspectionReportRecord],
        exportedAt: Date = Date()
    ) -> AutomationDataBundle {
        AutomationDataBundle(
            schemaVersion: AutomationDataBundle.currentSchemaVersion,
            exportedAt: exportedAt,
            automationProfile: profile,
            upgradePolicyOverrides: upgradePolicyOverrides,
            inspectionReports: inspectionReports
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
        guard bundle.schemaVersion == AutomationDataBundle.currentSchemaVersion else {
            throw AutomationDataBundleError.unsupportedSchemaVersion(bundle.schemaVersion)
        }
        return bundle
    }
}
