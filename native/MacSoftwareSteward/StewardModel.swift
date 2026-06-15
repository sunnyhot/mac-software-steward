import AppKit
import Foundation

@MainActor
final class StewardModel: ObservableObject {
    @Published var selectedTab: AppTab = .inbox
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
    @Published var jobs: [UpgradeJob] = []
    @Published var dailyInspectionEnabled = false
    @Published var dailyHour = 9
    @Published var dailyMinute = 0
    @Published var dailyLog = ""
    @Published var dailyLaunchAgentPath = DailyInspectionScheduler.launchAgentURL.path
    @Published var dailyLogPath = DailyInspectionScheduler.logURL.path
    @Published var packageProgress: [String: PackageUpgradeProgress] = [:]
    @Published var upgradePlanRows: [UpgradePlanRow] = []
    @Published var selectedPlanIDs: Set<String> = []
    @Published var showingUpgradePlan = false
    @Published var isConfirmingUpgradePlan = false
    @Published var maxConcurrentUpgrades: Int = UserDefaults.standard.object(forKey: "maxConcurrentUpgrades") as? Int ?? 3 {
        didSet { UserDefaults.standard.set(maxConcurrentUpgrades, forKey: "maxConcurrentUpgrades") }
    }

    let policyStore = UpgradePolicyStore()
    let historyStore = UpgradeHistoryStore()
    let inspectionReportStore = InspectionReportStore()

    private let scanner: SoftwareScanning
    private var activeJobCount = 0
    private var pendingJobQueue: [(id: UUID, steps: [UpgradeStep], rescanAfterSuccess: Bool)] = []
    private var debounceTask: Task<Void, Never>?
    private var activeCancellationTokens: [UUID: CommandCancellationToken] = [:]
    private var downloadMonitorTasks: [String: Task<Void, Never>] = [:]
    private var downloadSizeTasks: [String: Task<Void, Never>] = [:]
    private var downloadExpectedSizes: [String: Int64] = [:]
    @Published var upgradeProgress: UpgradeProgress?
    /// 用户关闭过的失败任务 ID，关闭后不再显示失败通知（直到新任务失败）
    @Published var dismissedFailureJobID: UUID?

    init(scanner: SoftwareScanning = LiveSoftwareScanning()) {
        self.scanner = scanner
        refreshDailyInspectionStatus()
    }

    /// 所有可升级的包（用于 UI 显示，包含正在升级的包以显示进度）
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
        allUpgradeablePackages = scan.brew.formulae.filter(\.upgradeable).map(UpdatablePackage.brew)
            + scan.brew.casks.filter(\.upgradeable).map(UpdatablePackage.brew)
            + scan.mas.apps.filter(\.upgradeable).map(UpdatablePackage.mas)
        availableUpdates = allUpgradeablePackages.filter { package in
            let status = packageProgress[package.id]?.status
            return status != .succeeded && status != .running && status != .queued
        }
    }

    var hasRunningJob: Bool {
        jobs.contains { $0.status == .queued || $0.status == .running }
    }

    var jobNotice: JobNotice? {
        if let job = jobs.first(where: { $0.status == .queued || $0.status == .running }) {
            return JobNotice(
                title: job.status == .queued ? "升级任务已排队" : "升级任务正在执行",
                detail: currentCommandText(for: job),
                symbol: job.status == .queued ? "clock" : "arrow.triangle.2.circlepath",
                isFailure: false
            )
        }

        if let job = jobs.first(where: { $0.status == .failed }), job.id != dismissedFailureJobID {
            return JobNotice(
                title: "上次升级失败",
                detail: failureSummary(for: job),
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
        if let status = packageProgress[id]?.status {
            return status == .queued || status == .running
        }
        return false
    }

    func scanSoftware() async {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = ""
        scanPhase = .systemProfiler
        defer {
            scanPhase = nil
            isScanning = false
        }

        let result = await scanner.scanAll(includeGreedy: includeGreedy) { [weak self] phase in
            Task { @MainActor in
                self?.scanPhase = phase
            }
        }
        scan = result
        prunePackageProgress(keeping: result)
        recomputeDerivedData()
    }

    func upgrade(_ package: UpdatablePackage) async {
        guard !isConfirmingUpgradePlan, !isPackageActive(package.id) else { return }
        do {
            let command = try await command(for: package)
            guard !isConfirmingUpgradePlan, !isPackageActive(package.id) else { return }
            enqueueJob(label: "升级 \(package.name)", steps: [
                UpgradeStep(command: command, packageID: package.id, packageName: package.name)
            ], rescanAfterSuccess: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 重试升级某个包（清除失败状态后重新执行）
    func retryPackage(_ packageID: String) async {
        guard !isConfirmingUpgradePlan else { return }
        // 清除旧的失败状态
        packageProgress.removeValue(forKey: packageID)
        recomputeDerivedData()
        // 在 availableUpdates 或 scan 中找到对应的包
        guard let scan else { return }
        let allPackages = (scan.brew.formulae.filter { $0.upgradeable }.map { UpdatablePackage.brew($0) })
            + (scan.brew.casks.filter { $0.upgradeable }.map { UpdatablePackage.brew($0) })
            + (scan.mas.apps.filter { $0.upgradeable }.map { UpdatablePackage.mas($0) })
        guard let package = allPackages.first(where: { $0.id == packageID }) else {
            // 包不在可升级列表中了，重新扫描
            await scanSoftware()
            return
        }
        await upgrade(package)
    }

    /// 清除某个包的失败状态
    func clearPackageFailure(_ packageID: String) {
        packageProgress.removeValue(forKey: packageID)
        recomputeDerivedData()
    }

    func cancelJob(_ id: UUID) {
        activeCancellationTokens[id]?.cancel()
    }

    /// 关闭失败通知面板（不删除任务记录，仅隐藏通知）
    func dismissFailureNotice() {
        if let job = jobs.first(where: { $0.status == .failed }) {
            dismissedFailureJobID = job.id
        }
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

    func confirmUpgradePlan() async {
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
        await upgradeSelectedPlanRows(selectedRows)
        showingUpgradePlan = false
    }

    func upgradeAll() async {
        prepareUpgradePlan()
    }

    private func upgradeSelectedPlanRows(_ rows: [UpgradePlanRow]) async {
        do {
            var steps: [UpgradeStep] = []

            let brewRows = rows.filter {
                if case .brew = $0.package { return true }
                return false
            }

            if !brewRows.isEmpty && runBrewUpdate {
                let brew = try await requireCommand("brew")
                steps.append(UpgradeStep(command: UpgradeCommand(executable: brew, arguments: ["update"], display: "brew update"), packageID: nil, packageName: nil))
            }

            var packageSteps: [UpgradeStep] = []
            for row in rows {
                guard let package = row.package else { continue }
                let status = packageProgress[package.id]?.status
                guard status != .succeeded, !isPackageActive(package.id) else { continue }
                let command = try await command(for: package)
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
            enqueueJob(label: "一键升级可管理软件", steps: steps, rescanAfterSuccess: true)
            selectedTab = .updates
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func installMasCLI() async {
        do {
            let brew = try await requireCommand("brew")
            let command = UpgradeCommand(
                executable: brew,
                arguments: ["install", "mas"],
                display: "brew install mas"
            )
            startJob(label: "安装 mas CLI", commands: [command], rescanAfterSuccess: true)
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
            startJob(label: "立即巡检并自动升级", commands: [command], rescanAfterSuccess: true)
            selectedTab = .jobs
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func command(for package: UpdatablePackage) async throws -> UpgradeCommand {
        switch package {
        case .brew(let brewPackage):
            try validateBrewToken(brewPackage.name)
            let brew = try await requireCommand("brew")
            var args = ["upgrade"]
            if brewPackage.kind == "cask" {
                args.append("--cask")
                if includeGreedy { args.append("--greedy") }
            }
            args.append(brewPackage.name)
            return UpgradeCommand(executable: brew, arguments: args, display: (["brew"] + args).joined(separator: " "))

        case .mas(let app):
            guard app.appId.allSatisfy(\.isNumber) else {
                throw StewardError.message("无效的 Mac App Store app id。")
            }
            let mas = try await requireCommand("mas")
            return UpgradeCommand(executable: mas, arguments: ["upgrade", app.appId], display: "mas upgrade \(app.appId)")
        }
    }

    private func startJob(label: String, commands: [UpgradeCommand], rescanAfterSuccess: Bool = false) {
        let steps = commands.map { UpgradeStep(command: $0, packageID: nil, packageName: nil) }
        startJob(label: label, steps: steps, rescanAfterSuccess: rescanAfterSuccess)
    }

    private func startJob(label: String, steps: [UpgradeStep], rescanAfterSuccess: Bool = false) {
        let job = UpgradeJob(label: label, commands: steps.map(\.command.display))
        jobs.insert(job, at: 0)
        let id = job.id
        markQueued(steps)
        recomputeDerivedData()

        activeJobCount += 1
        let packageSteps = steps.filter { $0.packageID != nil }
        upgradeProgress = UpgradeProgress(
            completed: 0,
            total: packageSteps.count,
            failed: 0,
            currentPackage: nil
        )

        Task {
            await runJob(id: id, steps: steps, rescanAfterSuccess: rescanAfterSuccess)
            activeJobCount -= 1
            scheduleRescanAfterJobCompletion(rescanAfterSuccess: rescanAfterSuccess)
            dequeueNext()
        }
    }

    private func enqueueJob(label: String, steps: [UpgradeStep], rescanAfterSuccess: Bool = false) {
        let maxSlots = maxConcurrentUpgrades <= 0 ? Int.max : maxConcurrentUpgrades
        if activeJobCount < maxSlots {
            startJob(label: label, steps: steps, rescanAfterSuccess: rescanAfterSuccess)
        } else {
            let job = UpgradeJob(label: label, commands: steps.map(\.command.display))
            jobs.insert(job, at: 0)
            markQueued(steps)
            recomputeDerivedData()
            pendingJobQueue.append((id: job.id, steps: steps, rescanAfterSuccess: rescanAfterSuccess))
        }
    }

    private func dequeueNext() {
        guard !pendingJobQueue.isEmpty else { return }
        let maxSlots = maxConcurrentUpgrades <= 0 ? Int.max : maxConcurrentUpgrades
        guard activeJobCount < maxSlots else { return }
        let next = pendingJobQueue.removeFirst()
        // Update the queued job's steps — markQueued was already called
        activeJobCount += 1
        Task {
            await runJob(id: next.id, steps: next.steps, rescanAfterSuccess: next.rescanAfterSuccess)
            activeJobCount -= 1
            scheduleRescanAfterJobCompletion(rescanAfterSuccess: next.rescanAfterSuccess)
            dequeueNext()
        }
    }

    private func scheduleRescanAfterJobCompletion(rescanAfterSuccess: Bool) {
        guard rescanAfterSuccess, !hasRunningJob, pendingJobQueue.isEmpty else { return }
        Task { await scanSoftware() }
    }

    private func runJob(id: UUID, steps: [UpgradeStep], rescanAfterSuccess: Bool) async {
        updateJob(id) {
            $0.status = .running
            $0.startedAt = Date()
            $0.log.append(LogLine(stream: "system", text: "开始：\($0.label)"))
        }

        var failedCount = 0
        var firstErrorCode: Int32?
        var completedSteps = 0
        var shouldStop = false
        let token = CommandCancellationToken()
        activeCancellationTokens[id] = token

        let setupSteps = steps.filter { $0.packageID == nil }
        let packageSteps = steps.filter { $0.packageID != nil }

        for step in setupSteps {
            let command = prepareStepExecution(jobID: id, step: step)
            let result = await runCommand(jobID: id, step: step, command: command, token: token)
            shouldStop = await handleStepResult(
                jobID: id,
                step: step,
                command: command,
                result: result,
                failedCount: &failedCount,
                firstErrorCode: &firstErrorCode,
                completedSteps: &completedSteps
            )
            if shouldStop { break }
        }

        if !shouldStop {
            shouldStop = await runPackageStepsConcurrently(
                jobID: id,
                steps: packageSteps,
                token: token,
                failedCount: &failedCount,
                firstErrorCode: &firstErrorCode,
                completedSteps: &completedSteps
            )
        }

        activeCancellationTokens[id] = nil

        updateJob(id) {
            if $0.status == .cancelled || $0.status == .timedOut {
                $0.exitCode = firstErrorCode ?? $0.exitCode ?? 1
            } else if failedCount > 0 {
                $0.status = .failed
                $0.exitCode = firstErrorCode ?? 1
                $0.log.append(LogLine(stream: "system", text: "完成，\(failedCount) 个步骤失败"))
            } else {
                $0.status = .succeeded
                $0.exitCode = 0
                $0.log.append(LogLine(stream: "system", text: "完成"))
            }
            $0.finishedAt = Date()
        }
        if let job = jobs.first(where: { $0.id == id }) {
            historyStore.append(UpgradeHistoryRecord(
                id: job.id,
                label: job.label,
                status: job.status.rawValue,
                startedAt: job.startedAt,
                finishedAt: job.finishedAt,
                commands: job.commands,
                exitCode: job.exitCode,
                summary: failureSummary(for: job)
            ))
        }

        upgradeProgress = nil

        if rescanAfterSuccess {
            let previousProgress = packageProgress
            await scanSoftware()
            if let scan {
                let remaining = UpgradeVerifier.remainingOutdatedIDs(in: scan)
                for (id, progress) in previousProgress {
                    packageProgress[id] = UpgradeVerifier.verify(progress: progress, remainingPackageIDs: remaining)
                }
            }
        }
    }

    private func prepareStepExecution(jobID id: UUID, step: UpgradeStep) -> UpgradeCommand {
        let command = step.command
        markRunning(step)
        recomputeDerivedData()
        if step.packageName != nil {
            updateUpgradeProgress(currentPackage: step.packageName)
        }
        appendLog(id: id, stream: "command", text: "$ \(command.display)")
        return command
    }

    private func runCommand(jobID id: UUID, step: UpgradeStep, command: UpgradeCommand, token: CommandCancellationToken) async -> StreamingCommandResult {
        await CommandRunner.runStreamingDetailed(
            command.executable,
            arguments: command.arguments,
            timeout: 7200,
            cancellationToken: token
        ) { stream, text in
            Task { @MainActor in
                self.appendLog(id: id, stream: stream, text: text)
                self.updatePackageDetail(for: step, stream: stream, text: text)
            }
        }
    }

    private func runPackageStepsConcurrently(
        jobID id: UUID,
        steps: [UpgradeStep],
        token: CommandCancellationToken,
        failedCount: inout Int,
        firstErrorCode: inout Int32?,
        completedSteps: inout Int
    ) async -> Bool {
        guard !steps.isEmpty else { return false }
        let maxSlots = maxConcurrentUpgrades <= 0 ? steps.count : max(1, maxConcurrentUpgrades)
        let launchCount = min(maxSlots, steps.count)
        var nextIndex = 0
        var shouldStop = false

        await withTaskGroup(of: StepExecutionOutcome.self) { group in
            func launchNext() async {
                guard nextIndex < steps.count, !shouldStop, !token.isCancelled else { return }
                let step = steps[nextIndex]
                nextIndex += 1
                let command = await MainActor.run {
                    self.prepareStepExecution(jobID: id, step: step)
                }
                let model = self
                group.addTask {
                    let result = await CommandRunner.runStreamingDetailed(
                        command.executable,
                        arguments: command.arguments,
                        timeout: 7200,
                        cancellationToken: token
                    ) { stream, text in
                        Task { @MainActor in
                            model.appendLog(id: id, stream: stream, text: text)
                            model.updatePackageDetail(for: step, stream: stream, text: text)
                        }
                    }
                    return StepExecutionOutcome(step: step, command: command, result: result)
                }
            }

            for _ in 0..<launchCount {
                await launchNext()
            }

            if launchCount > 1 {
                updateUpgradeProgress(currentPackage: "\(launchCount) 个任务并行中")
            }

            while let outcome = await group.next() {
                let stop = await handleStepResult(
                    jobID: id,
                    step: outcome.step,
                    command: outcome.command,
                    result: outcome.result,
                    failedCount: &failedCount,
                    firstErrorCode: &firstErrorCode,
                    completedSteps: &completedSteps
                )
                if stop {
                    shouldStop = true
                    token.cancel()
                    group.cancelAll()
                }
                await launchNext()
            }
        }

        return shouldStop
    }

    private func handleStepResult(
        jobID id: UUID,
        step: UpgradeStep,
        command: UpgradeCommand,
        result: StreamingCommandResult,
        failedCount: inout Int,
        firstErrorCode: inout Int32?,
        completedSteps: inout Int
    ) async -> Bool {
        let code = result.code

        if result.terminationReason == .cancelled {
            failedCount += 1
            firstErrorCode = firstErrorCode ?? (code == 0 ? 1 : code)
            markCancelled(step)
            updateJob(id) {
                $0.status = .cancelled
                $0.exitCode = code == 0 ? 1 : code
                $0.log.append(LogLine(stream: "system", text: "已取消：\(command.display)"))
            }
            if step.packageID != nil {
                completedSteps += 1
                updateUpgradeProgress(completed: completedSteps, failed: failedCount, currentPackage: nil)
            }
            return true
        } else if result.terminationReason == .timedOut {
            failedCount += 1
            firstErrorCode = firstErrorCode ?? (code == 0 ? 1 : code)
            let analysis = FailureAnalysis(
                summary: "升级命令超时。",
                suggestion: "请稍后重试，或在终端中手动运行命令检查是否卡在网络、权限或交互提示。",
                action: .retryInTerminal,
                copyText: "命令：\(command.display)\n最近输出：\n\(result.recentOutput)",
                command: command.display
            )
            markTimedOut(step, analysis: analysis)
            updateJob(id) {
                $0.status = .timedOut
                $0.exitCode = code == 0 ? 1 : code
                $0.log.append(LogLine(stream: "system", text: "超时：\(command.display)"))
            }
            if step.packageID != nil {
                completedSteps += 1
                updateUpgradeProgress(completed: completedSteps, failed: failedCount, currentPackage: nil)
            }
            return true
        } else if code != 0 {
            if await cleanupStaleBrewCaskIfNeeded(jobID: id, step: step, command: command, output: result.recentOutput, token: activeCancellationTokens[id]) {
                markCleanedUp(step)
                recomputeDerivedData()
                updateJob(id) {
                    $0.log.append(LogLine(stream: "system", text: "已清理失效的 Homebrew Cask：\(step.packageName ?? command.display)"))
                }
            } else {
                failedCount += 1
                if firstErrorCode == nil { firstErrorCode = code }
                let analysis = failureAnalysis(command: command.display, code: code, output: result.recentOutput)
                markFailed(step, analysis: analysis)
                recomputeDerivedData()
                updateJob(id) {
                    $0.log.append(LogLine(stream: "system", text: "失败：\(command.display)，退出码 \(code)"))
                }
            }
        } else {
            markSucceeded(step)
            recomputeDerivedData()
        }

        if step.packageID != nil {
            completedSteps += 1
            updateUpgradeProgress(completed: completedSteps, failed: failedCount, currentPackage: nil)
        }

        return false
    }

    private func cleanupStaleBrewCaskIfNeeded(
        jobID id: UUID,
        step: UpgradeStep,
        command: UpgradeCommand,
        output: String,
        token: CommandCancellationToken?
    ) async -> Bool {
        let appPresence = appPresenceForBrewCask(step)
        guard let caskName = BrewCaskCleanupDetector.cleanupCandidate(command: command, output: output, appPresence: appPresence) else { return false }
        appendLog(id: id, stream: "system", text: "检测到 \(caskName) 的 App 已不存在，自动从 Homebrew Cask 中移除。")
        let cleanupCommand = UpgradeCommand(
            executable: command.executable,
            arguments: ["uninstall", "--cask", "--force", caskName],
            display: "brew uninstall --cask --force \(caskName)"
        )
        appendLog(id: id, stream: "command", text: "$ \(cleanupCommand.display)")
        let result = await CommandRunner.runStreamingDetailed(
            cleanupCommand.executable,
            arguments: cleanupCommand.arguments,
            timeout: 600,
            cancellationToken: token
        ) { stream, text in
            Task { @MainActor in
                self.appendLog(id: id, stream: stream, text: text)
                self.updatePackageDetail(for: step, stream: stream, text: text)
            }
        }
        guard result.terminationReason == .exited, result.code == 0 else {
            appendLog(id: id, stream: "system", text: "清理 \(caskName) 失败，退出码 \(result.code)。")
            return false
        }
        return true
    }

    private func appPresenceForBrewCask(_ step: UpgradeStep) -> BrewCaskAppPresence {
        guard let packageID = step.packageID, packageID.hasPrefix("brew:cask:") else {
            return BrewCaskAppPresence(scanSucceeded: false, relatedAppExists: false)
        }
        guard let applications = scan?.applications else {
            return BrewCaskAppPresence(scanSucceeded: false, relatedAppExists: false)
        }
        let relatedAppExists = applications.items.contains { $0.relatedPackageID == packageID }
        return BrewCaskAppPresence(scanSucceeded: applications.ok, relatedAppExists: relatedAppExists)
    }

    private struct StepExecutionOutcome {
        var step: UpgradeStep
        var command: UpgradeCommand
        var result: StreamingCommandResult
    }

    private func updateUpgradeProgress(completed: Int? = nil, failed: Int? = nil, currentPackage: String? = nil) {
        guard var progress = upgradeProgress else { return }
        if let completed { progress.completed = completed }
        if let failed { progress.failed = failed }
        if let currentPackage { progress.currentPackage = currentPackage }
        upgradeProgress = progress
    }

    private func updateJob(_ id: UUID, mutate: (inout UpgradeJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&jobs[index])
        if jobs[index].log.count > 1_500 {
            jobs[index].log.removeFirst(jobs[index].log.count - 1_500)
        }
    }

    private func appendLog(id: UUID, stream: String, text: String) {
        updateJob(id) {
            $0.log.append(LogLine(stream: stream, text: text))
        }
    }

    private func markQueued(_ steps: [UpgradeStep]) {
        for step in steps {
            guard let packageID = step.packageID, let packageName = step.packageName else { continue }
            stopHomebrewDownloadMonitor(packageID: packageID)
            packageProgress[packageID] = PackageUpgradeProgress(
                packageID: packageID,
                packageName: packageName,
                status: .queued,
                detail: "等待升级"
            )
        }
    }

    private func markRunning(_ step: UpgradeStep) {
        guard let packageID = step.packageID, let packageName = step.packageName else { return }
        packageProgress[packageID] = PackageUpgradeProgress(
            packageID: packageID,
            packageName: packageName,
            status: .running,
            detail: step.command.display,
            phaseText: "执行命令"
        )
        startHomebrewDownloadMonitorIfNeeded(for: step)
    }

    private func markSucceeded(_ step: UpgradeStep) {
        guard let packageID = step.packageID, let packageName = step.packageName else { return }
        stopHomebrewDownloadMonitor(packageID: packageID)
        packageProgress[packageID] = PackageUpgradeProgress(
            packageID: packageID,
            packageName: packageName,
            status: .succeeded,
            detail: "升级完成"
        )
    }

    private func markCleanedUp(_ step: UpgradeStep) {
        guard let packageID = step.packageID, let packageName = step.packageName else { return }
        stopHomebrewDownloadMonitor(packageID: packageID)
        packageProgress[packageID] = PackageUpgradeProgress(
            packageID: packageID,
            packageName: packageName,
            status: .succeeded,
            detail: "已清理失效的 Homebrew Cask"
        )
    }

    private func markFailed(_ step: UpgradeStep, analysis: FailureAnalysis) {
        guard let packageID = step.packageID, let packageName = step.packageName else { return }
        stopHomebrewDownloadMonitor(packageID: packageID)
        packageProgress[packageID] = PackageUpgradeProgress(
            packageID: packageID,
            packageName: packageName,
            status: .failed,
            detail: analysis.summary,
            failureSummary: analysis.summary,
            recoverySuggestion: analysis.suggestion,
            copyText: analysis.copyText,
            recoveryAction: analysis.action,
            lastFailedCommand: analysis.command
        )
    }

    private func markCancelled(_ step: UpgradeStep) {
        guard let packageID = step.packageID, let packageName = step.packageName else { return }
        stopHomebrewDownloadMonitor(packageID: packageID)
        packageProgress[packageID] = PackageUpgradeProgress(
            packageID: packageID,
            packageName: packageName,
            status: .cancelled,
            detail: "升级已取消"
        )
    }

    private func markTimedOut(_ step: UpgradeStep, analysis: FailureAnalysis) {
        guard let packageID = step.packageID, let packageName = step.packageName else { return }
        stopHomebrewDownloadMonitor(packageID: packageID)
        packageProgress[packageID] = PackageUpgradeProgress(
            packageID: packageID,
            packageName: packageName,
            status: .timedOut,
            detail: analysis.summary,
            failureSummary: analysis.summary,
            recoverySuggestion: analysis.suggestion,
            copyText: analysis.copyText,
            recoveryAction: analysis.action,
            lastFailedCommand: analysis.command
        )
    }

    private func updatePackageDetail(for step: UpgradeStep, stream: String, text: String) {
        guard let packageID = step.packageID, var progress = packageProgress[packageID] else { return }
        guard progress.status == .running else { return }
        let parsed = PackageProgressParser.parse(stream: stream, text: text)
        if let phaseText = parsed.phaseText {
            progress.phaseText = phaseText
            if phaseText == "准备下载" || phaseText == "下载中" {
                startHomebrewDownloadMonitorIfNeeded(for: step)
            }
        }
        progress.detail = parsed.detail
        progress.updatedAt = Date()

        if parsed.clearsDownloadProgress {
            progress.downloadFraction = nil
            progress.downloadSizeText = nil
            progress.downloadSpeedText = nil
            progress.downloadTimeRemainingText = nil
        }
        if let fraction = parsed.downloadFraction { progress.downloadFraction = fraction }
        if let sizeText = parsed.downloadSizeText { progress.downloadSizeText = sizeText }
        if let speedText = parsed.downloadSpeedText { progress.downloadSpeedText = speedText }

        packageProgress[packageID] = progress
    }

    private func startHomebrewDownloadMonitorIfNeeded(for step: UpgradeStep) {
        guard let packageID = step.packageID,
              let packageName = step.packageName,
              isHomebrewCaskUpgrade(step),
              downloadMonitorTasks[packageID] == nil else { return }

        startHomebrewDownloadSizeLookupIfNeeded(for: step)
        let directory = HomebrewDownloadMonitor.downloadsDirectory()
        downloadMonitorTasks[packageID] = Task { @MainActor in
            var previous: HomebrewDownloadSnapshot?
            while !Task.isCancelled {
                guard packageProgress[packageID]?.status == .running else { break }
                if let snapshot = try? HomebrewDownloadMonitor.snapshot(
                    packageName: packageName,
                    in: directory,
                    previous: previous,
                    expectedByteCountHint: downloadExpectedSizes[packageID]
                ) {
                    previous = snapshot
                    applyHomebrewDownloadSnapshot(snapshot, packageID: packageID)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            downloadMonitorTasks[packageID] = nil
        }
    }

    private func stopHomebrewDownloadMonitor(packageID: String) {
        downloadMonitorTasks[packageID]?.cancel()
        downloadMonitorTasks[packageID] = nil
        downloadSizeTasks[packageID]?.cancel()
        downloadSizeTasks[packageID] = nil
        downloadExpectedSizes[packageID] = nil
    }

    private func startHomebrewDownloadSizeLookupIfNeeded(for step: UpgradeStep) {
        guard let packageID = step.packageID,
              let packageName = step.packageName,
              downloadExpectedSizes[packageID] == nil,
              downloadSizeTasks[packageID] == nil else { return }

        let brewExecutable = step.command.executable
        downloadSizeTasks[packageID] = Task { [weak self] in
            let size = await HomebrewCaskDownloadSizeResolver.resolve(
                caskName: packageName,
                brewExecutable: brewExecutable
            )
            await MainActor.run {
                guard let self else { return }
                if let size {
                    self.downloadExpectedSizes[packageID] = size
                }
                self.downloadSizeTasks[packageID] = nil
            }
        }
    }

    private func isHomebrewCaskUpgrade(_ step: UpgradeStep) -> Bool {
        step.command.arguments.contains("upgrade") && step.command.arguments.contains("--cask")
    }

    private func applyHomebrewDownloadSnapshot(_ snapshot: HomebrewDownloadSnapshot, packageID: String) {
        guard var progress = packageProgress[packageID], progress.status == .running else { return }
        guard HomebrewDownloadMonitor.canApplySnapshot(toPhase: progress.phaseText) else { return }

        progress.phaseText = "下载中"
        progress.detail = snapshot.detailText
        progress.updatedAt = Date()
        progress.downloadSizeText = snapshot.downloadSizeText
        progress.downloadSpeedText = snapshot.downloadSpeedText
        progress.downloadTimeRemainingText = snapshot.downloadTimeRemainingText
        if let fraction = snapshot.downloadFraction {
            progress.downloadFraction = fraction
        } else if progress.downloadFraction == 0 {
            progress.downloadFraction = nil
        }
        packageProgress[packageID] = progress
    }

    private func failureAnalysis(command: String, code: Int32, output: String) -> FailureAnalysis {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary: String
        let suggestion: String
        let action: FailureActionType?

        // Check for process crash (signal termination)
        let signalNum = code - 128
        if code < 0 || (signalNum > 0 && signalNum < 32) {
            if code < 0 {
                summary = "升级命令超时被终止。"
                suggestion = "请点击「重试」，如果持续超时，可能是网络或依赖问题。"
            } else {
                summary = "升级命令崩溃（信号 \(signalNum)），进程异常退出。"
                suggestion = "请尝试在终端手动运行 `\(command)` 检查具体错误，然后点击「重试」。如果持续崩溃，该工具可能与当前系统版本不兼容。"
            }
            action = .retry
            var copyText = ""
            copyText += "失败原因：\(summary)\n"
            copyText += "解决方案：\(suggestion)\n"
            copyText += "命令：\(command)"
            if !trimmed.isEmpty {
                copyText += "\n最近输出：\n\(trimmed)"
            }
            return FailureAnalysis(summary: summary, suggestion: suggestion, action: action, copyText: copyText, command: command)
        }

        if let hint = UpgradeFailureAnalyzer.knownFailureHint(in: trimmed) {
            summary = hint.summary
            suggestion = hint.suggestion
            action = hint.action
        } else if let errorLine = firstErrorLine(in: trimmed) {
            summary = errorLine
            suggestion = "请点击「查看日志」了解详情，或尝试重新升级。"
            action = .retry
        } else {
            summary = "升级过程中遇到未知错误。"
            suggestion = "请点击「查看日志」查看完整信息，或稍后再试一次。"
            action = .openLog
        }

        var copyText = ""
        copyText += "失败原因：\(summary)\n"
        copyText += "解决方案：\(suggestion)\n"
        copyText += "命令：\(command)"
        if !trimmed.isEmpty {
            copyText += "\n最近输出：\n\(trimmed)"
        }

        return FailureAnalysis(summary: summary, suggestion: suggestion, action: action, copyText: copyText, command: command)
    }

    private func firstErrorLine(in output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                let lowercased = line.lowercased()
                return lowercased.contains("error")
                    || lowercased.contains("failed")
                    || lowercased.contains("failure")
                    || lowercased.contains("permission denied")
                    || lowercased.contains("already exists")
                    || lowercased.contains("checksum")
                    || lowercased.contains("not found")
            }
    }

    private func currentCommandText(for job: UpgradeJob) -> String {
        if let command = job.log.reversed().first(where: { $0.stream == "command" }) {
            return command.text.replacingOccurrences(of: "$ ", with: "")
        }
        return job.commands.first ?? job.label
    }

    private func failureSummary(for job: UpgradeJob) -> String {
        if let output = job.log.reversed().first(where: { $0.stream == "stderr" || $0.stream == "stdout" }) {
            return output.text
        }
        if let system = job.log.reversed().first(where: { $0.stream == "system" }) {
            return system.text
        }
        return "请打开任务日志查看完整输出。"
    }

    private func prunePackageProgress(keeping result: ScanResult) {
        let ids = Set(
            result.brew.formulae.map(\.id)
                + result.brew.casks.map(\.id)
                + result.mas.apps.map(\.id)
        )
        packageProgress = packageProgress.filter { ids.contains($0.key) }
        recomputeDerivedData()
    }

    private func requireCommand(_ command: String) async throws -> String {
        if let path = await CommandRunner.commandPath(command) {
            return path
        }
        throw StewardError.message("\(command) is not installed or not in PATH.")
    }

    private func validateBrewToken(_ token: String) throws {
        let pattern = "^[A-Za-z0-9][A-Za-z0-9@._+-]*$"
        if token.range(of: pattern, options: .regularExpression) == nil {
            throw StewardError.message("无效的 Homebrew token。")
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
}

private struct FailureAnalysis {
    var summary: String
    var suggestion: String
    var action: FailureActionType?
    var copyText: String
    var command: String
}

enum StewardError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}
