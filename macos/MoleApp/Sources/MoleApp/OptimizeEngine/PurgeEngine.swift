import Foundation
import os.log

/// Engine for managing heavy project build artifact cleanup
actor PurgeEngine {
    private let logger = Logger(subsystem: "com.mole.purge", category: "PurgeEngine")
    private let fileManager = FileManager.default
    private let processManager = ProcessManager()
    private let safeRemover = SafeRemover()

    // Purge state tracking
    private var customPaths: [String] = []
    private var sudoAvailable = false

    /// Result type for purge operations
    struct PurgeResult: Sendable {
        let taskName: String
        let success: Bool
        let message: String
        let sizeSavedKB: Int
        let filesDeleted: Int
        let executionTime: TimeInterval
    }

    /// Configuration for purge operations
    struct PurgeConfig: Sendable {
        let dryRun: Bool
        let requireSudo: Bool
        let maxDepth: Int
        let includeNodeModules: Bool
        let includeBuildFolders: Bool
        let includeDerivedData: Bool
        let includePods: Bool
        let includeVendor: Bool

        static let `default` = PurgeConfig(
            dryRun: false,
            requireSudo: false,
            maxDepth: 4,
            includeNodeModules: true,
            includeBuildFolders: true,
            includeDerivedData: true,
            includePods: true,
            includeVendor: true
        )
    }

    private var config: PurgeConfig = .default

    /// Update configuration
    func configure(_ newConfig: PurgeConfig) {
        config = newConfig
        logger.info("PurgeEngine configured: dryRun=\(newConfig.dryRun), maxDepth=\(newConfig.maxDepth)")

        // Check sudo availability when config requires sudo
        if newConfig.requireSudo {
            checkSudoAvailability()
        }
    }

    /// Check if sudo is available without password prompt
    private func checkSudoAvailability() {
        Task.detached {
            do {
                let result = try await self.processManager.executeWithSudoOutput(command: "true", arguments: [])
                await MainActor.run {
                    self.sudoAvailable = true
                    self.logger.info("Sudo is available without password")
                }
            } catch {
                await MainActor.run {
                    self.sudoAvailable = false
                    self.logger.warning("Sudo requires password or is not available")
                }
            }
        }
    }

    /// Request sudo permission from user
    func requestSudoPermission() async throws {
        logger.info("Requesting sudo permission from user")

        do {
            // Try a simple sudo command that requires privilege
            _ = try await processManager.executeWithSudoOutput(command: "true", arguments: [])
            sudoAvailable = true
            logger.info("Sudo permission granted")
        } catch {
            sudoAvailable = false
            logger.error("Sudo permission denied: \(error.localizedDescription)")
            throw PurgeError.sudoRequired("Sudo permission is required but not available. Please run: sudo true")
        }
    }

    /// Add custom path to purge list
    func addCustomPath(_ path: String) {
        customPaths.append(path)
        logger.info("Added custom purge path: \(path)")
    }

    /// Remove custom path from purge list
    func removeCustomPath(_ path: String) {
        customPaths.removeAll { $0 == path }
        logger.info("Removed custom purge path: \(path)")
    }

    /// Get all custom paths
    func getCustomPaths() -> [String] {
        return customPaths
    }

    /// Execute purge operation on all configured paths
    func runPurge() async throws -> [PurgeResult] {
        logger.info("Starting purge operation")

        // Check sudo permission if required
        if config.requireSudo && !sudoAvailable {
            try await requestSudoPermission()
        }

        var results: [PurgeResult] = []

        // Standard project purge paths
        let projectPaths = getStandardProjectPaths()
        results.append(contentsOf: try await purgePaths(projectPaths, category: "Standard Projects"))

        // Custom paths
        if !customPaths.isEmpty {
            results.append(contentsOf: try await purgePaths(customPaths, category: "Custom Paths"))
        }

        // Development cache purge
        results.append(contentsOf: try await purgeDevelopmentCaches())

        logger.info("Purge operation completed with \(results.count) results")
        return results
    }

    /// Get standard project paths to scan
    private func getStandardProjectPaths() -> [String] {
        let homePath = fileManager.homeDirectoryForCurrentUser.path

        return [
            "\(homePath)/Developer",
            "\(homePath)/Projects",
            "\(homePath)/project",
            "\(homePath)/workspace",
            "\(homePath)/workspaces",
            "\(homePath)/src",
            "\(homePath)/code",
            "/Users/Shared/Developer",
            "/Users/Shared/Projects"
        ]
    }

    /// Purge specific paths with given category
    private func purgePaths(_ paths: [String], category: String) async throws -> [PurgeResult] {
        var results: [PurgeResult] = []

        for path in paths {
            if fileManager.fileExists(atPath: path) {
                let result = try await purgeDirectory(path, category: category)
                results.append(result)
            }
        }

        return results
    }

    /// Purge a single directory
    private func purgeDirectory(_ path: String, category: String) async throws -> PurgeResult {
        let startTime = Date()
        logger.info("Purging directory: \(path)")

        var totalSizeKB = 0
        var totalFiles = 0
        var targetsFound: [String] = []

        // Scan for purge targets
        if let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                let path = fileURL.path
                let fileName = fileURL.lastPathComponent.lowercased()

                // Check if this is a purge target
                if isPurgeTarget(fileName, path: path) {
                    if let attributes = try? fileManager.attributesOfItem(atPath: path),
                       let fileSize = attributes[.size] as? UInt64 {
                        totalSizeKB += Int(fileSize / 1024)
                        totalFiles += 1
                        targetsFound.append(path)
                    }
                }
            }
        }

        guard !config.dryRun else {
            return PurgeResult(
                taskName: "Purge \(category)",
                success: true,
                message: "Purge (dry run) for \(path): \(totalFiles) targets, \(formatBytes(totalSizeKB * 1024))",
                sizeSavedKB: totalSizeKB,
                filesDeleted: totalFiles,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            // Delete found targets using SafeRemover
            for target in targetsFound {
                try? await safeRemover.remove(at: URL(fileURLWithPath: target))
            }

            logger.info("Purge completed for \(path): \(totalFiles) files deleted, \(self.formatBytes(totalSizeKB * 1024)) saved")
            return PurgeResult(
                taskName: "Purge \(category)",
                success: true,
                message: "Purged \(path): \(totalFiles) targets deleted, \(formatBytes(totalSizeKB * 1024)) saved",
                sizeSavedKB: totalSizeKB,
                filesDeleted: totalFiles,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to purge directory: \(error.localizedDescription)")
            return PurgeResult(
                taskName: "Purge \(category)",
                success: false,
                message: "Failed to purge \(path): \(error.localizedDescription)",
                sizeSavedKB: 0,
                filesDeleted: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    /// Check if a file/directory is a purge target
    private func isPurgeTarget(_ fileName: String, path: String) -> Bool {
        // Node.js modules
        if fileName == "node_modules" && config.includeNodeModules {
            return true
        }

        // Build folders
        if fileName.hasSuffix("build") || fileName.hasPrefix("build.") {
            if config.includeBuildFolders {
                return true
            }
        }

        // Derived data (Xcode)
        if fileName.contains("deriveddata") || path.contains("DerivedData") {
            if config.includeDerivedData {
                return true
            }
        }

        // CocoaPods
        if fileName == "pods" || fileName == "pod" {
            if config.includePods {
                return true
            }
        }

        // Vendor folders
        if fileName == "vendor" {
            if config.includeVendor {
                return true
            }
        }

        // Common build artifacts
        let buildArtifacts = [
            ".next", ".nuxt", "dist", "out", "build", "target",
            "bin", "obj", ".gradle", ".maven", ".cache",
            "__pycache__", ".pytest_cache", ".tox", ".eggs",
            ".dart_tool", ".flutter-plugins", ".flutter-plugins-dependencies",
            "carthage", "packages", ".symlinks", "index"
        ]

        if buildArtifacts.contains(fileName) {
            return true
        }

        return false
    }

    /// Purge development caches
    private func purgeDevelopmentCaches() async throws -> [PurgeResult] {
        var results: [PurgeResult] = []

        let cachePaths = [
            ("Homebrew Cache", "\(fileManager.homeDirectoryForCurrentUser.path)/Library/Caches/Homebrew"),
            ("pip Cache", "\(fileManager.homeDirectoryForCurrentUser.path)/Library/Caches/pip"),
            ("npm Cache", "\(fileManager.homeDirectoryForCurrentUser.path)/.npm"),
            ("yarn Cache", "\(fileManager.homeDirectoryForCurrentUser.path)/Library/Caches/Yarn"),
            ("gradle Cache", "\(fileManager.homeDirectoryForCurrentUser.path)/.gradle/caches"),
            ("maven Cache", "\(fileManager.homeDirectoryForCurrentUser.path)/.m2/repository"),
            ("cargo Cache", "\(fileManager.homeDirectoryForCurrentUser.path)/.cargo/registry"),
            ("go Cache", "\(fileManager.homeDirectoryForCurrentUser.path)/Library/Caches/go-build"),
            ("swift Cache", "\(fileManager.homeDirectoryForCurrentUser.path)/Library/Caches/org.swift.swiftpm")
        ]

        for (name, path) in cachePaths {
            if fileManager.fileExists(atPath: path) {
                let result = try await purgeCacheDirectory(path, category: name)
                results.append(result)
            }
        }

        return results
    }

    /// Purge a cache directory
    private func purgeCacheDirectory(_ path: String, category: String) async throws -> PurgeResult {
        let startTime = Date()
        logger.info("Purging cache directory: \(path)")

        var totalSizeKB = 0
        var totalFiles = 0

        if let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                   let fileSize = attributes[.size] as? UInt64 {
                    totalSizeKB += Int(fileSize / 1024)
                    totalFiles += 1
                }
            }
        }

        guard !config.dryRun else {
            return PurgeResult(
                taskName: "Purge \(category)",
                success: true,
                message: "Cache purge (dry run) for \(category): \(totalFiles) files, \(formatBytes(totalSizeKB * 1024))",
                sizeSavedKB: totalSizeKB,
                filesDeleted: totalFiles,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            try? fileManager.removeItem(atPath: path)
            try? fileManager.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)

            logger.info("Cache purge completed for \(category): \(self.formatBytes(totalSizeKB * 1024)) saved")
            return PurgeResult(
                taskName: "Purge \(category)",
                success: true,
                message: "Purged \(category): \(totalFiles) files deleted, \(formatBytes(totalSizeKB * 1024)) saved",
                sizeSavedKB: totalSizeKB,
                filesDeleted: totalFiles,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to purge cache directory: \(error.localizedDescription)")
            return PurgeResult(
                taskName: "Purge \(category)",
                success: false,
                message: "Failed to purge \(category): \(error.localizedDescription)",
                sizeSavedKB: 0,
                filesDeleted: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    /// Scan for available purge targets without deleting
    func scanPurgeTargets() async throws -> [PurgeTarget] {
        logger.info("Scanning for purge targets")
        var targets: [PurgeTarget] = []

        let allPaths = getStandardProjectPaths() + customPaths

        for path in allPaths {
            if fileManager.fileExists(atPath: path) {
                if let foundTargets = scanPathForTargets(path) {
                    targets.append(contentsOf: foundTargets)
                }
            }
        }

        logger.info("Found \(targets.count) purge targets")
        return targets
    }

    /// Scan a specific path for purge targets
    private func scanPathForTargets(_ path: String) -> [PurgeTarget]? {
        var foundTargets: [PurgeTarget] = []

        if let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                let targetPath = fileURL.path
                let fileName = fileURL.lastPathComponent

                if isPurgeTarget(fileName.lowercased(), path: targetPath) {
                    var isDirectory: ObjCBool = false
                    fileManager.fileExists(atPath: targetPath, isDirectory: &isDirectory)

                    let sizeKB = getDirectorySizeKB(targetPath) ?? 0

                    foundTargets.append(
                        PurgeTarget(
                            path: targetPath,
                            name: fileName,
                            isDirectory: isDirectory.boolValue,
                            sizeKB: sizeKB,
                            category: categorizeTarget(fileName)
                        )
                    )
                }
            }
        }

        return foundTargets.isEmpty ? nil : foundTargets
    }

    /// Get directory size in KB
    private func getDirectorySizeKB(_ path: String) -> Int? {
        guard let enumerator = fileManager.enumerator(atPath: path) else {
            return nil
        }

        var totalSize: UInt64 = 0
        for case let file as String in enumerator {
            if let fullPath = (path as NSString).appendingPathComponent(file) as String?,
               let attributes = try? fileManager.attributesOfItem(atPath: fullPath),
               let fileSize = attributes[.size] as? UInt64 {
                totalSize += fileSize
            }
        }

        return Int(totalSize / 1024)
    }

    /// Categorize a purge target
    private func categorizeTarget(_ fileName: String) -> String {
        let lower = fileName.lowercased()

        if lower == "node_modules" { return "Node.js" }
        if lower.contains("deriveddata") { return "Xcode" }
        if lower == "pods" { return "CocoaPods" }
        if lower == "vendor" { return "Vendor" }
        if lower.hasSuffix("build") { return "Build" }
        if lower.hasPrefix(".next") { return "Next.js" }
        if lower.hasPrefix(".nuxt") { return "Nuxt.js" }
        if lower == "dist" { return "Distribution" }
        if lower == "target" { return "Rust/Java" }
        if lower.contains("gradle") { return "Gradle" }
        if lower.contains("maven") { return "Maven" }
        if lower.contains("cache") { return "Cache" }

        return "Other"
    }

    /// Format bytes to human readable string
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

/// Purge target information
struct PurgeTarget: Identifiable, Sendable {
    let id = UUID()
    let path: String
    let name: String
    let isDirectory: Bool
    let sizeKB: Int
    let category: String

    var sizeHuman: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(sizeKB * 1024))
    }
}

/// Purge-specific errors
enum PurgeError: LocalizedError {
    case sudoRequired(String)
    case pathInaccessible(String)
    case permissionDenied(String)

    var errorDescription: String? {
        switch self {
        case .sudoRequired(let message):
            return message
        case .pathInaccessible(let path):
            return "Path is not accessible: \(path)"
        case .permissionDenied(let path):
            return "Permission denied for path: \(path)"
        }
    }
}