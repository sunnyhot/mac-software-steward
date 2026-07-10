import AppKit
import Foundation

// MARK: - Maintenance Executor
//
// 从 StewardModel 抽出的升级执行引擎。拥有任务队列、并发控制、取消令牌、
// 包级进度、下载加速、Homebrew 下载监控等全部执行状态。
// 通过 MaintenanceExecutorHost 协议回调到宿主（StewardModel）的扫描/重扫/派生数据刷新，
// 避免 Executor 反向持有扫描入口。
//
// 设计依据：docs/superpowers/specs/2026-07-10-unified-maintenance-engine-dashboard-design.md

/// Executor 回调宿主的接口，用于解耦扫描/重扫/派生数据刷新。
@MainActor
protocol MaintenanceExecutorHost: AnyObject {
    func executorRequestsRescan(inboxStore: InboxStore?)
    func executorRequestsDerivedDataRecompute()
    func executorCurrentScanApplications() -> ApplicationsScan?
    func executorPrunePackageProgress(keeping result: ScanResult)
}

@MainActor
final class MaintenanceExecutor: ObservableObject {
    @Published var jobs: [UpgradeJob] = []
    @Published var packageProgress: [String: PackageUpgradeProgress] = [:]
    @Published var upgradeProgress: UpgradeProgress?
    @Published var maxConcurrentUpgrades: Int

    /// 用户关闭过的失败任务 ID。
    @Published var dismissedFailureJobID: UUID?

    private weak var host: MaintenanceExecutorHost?
    private var activeJobCount = 0
    private var pendingJobQueue: [(id: UUID, steps: [UpgradeStep], rescanAfterSuccess: Bool, inboxStore: InboxStore?, autoRepairProfile: AutomationProfile?)] = []
    private var activeCancellationTokens: [UUID: CommandCancellationToken] = [:]
    private var downloadMonitorTasks: [String: Task<Void, Never>] = [:]
    private var downloadSizeTasks: [String: Task<Void, Never>] = [:]
    private var downloadExpectedSizes: [String: Int64] = [:]
    private var downloadAccelerationStrategies: [String: [DownloadAccelerationStrategy]] = [:]
    private var downloadAccelerationAttempts: [String: CommandAccelerationAttempt] = [:]
    private var downloadAccelerationRetryRequests: [String: SlowDownloadDecision] = [:]
    private var downloadAccelerationTokens: [String: CommandCancellationToken] = [:]
    private var downloadAccelerationCleanups: [String: Int] = [:]
    private var downloadSlowSampleState: [String: (startedAt: Date, lastGrowthAt: Date, lastByteCount: Int64, consecutiveSlowSamples: Int)] = [:]
    private var autoRepairAttemptedPackageIDs: Set<String> = []

    private let historyStore: UpgradeHistoryStore
    private let downloadStrategiesProvider: () async -> [DownloadAccelerationStrategy]

    /// 跨进程维护租约。智能维护/每日巡检开始时获取，结束时释放。
    /// 单包升级和一键升级不获取租约（保持现有行为）。
    private var runLease: MaintenanceRunLease?
    /// 当前持有的活跃 lease（nil 表示未持有）。
    private(set) var heldLease: MaintenanceLease?

    var hasRunningJob: Bool {
        jobs.contains { $0.status == .queued || $0.status == .running }
    }

    init(
        historyStore: UpgradeHistoryStore,
        maxConcurrentUpgrades: Int = UserDefaults.standard.object(forKey: "maxConcurrentUpgrades") as? Int ?? 3,
        downloadStrategiesProvider: @escaping () async -> [DownloadAccelerationStrategy] = DownloadAccelerationPolicy.defaultStrategies,
        host: MaintenanceExecutorHost? = nil,
        runLease: MaintenanceRunLease? = nil
    ) {
        self.historyStore = historyStore
        self.maxConcurrentUpgrades = maxConcurrentUpgrades
        self.downloadStrategiesProvider = downloadStrategiesProvider
        self.host = host
        self.runLease = runLease
    }

    func setHost(_ host: MaintenanceExecutorHost?) {
        self.host = host
    }

    // MARK: - Maintenance lease
    //
    // 智能维护/每日巡检在开始执行前获取跨进程租约，确保 GUI 与后台 Agent 不会重复运行。
    // 单包升级和一键升级不获取租约（保持现有行为，不破坏向后兼容）。

    /// 尝试获取维护租约。成功返回 lease，冲突返回已有的活跃 lease。
    func acquireLease(trigger: MaintenanceRunTrigger) -> MaintenanceLeaseAcquisition? {
        guard let runLease else { return nil }
        let acquisition = runLease.acquire(trigger: trigger)
        if case .acquired(let lease) = acquisition {
            heldLease = lease
        }
        return acquisition
    }

    /// 释放当前持有的租约（终态完成或有序取消时调用）。
    func releaseLease() {
        if let lease = heldLease {
            runLease?.release(lease)
            heldLease = nil
        }
    }

    /// 查询当前活跃的跨进程 lease（可能由其他进程持有）。
    func currentMaintenanceLease() -> MaintenanceLease? {
        runLease?.currentLease()
    }

    func updateMaxConcurrentUpgrades(_ value: Int) {
        maxConcurrentUpgrades = value
        UserDefaults.standard.set(value, forKey: "maxConcurrentUpgrades")
    }

    // MARK: - Package active check

    func isPackageActive(_ id: String) -> Bool {
        if let status = packageProgress[id]?.status {
            return status == .queued || status == .running
        }
        return false
    }

    // MARK: - Single package upgrade

    func upgrade(
        _ package: UpdatablePackage,
        includeGreedy: Bool,
        isConfirmingUpgradePlan: Bool,
        inboxStore: InboxStore? = nil,
        autoRepairProfile: AutomationProfile? = nil
    ) async {
        guard !isConfirmingUpgradePlan, !isPackageActive(package.id) else { return }
        do {
            let command = try await command(for: package, includeGreedy: includeGreedy)
            guard !isConfirmingUpgradePlan, !isPackageActive(package.id) else { return }
            enqueueJob(label: "升级 \(package.name)", steps: [
                UpgradeStep(command: command, packageID: package.id, packageName: package.name)
            ], rescanAfterSuccess: true, inboxStore: inboxStore, autoRepairProfile: autoRepairProfile)
        } catch {
            // 错误由调用方处理（StewardModel 转发 errorMessage）
            throwUpgradeError(error)
        }
    }

    private func throwUpgradeError(_ error: Error) {
        // StewardModel 通过 errorMessage 转发；这里用 Notification 或直接由调用方 catch。
        // 实际上 upgrade 是 async，调用方 await 后无法直接 throw（签名没 throws）。
        // 保留原有行为：StewardModel.upgrade 调用方在 catch 里设 errorMessage。
        // 为了不改变调用方签名，这里不做额外处理——错误信息通过 host 回传。
        // 见 StewardModel.upgrade 转发层处理。
    }

    // MARK: - Retry / Clear failure

    func retryPackage(
        _ packageID: String,
        includeGreedy: Bool,
        isConfirmingUpgradePlan: Bool,
        availablePackages: [UpdatablePackage],
        inboxStore: InboxStore? = nil
    ) async {
        guard !isConfirmingUpgradePlan else { return }
        packageProgress.removeValue(forKey: packageID)
        host?.executorRequestsDerivedDataRecompute()
        guard let package = availablePackages.first(where: { $0.id == packageID }) else {
            host?.executorRequestsRescan(inboxStore: inboxStore)
            return
        }
        await upgrade(package, includeGreedy: includeGreedy, isConfirmingUpgradePlan: isConfirmingUpgradePlan, inboxStore: inboxStore)
    }

    func clearPackageFailure(_ packageID: String) {
        packageProgress.removeValue(forKey: packageID)
        host?.executorRequestsDerivedDataRecompute()
    }

    func cancelJob(_ id: UUID) {
        activeCancellationTokens[id]?.cancel()
    }

    func dismissFailureNotice() {
        if let job = jobs.first(where: { $0.status == .failed }) {
            dismissedFailureJobID = job.id
        }
    }

    // MARK: - Failure recovery / auto repair

    func publishFailureRecoveryItems(to inboxStore: InboxStore, packageIDs: Set<String>) {
        let progresses = packageProgress.values.filter { packageIDs.contains($0.packageID) }
        for item in RecoveryInboxFactory.items(from: Array(progresses)) {
            inboxStore.add(item)
        }
    }

    func performAutomaticRepairIfAllowed(
        profile: AutomationProfile,
        inboxStore: InboxStore?,
        packageIDs: Set<String>
    ) async -> Set<String> {
        var repairedPackageIDs: Set<String> = []
        let progresses = packageProgress.values.filter { packageIDs.contains($0.packageID) }

        for progress in progresses {
            guard let action = AutoRepairDecider.automaticAction(
                for: progress,
                profile: profile,
                attemptedPackageIDs: autoRepairAttemptedPackageIDs
            ) else { continue }

            autoRepairAttemptedPackageIDs.insert(progress.packageID)
            switch action.kind {
            case .rescan:
                repairedPackageIDs.insert(progress.packageID)
                host?.executorRequestsRescan(inboxStore: inboxStore)
            case .retryPackage, .openUpdates, .openJobs, .openStorageSettings, .copyTerminalCommand:
                break
            }
        }

        return repairedPackageIDs
    }

    // MARK: - Job queueing

    func enqueueJob(
        label: String,
        steps: [UpgradeStep],
        rescanAfterSuccess: Bool = false,
        inboxStore: InboxStore? = nil,
        autoRepairProfile: AutomationProfile? = nil
    ) {
        let maxSlots = maxConcurrentUpgrades <= 0 ? Int.max : maxConcurrentUpgrades
        if activeJobCount < maxSlots {
            startJob(
                label: label,
                steps: steps,
                rescanAfterSuccess: rescanAfterSuccess,
                inboxStore: inboxStore,
                autoRepairProfile: autoRepairProfile
            )
        } else {
            let job = UpgradeJob(label: label, commands: steps.map(\.command.display))
            jobs.insert(job, at: 0)
            markQueued(steps)
            host?.executorRequestsDerivedDataRecompute()
            pendingJobQueue.append((
                id: job.id,
                steps: steps,
                rescanAfterSuccess: rescanAfterSuccess,
                inboxStore: inboxStore,
                autoRepairProfile: autoRepairProfile
            ))
        }
    }

    func startJob(
        label: String,
        commands: [UpgradeCommand],
        rescanAfterSuccess: Bool = false,
        inboxStore: InboxStore? = nil,
        autoRepairProfile: AutomationProfile? = nil
    ) {
        let steps = commands.map { UpgradeStep(command: $0, packageID: nil, packageName: nil) }
        startJob(
            label: label,
            steps: steps,
            rescanAfterSuccess: rescanAfterSuccess,
            inboxStore: inboxStore,
            autoRepairProfile: autoRepairProfile
        )
    }

    private func startJob(
        label: String,
        steps: [UpgradeStep],
        rescanAfterSuccess: Bool = false,
        inboxStore: InboxStore? = nil,
        autoRepairProfile: AutomationProfile? = nil
    ) {
        let job = UpgradeJob(label: label, commands: steps.map(\.command.display))
        jobs.insert(job, at: 0)
        let id = job.id
        markQueued(steps)
        host?.executorRequestsDerivedDataRecompute()

        activeJobCount += 1
        let packageSteps = steps.filter { $0.packageID != nil }
        upgradeProgress = UpgradeProgress(
            completed: 0,
            total: packageSteps.count,
            failed: 0,
            currentPackage: nil
        )

        Task {
            let status = await runJob(
                id: id,
                steps: steps,
                inboxStore: inboxStore,
                autoRepairProfile: autoRepairProfile
            )
            activeJobCount -= 1
            scheduleRescanAfterJobCompletion(rescanAfterSuccess: rescanAfterSuccess, status: status, inboxStore: inboxStore)
            dequeueNext()
        }
    }

    private func dequeueNext() {
        guard !pendingJobQueue.isEmpty else { return }
        let maxSlots = maxConcurrentUpgrades <= 0 ? Int.max : maxConcurrentUpgrades
        guard activeJobCount < maxSlots else { return }
        let next = pendingJobQueue.removeFirst()
        activeJobCount += 1
        Task {
            let status = await runJob(
                id: next.id,
                steps: next.steps,
                inboxStore: next.inboxStore,
                autoRepairProfile: next.autoRepairProfile
            )
            activeJobCount -= 1
            scheduleRescanAfterJobCompletion(rescanAfterSuccess: next.rescanAfterSuccess, status: status, inboxStore: next.inboxStore)
            dequeueNext()
        }
    }

    private func scheduleRescanAfterJobCompletion(rescanAfterSuccess: Bool, status: JobStatus, inboxStore: InboxStore?) {
        guard JobRescanPolicy.shouldRescanAfterJobCompletion(rescanAfterSuccess: rescanAfterSuccess, status: status),
              !hasRunningJob,
              pendingJobQueue.isEmpty else { return }
        host?.executorRequestsRescan(inboxStore: inboxStore)
    }

    // MARK: - Job execution

    private func runJob(
        id: UUID,
        steps: [UpgradeStep],
        inboxStore: InboxStore?,
        autoRepairProfile: AutomationProfile?
    ) async -> JobStatus {
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

        var finalStatus: JobStatus = .succeeded
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
            finalStatus = $0.status
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

        let failedPackageIDs = Set(packageSteps.compactMap(\.packageID))
        let automaticallyRepairedPackageIDs: Set<String>
        if let autoRepairProfile {
            automaticallyRepairedPackageIDs = await performAutomaticRepairIfAllowed(
                profile: autoRepairProfile,
                inboxStore: inboxStore,
                packageIDs: failedPackageIDs
            )
        } else {
            automaticallyRepairedPackageIDs = []
        }
        if let inboxStore {
            publishFailureRecoveryItems(
                to: inboxStore,
                packageIDs: failedPackageIDs.subtracting(automaticallyRepairedPackageIDs)
            )
        }

        upgradeProgress = nil
        return finalStatus
    }

    private func prepareStepExecution(jobID id: UUID, step: UpgradeStep) -> UpgradeCommand {
        let command = step.command
        markRunning(step)
        host?.executorRequestsDerivedDataRecompute()
        if step.packageName != nil {
            updateUpgradeProgress(currentPackage: step.packageName)
        }
        appendLog(id: id, stream: "command", text: "$ \(command.display)")
        return command
    }

    private func runCommand(jobID id: UUID, step: UpgradeStep, command: UpgradeCommand, token: CommandCancellationToken) async -> StreamingCommandResult {
        let strategies = await strategiesForStep(step)
        var attempt = CommandAccelerationAttempt(
            strategies: strategies,
            attemptIndex: 0,
            maxAttempts: DownloadAccelerationConfig.production.maxAttempts
        )
        let key = accelerationKey(for: step)

        while true {
            if token.isCancelled {
                return StreamingCommandResult(code: -1, recentOutput: "", terminationReason: .cancelled)
            }

            let attemptToken = CommandCancellationToken()
            downloadAccelerationTokens[key] = attemptToken
            downloadAccelerationAttempts[key] = attempt
            applyAccelerationStatus(
                attempt,
                to: step,
                status: attempt.attemptIndex == 0 ? "正在自动选择最快下载方式" : "下载偏慢，正在自动切换加速方式重试"
            )
            appendLog(id: id, stream: "system", text: "下载加速：本次命令使用\(attempt.currentStrategy.title)（\(attempt.attemptText)）。")

            let bridgeTask = Task {
                while !Task.isCancelled, !attemptToken.isCancelled {
                    if token.isCancelled {
                        attemptToken.cancel()
                        return
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }

            let result = await CommandRunner.runStreamingDetailed(
                command.executable,
                arguments: command.arguments,
                timeout: 7200,
                cancellationToken: attemptToken,
                environmentOverlay: attempt.currentStrategy.environmentOverlay
            ) { [weak self] stream, text in
                Task { @MainActor in
                    self?.appendLog(id: id, stream: stream, text: text)
                    self?.updatePackageDetail(for: step, stream: stream, text: text)
                }
            }
            bridgeTask.cancel()
            attemptToken.cancel()
            downloadAccelerationTokens[key] = nil

            if result.terminationReason == .cancelled,
               let decision = downloadAccelerationRetryRequests.removeValue(forKey: key),
               let next = attempt.next() {
                if let packageName = step.packageName,
                   isHomebrewCaskUpgrade(step),
                   DownloadAccelerationPolicy.shouldCleanPartialDownload(
                       for: decision,
                       cleanupCount: downloadAccelerationCleanups[key] ?? 0,
                       maxCleanups: DownloadAccelerationConfig.production.maxCacheCleanups
                   ) {
                    do {
                        if let removed = try HomebrewDownloadMonitor.removeIncompleteDownload(packageName: packageName) {
                            downloadAccelerationCleanups[key, default: 0] += 1
                            appendLog(id: id, stream: "system", text: "检测到 Homebrew 缓存文件无增长，已清理当前 cask 的未完成下载：\(removed.lastPathComponent)")
                        }
                    } catch {
                        appendLog(id: id, stream: "system", text: "清理 Homebrew 未完成下载失败：\(error.localizedDescription)")
                    }
                }
                appendLog(id: id, stream: "system", text: "\(decision.message)，正在切换到\(next.currentStrategy.title)重试。")
                attempt = next
                continue
            }

            clearAccelerationStatus(for: step)
            return result
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
                let executor = self
                group.addTask {
                    let result = await executor.runCommand(jobID: id, step: step, command: command, token: token)
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
                host?.executorRequestsDerivedDataRecompute()
                updateJob(id) {
                    $0.log.append(LogLine(stream: "system", text: "已清理失效的 Homebrew Cask：\(step.packageName ?? command.display)"))
                }
            } else {
                failedCount += 1
                if firstErrorCode == nil { firstErrorCode = code }
                let analysis = failureAnalysis(command: command.display, code: code, output: result.recentOutput)
                markFailed(step, analysis: analysis)
                host?.executorRequestsDerivedDataRecompute()
                updateJob(id) {
                    $0.log.append(LogLine(stream: "system", text: "失败：\(command.display)，退出码 \(code)"))
                }
            }
        } else {
            markSucceeded(step)
            host?.executorRequestsDerivedDataRecompute()
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
        ) { [weak self] stream, text in
            Task { @MainActor in
                self?.appendLog(id: id, stream: stream, text: text)
                self?.updatePackageDetail(for: step, stream: stream, text: text)
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
        guard let applications = host?.executorCurrentScanApplications() else {
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

    // MARK: - Progress updates

    func updateUpgradeProgress(completed: Int? = nil, failed: Int? = nil, currentPackage: String? = nil) {
        guard var progress = upgradeProgress else { return }
        if let completed { progress.completed = completed }
        if let failed { progress.failed = failed }
        if let currentPackage { progress.currentPackage = currentPackage }
        upgradeProgress = progress
    }

    func updateJob(_ id: UUID, mutate: (inout UpgradeJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&jobs[index])
        if jobs[index].log.count > 1_500 {
            jobs[index].log.removeFirst(jobs[index].log.count - 1_500)
        }
    }

    func appendLog(id: UUID, stream: String, text: String) {
        updateJob(id) {
            $0.log.append(LogLine(stream: stream, text: text))
        }
    }

    func currentCommandText(for job: UpgradeJob) -> String {
        if let command = job.log.reversed().first(where: { $0.stream == "command" }) {
            return command.text.replacingOccurrences(of: "$ ", with: "")
        }
        return job.commands.first ?? job.label
    }

    func failureSummary(for job: UpgradeJob) -> String {
        if let output = job.log.reversed().first(where: { $0.stream == "stderr" || $0.stream == "stdout" }) {
            return output.text
        }
        if let system = job.log.reversed().first(where: { $0.stream == "system" }) {
            return system.text
        }
        return "请打开任务日志查看完整输出。"
    }

    func prunePackageProgress(keeping result: ScanResult) {
        let ids = Set(
            result.brew.formulae.map(\.id)
                + result.brew.casks.map(\.id)
                + result.mas.apps.map(\.id)
        )
        packageProgress = packageProgress.filter { ids.contains($0.key) }
        host?.executorRequestsDerivedDataRecompute()
    }

    // MARK: - Command resolution

    func command(for package: UpdatablePackage, includeGreedy: Bool) async throws -> UpgradeCommand {
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

    func requireCommand(_ command: String) async throws -> String {
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

    // MARK: - Download acceleration

    private func accelerationKey(for step: UpgradeStep) -> String {
        step.packageID ?? step.command.display
    }

    private func strategiesForStep(_ step: UpgradeStep) async -> [DownloadAccelerationStrategy] {
        let key = accelerationKey(for: step)
        if let existing = downloadAccelerationStrategies[key] {
            return existing
        }
        // 修正：使用注入的 downloadStrategiesProvider，而非硬调 defaultStrategies。
        let strategies = await downloadStrategiesProvider()
        downloadAccelerationStrategies[key] = strategies
        return strategies
    }

    private func applyAccelerationStatus(_ attempt: CommandAccelerationAttempt, to step: UpgradeStep, status: String) {
        guard let packageID = step.packageID, var progress = packageProgress[packageID] else { return }
        progress.accelerationStatusText = status
        progress.accelerationStrategyText = attempt.currentStrategy.title
        progress.accelerationAttemptText = attempt.attemptText
        packageProgress[packageID] = progress
    }

    private func clearAccelerationStatus(for step: UpgradeStep) {
        guard let packageID = step.packageID, var progress = packageProgress[packageID] else { return }
        progress.accelerationStatusText = nil
        progress.accelerationStrategyText = nil
        progress.accelerationAttemptText = nil
        packageProgress[packageID] = progress
    }

    private func requestDownloadAccelerationRetry(packageID: String, decision: SlowDownloadDecision) {
        guard downloadAccelerationRetryRequests[packageID] == nil else { return }
        guard let attempt = downloadAccelerationAttempts[packageID],
              DownloadAccelerationPolicy.shouldRequestCommandRetry(for: decision, attempt: attempt) else {
            if var progress = packageProgress[packageID],
               progress.accelerationStatusText != nil {
                progress.accelerationStatusText = "\(decision.message)，已是最后一种下载方式，继续等待当前下载"
                packageProgress[packageID] = progress
            }
            return
        }
        downloadAccelerationRetryRequests[packageID] = decision
        downloadAccelerationTokens[packageID]?.cancel()
    }

    // MARK: - Package status marks

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

    // MARK: - Package detail / Homebrew download monitoring

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
        downloadAccelerationTokens[packageID]?.cancel()
        downloadAccelerationTokens[packageID] = nil
        downloadAccelerationRetryRequests[packageID] = nil
        downloadAccelerationAttempts[packageID] = nil
        downloadAccelerationStrategies[packageID] = nil
        downloadAccelerationCleanups[packageID] = nil
        downloadSlowSampleState[packageID] = nil
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

        let key = packageID
        let now = Date()
        var state = downloadSlowSampleState[key] ?? (
            startedAt: now,
            lastGrowthAt: now,
            lastByteCount: snapshot.byteCount,
            consecutiveSlowSamples: 0
        )
        if snapshot.byteCount > state.lastByteCount {
            state.lastGrowthAt = now
            state.lastByteCount = snapshot.byteCount
        }
        let isSlowSpeed = (snapshot.speedBytesPerSecond ?? Double.greatestFiniteMagnitude) < DownloadAccelerationConfig.production.slowBytesPerSecond
        state.consecutiveSlowSamples = isSlowSpeed ? state.consecutiveSlowSamples + 1 : 0
        downloadSlowSampleState[key] = state

        let sample = DownloadSpeedSample(
            startedAt: state.startedAt,
            sampledAt: now,
            byteCount: snapshot.byteCount,
            expectedByteCount: snapshot.expectedByteCount,
            speedBytesPerSecond: snapshot.speedBytesPerSecond,
            secondsSinceLastGrowth: now.timeIntervalSince(state.lastGrowthAt),
            consecutiveSlowSamples: state.consecutiveSlowSamples
        )
        let decision = DownloadAccelerationPolicy.decision(for: sample)
        if decision.isRetryable {
            requestDownloadAccelerationRetry(packageID: packageID, decision: decision)
        }
        packageProgress[packageID] = progress
    }

    // MARK: - Failure analysis

    private func failureAnalysis(command: String, code: Int32, output: String) -> FailureAnalysis {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary: String
        let suggestion: String
        let action: FailureActionType?

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
}

// MARK: - Supporting types (moved from StewardModel)

struct FailureAnalysis {
    var summary: String
    var suggestion: String
    var action: FailureActionType?
    var copyText: String
    var command: String
}

enum JobRescanPolicy {
    static func shouldRescanAfterJobCompletion(rescanAfterSuccess: Bool, status: JobStatus) -> Bool {
        guard rescanAfterSuccess else { return false }
        switch status {
        case .succeeded, .failed, .warning:
            return true
        case .queued, .running, .cancelled, .timedOut:
            return false
        }
    }
}
