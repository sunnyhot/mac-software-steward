import Foundation

actor PathValidator {
    private let fileManager = FileManager.default

    private static let forbiddenPrefixes = [
        "/", "/System", "/usr", "/bin", "/sbin", "/etc",
        "/private/var", "/Library/System", "/dev"
    ]

    func isValidCleanTarget(_ path: String) -> Bool {
        let expandedPath = expandPath(path)

        guard !expandedPath.isEmpty else { return false }
        guard fileManager.fileExists(atPath: expandedPath) else { return false }

        for prefix in Self.forbiddenPrefixes {
            if expandedPath == prefix { return false }
        }

        return true
    }

    func isWithinUserHome(_ path: String) -> Bool {
        let expandedPath = expandPath(path)
        let homeDir = fileManager.homeDirectoryForCurrentUser.path
        return expandedPath.hasPrefix(homeDir)
    }

    func expandPath(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }
}
