import Foundation

@MainActor
final class StewardRuntime: ObservableObject {
    static let shared = StewardRuntime()

    @Published var isCleaning = false
    @Published var isOptimizing = false
    @Published var isScanningApps = false
    @Published var cleanReport: CleanReport?
    @Published var optimizeReport: OptimizeReport?
    @Published var uninstallResult: UninstallResult?
    @Published var errorMessage = ""

    private let cleanConfig = CleanEngineConfiguration.default
    private lazy var pathValidator = PathValidator()
    private lazy var whitelistManager = WhitelistManager()
    private lazy var protectionManager = ProtectionManager()

    private init() {}

    // MARK: - Clean Operations

    func scanCleanTargets() async -> [CleanScanResult] {
        isCleaning = true
        defer { isCleaning = false }

        do {
            let safeRemover = SafeRemover()
            let projectCleaner = ProjectCleaner(
                configuration: cleanConfig,
                safeRemover: safeRemover,
                pathValidator: pathValidator,
                whitelistManager: whitelistManager,
                protectionManager: protectionManager
            )
            let devToolsCleaner = DevToolsCleaner(
                configuration: cleanConfig,
                safeRemover: safeRemover,
                pathValidator: pathValidator,
                whitelistManager: whitelistManager,
                protectionManager: protectionManager
            )
            let hintEngine = HintEngine(
                configuration: cleanConfig,
                pathValidator: pathValidator,
                whitelistManager: whitelistManager
            )

            var allItems: [CleanItem] = []
            allItems.append(contentsOf: await projectCleaner.scanAllProjectArtifacts())
            allItems.append(contentsOf: await devToolsCleaner.scanAllDevTools())
            _ = await hintEngine.generateAllHints()

            return CleanAdapter.toScanResults(allItems)
        }
    }

    func cleanItems(_ items: [CleanItem]) async -> CleanReport {
        isCleaning = true
        defer { isCleaning = false }

        let safeRemover = SafeRemover()
        let results = await safeRemover.batchRemove(items)
        let report = CleanAdapter.toReport(results)
        cleanReport = report
        return report
    }

    // MARK: - Uninstall Operations

    func scanApplications() async -> [AppItem] {
        isScanningApps = true
        defer { isScanningApps = false }

        do {
            let engine = UninstallEngine()
            let apps = try await engine.listApps()
            return AppAdapter.convert(apps)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func uninstallApp(_ item: AppItem, removeResiduals: Bool = true) async -> UninstallResult? {
        guard let appInfo = AppAdapter.convert(item) else { return nil }

        do {
            let engine = UninstallEngine()
            let residuals = removeResiduals
                ? (try await engine.findResidualFiles(bundleId: appInfo.id, appName: appInfo.name))
                : []
            let result = try await engine.uninstallApp(appInfo, residuals: residuals)
            uninstallResult = result
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Optimize Operations

    func runOptimizations() async -> OptimizeReport {
        isOptimizing = true
        defer { isOptimizing = false }

        do {
            let engine = OptimizeEngine()
            let results = try await engine.runAllOptimizations()
            let report = OptimizeAdapter.toReport(results)
            optimizeReport = report
            return report
        } catch {
            errorMessage = error.localizedDescription
            return OptimizeReport(
                results: [],
                successCount: 0,
                failureCount: 1,
                totalSpaceSavedKB: 0,
                executionTime: 0
            )
        }
    }

    func runOptimizations(dryRun: Bool) async -> OptimizeReport {
        isOptimizing = true
        defer { isOptimizing = false }

        do {
            let engine = OptimizeEngine()
            await engine.configure(OptimizeEngine.OptimizeConfig(
                dryRun: dryRun,
                requireSudo: false,
                maxDatabaseSize: 104857600,
                sqliteMaxSize: 104857600
            ))
            let results = try await engine.runAllOptimizations()
            let report = OptimizeAdapter.toReport(results)
            optimizeReport = report
            return report
        } catch {
            errorMessage = error.localizedDescription
            return OptimizeReport(
                results: [],
                successCount: 0,
                failureCount: 1,
                totalSpaceSavedKB: 0,
                executionTime: 0
            )
        }
    }
}
