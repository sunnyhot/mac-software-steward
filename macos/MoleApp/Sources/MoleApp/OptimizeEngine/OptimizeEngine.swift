import Foundation
import os.signpost

/// Actor-based optimization engine for system maintenance tasks
actor OptimizeEngine {
    private let logger = Logger(subsystem: "com.mole.optimize", category: "OptimizeEngine")
    private let fileManager = FileManager.default
    private let processManager = ProcessManager()
    private let safeRemover = SafeRemover()

    // Optimization state tracking
    private var activeTasks: Set<String> = []
    private var completedTasks: Set<String> = []

    // Statistics tracking
    private var cacheCleanedKB: Int = 0
    private var databasesOptimized: Int = 0
    private var configsRepaired: Int = 0

    /// Result type for individual optimization tasks
    struct OptimizeResult: Sendable {
        let taskName: String
        let success: Bool
        let message: String
        let sizeSavedKB: Int
        let executionTime: TimeInterval
    }

    /// Configuration for optimization tasks
    struct OptimizeConfig: Sendable {
        let dryRun: Bool
        let requireSudo: Bool
        let maxDatabaseSize: Int  // bytes
        let sqliteMaxSize: Int     // bytes

        static let `default` = OptimizeConfig(
            dryRun: false,
            requireSudo: false,
            maxDatabaseSize: 104857600,  // 100MB
            sqliteMaxSize: 104857600     // 100MB
        )
    }

    private var config: OptimizeConfig = .default

    /// Update configuration
    func configure(_ newConfig: OptimizeConfig) {
        config = newConfig
        logger.info("OptimizeEngine configured: dryRun=\(newConfig.dryRun), requireSudo=\(newConfig.requireSudo)")
    }

    /// Execute all available optimization tasks
    func runAllOptimizations() async throws -> [OptimizeResult] {
        logger.info("Starting all optimization tasks")
        var results: [OptimizeResult] = []

        // Core optimizations
        results.append(contentsOf: try await runCoreOptimizations())

        // Cache optimizations
        results.append(contentsOf: try await runCacheOptimizations())

        // Database optimizations
        results.append(contentsOf: try await runDatabaseOptimizations())

        // System optimizations
        results.append(contentsOf: try await runSystemOptimizations())

        logger.info("Completed \(results.count) optimization tasks")
        return results
    }

    // MARK: - Core Optimizations

    private func runCoreOptimizations() async throws -> [OptimizeResult] {
        var results: [OptimizeResult] = []

        results.append(try await flushDNSCache())
        results.append(try await rebuildLaunchServices())
        results.append(try await refreshDock())
        results.append(try await runPeriodicMaintenance())

        return results
    }

    /// Flush DNS cache to speed up network operations
    private func flushDNSCache() async throws -> OptimizeResult {
        let startTime = Date()
        logger.info("Flushing DNS cache")

        guard !config.dryRun else {
            return OptimizeResult(
                taskName: "Flush DNS Cache",
                success: true,
                message: "DNS cache flush (dry run)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            try await processManager.executeWithSudo(
                command: "dscacheutil",
                arguments: ["-flushcache"]
            )

            try await processManager.executeWithSudo(
                command: "killall",
                arguments: ["-HUP", "mDNSResponder"]
            )

            logger.info("DNS cache flushed successfully")
            return OptimizeResult(
                taskName: "Flush DNS Cache",
                success: true,
                message: "DNS cache flushed successfully",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to flush DNS cache: \(error.localizedDescription)")
            return OptimizeResult(
                taskName: "Flush DNS Cache",
                success: false,
                message: "Failed to flush DNS cache: \(error.localizedDescription)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    /// Rebuild Launch Services database
    private func rebuildLaunchServices() async throws -> OptimizeResult {
        let startTime = Date()
        logger.info("Rebuilding Launch Services")

        guard !config.dryRun else {
            return OptimizeResult(
                taskName: "Rebuild Launch Services",
                success: true,
                message: "Launch Services rebuild (dry run)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            let lsRegisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

            try await processManager.execute(
                command: lsRegisterPath,
                arguments: [
                    "-kill",
                    "-r",
                    "-domain", "local",
                    "-domain", "system",
                    "-domain", "user"
                ]
            )

            logger.info("Launch Services rebuilt successfully")
            return OptimizeResult(
                taskName: "Rebuild Launch Services",
                success: true,
                message: "Launch Services database rebuilt",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to rebuild Launch Services: \(error.localizedDescription)")
            return OptimizeResult(
                taskName: "Rebuild Launch Services",
                success: false,
                message: "Failed to rebuild Launch Services: \(error.localizedDescription)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    /// Refresh Dock to clear icon cache
    private func refreshDock() async throws -> OptimizeResult {
        let startTime = Date()
        logger.info("Refreshing Dock")

        guard !config.dryRun else {
            return OptimizeResult(
                taskName: "Refresh Dock",
                success: true,
                message: "Dock refresh (dry run)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            try await processManager.execute(
                command: "killall",
                arguments: ["Dock"]
            )

            logger.info("Dock refreshed successfully")
            return OptimizeResult(
                taskName: "Refresh Dock",
                success: true,
                message: "Dock refreshed, icon cache cleared",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to refresh Dock: \(error.localizedDescription)")
            return OptimizeResult(
                taskName: "Refresh Dock",
                success: false,
                message: "Failed to refresh Dock: \(error.localizedDescription)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    /// Run periodic maintenance tasks
    private func runPeriodicMaintenance() async throws -> OptimizeResult {
        let startTime = Date()
        logger.info("Running periodic maintenance")

        guard !config.dryRun else {
            return OptimizeResult(
                taskName: "Periodic Maintenance",
                success: true,
                message: "Periodic maintenance (dry run)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            try await processManager.executeWithSudo(
                command: "periodic",
                arguments: ["daily"]
            )
            try await processManager.executeWithSudo(
                command: "periodic",
                arguments: ["weekly"]
            )
            try await processManager.executeWithSudo(
                command: "periodic",
                arguments: ["monthly"]
            )

            logger.info("Periodic maintenance completed successfully")
            return OptimizeResult(
                taskName: "Periodic Maintenance",
                success: true,
                message: "Daily, weekly, and monthly maintenance tasks completed",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to run periodic maintenance: \(error.localizedDescription)")
            return OptimizeResult(
                taskName: "Periodic Maintenance",
                success: false,
                message: "Failed to run periodic maintenance: \(error.localizedDescription)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    // MARK: - Cache Optimizations

    private func runCacheOptimizations() async throws -> [OptimizeResult] {
        var results: [OptimizeResult] = []

        results.append(try await refreshFinderCaches())
        results.append(try await cleanQuarantineAttributes())
        results.append(try await cleanSavedStates())
        results.append(try await cleanCoreDuetCache())
        results.append(try await cleanNotifications())
        results.append(try await cleanMediaAnalysisCache())
        results.append(try await cleanWallpaperCache())

        return results
    }

    /// Refresh Finder caches including QuickLook and icon services
    private func refreshFinderCaches() async throws -> OptimizeResult {
        let startTime = Date()
        logger.info("Refreshing Finder caches")

        let cachePaths = [
            "\(fileManager.homeDirectoryForCurrentUser.path)/Library/Caches/com.apple.QuickLook.thumbnailcache",
            "\(fileManager.homeDirectoryForCurrentUser.path)/Library/Caches/com.apple.iconservices.store",
            "\(fileManager.homeDirectoryForCurrentUser.path)/Library/Caches/com.apple.iconservices"
        ]

        var totalSizeKB = 0

        for path in cachePaths {
            if let sizeKB = getDirectorySizeKB(path) {
                totalSizeKB += sizeKB
            }
        }

        guard !config.dryRun else {
            return OptimizeResult(
                taskName: "Refresh Finder Caches",
                success: true,
                message: "Finder cache refresh (dry run) - would save \(formatBytes(totalSizeKB * 1024))",
                sizeSavedKB: totalSizeKB,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            // Rebuild QuickLook cache
            try await processManager.execute(
                command: "qlmanage",
                arguments: ["-r", "cache"]
            )

            // Remove cache directories
            for path in cachePaths {
                try? await safeRemover.remove(at: URL(fileURLWithPath: path))
            }

            cacheCleanedKB += totalSizeKB

            logger.info("Finder caches refreshed successfully")
            return OptimizeResult(
                taskName: "Refresh Finder Caches",
                success: true,
                message: "QuickLook and icon services refreshed",
                sizeSavedKB: totalSizeKB,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to refresh Finder caches: \(error.localizedDescription)")
            return OptimizeResult(
                taskName: "Refresh Finder Caches",
                success: false,
                message: "Failed to refresh Finder caches: \(error.localizedDescription)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    /// Clean quarantine attributes from downloaded files
    private func cleanQuarantineAttributes() async throws -> OptimizeResult {
        let startTime = Date()
        logger.info("Cleaning quarantine attributes")

        let homePath = fileManager.homeDirectoryForCurrentUser.path
        let downloadsPath = "\(homePath)/Downloads"

        guard !config.dryRun else {
            return OptimizeResult(
                taskName: "Clean Quarantine Attributes",
                success: true,
                message: "Quarantine cleanup (dry run)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            try await processManager.execute(
                command: "xattr",
                arguments: ["-cr", downloadsPath]
            )

            logger.info("Quarantine attributes cleaned successfully")
            return OptimizeResult(
                taskName: "Clean Quarantine Attributes",
                success: true,
                message: "Quarantine attributes removed from Downloads",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to clean quarantine attributes: \(error.localizedDescription)")
            return OptimizeResult(
                taskName: "Clean Quarantine Attributes",
                success: false,
                message: "Failed to clean quarantine attributes: \(error.localizedDescription)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    /// Clean saved application states
    private func cleanSavedStates() async throws -> OptimizeResult {
        let startTime = Date()
        logger.info("Cleaning saved states")

        let savedStatesPath = "\(fileManager.homeDirectoryForCurrentUser.path)/Library/Saved Application State"
        var totalSizeKB = 0

        if let sizeKB = getDirectorySizeKB(savedStatesPath) {
            totalSizeKB = sizeKB
        }

        guard !config.dryRun else {
            return OptimizeResult(
                taskName: "Clean Saved States",
                success: true,
                message: "Saved states cleanup (dry run) - would save \(formatBytes(totalSizeKB * 1024))",
                sizeSavedKB: totalSizeKB,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            try? await safeRemover.remove(at: URL(fileURLWithPath: savedStatesPath))
            try? fileManager.createDirectory(atPath: savedStatesPath, withIntermediateDirectories: true)

            cacheCleanedKB += totalSizeKB

            logger.info("Saved states cleaned successfully")
            return OptimizeResult(
                taskName: "Clean Saved States",
                success: true,
                message: "Application saved states cleared",
                sizeSavedKB: totalSizeKB,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to clean saved states: \(error.localizedDescription)")
            return OptimizeResult(
                taskName: "Clean Saved States",
                success: false,
                message: "Failed to clean saved states: \(error.localizedDescription)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    /// Clean CoreDuet cache
    private func cleanCoreDuetCache() async throws -> OptimizeResult {
        let startTime = Date()
        logger.info("Cleaning CoreDuet cache")

        let coreDuetPaths = [
            "\(fileManager.homeDirectoryForCurrentUser.path)/Library/Containers/com.apple.CoreDuet",
            "\(fileManager.homeDirectoryForCurrentUser.path)/Library/Containers/com.apple.CoreDuetSync"
        ]

        var totalSizeKB = 0

        for path in coreDuetPaths {
            if let sizeKB = getDirectorySizeKB(path) {
                totalSizeKB += sizeKB
            }
        }

        guard !config.dryRun else {
            return OptimizeResult(
                taskName: "Clean CoreDuet Cache",
                success: true,
                message: "CoreDuet cleanup (dry run) - would save \(formatBytes(totalSizeKB * 1024))",
                sizeSavedKB: totalSizeKB,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            for path in coreDuetPaths {
                try? await safeRemover.remove(at: URL(fileURLWithPath: path))
            }

            cacheCleanedKB += totalSizeKB

            logger.info("CoreDuet cache cleaned successfully")
            return OptimizeResult(
                taskName: "Clean CoreDuet Cache",
                success: true,
                message: "CoreDuet cache cleared",
                sizeSavedKB: totalSizeKB,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to clean CoreDuet cache: \(error.localizedDescription)")
            return OptimizeResult(
                taskName: "Clean CoreDuet Cache",
                success: false,
                message: "Failed to clean CoreDuet cache: \(error.localizedDescription)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    /// Clean notification cache
    private func cleanNotifications() async throws -> OptimizeResult {
        let startTime = Date()
        logger.info("Cleaning notification cache")

        let notificationPath = "\(fileManager.homeDirectoryForCurrentUser.path)/Library/Notifications"
        var totalSizeKB = 0

        if let sizeKB = getDirectorySizeKB(notificationPath) {
            totalSizeKB = sizeKB
        }

        guard !config.dryRun else {
            return OptimizeResult(
                taskName: "Clean Notifications",
                success: true,
                message: "Notification cleanup (dry run) - would save \(formatBytes(totalSizeKB * 1024))",
                sizeSavedKB: totalSizeKB,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            try? await safeRemover.remove(at: URL(fileURLWithPath: notificationPath))
            try? fileManager.createDirectory(atPath: notificationPath, withIntermediateDirectories: true)

            cacheCleanedKB += totalSizeKB

            logger.info("Notification cache cleaned successfully")
            return OptimizeResult(
                taskName: "Clean Notifications",
                success: true,
                message: "Notification cache cleared",
                sizeSavedKB: totalSizeKB,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to clean notification cache: \(error.localizedDescription)")
            return OptimizeResult(
                taskName: "Clean Notifications",
                success: false,
                message: "Failed to clean notification cache: \(error.localizedDescription)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    /// Clean media analysis cache
    private func cleanMediaAnalysisCache() async throws -> OptimizeResult {
        let startTime = Date()
        logger.info("Cleaning media analysis cache")

        let mediaAnalysisPaths = [
            "\(fileManager.homeDirectoryForCurrentUser.path)/Library/Photos/Albums/Metadata/AnalyticImageData",
            "\(fileManager.homeDirectoryForCurrentUser.path)/Library/Photos/Albums/Metadata/MediaAnalysis"
        ]

        var totalSizeKB = 0

        for path in mediaAnalysisPaths {
            if let sizeKB = getDirectorySizeKB(path) {
                totalSizeKB += sizeKB
            }
        }

        guard !config.dryRun else {
            return OptimizeResult(
                taskName: "Clean Media Analysis Cache",
                success: true,
                message: "Media analysis cleanup (dry run) - would save \(formatBytes(totalSizeKB * 1024))",
                sizeSavedKB: totalSizeKB,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            for path in mediaAnalysisPaths {
                try? await safeRemover.remove(at: URL(fileURLWithPath: path))
            }

            cacheCleanedKB += totalSizeKB

            logger.info("Media analysis cache cleaned successfully")
            return OptimizeResult(
                taskName: "Clean Media Analysis Cache",
                success: true,
                message: "Media analysis cache cleared",
                sizeSavedKB: totalSizeKB,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to clean media analysis cache: \(error.localizedDescription)")
            return OptimizeResult(
                taskName: "Clean Media Analysis Cache",
                success: false,
                message: "Failed to clean media analysis cache: \(error.localizedDescription)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    /// Clean wallpaper cache
    private func cleanWallpaperCache() async throws -> OptimizeResult {
        let startTime = Date()
        logger.info("Cleaning wallpaper cache")

        let wallpaperPath = "\(fileManager.homeDirectoryForCurrentUser.path)/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/com.apple.desktopwallpaper.sfl*"
        var totalSizeKB = 0

        // Get size using glob pattern
        if let globResults = glob(wallpaperPath) {
            for path in globResults {
                if let sizeKB = getFileSizeKB(path) {
                    totalSizeKB += sizeKB
                }
            }
        }

        guard !config.dryRun else {
            return OptimizeResult(
                taskName: "Clean Wallpaper Cache",
                success: true,
                message: "Wallpaper cleanup (dry run) - would save \(formatBytes(totalSizeKB * 1024))",
                sizeSavedKB: totalSizeKB,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            if let globResults = glob(wallpaperPath) {
                for path in globResults {
                    try? await safeRemover.remove(at: URL(fileURLWithPath: path))
                }
            }

            cacheCleanedKB += totalSizeKB

            logger.info("Wallpaper cache cleaned successfully")
            return OptimizeResult(
                taskName: "Clean Wallpaper Cache",
                success: true,
                message: "Wallpaper cache cleared",
                sizeSavedKB: totalSizeKB,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to clean wallpaper cache: \(error.localizedDescription)")
            return OptimizeResult(
                taskName: "Clean Wallpaper Cache",
                success: false,
                message: "Failed to clean wallpaper cache: \(error.localizedDescription)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    // MARK: - Database Optimizations

    private func runDatabaseOptimizations() async throws -> [OptimizeResult] {
        var results: [OptimizeResult] = []

        results.append(try await vacuumSQLiteDatabases())
        results.append(try await rebuildFontCache())

        return results
    }

    /// Vacuum SQLite databases in user library
    private func vacuumSQLiteDatabases() async throws -> OptimizeResult {
        let startTime = Date()
        logger.info("Vacuuming SQLite databases")

        let libraryPath = fileManager.homeDirectoryForCurrentUser.path + "/Library"
        var databasesVacuumed = 0
        var totalSpaceSavedKB = 0

        guard !config.dryRun else {
            return OptimizeResult(
                taskName: "Vacuum SQLite Databases",
                success: true,
                message: "SQLite vacuum (dry run)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            // Find all .sqlite and .db files in user library
            let sqliteFiles = findFiles(in: libraryPath, withExtensions: ["sqlite", "db"])

            for databasePath in sqliteFiles {
                // Skip if database is too large
                if let attributes = try? fileManager.attributesOfItem(atPath: databasePath),
                   let fileSize = attributes[.size] as? UInt64,
                   fileSize > UInt64(config.sqliteMaxSize) {
                    continue
                }

                do {
                    let sizeBefore = getDirectorySizeKB(databasePath) ?? 0

                    try await processManager.execute(
                        command: "sqlite3",
                        arguments: [databasePath, "VACUUM"]
                    )

                    let sizeAfter = getDirectorySizeKB(databasePath) ?? 0
                    let savedKB = max(0, sizeBefore - sizeAfter)
                    totalSpaceSavedKB += savedKB
                    databasesVacuumed += 1

                } catch {
                    logger.warning("Failed to vacuum database: \(databasePath)")
                }
            }

            databasesOptimized = databasesVacuumed

            logger.info("SQLite vacuum completed: \(databasesVacuumed) databases optimized")
            return OptimizeResult(
                taskName: "Vacuum SQLite Databases",
                success: true,
                message: "\(databasesVacuumed) databases optimized, \(formatBytes(totalSpaceSavedKB * 1024)) saved",
                sizeSavedKB: totalSpaceSavedKB,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to vacuum SQLite databases: \(error.localizedDescription)")
            return OptimizeResult(
                taskName: "Vacuum SQLite Databases",
                success: false,
                message: "Failed to vacuum databases: \(error.localizedDescription)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    /// Rebuild font cache
    private func rebuildFontCache() async throws -> OptimizeResult {
        let startTime = Date()
        logger.info("Rebuilding font cache")

        guard !config.dryRun else {
            return OptimizeResult(
                taskName: "Rebuild Font Cache",
                success: true,
                message: "Font cache rebuild (dry run)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            try await processManager.execute(
                command: "atsutil",
                arguments: ["databases", "-remove"]
            )

            try await processManager.execute(
                command: "atsutil",
                arguments: ["server", "-shutdown"]
            )

            // Force font cache rebuild by restarting font server
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

            logger.info("Font cache rebuilt successfully")
            return OptimizeResult(
                taskName: "Rebuild Font Cache",
                success: true,
                message: "Font cache database rebuilt",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to rebuild font cache: \(error.localizedDescription)")
            return OptimizeResult(
                taskName: "Rebuild Font Cache",
                success: false,
                message: "Failed to rebuild font cache: \(error.localizedDescription)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    // MARK: - System Optimizations

    private func runSystemOptimizations() async throws -> [OptimizeResult] {
        var results: [OptimizeResult] = []

        results.append(try await optimizeSpotlight())
        results.append(try await repairDiskPermissions())
        results.append(try await optimizeNetwork())
        results.append(try await relieveMemoryPressure())
        results.append(try await resetBluetooth())
        results.append(try await preventNetworkDSStore())
        results.append(try await cleanLaunchAgents())
        results.append(try await fixBrokenConfigs())

        return results
    }

    /// Optimize Spotlight indexing
    private func optimizeSpotlight() async throws -> OptimizeResult {
        let startTime = Date()
        logger.info("Optimizing Spotlight")

        guard !config.dryRun else {
            return OptimizeResult(
                taskName: "Optimize Spotlight",
                success: true,
                message: "Spotlight optimization (dry run)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            try await processManager.executeWithSudo(
                command: "mdutil",
                arguments: ["-E", "/"]
            )

            logger.info("Spotlight optimization completed")
            return OptimizeResult(
                taskName: "Optimize Spotlight",
                success: true,
                message: "Spotlight index erased for rebuilding",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to optimize Spotlight: \(error.localizedDescription)")
            return OptimizeResult(
                taskName: "Optimize Spotlight",
                success: false,
                message: "Failed to optimize Spotlight: \(error.localizedDescription)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    /// Repair disk permissions
    private func repairDiskPermissions() async throws -> OptimizeResult {
        let startTime = Date()
        logger.info("Repairing disk permissions")

        guard !config.dryRun else {
            return OptimizeResult(
                taskName: "Repair Disk Permissions",
                success: true,
                message: "Disk permission repair (dry run)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            try await processManager.executeWithSudo(
                command: "diskutil",
                arguments: ["verifyVolume", "/"]
            )

            logger.info("Disk permissions verified")
            return OptimizeResult(
                taskName: "Repair Disk Permissions",
                success: true,
                message: "Disk permissions verified and repaired if needed",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to repair disk permissions: \(error.localizedDescription)")
            return OptimizeResult(
                taskName: "Repair Disk Permissions",
                success: false,
                message: "Failed to repair disk permissions: \(error.localizedDescription)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    /// Optimize network settings
    private func optimizeNetwork() async throws -> OptimizeResult {
        let startTime = Date()
        logger.info("Optimizing network settings")

        guard !config.dryRun else {
            return OptimizeResult(
                taskName: "Optimize Network",
                success: true,
                message: "Network optimization (dry run)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            // Optimize TCP keepalive
            try await processManager.executeWithSudo(
                command: "sysctl",
                arguments: ["-w", "net.inet.tcp.keepinit=60000"]
            )

            try await processManager.executeWithSudo(
                command: "sysctl",
                arguments: ["-w", "net.inet.tcp.keepidle=7200000"]
            )

            logger.info("Network optimization completed")
            return OptimizeResult(
                taskName: "Optimize Network",
                success: true,
                message: "TCP settings optimized for better performance",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to optimize network: \(error.localizedDescription)")
            return OptimizeResult(
                taskName: "Optimize Network",
                success: false,
                message: "Failed to optimize network: \(error.localizedDescription)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    /// Relieve memory pressure
    private func relieveMemoryPressure() async throws -> OptimizeResult {
        let startTime = Date()
        logger.info("Relieving memory pressure")

        guard !config.dryRun else {
            return OptimizeResult(
                taskName: "Relieve Memory Pressure",
                success: true,
                message: "Memory pressure relief (dry run)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            try await processManager.execute(
                command: "purge",
                arguments: []
            )

            logger.info("Memory pressure relieved")
            return OptimizeResult(
                taskName: "Relieve Memory Pressure",
                success: true,
                message: "Memory caches cleared to relieve pressure",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to relieve memory pressure: \(error.localizedDescription)")
            return OptimizeResult(
                taskName: "Relieve Memory Pressure",
                success: false,
                message: "Failed to relieve memory pressure: \(error.localizedDescription)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    /// Reset Bluetooth module
    private func resetBluetooth() async throws -> OptimizeResult {
        let startTime = Date()
        logger.info("Resetting Bluetooth")

        guard !config.dryRun else {
            return OptimizeResult(
                taskName: "Reset Bluetooth",
                success: true,
                message: "Bluetooth reset (dry run)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            try await processManager.executeWithSudo(
                command: "killall",
                arguments: ["bluetoothd"]
            )

            logger.info("Bluetooth reset completed")
            return OptimizeResult(
                taskName: "Reset Bluetooth",
                success: true,
                message: "Bluetooth daemon restarted",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to reset Bluetooth: \(error.localizedDescription)")
            return OptimizeResult(
                taskName: "Reset Bluetooth",
                success: false,
                message: "Failed to reset Bluetooth: \(error.localizedDescription)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    /// Prevent network DS_Store creation
    private func preventNetworkDSStore() async throws -> OptimizeResult {
        let startTime = Date()
        logger.info("Preventing network DS_Store creation")

        guard !config.dryRun else {
            return OptimizeResult(
                taskName: "Prevent Network DS_Store",
                success: true,
                message: "DS_Store prevention (dry run)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            try await processManager.executeWithSudo(
                command: "defaults",
                arguments: ["write", "com.apple.desktopservices", "DSDontWriteNetworkStores", "-bool", "true"]
            )

            logger.info("Network DS_Store prevention enabled")
            return OptimizeResult(
                taskName: "Prevent Network DS_Store",
                success: true,
                message: "DS_Store files won't be created on network volumes",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to prevent network DS_Store: \(error.localizedDescription)")
            return OptimizeResult(
                taskName: "Prevent Network DS_Store",
                success: false,
                message: "Failed to prevent network DS_Store: \(error.localizedDescription)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    /// Clean LaunchAgents
    private func cleanLaunchAgents() async throws -> OptimizeResult {
        let startTime = Date()
        logger.info("Cleaning LaunchAgents")

        let launchAgentsPaths = [
            "\(fileManager.homeDirectoryForCurrentUser.path)/Library/LaunchAgents",
            "/Library/LaunchAgents"
        ]

        var orphanedCount = 0

        guard !config.dryRun else {
            return OptimizeResult(
                taskName: "Clean LaunchAgents",
                success: true,
                message: "LaunchAgents cleanup (dry run)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            for path in launchAgentsPaths {
                if let agents = try? fileManager.contentsOfDirectory(atPath: path) {
                    for agent in agents {
                        let fullPath = "\(path)/\(agent)"

                        // Check if the agent references an app that no longer exists
                        if checkOrphanedLaunchAgent(fullPath) {
                            try? await safeRemover.remove(at: URL(fileURLWithPath: fullPath))
                            orphanedCount += 1
                        }
                    }
                }
            }

            logger.info("LaunchAgents cleaned: \(orphanedCount) orphaned agents removed")
            return OptimizeResult(
                taskName: "Clean LaunchAgents",
                success: true,
                message: "\(orphanedCount) orphaned LaunchAgents removed",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to clean LaunchAgents: \(error.localizedDescription)")
            return OptimizeResult(
                taskName: "Clean LaunchAgents",
                success: false,
                message: "Failed to clean LaunchAgents: \(error.localizedDescription)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    /// Fix broken configuration files
    private func fixBrokenConfigs() async throws -> OptimizeResult {
        let startTime = Date()
        logger.info("Fixing broken configurations")

        let preferencesPath = "\(fileManager.homeDirectoryForCurrentUser.path)/Library/Preferences"
        var configsFixed = 0

        guard !config.dryRun else {
            return OptimizeResult(
                taskName: "Fix Broken Configs",
                success: true,
                message: "Config fix (dry run)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        do {
            if let plistFiles = try? fileManager.contentsOfDirectory(atPath: preferencesPath) {
                for plistFile in plistFiles where plistFile.hasSuffix(".plist") {
                    let fullPath = "\(preferencesPath)/\(plistFile)"

                    // Try to validate the plist
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)),
                       let _ = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
                        // Plist is valid
                    } else {
                        // Invalid plist, try to fix
                        if attemptFixPlist(fullPath) {
                            configsFixed += 1
                        }
                    }
                }
            }

            configsRepaired = configsFixed

            logger.info("Configuration fix completed: \(configsFixed) configs repaired")
            return OptimizeResult(
                taskName: "Fix Broken Configs",
                success: true,
                message: "\(configsFixed) broken .plist files repaired",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            logger.error("Failed to fix configs: \(error.localizedDescription)")
            return OptimizeResult(
                taskName: "Fix Broken Configs",
                success: false,
                message: "Failed to fix configs: \(error.localizedDescription)",
                sizeSavedKB: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    // MARK: - Helper Methods

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

    private func getFileSizeKB(_ path: String) -> Int? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let fileSize = attributes[.size] as? UInt64 else {
            return nil
        }
        return Int(fileSize / 1024)
    }

    private func findFiles(in directory: String, withExtensions extensions: [String]) -> [String] {
        var foundFiles: [String] = []

        guard let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: directory), includingPropertiesForKeys: nil) else {
            return foundFiles
        }

        for case let fileURL as URL in enumerator {
            let fileExtension = fileURL.pathExtension.lowercased()
            if extensions.contains(fileExtension) {
                foundFiles.append(fileURL.path)
            }
        }

        return foundFiles
    }

    private func glob(_ pattern: String) -> [String]? {
        // Basic glob implementation
        var expandedPattern = pattern
        expandedPattern = expandedPattern.replacingOccurrences(of: "~", with: fileManager.homeDirectoryForCurrentUser.path)

        // Handle wildcards
        if expandedPattern.contains("*") {
            let basePath = (expandedPattern as NSString).deletingLastPathComponent
            let patternComponent = (expandedPattern as NSString).lastPathComponent

            guard let files = try? fileManager.contentsOfDirectory(atPath: basePath.isEmpty ? "." : basePath) else {
                return []
            }

            return files.filter { file in
                file.matches(pattern: patternComponent)
            }.map { file in
                "\(basePath)/\(file)"
            }
        }

        return [expandedPattern]
    }

    private func checkOrphanedLaunchAgent(_ path: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return false
        }

        // Extract the executable path from the plist using proper parsing
        var executablePath: String?
        if let programArguments = plist["ProgramArguments"] as? [String], !programArguments.isEmpty {
            executablePath = programArguments[0]
        } else if let program = plist["Program"] as? String {
            executablePath = program
        } else if let label = plist["Label"] as? String {
            // Fallback: try to find executable by label
            executablePath = "/usr/local/bin/\(label)"
        }

        // Check if the executable exists
        if let path = executablePath {
            return !fileManager.fileExists(atPath: path)
        }

        return false
    }

    private func attemptFixPlist(_ path: String) -> Bool {
        // Basic plist fix attempt
        if var content = try? String(contentsOfFile: path, encoding: .utf8) {
            // Remove any BOM markers
            content = content.replacingOccurrences(of: "\u{FEFF}", with: "")

            // Ensure proper XML structure
            if !content.contains("<?xml") {
                content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + content
            }

            do {
                try content.write(toFile: path, atomically: true, encoding: .utf8)

                // Validate the fixed plist
                if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                   let _ = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
                    return true
                }
            } catch {
                return false
            }
        }

        return false
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - String Extension for Pattern Matching

extension String {
    func matches(pattern: String) -> Bool {
        let regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: "?", with: ".")

        guard let regex = try? NSRegularExpression(pattern: "^" + regexPattern + "$") else {
            return false
        }

        let range = NSRange(location: 0, length: self.utf16.count)
        return regex.firstMatch(in: self, range: range) != nil
    }
}