import Foundation

// MARK: - Risk Level
enum RiskLevel: String, Codable, Sendable {
    case low
    case medium
    case high
}

// MARK: - Clean Item Type
enum CleanItemType: String, Codable, Sendable {
    case file
    case directory
}

// MARK: - Clean Item Category
enum CleanItemCategory: String, Codable, CaseIterable, Sendable {
    case developmentTools
    case systemCache
    case applicationCache
    case logs
    case temporaryFiles
    case browserData
    case mailData
    case other
}

// MARK: - Clean Item
struct CleanItem: Identifiable, Sendable {
    let id = UUID()
    let path: String
    let size: Int64
    let type: CleanItemType
    let category: CleanItemCategory
    let riskLevel: RiskLevel
    let lastAccessed: Date?
    let isProtected: Bool
    let isWhitelisted: Bool

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

// MARK: - Clean Result
struct CleanResult: Identifiable, Sendable {
    let id = UUID()
    let item: CleanItem
    let success: Bool
    let bytesFreed: Int64
    let error: String?

    var formattedBytesFreed: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytesFreed)
    }
}

// MARK: - Clean Engine Configuration
struct CleanEngineConfiguration: Sendable {
    let dryRun: Bool
    let requireConfirmation: Bool
    let maxRiskLevel: RiskLevel
    let excludePaths: [String]
    let includeHiddenFiles: Bool

    static let `default` = CleanEngineConfiguration(
        dryRun: false,
        requireConfirmation: true,
        maxRiskLevel: .medium,
        excludePaths: [],
        includeHiddenFiles: false
    )
}
