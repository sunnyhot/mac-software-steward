import Foundation

// MARK: - Main Uninstall Engine
actor UninstallEngine {

    // MARK: - Dependencies
    private let appDiscovery = AppDiscovery()
    private let residualScanner = ResidualScanner()
    private let batchUninstaller = BatchUninstaller()
    private let safeRemover = SafeRemover()

    // MARK: - Cache Management
    private var metadataCache: AppMetadataCache?
    private var cacheLoadTime: Date?

    // MARK: - Public Methods

    /// Scan for all applications
    func scanApplications() async throws -> [AppInfo] {
        let apps = try await appDiscovery.scanApplications()

        // Update cache in background
        Task {
            await updateMetadataCache(for: apps)
        }

        return apps
    }

    /// Find residual files for a given bundle ID
    func findResidualFiles(bundleId: String, appName: String) async throws -> [ResidualFile] {
        return try await residualScanner.findResidualFiles(bundleId: bundleId, appName: appName)
    }

    /// Uninstall an application
    func uninstallApp(_ app: AppInfo, residuals: [ResidualFile]) async throws -> UninstallResult {
        // Check if app is system critical
        if await safeRemover.isSystemCritical(bundleId: app.id) {
            throw UninstallError.systemAppCannotBeUninstalled(app.name)
        }

        // Check if app is a system app
        if app.isSystemApp {
            throw UninstallError.systemAppCannotBeUninstalled(app.name)
        }

        return try await batchUninstaller.uninstallApp(app, residuals: residuals)
    }

    /// List all applications
    func listApps() async throws -> [AppInfo] {
        let apps = try await scanApplications()

        // Sort by name for display
        return apps.sorted { $0.name < $1.name }
    }

    /// Get application by bundle ID
    func getApp(byBundleId bundleId: String) async throws -> AppInfo? {
        let apps = try await scanApplications()

        return apps.first { $0.id == bundleId }
    }

    /// Search applications by name
    func searchApps(byName name: String) async throws -> [AppInfo] {
        let apps = try await scanApplications()

        return apps.filter { $0.name.localizedCaseInsensitiveContains(name) }
    }

    /// Get metadata from cache
    func getMetadataFromCache() async -> AppMetadataCache? {
        // Refresh cache if too old or not loaded
        if let cache = metadataCache,
           let loadTime = cacheLoadTime,
           Date().timeIntervalSince(loadTime) < 60 { // Cache for 1 minute in memory
            return cache
        }

        // Try to load from disk
        if let diskCache = await appDiscovery.loadCachedMetadata() {
            metadataCache = diskCache
            cacheLoadTime = Date()
            return diskCache
        }

        return nil
    }

    /// Force refresh metadata cache
    func refreshMetadataCache() async throws {
        let apps = try await scanApplications()
        await updateMetadataCache(for: apps)
    }

    // MARK: - Private Methods

    private func updateMetadataCache(for apps: [AppInfo]) async {
        var cachedApps: [CachedAppMetadata] = []

        for app in apps {
            let metadata = await appDiscovery.collectMetadata(for: app.path)

            let cachedApp = CachedAppMetadata(
                bundleId: app.id,
                path: app.path.path,
                size: metadata.size,
                lastUsed: metadata.lastUsed,
                scanTime: metadata.scanTime
            )

            cachedApps.append(cachedApp)
        }

        do {
            try await appDiscovery.saveMetadataToCache(cachedApps)

            // Update in-memory cache
            metadataCache = AppMetadataCache(
                apps: cachedApps,
                timestamp: Date(),
                version: AppMetadataCache.currentVersion
            )
            cacheLoadTime = Date()
        } catch {
            // Silently fail cache updates
        }
    }
}

// MARK: - Public API Extensions
extension UninstallEngine {

    /// Get statistics about installed applications
    func getApplicationStats() async throws -> AppStats {
        let apps = try await scanApplications()

        let totalCount = apps.count
        let brewCaskCount = apps.filter { $0.isBrewCask }.count
        let systemAppCount = apps.filter { $0.isSystemApp }.count
        let backgroundAppCount = apps.filter { $0.isBackgroundOnly }.count

        let totalSize = apps.reduce(Int64(0)) { $0 + $1.size }

        let recentApps = apps.filter { app in
            guard let lastUsed = app.lastUsed else { return false }
            let daysSinceLastUse = Date().timeIntervalSince(lastUsed) / (24 * 60 * 60)
            return daysSinceLastUse <= 30
        }.count

        return AppStats(
            totalApps: totalCount,
            brewCaskApps: brewCaskCount,
            systemApps: systemAppCount,
            backgroundApps: backgroundAppCount,
            recentApps: recentApps,
            totalSize: totalSize
        )
    }

    /// Get applications sorted by size
    func getAppsBySize() async throws -> [AppInfo] {
        let apps = try await scanApplications()
        return apps.sorted { $0.size > $1.size }
    }

    /// Get applications sorted by last used date
    func getAppsByLastUsed() async throws -> [AppInfo] {
        let apps = try await scanApplications()
        return apps.sorted { (app1, app2) in
            guard let date1 = app1.lastUsed else { return false }
            guard let date2 = app2.lastUsed else { return true }
            return date1 > date2
        }
    }

    /// Get large applications (over 1GB)
    func getLargeApps(sizeThresholdGB: Double = 1.0) async throws -> [AppInfo] {
        let apps = try await scanApplications()
        let threshold = Int64(sizeThresholdGB * 1024 * 1024 * 1024)
        return apps.filter { $0.size >= threshold }.sorted { $0.size > $1.size }
    }

    /// Get unused applications (not used in over 90 days)
    func getUnusedApps(daysThreshold: Int = 90) async throws -> [AppInfo] {
        let apps = try await scanApplications()
        let threshold = TimeInterval(daysThreshold * 24 * 60 * 60)

        return apps.filter { app in
            guard let lastUsed = app.lastUsed else { return true }
            let daysSinceLastUse = Date().timeIntervalSince(lastUsed)
            return daysSinceLastUse >= threshold
        }.sorted { (app1, app2) in
            guard let date1 = app1.lastUsed else { return false }
            guard let date2 = app2.lastUsed else { return true }
            return date1 < date2
        }
    }

    /// Batch uninstall multiple applications with safety checks
    func batchUninstall(_ apps: [AppInfo], dryRun: Bool = false) async throws -> [UninstallResult] {
        var results: [UninstallResult] = []

        // Safety check: don't allow batch uninstall of system apps
        var safeApps: [AppInfo] = []
        for app in apps {
            let isSystemCritical = await safeRemover.isSystemCritical(bundleId: app.id)
            if !app.isSystemApp && !isSystemCritical {
                safeApps.append(app)
            }
        }

        if safeApps.count != apps.count {
            throw UninstallError.systemAppCannotBeUninstalled("Some apps in the batch are system-protected")
        }

        return try await batchUninstaller.batchUninstall(safeApps, dryRun: dryRun)
    }
}

// MARK: - Supporting Types
struct AppStats {
    let totalApps: Int
    let brewCaskApps: Int
    let systemApps: Int
    let backgroundApps: Int
    let recentApps: Int
    let totalSize: Int64

    var totalSizeGB: Double {
        Double(totalSize) / (1024 * 1024 * 1024)
    }
}

// MARK: - Convenience Extensions
extension UninstallEngine {

    /// Quick uninstall by bundle ID
    func quickUninstall(bundleId: String) async throws -> UninstallResult {
        guard let app = try await getApp(byBundleId: bundleId) else {
            throw UninstallError.appNotFound(bundleId)
        }

        let residuals = try await findResidualFiles(bundleId: bundleId, appName: app.name)
        return try await uninstallApp(app, residuals: residuals)
    }

    /// Analyze potential residuals before uninstall
    func analyzeResiduals(for bundleId: String, appName: String) async throws -> ResidualAnalysis {
        let residuals = try await findResidualFiles(bundleId: bundleId, appName: appName)

        let totalSize = residuals.reduce(Int64(0)) { $0 + $1.size }
        let fileCount = residuals.count

        let byCategory = Dictionary(grouping: residuals, by: { $0.category })
            .mapValues { $0.reduce(Int64(0)) { $0 + $1.size } }

        let byRiskLevel = Dictionary(grouping: residuals, by: { $0.riskLevel })
            .mapValues { $0.reduce(Int64(0)) { $0 + $1.size } }

        return ResidualAnalysis(
            totalFiles: fileCount,
            totalSize: totalSize,
            byCategory: byCategory,
            byRiskLevel: byRiskLevel
        )
    }
}

struct ResidualAnalysis {
    let totalFiles: Int
    let totalSize: Int64
    let byCategory: [ResidualFile.ResidualCategory: Int64]
    let byRiskLevel: [ResidualFile.RiskLevel: Int64]

    var totalSizeGB: Double {
        Double(totalSize) / (1024 * 1024 * 1024)
    }
}