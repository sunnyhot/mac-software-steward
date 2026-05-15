import Foundation

// MARK: - Safe File Removal Utility
actor SafeRemover {

    // MARK: - Protected Paths
    private static let protectedPaths = [
        "/", "/System", "/System/*", "/bin", "/bin/*", "/sbin", "/sbin/*",
        "/usr", "/usr/bin", "/usr/bin/*", "/usr/lib", "/usr/lib/*",
        "/etc", "/etc/*", "/private/etc", "/private/etc/*",
        "/Library/Extensions", "/Library/Extensions/*",
        "/Applications/System Preferences.app",
        "/Applications/Utilities/System Information.app"
    ]

    // MARK: - Sensitive Data Patterns
    private static let sensitivePatterns = [
        // Only exact path matches, not substring matches
        ".ssh", ".gnupg", ".gpg", ".password-store",
        "keychain", ".password", ".token", ".auth",
        "Passwords", "Accounts", "credentials", "secrets",
        ".aws", ".kube/config"
    ]

    // MARK: - System Critical Bundle IDs
    private static let systemCriticalBundles = [
        // Core system applications
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.Safari",
        "com.apple.mail",
        "com.apple.systempreferences",
        "com.apple.SystemSettings",
        "com.apple.Settings",
        "com.apple.controlcenter",
        "com.apple.Spotlight",
        "com.apple.notificationcenterui",
        "com.apple.loginwindow",
        "com.apple.Preview",
        "com.apple.TextEdit",
        "com.apple.Notes",
        "com.apple.reminders",
        "com.apple.iCal",
        "com.apple.AddressBook",
        "com.apple.Photos",
        "com.apple.AppStore",
        "com.apple.calculator",
        "com.apple.Dictionary",
        "com.apple.ScreenSharing",
        "com.apple.ActivityMonitor",
        "com.apple.Console",
        "com.apple.DiskUtility",
        "com.apple.KeychainAccess",
        "com.apple.DigitalColorMeter",
        "com.apple.grapher",
        "com.apple.Terminal"
    ]

    // MARK: - Public Methods

    /// Safely remove a file or directory
    func remove(at url: URL) async throws {
        try validatePathForRemoval(url)

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Safely remove multiple files
    func removeMultiple(at urls: [URL]) async throws -> [URL: Error] {
        var failures: [URL: Error] = [:]

        for url in urls {
            do {
                try await remove(at: url)
            } catch {
                failures[url] = error
            }
        }

        return failures
    }

    /// Check if a path contains sensitive data
    func containsSensitiveData(at url: URL) -> Bool {
        let path = url.path.lowercased()

        return SafeRemover.sensitivePatterns.contains { pattern in
            let exactPattern = "/\(pattern.lowercased())"
            return path.hasSuffix(exactPattern) || path.contains(exactPattern + "/")
        }
    }

    /// Check if a bundle ID is system critical
    func isSystemCritical(bundleId: String) -> Bool {
        // Fast wildcard check for com.apple.*
        if bundleId.hasPrefix("com.apple.") {
            return true
        }

        return SafeRemover.systemCriticalBundles.contains(bundleId)
    }

    /// Check if a path is protected
    func isProtectedPath(_ url: URL) -> Bool {
        let path = url.path

        return SafeRemover.protectedPaths.contains { pattern in
            if pattern.hasSuffix("/*") {
                let basePath = String(pattern.dropLast(2))
                return path.hasPrefix(basePath) && path != basePath
            } else {
                return path == pattern
            }
        }
    }

    // MARK: - Private Validation Methods

    private func validatePathForRemoval(_ url: URL) throws {
        let path = url.path

        // Check if path is empty
        guard !path.isEmpty else {
            throw RemovalError.invalidPath("Path is empty")
        }

        // Check if path is protected
        guard !isProtectedPath(url) else {
            throw RemovalError.protectedPath("Path is protected: \(path)")
        }

        // Check if path exists
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            throw RemovalError.pathNotFound("Path does not exist: \(path)")
        }

        // Resolve symlinks
        var isSymlink: AnyObject?
        try (url as NSURL).getResourceValue(&isSymlink, forKey: URLResourceKey.isSymbolicLinkKey)

        if let isSymlink = isSymlink as? Bool, isSymlink {
            let destination = try fileManager.destinationOfSymbolicLink(atPath: path)

            // Convert relative symlinks to absolute for validation
            var resolvedDestination = destination
            if !destination.hasPrefix("/") {
                let baseDir = (path as NSString).deletingLastPathComponent
                resolvedDestination = URL(fileURLWithPath: baseDir)
                    .appendingPathComponent(destination)
                    .path
            }

            let destinationURL = URL(fileURLWithPath: resolvedDestination)

            // Check if symlink target is protected
            guard !isProtectedPath(destinationURL) else {
                throw RemovalError.protectedPath("Symlink points to protected path: \(path) -> \(resolvedDestination)")
            }
        }

        // Check for sensitive data
        if containsSensitiveData(at: url) {
            throw RemovalError.sensitiveData("Path may contain sensitive data: \(path)")
        }
    }
}

// MARK: - Removal Errors
enum RemovalError: Error, LocalizedError {
    case invalidPath(String)
    case protectedPath(String)
    case pathNotFound(String)
    case sensitiveData(String)
    case permissionDenied(String)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .invalidPath(let message):
            return "Invalid path: \(message)"
        case .protectedPath(let message):
            return "Protected path: \(message)"
        case .pathNotFound(let message):
            return "Path not found: \(message)"
        case .sensitiveData(let message):
            return "Sensitive data: \(message)"
        case .permissionDenied(let resource):
            return "Permission denied: \(resource)"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}