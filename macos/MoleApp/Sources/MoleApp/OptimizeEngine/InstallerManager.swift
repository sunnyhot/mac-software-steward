import Foundation
import os.log

/// Manager for scanning and managing installer files (.dmg, .pkg, .mpkg, .iso, .xip, .zip)
actor InstallerManager {
    private let logger = Logger(subsystem: "com.mole.installer", category: "InstallerManager")
    private let fileManager = FileManager.default
    private let processManager = ProcessManager()

    // Installer state tracking
    private var hasResumed = false
    private var scanResults: [InstallerPackage] = []

    /// Supported installer file extensions
    private let supportedExtensions = [
        "dmg",      // Disk image
        "pkg",      // Package installer
        "mpkg",     // Meta package
        "iso",      // Disk image (CD/DVD)
        "xip",      // XIP archive
        "zip",      // ZIP archive (can contain installers)
        "tar",      // TAR archive
        "gz",       // GZIP archive
        "bz2"       // BZIP2 archive
    ]

    /// Default scan paths for installers
    private let defaultScanPaths: [String] = {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(homePath)/Downloads",
            "\(homePath)/Desktop",
            "\(homePath)/Documents",
            "\(homePath)/Public",
            "\(homePath)/Library/Downloads",
            "/Users/Shared",
            "/Users/Shared/Downloads",
            "\(homePath)/Library/Caches/Homebrew",
            "\(homePath)/Library/Mobile Documents/com~apple~CloudDocs/Downloads",
            "\(homePath)/Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
            "\(homePath)/Library/Application Support/Telegram Desktop",
            "\(homePath)/Downloads/Telegram Desktop"
        ]
    }()

    /// Result type for installer operations
    struct InstallerResult: Sendable {
        let operation: String
        let success: Bool
        let message: String
        let packagesAffected: Int
        let spaceSavedKB: Int
        let executionTime: TimeInterval
    }

    /// Installer package information
    struct InstallerPackage: Identifiable, Sendable {
        let id = UUID()
        let name: String
        let path: String
        let type: InstallerType
        let sizeKB: Int
        let creationDate: Date?
        let modificationDate: Date?
        let isArchive: Bool
        let archiveContents: [String]?

        var sizeHuman: String {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: Int64(sizeKB * 1024))
        }
    }

    /// Installer type enumeration
    enum InstallerType: String, CaseIterable {
        case dmg = "Disk Image"
        case pkg = "Package"
        case mpkg = "Meta Package"
        case iso = "ISO Image"
        case xip = "XIP Archive"
        case zip = "ZIP Archive"
        case tar = "TAR Archive"
        case gz = "GZIP Archive"
        case bz2 = "BZIP2 Archive"
        case unknown = "Unknown"
    }

    /// Configuration for installer operations
    struct InstallerConfig: Sendable {
        let maxDepth: Int
        let includeArchives: Bool
        let maxArchiveEntries: Int
        let minSizeKB: Int
        let scanCloudStorage: Bool

        static let `default` = InstallerConfig(
            maxDepth: 2,
            includeArchives: true,
            maxArchiveEntries: 50,
            minSizeKB: 1024,  // 1MB minimum
            scanCloudStorage: false
        )
    }

    private var config: InstallerConfig = .default

    /// Update configuration
    func configure(_ newConfig: InstallerConfig) {
        config = newConfig
        logger.info("InstallerManager configured: maxDepth=\(newConfig.maxDepth), includeArchives=\(newConfig.includeArchives)")
    }

    /// Scan for all installer files in default locations
    func scanAllInstallers() async throws -> [InstallerPackage] {
        logger.info("Scanning for installers in default locations")

        var allPackages: [InstallerPackage] = []

        for path in defaultScanPaths {
            // Skip cloud storage if not configured to scan it
            if !config.scanCloudStorage && (path.contains("icloud") || path.contains("CloudDocs")) {
                continue
            }

            if fileManager.fileExists(atPath: path) {
                let packages = try await scanPathForInstallers(path)
                allPackages.append(contentsOf: packages)
            }
        }

        scanResults = allPackages
        logger.info("Found \(allPackages.count) installer packages")
        return allPackages
    }

    /// Scan a specific path for installer files
    func scanPathForInstallers(_ path: String) async throws -> [InstallerPackage] {
        logger.info("Scanning path: \(path)")

        var packages: [InstallerPackage] = []

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [
                .nameKey,
                .pathKey,
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey,
                .isDirectoryKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            logger.warning("Cannot create enumerator for path: \(path)")
            return packages
        }

        var currentDepth = 0
        let maxDepth = config.maxDepth

        for case let fileURL as URL in enumerator {
            // Check depth
            let resourceValues = try? fileURL.resourceValues(forKeys: [URLResourceKey.isDirectoryKey])
            if let isDirectory = resourceValues?.isDirectory, isDirectory {
                currentDepth += 1
                if currentDepth > maxDepth {
                    enumerator.skipDescendants()
                    currentDepth -= 1
                    continue
                }
            }

            // Check if file has supported extension
            let fileExtension = fileURL.pathExtension.lowercased()
            guard supportedExtensions.contains(fileExtension) else {
                continue
            }

            // Get file attributes
            let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
            let fileSize = attributes?[FileAttributeKey.size] as? UInt64 ?? 0
            let sizeKB = Int(fileSize / 1024)

            // Skip files that are too small
            if sizeKB < config.minSizeKB {
                continue
            }

            // Get file type
            let installerType = InstallerType(rawValue: fileExtension) ?? .unknown
            let isArchive = ["zip", "tar", "gz", "bz2"].contains(fileExtension)

            // Get dates
            let creationDate = attributes?[FileAttributeKey.creationDate] as? Date
            let modificationDate = attributes?[FileAttributeKey.modificationDate] as? Date

            // Check archive contents if applicable
            var archiveContents: [String]? = nil
            if isArchive && config.includeArchives {
                archiveContents = await getArchiveContents(fileURL.path)
            }

            let package = InstallerPackage(
                name: fileURL.lastPathComponent,
                path: fileURL.path,
                type: installerType,
                sizeKB: sizeKB,
                creationDate: creationDate,
                modificationDate: modificationDate,
                isArchive: isArchive,
                archiveContents: archiveContents
            )

            packages.append(package)

            logger.debug("Found installer: \(package.name) (\(package.sizeHuman))")
        }

        return packages
    }

    /// Get contents of an archive file
    private func getArchiveContents(_ path: String) async -> [String]? {
        let fileExtension = URL(fileURLWithPath: path).pathExtension.lowercased()

        do {
            switch fileExtension {
            case "zip":
                return try await getZipContents(path)
            case "tar", "gz", "bz2":
                return try await getTarContents(path)
            default:
                return nil
            }
        } catch {
            logger.warning("Failed to get archive contents for \(path): \(error.localizedDescription)")
            return nil
        }
    }

    /// Get contents of a ZIP file
    private func getZipContents(_ path: String) async throws -> [String] {
        // Use zipinfo command if available
        if let output = try? await processManager.executeWithOutput(
            command: "/usr/bin/zipinfo",
            arguments: ["-1", path]
        ) {
            let contents = output
                .components(separatedBy: "\n")
                .filter { !$0.isEmpty }
                .prefix(config.maxArchiveEntries)
                .map { String($0) }

            return Array(contents)
        }

        // Fallback: use unzip -l
        if let output = try? await processManager.executeWithOutput(
            command: "/usr/bin/unzip",
            arguments: ["-l", path]
        ) {
            let contents = output
                .components(separatedBy: "\n")
                .drop { $0.contains("Archive:") || $0.contains("----") || $0.isEmpty }
                .map { line in
                    let components = line.components(separatedBy: " ").filter { !$0.isEmpty }
                    return components.last ?? line
                }
                .filter { !$0.isEmpty }
                .prefix(config.maxArchiveEntries)
                .map { String($0) }

            return Array(contents)
        }

        return []
    }

    /// Get contents of a TAR file
    private func getTarContents(_ path: String) async throws -> [String] {
        if let output = try? await processManager.executeWithOutput(
            command: "/usr/bin/tar",
            arguments: ["-tf", path]
        ) {
            let contents = output
                .components(separatedBy: "\n")
                .filter { !$0.isEmpty }
                .prefix(config.maxArchiveEntries)
                .map { String($0) }

            return Array(contents)
        }

        return []
    }

    /// Delete selected installer packages
    func deleteInstallers(_ packages: [InstallerPackage]) async throws -> InstallerResult {
        let startTime = Date()
        logger.info("Deleting \(packages.count) installer packages")

        var deletedCount = 0
        var totalSpaceSavedKB = 0
        var errors: [String] = []

        for package in packages {
            do {
                // Check if file still exists
                guard fileManager.fileExists(atPath: package.path) else {
                    logger.warning("File no longer exists: \(package.path)")
                    continue
                }

                // Get size before deletion
                let attributes = try fileManager.attributesOfItem(atPath: package.path)
                let fileSize = attributes[.size] as? UInt64 ?? 0
                let sizeKB = Int(fileSize / 1024)

                // Move to trash instead of permanent deletion
                try fileManager.trashItem(at: URL(fileURLWithPath: package.path), resultingItemURL: nil)

                deletedCount += 1
                totalSpaceSavedKB += sizeKB

                logger.info("Deleted installer: \(package.name) (\(package.sizeHuman))")
            } catch {
                let errorMsg = "Failed to delete \(package.name): \(error.localizedDescription)"
                errors.append(errorMsg)
                logger.error("\(errorMsg)")
            }
        }

        let success = errors.isEmpty
        let message: String
        if success {
            message = "Successfully deleted \(deletedCount) installers, freed \(formatBytes(totalSpaceSavedKB * 1024))"
        } else {
            message = "Deleted \(deletedCount)/\(packages.count) installers. Errors: \(errors.joined(separator: "; "))"
        }

        logger.info("Deletion completed: \(message)")

        return InstallerResult(
            operation: "Delete Installers",
            success: success,
            message: message,
            packagesAffected: deletedCount,
            spaceSavedKB: totalSpaceSavedKB,
            executionTime: Date().timeIntervalSince(startTime)
        )
    }

    /// Get storage statistics for found installers
    func getStorageStatistics() async -> InstallerStatistics {
        let totalSizeKB = scanResults.reduce(0) { $0 + $1.sizeKB }
        let countByType = Dictionary(grouping: scanResults) { $0.type }
            .mapValues { $0.count }
        let totalSizeByType = Dictionary(grouping: scanResults) { $0.type }
            .mapValues { packages in
                packages.reduce(0) { $0 + $1.sizeKB }
            }

        return InstallerStatistics(
            totalPackages: scanResults.count,
            totalSizeKB: totalSizeKB,
            totalSizeHuman: formatBytes(totalSizeKB * 1024),
            countByType: countByType,
            totalSizeByType: totalSizeByType,
            averageSizeKB: scanResults.isEmpty ? 0 : totalSizeKB / scanResults.count
        )
    }

    /// Get large installers (top N by size)
    func getLargeInstallers(limit: Int = 10) -> [InstallerPackage] {
        return scanResults
            .sorted { $0.sizeKB > $1.sizeKB }
            .prefix(limit)
            .map { $0 }
    }

    /// Get old installers (older than specified days)
    func getOldInstallers(olderThan days: Int) -> [InstallerPackage] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        return scanResults.filter { package in
            if let modificationDate = package.modificationDate {
                return modificationDate < cutoffDate
            }
            return false
        }
    }

    /// Group installers by type
    func getInstallersByType() -> [InstallerType: [InstallerPackage]] {
        return Dictionary(grouping: scanResults) { $0.type }
    }

    /// Search installers by name
    func searchInstallers(_ query: String) -> [InstallerPackage] {
        let lowercasedQuery = query.lowercased()
        return scanResults.filter { package in
            package.name.lowercased().contains(lowercasedQuery) ||
            package.path.lowercased().contains(lowercasedQuery)
        }
    }

    /// Clear scan results
    func clearScanResults() {
        scanResults.removeAll()
        logger.info("Scan results cleared")
    }

    /// Get current scan results
    func getScanResults() -> [InstallerPackage] {
        return scanResults
    }

    // MARK: - Private Helper Methods

    /// Format bytes to human readable string
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

/// Storage statistics for installer packages
struct InstallerStatistics: Sendable {
    let totalPackages: Int
    let totalSizeKB: Int
    let totalSizeHuman: String
    let countByType: [InstallerManager.InstallerType: Int]
    let totalSizeByType: [InstallerManager.InstallerType: Int]
    let averageSizeKB: Int

    var largestPackageSize: String {
        let maxSize = totalSizeByType.values.max() ?? 0
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(maxSize * 1024))
    }

    var mostCommonType: InstallerManager.InstallerType? {
        countByType.max { $0.value < $1.value }?.key
    }
}