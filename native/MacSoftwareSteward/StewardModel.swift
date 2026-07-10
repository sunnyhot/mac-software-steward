import AppKit
import Combine
import Foundation

@MainActor
final class StewardModel: ObservableObject, MaintenanceExecutorHost {
    @Published var selectedTab: AppTab = .applications
    @Published var scan: ScanResult?
    @Published var isScanning = false
    @Published var scanPhase: ScanPhase?
    @Published var includeGreedy = true
    @Published var runBrewUpdate = true
    @Published var debouncedQuery = ""
    @Published var query = "" {
        didSet {
            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                self.debouncedQuery = self.query
            }
        }
    }
    @Published var errorMessage = ""

    @Published var dailyInspectionEnabled = false
    @Published var dailyHour = 9
    @Published var dailyMinute = 0
    @Published var dailyLog = ""
    @Published var dailyLaunchAgentPath = DailyInspectionScheduler.launchAgentURL.path
    @Published var dailyLogPath = DailyInspectionScheduler.logURL.path
    @Published var upgradePlanRows: [UpgradePlanRow] = []
    @Published var selectedPlanIDs: Set<String> = []
    @Published var showingUpgradePlan = false
    @Published var isConfirmingUpgradePlan = false

    let policyStore = UpgradePolicyStore()
    let historyStore: UpgradeHistoryStore
    let inspectionReportStore = InspectionReportStore()
    let scanPerformanceStore: ScanPerformanceStore

    /// 执行引擎。jobs / packageProgress / upgradeProgress / maxConcurrentUpgrades 的
    /// 真实状态由 executor 持有；StewardModel 通过下面的转发属性暴露给现有 UI。
    let executor: MaintenanceExecutor

    private let scanner: SoftwareScanning
    private let notificationDispatcher: AutomationNotificationDelivering
    private let downloadStrategiesProvider: () async -> [DownloadAccelerationStrategy]
    private let acceleratedDownloadRunner: AcceleratedDownloader.Runner?
    private var debounceTask: Task<Void, Never>?
    private var executorObserver: AnyCancellable?

    // MARK: - Executor-backed forwarding properties
    //
    // 这些属性的值来自 executor；通过 objectWillChange 合并让 SwiftUI 能观察到变化。

    var jobs: [UpgradeJob] { executor.jobs }
    var packageProgress: [String: PackageUpgradeProgress] { executor.packageProgress }
    var upgradeProgress: UpgradeProgress? { executor.upgradeProgress }
    var dismissedFailureJobID: UUID? {
        get { executor.dismissedFailureJobID }
        set { executor.dismissedFailureJobID = newValue }
    }
    var maxConcurrentUpgrades: Int {
        get { executor.maxConcurrentUpgrades }
        set { executor.updateMaxConcurrentUpgrades(newValue) }
    }

    init(
        scanner: SoftwareScanning = LiveSoftwareScanning(),
        notificationDispatcher: AutomationNotificationDelivering? = nil,
        scanPerformanceStore: ScanPerformanceStore = ScanPerformanceStore(),
        downloadStrategiesProvider: @escaping () async -> [DownloadAccelerationStrategy] = DownloadAccelerationPolicy.defaultStrategies,
        acceleratedDownloadRunner: AcceleratedDownloader.Runner? = nil
    ) {
        self.scanner = scanner
        self.notificationDispatcher = notificationDispatcher ?? UserNotificationDispatcher()
        self.scanPerformanceStore = scanPerformanceStore
        self.downloadStrategiesProvider = downloadStrategiesProvider
        self.acceleratedDownloadRunner = acceleratedDownloadRunner

        let historyStore = UpgradeHistoryStore()
        self.historyStore = historyStore
        let runLease = MaintenanceRunLease(directory: MaintenanceRunLease.defaultDirectory)
        let executor = MaintenanceExecutor(
            historyStore: historyStore,
            downloadStrategiesProvider: downloadStrategiesProvider,
            runLease: runLease
        )
        self.executor = executor
        executor.setHost(self)

        // 合并 executor 的 objectWillChange 到 StewardModel，让 UI 能观察到 executor 状态变化。
        executorObserver = executor.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }

        refreshDailyInspectionStatus()
    }

    /// 所有待处理升级/提醒（用于 UI 显示，包含需手动处理的自更新 cask）
    @Published var allUpgradeablePackages: [UpdatablePackage] = []

    /// 未在升级中的可升级包（用于 upgradeAll，排除 queued/running/succeeded）
    @Published var availableUpdates: [UpdatablePackage] = []

    /// 数据变化时一次性计算并更新 allUpgradeablePackages 和 availableUpdates
    private func recomputeDerivedData() {
        guard let scan else {
            allUpgradeablePackages = []
            availableUpdates = []
            return
        }
        allUpgradeablePackages = scan.brew.formulae.filter { $0.outdated || $0.upgradeable }.map(UpdatablePackage.brew)
            + scan.brew.casks.filter { $0.outdated || $0.upgradeable }.map(UpdatablePackage.brew)
            + scan.mas.apps.filter { $0.outdated || $0.upgradeable }.map(UpdatablePackage.mas)
        availableUpdates = allUpgradeablePackages.filter { package in
            let status = packageProgress[package.id]?.status
            return package.upgradeable && status != .succeeded && status != .running && status != .queued
        }
    }

    var hasRunningJob: Bool {
        executor.hasRunningJob
    }

    /// 失败/超时/取消的升级记录中，已不在当前可升级集合里的孤儿。
    ///
    /// 重新扫描后，如果某个包不再 outdated（例如其实已升成功，或 brew 输出发生变化），
    /// 它会从 `allUpgradeablePackages` 消失，但 `packageProgress` 里的失败记录仍然残留。
    /// 这些孤儿会导致顶部状态横幅计数与下方升级列表对不上，这里把它们暴露出来，
    /// 让升级列表可以继续展示这些项，用户能看到失败原因并重试或清除。
    var orphanedFailedProgresses: [PackageUpgradeProgress] {
        let knownIDs = Set(allUpgradeablePackages.map(\.id))
        return packageProgress.values
            .filter {
                !knownIDs.contains($0.packageID) && [
                    PackageUpgradeStatus.failed,
                    PackageUpgradeStatus.timedOut,
                    PackageUpgradeStatus.cancelled
                ].contains($0.status)
            }
            .sorted { $0.packageName.localizedStandardCompare($1.packageName) == .orderedAscending }
    }

    var jobNotice: JobNotice? {
        if let job = jobs.first(where: { $0.status == .queued || $0.status == .running }) {
            return JobNotice(
                title: job.status == .queued ? "升级任务已排队" : "升级任务正在执行",
                detail: executor.currentCommandText(for: job),
                symbol: job.status == .queued ? "clock" : "arrow.triangle.2.circlepath",
                isFailure: false
            )
        }

        if let job = jobs.first(where: { $0.status == .failed }), job.id != dismissedFailureJobID {
            return JobNotice(
                title: "上次升级失败",
                detail: executor.failureSummary(for: job),
                symbol: "exclamationmark.triangle",
                isFailure: true
            )
        }

        return nil
    }

    var upgradeAllHelpText: String {
        if availableUpdates.isEmpty {
            return "没有可自动升级的项目。"
        }
        return "升级 \(availableUpdates.count) 个可管理软件（已跳过正在升级的项）。"
    }

    var canInstallMasCLI: Bool {
        scan?.brew.available == true && scan?.mas.available == false
    }

    func isPackageActive(_ id: String) -> Bool {
        executor.isPackageActive(id)
    }

    func scanSoftware(
        regularAppNetworkPolicy: RegularAppNetworkPolicy = .declaredSourcesOnly,
        notificationPolicy: NotificationPolicy = .silent,
        inboxStore: InboxStore? = nil
    ) async {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = ""
        scanPhase = .systemProfiler
        defer {
            scanPhase = nil
            isScanning = false
        }

        let result = await scanner.scanAll(
            includeGreedy: includeGreedy,
            regularAppNetworkPolicy: regularAppNetworkPolicy
        ) { [weak self] phase in
            Task { @MainActor in
                self?.scanPhase = phase
            }
        }
        scan = result
        scanPerformanceStore.append(result.performance)
        executor.prunePackageProgress(keeping: result)
        recomputeDerivedData()
        var newInboxItems: [InboxItem] = []
        if let inboxStore {
            let inboxItems = SourceIssueInboxFactory.items(from: result)
                + AppUpdateInboxFactory.items(from: result.applications.items)
            for item in inboxItems {
                if inboxStore.add(item) {
                    newInboxItems.append(item)
                }
            }
        }
        if let decision = AutomationNotificationDecider.decision(
            policy: notificationPolicy,
            newInboxItems: newInboxItems,
            automaticUpgradeCount: 0
        ) {
            await notificationDispatcher.deliver(decision)
        }
    }

    // MARK: - Upgrade delegation

    func upgrade(
        _ package: UpdatablePackage,
        inboxStore: InboxStore? = nil,
        autoRepairProfile: AutomationProfile? = nil
    ) async {
        guard !isConfirmingUpgradePlan, !isPackageActive(package.id) else { return }
        do {
            let command = try await executor.command(for: package, includeGreedy: includeGreedy)
            guard !isConfirmingUpgradePlan, !isPackageActive(package.id) else { return }
            executor.enqueueJob(label: "升级 \(package.name)", steps: [
                UpgradeStep(command: command, packageID: package.id, packageName: package.name)
            ], rescanAfterSuccess: true, inboxStore: inboxStore, autoRepairProfile: autoRepairProfile)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 重试升级某个包（清除失败状态后重新执行）
    func retryPackage(_ packageID: String, inboxStore: InboxStore? = nil) async {
        guard !isConfirmingUpgradePlan else { return }
        guard let scan else { return }
        let allPackages = (scan.brew.formulae.filter { $0.upgradeable }.map { UpdatablePackage.brew($0) })
            + (scan.brew.casks.filter { $0.upgradeable }.map { UpdatablePackage.brew($0) })
            + (scan.mas.apps.filter { $0.upgradeable }.map { UpdatablePackage.mas($0) })
        await executor.retryPackage(
            packageID,
            includeGreedy: includeGreedy,
            isConfirmingUpgradePlan: isConfirmingUpgradePlan,
            availablePackages: allPackages,
            inboxStore: inboxStore
        )
    }

    /// 清除某个包的失败状态
    func clearPackageFailure(_ packageID: String) {
        executor.clearPackageFailure(packageID)
    }

    func cancelJob(_ id: UUID) {
        executor.cancelJob(id)
    }

    /// 关闭失败通知面板（不删除任务记录，仅隐藏通知）
    func dismissFailureNotice() {
        executor.dismissFailureNotice()
    }

    func publishFailureRecoveryItems(to inboxStore: InboxStore, packageIDs: Set<String>) {
        executor.publishFailureRecoveryItems(to: inboxStore, packageIDs: packageIDs)
    }

    func performAutomaticRepairIfAllowed(
        profile: AutomationProfile,
        inboxStore: InboxStore?,
        packageIDs: Set<String>
    ) async -> Set<String> {
        await executor.performAutomaticRepairIfAllowed(profile: profile, inboxStore: inboxStore, packageIDs: packageIDs)
    }

    func prepareUpgradePlan(inboxStore: InboxStore? = nil) {
        guard !isConfirmingUpgradePlan else { return }
        guard let scan else {
            errorMessage = "请先扫描软件。"
            return
        }
        let rows = UpgradePlanner.makePlan(scan: scan, policyStore: policyStore, includeGreedy: includeGreedy)
        upgradePlanRows = rows
        if let inboxStore {
            for item in RiskInboxFactory.items(from: rows) {
                inboxStore.add(item)
            }
        }
        selectedPlanIDs = Set(rows.filter { $0.selection == .selected }.map(\.packageID))
        showingUpgradePlan = true
    }

    func setPlanSelection(_ packageID: String, selected: Bool) {
        if selected {
            selectedPlanIDs.insert(packageID)
        } else {
            selectedPlanIDs.remove(packageID)
        }
    }

    func confirmUpgradePlan(inboxStore: InboxStore? = nil, autoRepairProfile: AutomationProfile? = nil) async {
        guard !isConfirmingUpgradePlan else { return }
        let selectedRows = upgradePlanRows.filter { row in
            guard selectedPlanIDs.contains(row.packageID), row.canExecute, let package = row.package else {
                return false
            }
            let status = packageProgress[package.id]?.status
            return status != .succeeded && !isPackageActive(package.id)
        }
        guard !selectedRows.isEmpty else {
            errorMessage = "没有选中的可执行升级项。"
            return
        }
        isConfirmingUpgradePlan = true
        defer { isConfirmingUpgradePlan = false }
        await upgradeSelectedPlanRows(selectedRows, inboxStore: inboxStore, autoRepairProfile: autoRepairProfile)
        showingUpgradePlan = false
    }

    func upgradeAll() async {
        prepareUpgradePlan()
    }

    private func upgradeSelectedPlanRows(
        _ rows: [UpgradePlanRow],
        inboxStore: InboxStore? = nil,
        autoRepairProfile: AutomationProfile? = nil
    ) async {
        do {
            var steps: [UpgradeStep] = []

            let brewRows = rows.filter {
                if case .brew = $0.package { return true }
                return false
            }

            if !brewRows.isEmpty && runBrewUpdate {
                let brew = try await executor.requireCommand("brew")
                steps.append(UpgradeStep(command: UpgradeCommand(executable: brew, arguments: ["update"], display: "brew update"), packageID: nil, packageName: nil))
            }

            var packageSteps: [UpgradeStep] = []
            for row in rows {
                guard let package = row.package else { continue }
                let status = packageProgress[package.id]?.status
                guard status != .succeeded, !isPackageActive(package.id) else { continue }
                let command = try await executor.command(for: package, includeGreedy: includeGreedy)
                packageSteps.append(UpgradeStep(command: command, packageID: package.id, packageName: package.name))
            }

            packageSteps = packageSteps.filter { step in
                guard let packageID = step.packageID else { return false }
                let status = packageProgress[packageID]?.status
                return status != .succeeded && !isPackageActive(packageID)
            }

            guard !packageSteps.isEmpty else {
                throw StewardError.message("没有选中的可执行升级项。")
            }

            steps.append(contentsOf: packageSteps)
            executor.enqueueJob(
                label: "一键升级可管理软件",
                steps: steps,
                rescanAfterSuccess: true,
                inboxStore: inboxStore,
                autoRepairProfile: autoRepairProfile
            )
            selectedTab = .updates
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func installMasCLI() async {
        do {
            let brew = try await executor.requireCommand("brew")
            let command = UpgradeCommand(
                executable: brew,
                arguments: ["install", "mas"],
                display: "brew install mas"
            )
            executor.startJob(label: "安装 mas CLI", commands: [command], rescanAfterSuccess: true)
            selectedTab = .jobs
        } catch {
            errorMessage = "安装 mas CLI 需要可用的 Homebrew：\(error.localizedDescription)"
        }
    }

    func reveal(_ app: AppItem) {
        let url = URL(fileURLWithPath: app.path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func open(_ app: AppItem) {
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: app.path),
            configuration: configuration
        ) { _, error in
            if let error {
                Task { @MainActor in
                    self.errorMessage = "打开 \(app.name) 失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func performUpdateAction(_ action: AppUpdateAction, for app: AppItem) {
        switch action.kind {
        case .openApp:
            open(app)
        case .revealInFinder:
            reveal(app)
        case .directReplace:
            Task { await directlyReplace(app) }
        case .openUpdater:
            guard let path = RegularAppUpdateActionResolver.firstExistingUpdaterPath(for: app.updateCapability.detector) else {
                errorMessage = "未找到 \(app.updateCapability.detector.title) 更新器。"
                return
            }
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: path),
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, error in
                if let error {
                    Task { @MainActor in
                        self.errorMessage = "打开更新器失败：\(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func directlyReplace(_ app: AppItem) async {
        guard confirmDirectReplacement(for: app) else { return }

        do {
            let downloadURL = try directReplacementDownloadURL(for: app)
            let workDirectory = try makeManualReplacementWorkDirectory()
            defer { try? FileManager.default.removeItem(at: workDirectory) }

            let downloaded = try await downloadManualReplacement(from: downloadURL, into: workDirectory)
            let replacementApp = try await preparedReplacementApp(from: downloaded, workDirectory: workDirectory)
            let existingAppURL = URL(fileURLWithPath: app.path, isDirectory: true)

            try ManualAppReplacementInstaller.validateReplacement(
                existingAppURL: existingAppURL,
                newAppURL: replacementApp
            )
            try ManualAppReplacementInstaller.replace(existingAppURL: existingAppURL, with: replacementApp)
            showDirectReplacementFinishedAlert(appName: app.name)
        } catch {
            errorMessage = "直接替换 \(app.name) 失败：\(error.localizedDescription)"
        }
    }

    private func confirmDirectReplacement(for app: AppItem) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "直接替换 \(app.name)？"
        alert.informativeText = "会从应用声明的 Sparkle 更新源下载安装包，并覆盖当前 App。请先退出目标应用；如果更新源或安装包不可信，可能导致应用不可用。风险自负。"
        alert.addButton(withTitle: "直接替换")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func directReplacementDownloadURL(for app: AppItem) throws -> URL {
        let rawValue = (app.updateCapability.downloadURLString ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: rawValue),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw ManualAppReplacementError.message("当前更新源没有可直接下载的安装包地址。")
        }
        return url
    }

    func downloadManualReplacement(from url: URL, into workDirectory: URL) async throws -> URL {
        let fileName = safeDownloadFileName(from: url)
        let request = AcceleratedDownloadRequest(
            url: url,
            destinationFileName: fileName,
            expectedByteCount: nil,
            operationName: "直接替换下载"
        )
        let strategies = await downloadStrategiesProvider()
        let temporaryURL = try await AcceleratedDownloader.download(
            request,
            strategies: strategies,
            runner: acceleratedDownloadRunner
        )
        let destination = workDirectory.appendingPathComponent(fileName)
        if temporaryURL.path != destination.path,
           FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        if temporaryURL.path != destination.path {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
        }
        return destination
    }

    private func safeDownloadFileName(from url: URL) -> String {
        let urlName = url.lastPathComponent.isEmpty ? nil : url.lastPathComponent
        let name = urlName ?? "app-update"
        if URL(fileURLWithPath: name).pathExtension.isEmpty,
           !url.pathExtension.isEmpty {
            return "\(name).\(url.pathExtension)"
        }
        return name
    }

    private func preparedReplacementApp(from archiveURL: URL, workDirectory: URL) async throws -> URL {
        guard let kind = ManualAppReplacementInstaller.archiveKind(for: archiveURL) else {
            throw ManualAppReplacementError.message("目前直接替换只支持 .zip 或 .dmg 更新包。")
        }

        switch kind {
        case .zip:
            let extractDirectory = workDirectory.appendingPathComponent("extracted", isDirectory: true)
            try FileManager.default.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
            let result = await CommandRunner.run(
                "/usr/bin/ditto",
                arguments: ["-x", "-k", archiveURL.path, extractDirectory.path],
                timeout: 120
            )
            guard result.ok else {
                throw ManualAppReplacementError.message(result.stderr.isEmpty ? "解压更新包失败。" : result.stderr)
            }
            guard let appURL = ManualAppReplacementInstaller.findApp(in: extractDirectory) else {
                throw ManualAppReplacementError.message("更新包中没有找到 .app。")
            }
            return appURL
        case .dmg:
            return try await copyAppFromMountedDMG(archiveURL, workDirectory: workDirectory)
        }
    }

    private func copyAppFromMountedDMG(_ dmgURL: URL, workDirectory: URL) async throws -> URL {
        let attach = await CommandRunner.run(
            "/usr/bin/hdiutil",
            arguments: ["Attach", "-nobrowse", "-readonly", dmgURL.path],
            timeout: 120
        )
        guard attach.ok else {
            throw ManualAppReplacementError.message(attach.stderr.isEmpty ? "挂载 DMG 失败。" : attach.stderr)
        }
        guard let mountURL = ManualAppReplacementInstaller.mountPoint(fromHdiutilOutput: attach.stdout) else {
            throw ManualAppReplacementError.message("无法识别 DMG 挂载位置。")
        }

        do {
            guard let mountedApp = ManualAppReplacementInstaller.findApp(in: mountURL) else {
                throw ManualAppReplacementError.message("DMG 中没有找到 .app。")
            }
            let copiedApp = workDirectory.appendingPathComponent(mountedApp.lastPathComponent, isDirectory: true)
            if FileManager.default.fileExists(atPath: copiedApp.path) {
                try FileManager.default.removeItem(at: copiedApp)
            }
            try FileManager.default.copyItem(at: mountedApp, to: copiedApp)
            _ = await CommandRunner.run("/usr/bin/hdiutil", arguments: ["detach", mountURL.path], timeout: 30)
            return copiedApp
        } catch {
            _ = await CommandRunner.run("/usr/bin/hdiutil", arguments: ["detach", mountURL.path], timeout: 30)
            throw error
        }
    }

    private func makeManualReplacementWorkDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSoftwareStewardManualReplace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func showDirectReplacementFinishedAlert(appName: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "\(appName) 已直接替换"
        alert.informativeText = "建议重新打开应用，并点击“扫描”确认版本。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    func refreshDailyInspectionStatus() {
        let config = DailyInspectionScheduler.currentConfig()
        dailyInspectionEnabled = config.enabled
        dailyHour = config.hour
        dailyMinute = config.minute
        dailyLaunchAgentPath = config.launchAgentPath
        dailyLogPath = config.logPath
        dailyLog = DailyInspectionScheduler.recentLog()
    }

    func enableDailyInspection() async {
        do {
            try await DailyInspectionScheduler.install(
                hour: dailyHour,
                minute: dailyMinute,
                includeGreedy: includeGreedy,
                runBrewUpdate: runBrewUpdate,
                helperPath: dailyAgentPath
            )
            refreshDailyInspectionStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disableDailyInspection() async {
        do {
            try await DailyInspectionScheduler.uninstall()
            refreshDailyInspectionStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runDailyInspectionNow() {
        do {
            let command = try DailyInspectionScheduler.runNowCommand(
                includeGreedy: includeGreedy,
                runBrewUpdate: runBrewUpdate,
                helperPath: dailyAgentPath
            )
            executor.startJob(label: "立即巡检并自动升级", commands: [command], rescanAfterSuccess: true)
            selectedTab = .jobs
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var dailyAgentPath: String {
        DailyInspectionScheduler.helperPath()
    }

    /// 执行管理来源页面的恢复操作
    func performSourceRecovery(action: SourceRecoveryAction) async {
        switch action {
        case .rescan:
            await scanSoftware()
        case .installMas:
            await installMasCLI()
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - MaintenanceExecutorHost

    func executorRequestsRescan(inboxStore: InboxStore?) {
        let previousProgress = executor.packageProgress
        Task {
            await scanSoftware(inboxStore: inboxStore)
            if let scan {
                let remaining = UpgradeVerifier.remainingOutdatedIDs(in: scan)
                for (id, progress) in previousProgress {
                    executor.packageProgress[id] = UpgradeVerifier.verify(progress: progress, remainingPackageIDs: remaining)
                }
            }
        }
    }

    func executorRequestsDerivedDataRecompute() {
        recomputeDerivedData()
    }

    func executorCurrentScanApplications() -> ApplicationsScan? {
        scan?.applications
    }

    func executorPrunePackageProgress(keeping result: ScanResult) {
        executor.prunePackageProgress(keeping: result)
    }
}

enum StewardError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}
