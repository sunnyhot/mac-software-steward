import Foundation

enum RegularAppUpdateActionResolver {
    static func updaterPathCandidates(for detector: AppUpdateDetectorKind) -> [String] {
        switch detector {
        case .adobeUpdater:
            return [
                "/Applications/Utilities/Adobe Creative Cloud/ACC/Creative Cloud.app",
                "/Applications/Adobe Creative Cloud/Adobe Creative Cloud.app"
            ]
        case .jetBrainsToolbox:
            return [
                "/Applications/JetBrains Toolbox.app"
            ]
        case .microsoftAutoUpdate:
            return [
                "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app",
                "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app"
            ]
        case .none, .sparkle, .chromeKeystone, .unknownUpdater:
            return []
        }
    }

    static func firstExistingUpdaterPath(for detector: AppUpdateDetectorKind) -> String? {
        updaterPathCandidates(for: detector)
            .first { FileManager.default.fileExists(atPath: $0) }
    }
}
