import Foundation

@MainActor
final class DelayedScanner: SoftwareScanning {
    private(set) var callCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func scanAll(
        includeGreedy: Bool,
        regularAppNetworkPolicy: RegularAppNetworkPolicy,
        onPhaseChange: ((ScanPhase) -> Void)?
    ) async -> ScanResult {
        callCount += 1
        onPhaseChange?(.brewInfo)
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: includeGreedy,
            summary: ScanSummary(applications: 0, brewFormulae: 0, brewCasks: 0, masApps: 0, outdated: 0, actionable: 0, scanMs: 1),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
            brew: BrewScan(available: false, path: "", prefix: "", version: "", error: "", includeGreedy: includeGreedy, formulae: [], casks: []),
            mas: MasScan(available: false, path: "", error: "", apps: [])
        )
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class StaticScanner: SoftwareScanning {
    private let result: ScanResult

    init(result: ScanResult) {
        self.result = result
    }

    func scanAll(
        includeGreedy: Bool,
        regularAppNetworkPolicy: RegularAppNetworkPolicy,
        onPhaseChange: ((ScanPhase) -> Void)?
    ) async -> ScanResult {
        onPhaseChange?(.systemProfiler)
        return result
    }
}

@MainActor
final class RecordingNotificationDispatcher: AutomationNotificationDelivering {
    private(set) var decisions: [AutomationNotificationDecision] = []

    func deliver(_ decision: AutomationNotificationDecision) async {
        decisions.append(decision)
    }
}

@main
struct StewardModelScanGuardTest {
    @MainActor
    static func main() async throws {
        UserDefaults.standard.removeObject(forKey: "maxConcurrentUpgrades")
        precondition(JobRescanPolicy.shouldRescanAfterJobCompletion(rescanAfterSuccess: true, status: .succeeded))
        precondition(JobRescanPolicy.shouldRescanAfterJobCompletion(rescanAfterSuccess: true, status: .failed))
        precondition(!JobRescanPolicy.shouldRescanAfterJobCompletion(rescanAfterSuccess: true, status: .cancelled), "Cancelled upgrade jobs must not trigger an automatic rescan")
        precondition(!JobRescanPolicy.shouldRescanAfterJobCompletion(rescanAfterSuccess: true, status: .timedOut), "Timed-out upgrade jobs must not trigger an automatic rescan")
        precondition(!JobRescanPolicy.shouldRescanAfterJobCompletion(rescanAfterSuccess: false, status: .succeeded))

        let scanner = DelayedScanner()
        let model = StewardModel(scanner: scanner)
        let inboxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recovery-inbox-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: inboxURL) }
        let inboxStore = InboxStore(fileURL: inboxURL)
        model.packageProgress["brew:cask:broken"] = PackageUpgradeProgress(
            packageID: "brew:cask:broken",
            packageName: "Broken",
            status: .failed,
            detail: "下载失败",
            failureSummary: "下载失败",
            recoverySuggestion: "请重试。",
            recoveryAction: .retry,
            lastFailedCommand: "brew upgrade --cask broken"
        )
        model.publishFailureRecoveryItems(to: inboxStore, packageIDs: ["brew:cask:broken"])
        precondition(inboxStore.pendingItems.count == 1)
        precondition(inboxStore.pendingItems[0].kind == .failureRecovery)
        precondition(inboxStore.pendingItems[0].actions.map(\.kind).contains(.retryPackage))

        let repairScanner = DelayedScanner()
        let repairModel = StewardModel(scanner: repairScanner)
        repairModel.packageProgress["brew:formula:missing"] = PackageUpgradeProgress(
            packageID: "brew:formula:missing",
            packageName: "missing",
            status: .failed,
            detail: "所需的文件或工具未找到。",
            failureSummary: "所需的文件或工具未找到。",
            recoverySuggestion: "请点击「重新扫描」刷新软件列表后再试。",
            recoveryAction: .rescan
        )
        var autoRepairProfile = AutomationProfile.manualDefault
        autoRepairProfile.advancedModeEnabled = true
        autoRepairProfile.autoRepairPolicy = .allowLowRisk

        let repairTask = Task {
            await repairModel.performAutomaticRepairIfAllowed(
                profile: autoRepairProfile,
                inboxStore: inboxStore,
                packageIDs: ["brew:formula:missing"]
            )
        }
        while repairScanner.callCount == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        repairScanner.finish()
        let repairedPackageIDs = await repairTask.value
        precondition(repairedPackageIDs == ["brew:formula:missing"])

        let secondRepair = await repairModel.performAutomaticRepairIfAllowed(
            profile: autoRepairProfile,
            inboxStore: inboxStore,
            packageIDs: ["brew:formula:missing"]
        )
        precondition(secondRepair.isEmpty)
        precondition(repairScanner.callCount == 1)

        let sparkleApp = AppItem(
            id: "sparkle",
            name: "Sparkle",
            version: "1.0",
            availableVersion: "",
            path: "/tmp/Sparkle.app",
            source: "Third Party",
            obtainedFrom: "",
            architecture: "arm64",
            managedBy: "manual",
            updateState: "checkable",
            relatedPackageID: "",
            updateCapability: AppUpdateCapability(
                detector: .sparkle,
                confidence: .high,
                feedURLString: "",
                installedVersion: "1.0",
                summary: "可通过 Sparkle 检查更新",
                actions: [AppUpdateAction(kind: .openUpdater, title: "打开更新器", systemImage: "arrow.down.app")],
                diagnostic: ""
            )
        )

        model.performUpdateAction(sparkleApp.updateCapability.actions[0], for: sparkleApp)
        precondition(model.errorMessage == "未找到 Sparkle 更新器。")

        let executableFormula = BrewPackage(
            id: "brew:formula:jq",
            kind: "formula",
            name: "jq",
            installedVersion: "1.6",
            currentVersion: "1.7",
            pinned: false,
            autoUpdates: false,
            outdated: true,
            upgradeable: true
        )
        let manualCask = BrewPackage(
            id: "brew:cask:clash-party",
            kind: "cask",
            name: "clash-party",
            installedVersion: "1.9.6",
            currentVersion: "2.0.0",
            pinned: false,
            autoUpdates: true,
            outdated: true,
            upgradeable: false,
            manualUpdateOnly: true
        )
        let manualCaskModel = StewardModel(scanner: StaticScanner(result: ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: false,
            summary: ScanSummary(applications: 0, brewFormulae: 1, brewCasks: 1, masApps: 0, outdated: 2, actionable: 1, scanMs: 1),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
            brew: BrewScan(
                available: true,
                path: "/opt/homebrew/bin/brew",
                prefix: "/opt/homebrew",
                version: "Homebrew 5",
                error: "",
                includeGreedy: false,
                formulae: [executableFormula],
                casks: [manualCask]
            ),
            mas: MasScan(available: false, path: "", error: "", apps: [])
        )))
        await manualCaskModel.scanSoftware()
        precondition(manualCaskModel.allUpgradeablePackages.map(\.id) == [executableFormula.id, manualCask.id])
        precondition(manualCaskModel.availableUpdates.map(\.id) == [executableFormula.id])

        let directReplacementWorkDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("direct-replacement-download-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directReplacementWorkDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directReplacementWorkDirectory) }

        let acceleratedStrategies = [
            DownloadAccelerationStrategy(kind: .inheritedProxy, proxyURLString: "http://127.0.0.1:7890"),
            DownloadAccelerationStrategy(kind: .direct, proxyURLString: nil)
        ]
        let acceleratedSource = FileManager.default.temporaryDirectory
            .appendingPathComponent("direct-replacement-source-\(UUID().uuidString).zip")
        var directReplacementAttempts: [String] = []
        let directReplacementModel = StewardModel(
            scanner: StaticScanner(result: appUpdateScanResult()),
            downloadStrategiesProvider: { acceleratedStrategies },
            acceleratedDownloadRunner: { attempt, _ in
                directReplacementAttempts.append(attempt.strategy.title)
                if attempt.index == 0 {
                    throw AcceleratedDownloadError.retryable("模拟慢下载")
                }
                try Data("replacement".utf8).write(to: acceleratedSource)
                return acceleratedSource
            }
        )

        let directReplacementArchive = try await directReplacementModel.downloadManualReplacement(
            from: URL(string: "https://example.com/TestApp.zip")!,
            into: directReplacementWorkDirectory
        )
        let directReplacementText = try String(contentsOf: directReplacementArchive, encoding: .utf8)
        precondition(directReplacementAttempts == ["环境代理", "直连"], "Unexpected direct replacement attempts: \(directReplacementAttempts)")
        precondition(directReplacementArchive.lastPathComponent == "TestApp.zip")
        precondition(directReplacementText == "replacement")

        let notificationDispatcher = RecordingNotificationDispatcher()
        let notificationModel = StewardModel(
            scanner: StaticScanner(result: appUpdateScanResult()),
            notificationDispatcher: notificationDispatcher
        )
        let notificationInboxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notification-inbox-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: notificationInboxURL) }
        let notificationInboxStore = InboxStore(fileURL: notificationInboxURL)

        await notificationModel.scanSoftware(
            notificationPolicy: .decisionsAndFailures,
            inboxStore: notificationInboxStore
        )
        precondition(notificationDispatcher.decisions.map(\.title) == ["有 3 项需要处理"])
        precondition(notificationInboxStore.items.filter { $0.kind == .sourceIssue }.count == 2)
        precondition(notificationInboxStore.items.contains { $0.kind == .appUpdate })
        precondition(notificationInboxStore.items.contains { $0.sourceID == "source:homebrew" })
        precondition(notificationInboxStore.items.contains { $0.sourceID == "source:mas" })

        let performanceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-performance-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: performanceURL) }
        let performanceStore = ScanPerformanceStore(fileURL: performanceURL, limit: 10)
        let performanceSnapshot = ScanPerformanceSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
            scannedAt: Date(timeIntervalSince1970: 11),
            includeGreedy: false,
            stages: [
                ScanPerformanceStage(phase: .applications, durationMs: 20),
                ScanPerformanceStage(phase: .brew, durationMs: 10),
                ScanPerformanceStage(phase: .total, durationMs: 40)
            ],
            applications: 1,
            brewFormulae: 0,
            brewCasks: 0,
            masApps: 0,
            outdated: 1,
            actionable: 0,
            applicationsSource: "test",
            brewAvailable: false,
            masAvailable: false
        )
        var performanceResult = appUpdateScanResult()
        performanceResult.performance = performanceSnapshot
        let performanceModel = StewardModel(
            scanner: StaticScanner(result: performanceResult),
            scanPerformanceStore: performanceStore
        )
        await performanceModel.scanSoftware()
        precondition(performanceStore.records.map(\.id) == [performanceSnapshot.id])

        await notificationModel.scanSoftware(
            notificationPolicy: .decisionsAndFailures,
            inboxStore: notificationInboxStore
        )
        precondition(notificationDispatcher.decisions.count == 1)

        let first = Task { await model.scanSoftware() }

        while scanner.callCount == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }

        await model.scanSoftware()

        let callsWhileRunning = scanner.callCount
        precondition(callsWhileRunning == 1, "Expected duplicate scan call to be ignored, got \(callsWhileRunning)")

        scanner.finish()
        await first.value

        precondition(model.isScanning == false, "Expected scan flag to reset after completion")

        // 失败孤儿可见性：升级失败后重新扫描，包已不在可升级集合里，但失败记录仍残留。
        // 这种孤儿会让顶部状态横幅计数与升级列表对不上。orphanedFailedProgresses 必须把它暴露出来。
        let orphanScanner = StaticScanner(result: ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: false,
            summary: ScanSummary(applications: 0, brewFormulae: 0, brewCasks: 0, masApps: 0, outdated: 0, actionable: 0, scanMs: 1),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
            brew: BrewScan(available: true, path: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew", version: "Homebrew 5", error: "", includeGreedy: false, formulae: [], casks: []),
            mas: MasScan(available: false, path: "", error: "", apps: [])
        ))
        let orphanModel = StewardModel(scanner: orphanScanner)
        await orphanModel.scanSoftware()
        precondition(orphanModel.allUpgradeablePackages.isEmpty, "Empty scan should produce no upgradeable packages")

        let orphanProgress = PackageUpgradeProgress(
            packageID: "brew:formula:ghost",
            packageName: "ghost",
            status: .failed,
            detail: "升级失败",
            failureSummary: "升级失败",
            recoverySuggestion: "请重试。",
            recoveryAction: .retry,
            lastFailedCommand: "brew upgrade ghost"
        )
        orphanModel.packageProgress[orphanProgress.packageID] = orphanProgress
        precondition(orphanModel.orphanedFailedProgresses.map(\.packageID) == [orphanProgress.packageID], "Failed progress for a package no longer in scan must surface as orphan")
        precondition(orphanModel.allUpgradeablePackages.isEmpty, "Orphan must not leak into the upgradeable list")

        // 失败包重新出现在扫描中时，不再是孤儿：它回到 allUpgradeablePackages，不再算进 orphanedFailedProgresses。
        let ghostPackage = BrewPackage(
            id: orphanProgress.packageID,
            kind: "formula",
            name: "ghost",
            installedVersion: "1.0",
            currentVersion: "2.0",
            pinned: false,
            autoUpdates: false,
            outdated: true,
            upgradeable: true
        )
        let ghostRescannedModel = StewardModel(scanner: StaticScanner(result: ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: false,
            summary: ScanSummary(applications: 0, brewFormulae: 1, brewCasks: 0, masApps: 0, outdated: 1, actionable: 1, scanMs: 1),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
            brew: BrewScan(available: true, path: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew", version: "Homebrew 5", error: "", includeGreedy: false, formulae: [ghostPackage], casks: []),
            mas: MasScan(available: false, path: "", error: "", apps: [])
        )))
        ghostRescannedModel.packageProgress[orphanProgress.packageID] = orphanProgress
        await ghostRescannedModel.scanSoftware()
        precondition(ghostRescannedModel.allUpgradeablePackages.map(\.id) == [ghostPackage.id])
        precondition(ghostRescannedModel.orphanedFailedProgresses.isEmpty, "A failed package that reappears in scan must not be treated as orphan")

        // clearPackageFailure 必须把孤儿从 packageProgress 中移除。
        orphanModel.clearPackageFailure(orphanProgress.packageID)
        precondition(orphanModel.orphanedFailedProgresses.isEmpty, "clearPackageFailure must remove the orphan")
        precondition(orphanModel.packageProgress[orphanProgress.packageID] == nil)

        // 非 failed 状态（成功/排队/运行中）不应被算作孤儿。
        for nonFailureStatus in [PackageUpgradeStatus.succeeded, .queued, .running, .warning] {
            let nonFailureModel = StewardModel(scanner: orphanScanner)
            nonFailureModel.packageProgress["brew:formula:other"] = PackageUpgradeProgress(
                packageID: "brew:formula:other",
                packageName: "other",
                status: nonFailureStatus,
                detail: ""
            )
            precondition(nonFailureModel.orphanedFailedProgresses.isEmpty, "\(nonFailureStatus.rawValue) must not count as orphan")
        }
    }

    private static func appUpdateScanResult() -> ScanResult {
        let app = AppItem(
            id: "app:/Applications/Sparkle.app",
            name: "Sparkle",
            version: "1.0",
            availableVersion: "2.0",
            path: "/Applications/Sparkle.app",
            source: "Developer",
            obtainedFrom: "Identified Developer",
            architecture: "arm64",
            managedBy: "manual",
            updateState: "outdated",
            relatedPackageID: "",
            updateCapability: AppUpdateCapability(
                detector: .sparkle,
                confidence: .high,
                feedURLString: "https://example.com/appcast.xml",
                installedVersion: "1.0",
                summary: "Sparkle 发现新版本 2.0",
                actions: [AppUpdateAction(kind: .openUpdater, title: "打开更新器", systemImage: "arrow.down.app")],
                diagnostic: "ok"
            )
        )

        return ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: false,
            summary: ScanSummary(applications: 1, brewFormulae: 0, brewCasks: 0, masApps: 0, outdated: 1, actionable: 0, scanMs: 1),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: [app]),
            brew: BrewScan(available: false, path: "", prefix: "", version: "", error: "", includeGreedy: false, formulae: [], casks: []),
            mas: MasScan(available: false, path: "", error: "", apps: [])
        )
    }
}
