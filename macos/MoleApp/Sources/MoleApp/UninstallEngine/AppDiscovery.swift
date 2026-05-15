import Foundation

// MARK: - Application Discovery
actor AppDiscovery {

    // MARK: - Dependencies
    private let brewIntegration = BrewIntegration()
    private let safeRemover = SafeRemover()

    // MARK: - Constants
    private let searchPaths = [
        "/Applications",
        "\(NSHomeDirectory())/Applications",
        "/System/Applications",
        "/Library/PreferencePanes"
    ]

    private let cacheDirectory = "\(NSHomeDirectory())/.cache/mole"
    private let cacheFile = "\(NSHomeDirectory())/.cache/mole/uninstall_app_metadata_v1"
    private let cacheLockFile = "\(NSHomeDirectory())/.cache/mole/uninstall_app_metadata_v1.lock"
    private let cacheRefreshTTL: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    private let epochFloor: TimeInterval = 978307200 // 2001-01-01

    // MARK: - Public Methods

    /// Scan for all applications
    func scanApplications() async throws -> [AppInfo] {
        var apps: [AppInfo] = []
        var seenPaths: Set<String> = []

        for searchPath in searchPaths {
            let pathApps = try await scanApplications(at: URL(fileURLWithPath: searchPath))

            for app in pathApps {
                let path = app.path.path
                if !seenPaths.contains(path) {
                    seenPaths.insert(path)
                    apps.append(app)
                }
            }
        }

        return apps
    }

    /// Get application paths with modification times
    func getAppPathsWithMtime() async throws -> [(path: String, mtime: Int)] {
        var results: [(path: String, mtime: Int)] = []

        for searchPath in searchPaths {
            let paths = try getAppBundlePaths(at: URL(fileURLWithPath: searchPath))

            for path in paths {
                if let mtime = getFileModificationTime(at: path) {
                    results.append((path: path.path, mtime: mtime))
                }
            }
        }

        return results
    }

    /// Resolve bundle ID for an app
    func resolveBundleId(for appPath: URL) async -> String? {
        // Try Bundle first
        if let bundle = Bundle(url: appPath) {
            if let bundleId = bundle.bundleIdentifier {
                return bundleId
            }
        }

        // Fallback to plutil
        return await getBundleIdViaPlist(for: appPath)
    }

    /// Resolve display name for an app
    func resolveDisplayName(for appPath: URL, appName: String) async -> String {
        var displayName = appName

        // Try to get localized display name from metadata
        if let mdName = await getDisplayNameFromMetadata(appPath) {
            displayName = mdName
        } else if let bundleName = await getDisplayNameFromBundle(appPath) {
            displayName = bundleName
        }

        // Clean up display name
        displayName = displayName.replacingOccurrences(of: ".app", with: "")
        displayName = displayName.replacingOccurrences(of: "|", with: "-")

        // Handle versioned bundle names
        if !displayName.isEmpty && appName.hasPrefix(displayName) && appName != displayName {
            let suffix = String(appName.dropFirst(displayName.count))
            if suffix.range(of: "[0-9]", options: .regularExpression) != nil {
                displayName = appName.replacingOccurrences(of: ".app", with: "")
            }
        }

        return displayName.replacingOccurrences(of: ".app", with: "")
    }

    /// Collect inline metadata for an app
    func collectMetadata(for appPath: URL) async -> (size: Int64, lastUsed: Date?, scanTime: Date) {
        let size = await getDirectorySize(at: appPath)
        let lastUsed = await getLastUsedDate(for: appPath)
        let scanTime = Date()

        // Fallback to app mtime if lastUsed is unavailable
        let effectiveLastUsed: Date?
        if let lastUsed = lastUsed, lastUsed.timeIntervalSince1970 > epochFloor {
            effectiveLastUsed = lastUsed
        } else if let mtime = getFileModificationTime(at: appPath) {
            let mtimeDate = Date(timeIntervalSince1970: TimeInterval(mtime))
            effectiveLastUsed = mtimeDate.timeIntervalSince1970 > epochFloor ? mtimeDate : nil
        } else {
            effectiveLastUsed = nil
        }

        return (size: size, lastUsed: effectiveLastUsed, scanTime: scanTime)
    }

    /// Check if app is background only
    func isBackgroundOnly(_ appPath: URL) async -> Bool {
        guard let bundle = Bundle(url: appPath) else {
            return false
        }

        if let lsUIElement = bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool {
            return lsUIElement
        }

        if let lsUIElementString = bundle.object(forInfoDictionaryKey: "LSUIElement") as? String {
            return lsUIElementString.lowercased() == "true"
        }

        return false
    }

    /// Check if app path should be skipped
    func shouldSkipPath(_ path: URL) async -> Bool {
        let appName = path.lastPathComponent.lowercased()

        // Skip system preferences and system utilities
        let skipPatterns = [
            "system preferences",
            "system settings",
            "system information",
            "activity monitor",
            "console",
            "disk utility"
        ]

        for pattern in skipPatterns {
            if appName.contains(pattern) {
                return true
            }
        }

        return false
    }

    // MARK: - Cache Methods

    /// Load cached metadata
    func loadCachedMetadata() async -> AppMetadataCache? {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: cacheFile) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: cacheFile))
            let cache = try JSONDecoder().decode(AppMetadataCache.self, from: data)

            // Check if cache is expired
            if cache.isExpired {
                return nil
            }

            return cache
        } catch {
            return nil
        }
    }

    /// Save metadata to cache
    func saveMetadataToCache(_ apps: [CachedAppMetadata]) async throws {
        // Ensure cache directory exists
        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: cacheDirectory, withIntermediateDirectories: true)

        let cache = AppMetadataCache(apps: apps, timestamp: Date(), version: AppMetadataCache.currentVersion)
        let data = try JSONEncoder().encode(cache)

        // Write to temp file first, then move atomically
        let tempFile = "\(cacheFile).tmp"
        try data.write(to: URL(fileURLWithPath: tempFile))
        try fileManager.moveItem(atPath: tempFile, toPath: cacheFile)
    }

    // MARK: - Private Methods

    private func scanApplications(at searchPath: URL) async throws -> [AppInfo] {
        var apps: [AppInfo] = []
        let paths = try getAppBundlePaths(at: searchPath)

        for path in paths {
            do {
                if let app = try await createAppInfo(from: path) {
                    apps.append(app)
                }
            } catch {
                // Skip apps that can't be processed
                continue
            }
        }

        return apps
    }

    private func getAppBundlePaths(at searchPath: URL) throws -> [URL] {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: searchPath.path) else {
            return []
        }

        var appPaths: [URL] = []

        if let enumerator = fileManager.enumerator(at: searchPath, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                if url.pathExtension == "app" {
                    appPaths.append(url)
                }
            }
        }

        return appPaths
    }

    private func createAppInfo(from path: URL) async throws -> AppInfo? {
        let appName = path.lastPathComponent
        let bundleId = await resolveBundleId(for: path) ?? "unknown.\(appName.replacingOccurrences(of: ".app", with: ""))"

        let displayName = await resolveDisplayName(for: path, appName: appName)
        let version = await getAppVersion(for: path)
        let metadata = await collectMetadata(for: path)

        let caskName = await brewIntegration.getCaskName(for: path)
        let isBrewCask = caskName != nil

        let isSystemApp = path.path.starts(with: "/System/")
        let isBackgroundOnly = await isBackgroundOnly(path)

        return AppInfo(
            id: bundleId,
            name: displayName,
            path: path,
            version: version,
            size: metadata.size,
            lastUsed: metadata.lastUsed,
            isBrewCask: isBrewCask,
            brewCaskName: caskName,
            isSystemApp: isSystemApp,
            isBackgroundOnly: isBackgroundOnly
        )
    }

    private func getBundleIdViaPlist(for appPath: URL) async -> String? {
        let infoPlistPath = appPath.appendingPathComponent("Contents/Info.plist")

        guard FileManager.default.fileExists(atPath: infoPlistPath.path) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
                task.arguments = ["-extract", "CFBundleIdentifier", "raw", infoPlistPath.path]

                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = Pipe()

                do {
                    try task.run()
                    task.waitUntilExit()

                    if task.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        if let bundleId = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                            continuation.resume(returning: bundleId.isEmpty ? nil : bundleId)
                        } else {
                            continuation.resume(returning: nil)
                        }
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func getDisplayNameFromMetadata(_ appPath: URL) async -> String? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
                task.arguments = ["-name", "kMDItemDisplayName", "-raw", appPath.path]

                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = Pipe()

                do {
                    try task.run()
                    task.waitUntilExit()

                    if task.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        if let displayName = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                            // Filter out invalid display names
                            if !displayName.isEmpty && !displayName.hasPrefix("/") && displayName != "(null)" {
                                continuation.resume(returning: displayName)
                            } else {
                                continuation.resume(returning: nil)
                            }
                        } else {
                            continuation.resume(returning: nil)
                        }
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func getDisplayNameFromBundle(_ appPath: URL) async -> String? {
        guard let bundle = Bundle(url: appPath) else {
            return nil
        }

        // Try CFBundleDisplayName first
        if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
            return displayName.isEmpty ? nil : displayName
        }

        // Try CFBundleName
        if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            return name.isEmpty ? nil : name
        }

        return nil
    }

    private func getAppVersion(for appPath: URL) async -> String {
        guard let bundle = Bundle(url: appPath) else {
            return "Unknown"
        }

        if let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return version.isEmpty ? "Unknown" : version
        }

        if let version = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            return version.isEmpty ? "Unknown" : version
        }

        return "Unknown"
    }

    private func getLastUsedDate(for appPath: URL) async -> Date? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
                task.arguments = ["-name", "kMDItemLastUsedDate", "-raw", appPath.path]

                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = Pipe()

                do {
                    try task.run()
                    task.waitUntilExit()

                    if task.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        if let dateString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                            if !dateString.isEmpty && dateString != "(null)" {
                                let dateFormatter = DateFormatter()
                                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
                                continuation.resume(returning: dateFormatter.date(from: dateString))
                            } else {
                                continuation.resume(returning: nil)
                            }
                        } else {
                            continuation.resume(returning: nil)
                        }
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func getDirectorySize(at url: URL) async -> Int64 {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fileManager = FileManager.default
                var totalSize: Int64 = 0

                if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
                    for case let url as URL in enumerator {
                        if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
                           let fileSize = resourceValues.fileSize {
                            totalSize += Int64(fileSize)
                        }
                    }
                }

                continuation.resume(returning: totalSize)
            }
        }
    }

    private func getFileModificationTime(at url: URL) -> Int? {
        let fileManager = FileManager.default

        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                return Int(modificationDate.timeIntervalSince1970)
            }
        } catch {
            return nil
        }

        return nil
    }
}