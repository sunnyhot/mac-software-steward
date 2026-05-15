import Foundation

// MARK: - App Info
struct AppInfo: Codable, Identifiable, Hashable {
    let id: String              // bundle identifier
    let name: String            // display name
    let path: URL               // .app bundle path
    let version: String
    let size: Int64             // bytes
    let lastUsed: Date?
    let isBrewCask: Bool
    let brewCaskName: String?
    let isSystemApp: Bool
    let isBackgroundOnly: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(path)
    }

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.id == rhs.id && lhs.path == rhs.path
    }
}

// MARK: - Residual File
struct ResidualFile: Codable, Identifiable, Hashable {
    let id: UUID
    let path: URL
    let size: Int64
    let category: ResidualCategory
    let riskLevel: RiskLevel
    let description: String

    init(id: UUID = UUID(), path: URL, size: Int64, category: ResidualCategory, riskLevel: RiskLevel, description: String) {
        self.id = id
        self.path = path
        self.size = size
        self.category = category
        self.riskLevel = riskLevel
        self.description = description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.path = try container.decode(URL.self, forKey: .path)
        self.size = try container.decode(Int64.self, forKey: .size)
        self.category = try container.decode(ResidualCategory.self, forKey: .category)
        self.riskLevel = try container.decode(RiskLevel.self, forKey: .riskLevel)
        self.description = try container.decode(String.self, forKey: .description)
    }

    enum ResidualCategory: String, Codable {
        case support
        case cache
        case log
        case preference
        case launchAgent
        case launchDaemon
        case container
        case webkit
        case savedAppState
        case httpStorage
        case cookies
        case byHost
        case trash
        case other
    }

    enum RiskLevel: String, Codable {
        case safe
        case moderate
        case caution
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(path)
    }

    static func == (lhs: ResidualFile, rhs: ResidualFile) -> Bool {
        lhs.id == rhs.id && lhs.path == rhs.path
    }
}

// MARK: - Uninstall Result
struct UninstallResult: Codable {
    let app: AppInfo
    let removedFiles: [ResidualFile]
    let freedSpace: Int64
    let success: Bool
    let errors: [String]
}

// MARK: - Metadata Cache
struct AppMetadataCache: Codable {
    let apps: [CachedAppMetadata]
    let timestamp: Date
    let version: Int

    static let currentVersion = 1
    let cacheValidityDuration: TimeInterval = 7 * 24 * 60 * 60 // 7 days

    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > cacheValidityDuration
    }
}

struct CachedAppMetadata: Codable {
    let bundleId: String
    let path: String
    let size: Int64
    let lastUsed: Date?
    let scanTime: Date
}

// MARK: - Uninstall Error
enum UninstallError: Error, LocalizedError {
    case appNotFound(String)
    case systemAppCannotBeUninstalled(String)
    case brewCaskUninstallFailed(String)
    case launchAgentUnloadFailed(String)
    case bundleRemovalFailed(String)
    case residualFileRemovalFailed(String)
    case metadataRefreshFailed(String)
    case permissionDenied(String)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .appNotFound(let name):
            return "Application not found: \(name)"
        case .systemAppCannotBeUninstalled(let name):
            return "System applications cannot be uninstalled: \(name)"
        case .brewCaskUninstallFailed(let name):
            return "Homebrew cask uninstall failed for: \(name)"
        case .launchAgentUnloadFailed(let name):
            return "Failed to unload launch agent for: \(name)"
        case .bundleRemovalFailed(let path):
            return "Failed to remove application bundle at: \(path)"
        case .residualFileRemovalFailed(let path):
            return "Failed to remove residual file at: \(path)"
        case .metadataRefreshFailed(let message):
            return "Metadata refresh failed: \(message)"
        case .permissionDenied(let resource):
            return "Permission denied for: \(resource)"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}