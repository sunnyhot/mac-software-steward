import AppKit
import Combine
import Foundation

@MainActor
final class StewardModel: ObservableObject, MaintenanceExecutorHost {
    @Published var selectedTab: AppTab = .updates
    @Published var scan: ScanResult?
    @Published var isScanning = false
    @Published var scanPhase: ScanPhase?
    @Published var includeGreedy = UserDefaults.standard.object(forKey: "includeGreedy") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(includeGreedy, forKey: "includeGreedy")
            recomputeDerivedData()
        }
    }
    @Published var runBrewUpdate = UserDefaults.standard.object(forKey: "runBrewUpdate") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(runBrewUpdate, forKey: "runBrewUpdate")
        }
    }
    @Published var errorMessage = ""

    @Published var dailyInspectionEnabled = false
    @Published var dailyHour = 9
    @Published var dailyMinute = 0
    @Published var dailyInspectionHealth: DailyInspectionHealth = .disabled
    @Published var dailyInspectionRuntime = DailyInspectionRuntimeStatus(isLoaded: false, lastExitCode: nil)
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

    /// 执行引擎。jobs / packageProgress / upgradeProgress / maxConcurrentUpgrades 的
    /// 真实状态由 executor 持有；StewardModel 通过下面的转发属性暴露给现有 UI。
    let executor: MaintenanceExecutor

    private let scanner: SoftwareScanning
    private let notificationDispatcher: AutomationNotificationDelivering
    private var executorObserver: AnyCancellable?
    private var lastNotifiedUpgradeIDs: Set<String> = []
    @Published private var dismissedUpgradeReminderIDs: Set<String> = []

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
        downloadStrategiesProvider: @escaping () async -> [DownloadAccelerationStrategy] = DownloadAccelerationPolicy.defaultStrategies
    ) {
        self.scanner = scanner
        self.notificationDispatcher = notificationDispatcher ?? UserNotificationDispatcher()

        let historyStore = UpgradeHistoryStore()
        self.historyStore = historyStore
        let executor = MaintenanceExecutor(
            historyStore: historyStore,
            downloadStrategiesProvider: downloadStrategiesProvider
        )
        self.executor = executor
        executor.setHost(self)

        // 合并 executor 的 objectWillChange 到 StewardModel，让 UI 能观察到 executor 状态变化。
        // 节流到 ~10Hz：升级时 brew 每秒输出几十行 stdout，每行都会触发 executor publish，
        // 无条件桥接会让所有观察 StewardModel 的 view 每帧都重算。节流后刷新频率降到人眼
        // 无感但足够流畅的程度（100ms 间隔），同时保证最后一次变更不会被丢弃（latest: true）。
        executorObserver = executor.objectWillChange
            .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }

        refreshDailyInspectionStatus()
    }

    /// 所有待处理升级/提醒（用于 UI 显示，包含需手动处理的自更新 cask）
    @Published var allUpgradeablePackages: [UpdatablePackage] = []

    /// 未在升级中的可升级包（排除 queued/running/succeeded）
    @Published var availableUpdates: [UpdatablePackage] = []

    /// 当前扫描中可由应用直接执行的完整升级集合。
    /// 侧栏、升级列表、菜单栏和一键升级都以此为唯一数据源。
    @Published var executableUpdates: [UpdatablePackage] = []

    /// Homebrew 仍有 cask receipt，但其明确声明的所有 `.app` 目标都已不存在。
    @Published var staleCaskRecords: [UpdatablePackage] = []

    /// 升级页需要展示的全部项目：可执行升级、厂商手动更新、Homebrew 残留记录。
    @Published private(set) var updateAttentionPackages: [UpdatablePackage] = []

    /// 扫描完成时一次性构建，避免升级进度刷新时重复把完整扫描结果转换成列表行。
    @Published private(set) var localSoftwareRows: [LocalSoftwareRow] = []

    var shouldShowUpgradeReminder: Bool {
        let currentIDs = Set(availableUpdates.map(\.id))
        return !currentIDs.isEmpty && !currentIDs.subtracting(dismissedUpgradeReminderIDs).isEmpty
    }

    var dailyInspectionOperational: Bool {
        dailyInspectionEnabled && dailyInspectionHealth == .healthy
    }

    func dismissUpgradeReminder() {
        dismissedUpgradeReminderIDs.formUnion(availableUpdates.map(\.id))
    }

    /// 数据变化时一次性更新发现项、可执行项和当前可一键升级项。
    private func recomputeDerivedData() {
        guard let scan else {
            assignIfChanged(\.allUpgradeablePackages, [])
            assignIfChanged(\.availableUpdates, [])
            assignIfChanged(\.executableUpdates, [])
            assignIfChanged(\.staleCaskRecords, [])
            assignIfChanged(\.updateAttentionPackages, [])
            assignIfChanged(\.localSoftwareRows, [])
            assignIfChanged(\.dismissedUpgradeReminderIDs, [])
            return
        }
        let nextAllUpgradeablePackages = scan.brew.formulae.filter { $0.outdated || $0.upgradeable }.map(UpdatablePackage.brew)
            + scan.brew.casks.filter { $0.outdated || $0.upgradeable }.map(UpdatablePackage.brew)
            + scan.mas.apps.filter { $0.outdated || $0.upgradeable }.map(UpdatablePackage.mas)
        let nextStaleCaskRecords = scan.brew.casks.filter(\.hasStaleInstallRecord).map(UpdatablePackage.brew)
        let nextExecutableUpdates = UpgradePlanner.executablePackages(
            scan: scan,
            policyStore: policyStore,
            includeGreedy: includeGreedy
        )
        let nextAvailableUpdates = nextExecutableUpdates.filter { package in
            let status = packageProgress[package.id]?.status
            return status != .succeeded && status != .running && status != .queued
        }
        var seen: Set<String> = []
        let nextAttentionPackages = (
            nextExecutableUpdates
                + nextAllUpgradeablePackages.filter(\.manualUpdateOnly)
                + nextStaleCaskRecords
        ).filter { seen.insert($0.id).inserted }
        let currentIDs = Set(nextAvailableUpdates.map(\.id))
        let nextDismissedIDs = dismissedUpgradeReminderIDs.intersection(currentIDs)

        assignIfChanged(\.allUpgradeablePackages, nextAllUpgradeablePackages)
        assignIfChanged(\.availableUpdates, nextAvailableUpdates)
        assignIfChanged(\.executableUpdates, nextExecutableUpdates)
        assignIfChanged(\.staleCaskRecords, nextStaleCaskRecords)
        assignIfChanged(\.updateAttentionPackages, nextAttentionPackages)
        assignIfChanged(\.localSoftwareRows, LocalSoftwarePresenter.rows(from: scan))
        assignIfChanged(\.dismissedUpgradeReminderIDs, nextDismissedIDs)
    }

    /// 避免给 `@Published` 写回完全相同的值，减少无意义的视图刷新。
    private func assignIfChanged<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<StewardModel, Value>,
        _ value: Value
    ) {
        guard self[keyPath: keyPath] != value else { return }
        self[keyPath: keyPath] = value
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
        executor.prunePackageProgress(keeping: result)
        recomputeDerivedData()
        let currentUpgradeIDs = Set(availableUpdates.map(\.id))
        lastNotifiedUpgradeIDs.formIntersection(currentUpgradeIDs)
        let newlyAvailableUpgradeCount = currentUpgradeIDs.subtracting(lastNotifiedUpgradeIDs).count
        var newInboxItems: [InboxItem] = []
        if let inboxStore {
            let sourceIssueItems = SourceIssueInboxFactory.items(from: result)
            let appUpdateItems = AppUpdateInboxFactory.items(from: result.applications.items)
            // 扫描恢复正常时 factory 不再生成对应来源条目，需主动退出残留的旧问题条目，
            // 否则“扫描错误”会永久停留在收件箱（且已落盘，重启仍在）。
            inboxStore.retireSourceIssues(
                notPresentIn: Set(sourceIssueItems.compactMap(\.sourceID))
            )
            // 批量添加，只写盘一次（避免循环里逐条全量 encode + 写盘）。
            newInboxItems = inboxStore.addAll(sourceIssueItems + appUpdateItems)
        }
        if let decision = AutomationNotificationDecider.decision(
            policy: notificationPolicy,
            newInboxItems: newInboxItems,
            automaticUpgradeCount: 0,
            availableUpgradeCount: newlyAvailableUpgradeCount
        ) {
            await notificationDispatcher.deliver(decision)
            lastNotifiedUpgradeIDs.formUnion(currentUpgradeIDs)
        }
    }

    func checkAndPrepareMaintenance(
        regularAppNetworkPolicy: RegularAppNetworkPolicy = .declaredSourcesOnly,
        notificationPolicy: NotificationPolicy = .silent,
        inboxStore: InboxStore? = nil
    ) async {
        guard !isScanning, !hasRunningJob, !isConfirmingUpgradePlan else { return }
        await scanSoftware(
            regularAppNetworkPolicy: regularAppNetworkPolicy,
            notificationPolicy: notificationPolicy,
            inboxStore: inboxStore
        )
        guard scan != nil else { return }
        prepareUpgradePlan(inboxStore: inboxStore)
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
        guard !rows.isEmpty else {
            selectedPlanIDs.removeAll()
            selectedTab = .updates
            return
        }
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

    /// 一键升级所有可执行的升级项。
    ///
    /// 把当前扫描结果里所有 `canExecute` 的包（自动升级 + 无高风险阻断的确认后升级）
    /// 作为单次批量任务入队，复用 `upgradeSelectedPlanRows` 的批量化路径：
    /// 所有包进入同一个 job，sudos cask 由执行器在 job 结束时收集后只弹一次系统密码框。
    /// 不经过升级计划确认页（`showingUpgradePlan` 保持 false）。
    func upgradeAllExecutable(inboxStore: InboxStore? = nil, autoRepairProfile: AutomationProfile? = nil) async {
        guard let scan, !isScanning, !hasRunningJob, !isConfirmingUpgradePlan else { return }
        let rows = UpgradePlanner.makePlan(scan: scan, policyStore: policyStore, includeGreedy: includeGreedy)
        let availableIDs = Set(availableUpdates.map(\.id))
        let executable = rows.filter { $0.canExecute && availableIDs.contains($0.packageID) }
        guard !executable.isEmpty else {
            errorMessage = "没有可执行的升级项。"
            return
        }
        isConfirmingUpgradePlan = true
        defer { isConfirmingUpgradePlan = false }
        await upgradeSelectedPlanRows(executable, inboxStore: inboxStore, autoRepairProfile: autoRepairProfile)
    }

    func upgradeSelectedPlanRows(
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
                label: "维护可管理软件",
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
            selectedTab = .updates
        } catch {
            errorMessage = "安装 mas CLI 需要可用的 Homebrew：\(error.localizedDescription)"
        }
    }

    func performManualCaskResolution(
        _ resolution: ManualCaskUpdateResolution,
        for package: UpdatablePackage,
        inboxStore: InboxStore? = nil,
        autoRepairProfile: AutomationProfile? = nil
    ) async {
        guard case .brew(let cask) = package, cask.kind == "cask", cask.manualUpdateOnly else {
            errorMessage = "该项目不需要渠道修复。"
            return
        }

        switch resolution.kind {
        case .openOfficialUpdate:
            if let app = scan?.applications.items.first(where: {
                $0.relatedPackageID == package.id && FileManager.default.fileExists(atPath: $0.path)
            }) {
                open(app)
                return
            }
            guard let url = URL(string: resolution.officialURLString), NSWorkspace.shared.open(url) else {
                errorMessage = "没有可用的官方更新地址。"
                return
            }

        case .switchChannel:
            guard !isScanning, !hasRunningJob, !isConfirmingUpgradePlan else { return }
            do {
                let brew = try await executor.requireCommand("brew")
                let info = await CommandRunner.run(
                    brew,
                    arguments: ["info", "--cask", "--json=v2", resolution.targetCaskToken],
                    timeout: 30
                )
                guard info.ok,
                      let availableVersion = ManualCaskUpdateResolver.caskVersion(
                        fromBrewInfoJSON: info.stdout,
                        token: resolution.targetCaskToken
                      ),
                      ManualCaskUpdateResolver.versionsMatch(availableVersion, resolution.targetVersion) else {
                    errorMessage = "Homebrew 尚未提供 \(resolution.targetCaskToken) \(resolution.targetVersion)，暂时无法一键切换。"
                    return
                }

                let uninstall = UpgradeCommand(
                    executable: brew,
                    arguments: ["uninstall", "--cask", "--force", cask.name],
                    display: "brew uninstall --cask --force \(cask.name)"
                )
                let install = UpgradeCommand(
                    executable: brew,
                    arguments: ["install", "--cask", resolution.targetCaskToken],
                    display: "brew install --cask \(resolution.targetCaskToken)"
                )
                executor.enqueueJob(
                    label: "将 \(cask.name) 切换到 \(resolution.targetCaskToken)",
                    steps: [
                        UpgradeStep(command: uninstall, packageID: nil, packageName: nil),
                        UpgradeStep(command: install, packageID: package.id, packageName: cask.name)
                    ],
                    rescanAfterSuccess: true,
                    inboxStore: inboxStore,
                    autoRepairProfile: autoRepairProfile
                )
                selectedTab = .updates
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func removeStaleCaskRecord(
        _ package: UpdatablePackage,
        inboxStore: InboxStore? = nil,
        autoRepairProfile: AutomationProfile? = nil
    ) async {
        guard case .brew(let cask) = package,
              cask.kind == "cask",
              cask.hasStaleInstallRecord,
              !cask.expectedAppPaths.isEmpty else {
            errorMessage = "该项目不是可清理的 Homebrew 残留记录。"
            return
        }
        guard BrewCaskCleanupDetector.hasStaleInstallRecord(expectedAppPaths: cask.expectedAppPaths) else {
            errorMessage = "检测到应用文件已重新出现，请先重新扫描。"
            return
        }
        guard !isScanning, !hasRunningJob, !isConfirmingUpgradePlan else { return }

        do {
            let brew = try await executor.requireCommand("brew")
            let command = UpgradeCommand(
                executable: brew,
                arguments: ["uninstall", "--cask", "--force", cask.name],
                display: "brew uninstall --cask --force \(cask.name)"
            )
            executor.enqueueJob(
                label: "移除 \(cask.name) 的 Homebrew 残留记录",
                steps: [UpgradeStep(
                    command: command,
                    packageID: package.id,
                    packageName: cask.name,
                    purpose: .staleCaskCleanup
                )],
                rescanAfterSuccess: false,
                inboxStore: inboxStore,
                autoRepairProfile: autoRepairProfile
            )
            selectedTab = .updates
        } catch {
            errorMessage = error.localizedDescription
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

    func refreshDailyInspectionStatus() {
        let config = DailyInspectionScheduler.currentConfig()
        dailyInspectionEnabled = config.enabled
        dailyHour = config.hour
        dailyMinute = config.minute
        dailyInspectionHealth = config.health
        if config.enabled {
            includeGreedy = config.includeGreedy
            runBrewUpdate = config.runBrewUpdate
        }
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
            await refreshDailyInspectionRuntimeStatus()
        } catch {
            refreshDailyInspectionStatus()
            dailyInspectionHealth = .needsRepair("LaunchAgent 加载失败，请点击“一键修复”后重试。")
            errorMessage = error.localizedDescription
        }
    }

    /// 在应用升级、移动或 LaunchAgent 被卸载后恢复每日巡检。
    /// 调度时间和高级选项从现有 plist 读取，不会覆盖用户选择。
    func repairDailyInspectionIfNeeded() async {
        do {
            _ = try await DailyInspectionScheduler.repairIfNeeded(currentHelperPath: dailyAgentPath)
            refreshDailyInspectionStatus()
            await refreshDailyInspectionRuntimeStatus()
        } catch {
            refreshDailyInspectionStatus()
            dailyInspectionHealth = .needsRepair("LaunchAgent 加载失败，请点击“一键修复”后重试。")
            errorMessage = "每日巡检修复失败：\(error.localizedDescription)"
        }
    }

    func repairDailyInspection() async {
        guard dailyInspectionEnabled else { return }
        do {
            try await DailyInspectionScheduler.install(
                hour: dailyHour,
                minute: dailyMinute,
                includeGreedy: includeGreedy,
                runBrewUpdate: runBrewUpdate,
                helperPath: dailyAgentPath
            )
            refreshDailyInspectionStatus()
            await refreshDailyInspectionRuntimeStatus()
        } catch {
            refreshDailyInspectionStatus()
            dailyInspectionHealth = .needsRepair("LaunchAgent 加载失败，请点击“一键修复”后重试。")
            errorMessage = "每日巡检修复失败：\(error.localizedDescription)"
        }
    }

    func disableDailyInspection() async {
        do {
            try await DailyInspectionScheduler.uninstall()
            refreshDailyInspectionStatus()
            dailyInspectionRuntime = DailyInspectionRuntimeStatus(isLoaded: false, lastExitCode: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var dailyAgentPath: String {
        DailyInspectionScheduler.preferredHelperPath()
    }

    private func refreshDailyInspectionRuntimeStatus() async {
        guard dailyInspectionEnabled else {
            dailyInspectionRuntime = DailyInspectionRuntimeStatus(isLoaded: false, lastExitCode: nil)
            return
        }
        dailyInspectionRuntime = await DailyInspectionScheduler.runtimeStatus()
        if !dailyInspectionRuntime.isLoaded {
            dailyInspectionHealth = .needsRepair("LaunchAgent 尚未加载，请点击“一键修复”后重试。")
        }
    }

    func openDailyInspectionLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: dailyLogPath))
    }

    /// 执行可升级页来源诊断卡片的恢复操作
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

    func executorDidRemoveStaleCaskRecord(packageID: String) {
        guard var updatedScan = scan else { return }
        let previousCount = updatedScan.brew.casks.count
        updatedScan.brew.casks.removeAll { $0.id == packageID }
        guard updatedScan.brew.casks.count != previousCount else { return }
        updatedScan.summary.brewCasks = updatedScan.brew.casks.count
        scan = updatedScan
        recomputeDerivedData()
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
