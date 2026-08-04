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
    func executorDidRemoveStaleCaskRecord(packageID: String)
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
    /// 当前 job 并发批里挂起等待 sudo 重试的步骤（runJob 结束时结算）。
    private var sudoPendingSteps: [UpgradeStep] = []
    private var downloadMonitorTasks: [String: Task<Void, Never>] = [:]
    private var downloadSizeTasks: [String: Task<Void, Never>] = [:]
    private var downloadExpectedSizes: [String: Int64] = [:]
    private var downloadAccelerationStrategies: [String: [DownloadAccelerationStrategy]] = [:]
    private var downloadAccelerationAttempts: [String: CommandAccelerationAttempt] = [:]
    private var downloadAccelerationRetryRequests: [String: SlowDownloadDecision] = [:]
    private var downloadAccelerationTokens: [String: CommandCancellationToken] = [:]
    private var downloadSlowSampleState: [String: (startedAt: Date, lastGrowthAt: Date, lastByteCount: Int64, consecutiveSlowSamples: Int)] = [:]
    private var autoRepairAttemptedPackageIDs: Set<String> = []

    private let historyStore: UpgradeHistoryStore
    private let downloadStrategiesProvider: () async -> [DownloadAccelerationStrategy]

    var hasRunningJob: Bool {
        jobs.contains { $0.status == .queued || $0.status == .running }
    }

    init(
        historyStore: UpgradeHistoryStore,
        maxConcurrentUpgrades: Int = UserDefaults.standard.object(forKey: "maxConcurrentUpgrades") as? Int ?? 3,
        downloadStrategiesProvider: @escaping () async -> [DownloadAccelerationStrategy] = DownloadAccelerationPolicy.defaultStrategies,
        host: MaintenanceExecutorHost? = nil
    ) {
        self.historyStore = historyStore
        self.maxConcurrentUpgrades = maxConcurrentUpgrades
        self.downloadStrategiesProvider = downloadStrategiesProvider
        self.host = host
    }

    func setHost(_ host: MaintenanceExecutorHost?) {
        self.host = host
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

        // 并发批结束后：若收集到 needsSudo 步骤，弹一次密码框批量重试。
        if !shouldStop && !sudoPendingSteps.isEmpty {
            let pending = sudoPendingSteps
            sudoPendingSteps.removeAll()
            let sudoFailures = await runSudoRetryBatch(jobID: id, steps: pending, token: token)
            failedCount += sudoFailures
            if sudoFailures > 0 && firstErrorCode == nil {
                firstErrorCode = 1
            }
        } else {
            // 批被取消：挂起的 needsSudo 包按取消处理，不留中间态。
            for step in sudoPendingSteps { markCancelled(step) }
            sudoPendingSteps.removeAll()
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
                    // cask 升级前尝试通过国内镜像预下载到 brew 缓存，绕过 GitHub 直连慢的问题。
                    // 失败静默跳过，不影响原有 brew 下载流程。
                    if executor.isCaskStep(step) {
                        await executor.prefetchCask(jobID: id, step: step, token: token)
                    }
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
            } else if UpgradeFailureAnalyzer.requiresSudo(in: result.recentOutput) {
                // 卡在 sudo 密码：不立即计失败，挂起等待批量 osascript 重试。
                markNeedsSudo(step)
                sudoPendingSteps.append(step)
                host?.executorRequestsDerivedDataRecompute()
                updateJob(id) {
                    $0.log.append(LogLine(stream: "system", text: "需要管理员密码：\(command.display)，将批量请求授权后重试"))
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

    /// sudo 批次重试：把所有 needsSudo 的 cask 合并成一条 osascript，
    /// 弹一次系统原生密码框串行跑完，按 __RC__ 标记回填每个包状态。
    /// 密码由 macOS SecurityServer 处理，本进程绝不接触。
    /// 返回 sudo 批新增的失败数（供 runJob 累加到 failedCount）。
    private func runSudoRetryBatch(
        jobID id: UUID,
        steps: [UpgradeStep],
        token: CommandCancellationToken
    ) async -> Int {
        var failedInSudo = 0
        guard !steps.isEmpty else { return 0 }

        // 1. 解析 brew 绝对路径与最小环境（CommandRunner.processEnvironment 是 private，
        //    这里只取 PATH/HOME 透传给 root shell）。
        guard let brewPath = try? await requireCommand("brew") else {
            for step in steps {
                failedInSudo += 1
                markFailed(step, analysis: FailureAnalysis(
                    summary: "未找到 brew 命令，无法请求管理员授权升级。",
                    suggestion: "请确认 Homebrew 已安装，然后重试。",
                    action: .rescan,
                    copyText: "",
                    command: step.command.display
                ))
            }
            return failedInSudo
        }
        let pathEnv = CommandRunner.defaultPath
        let homeEnv = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()

        // 2. 按包名顺序拼脚本。
        let packageNames = steps.compactMap { $0.packageName }
        let script = SudoScriptBuilder.script(brewPath: brewPath, packageNames: packageNames, pathEnv: pathEnv, homeEnv: homeEnv)
        let args = SudoScriptBuilder.osaArguments(script)

        updateJob(id) {
            $0.log.append(LogLine(stream: "system", text: "sudo 批次：osascript 提权执行 \(packageNames.count) 个 cask 升级"))
            $0.log.append(LogLine(stream: "system", text: "正在请求管理员密码…"))
        }
        updateUpgradeProgress(currentPackage: "等待管理员授权升级 \(packageNames.count) 个软件")

        // 3. 流式跑 osascript，实时回传日志。
        appendLog(id: id, stream: "command", text: "$ osascript -e <do shell script ... with administrator privileges>（\(packageNames.joined(separator: ", "))）")
        let result = await CommandRunner.runStreamingDetailed(
            "/usr/bin/osascript",
            arguments: args,
            timeout: 7200,
            cancellationToken: token
        ) { [weak self] stream, text in
            Task { @MainActor in
                self?.appendLog(id: id, stream: stream, text: text)
            }
        }

        // 4. 用户取消密码框 / osascript 整体失败：每个包标失败，允许重试。
        if result.terminationReason == .cancelled {
            for step in steps { markCancelled(step) }
            updateJob(id) { $0.log.append(LogLine(stream: "system", text: "sudo 批次已取消")) }
            return failedInSudo
        }
        if result.code != 0 && !result.recentOutput.contains("__RC_") {
            // 整条 osascript 失败（如用户在密码框点取消、密码错误 3 次），无任何包完成。
            for step in steps {
                failedInSudo += 1
                markFailed(step, analysis: FailureAnalysis(
                    summary: "管理员授权未完成，sudo 升级被取消。",
                    suggestion: "点击「重试」会再次弹出密码框。若密码错误，请确认管理员密码后重试。",
                    action: .promptAdminPassword,
                    copyText: step.command.display,
                    command: step.command.display
                ))
            }
            updateJob(id) { $0.log.append(LogLine(stream: "system", text: "sudo 批次授权未完成，退出码 \(result.code)")) }
            return failedInSudo
        }

        // 5. 解析 __RC__ 标记，回填每个包。
        let parsed = SudoScriptParser.outcomes(in: result.recentOutput, count: packageNames.count)
        for (index, step) in steps.enumerated() {
            let pkgIndex = index + 1
            let outcome = parsed.first { $0.packageIndex == pkgIndex }
                ?? SudoScriptParser.Outcome(packageIndex: pkgIndex, exitCode: -1, outputSegment: "")

            if outcome.exitCode == 0 {
                markSucceeded(step)
                host?.executorRequestsDerivedDataRecompute()
                updateJob(id) { $0.log.append(LogLine(stream: "system", text: "sudo 升级完成：\(step.packageName ?? "")")) }
            } else {
                // 已 sudo 过仍失败：不是密码问题，走常规失败分析，但 action 降级为可重试。
                var analysis = failureAnalysis(command: step.command.display, code: outcome.exitCode, output: outcome.outputSegment)
                if analysis.action == .retryInTerminal {
                    analysis.action = .promptAdminPassword
                }
                failedInSudo += 1
                markFailed(step, analysis: analysis)
                host?.executorRequestsDerivedDataRecompute()
                updateJob(id) { $0.log.append(LogLine(stream: "system", text: "sudo 升级失败：\(step.packageName ?? "")，退出码 \(outcome.exitCode)")) }
            }
        }
        return failedInSudo
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
        return "升级未成功完成，可重试或在终端运行相关命令检查。"
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
        try await MaintenanceCommandResolver.command(for: package, includeGreedy: includeGreedy)
    }

    func requireCommand(_ command: String) async throws -> String {
        try await MaintenanceCommandResolver.requireCommand(command)
    }

    // MARK: - Download acceleration

    private func accelerationKey(for step: UpgradeStep) -> String {
        step.packageID ?? step.command.display
    }

    /// 判断 step 是否为 cask 升级（packageID 含 ":cask:"）。
    /// nonisolated：只读值类型 step，不访问可变状态，可在任意 actor 上下文同步调用。
    nonisolated private func isCaskStep(_ step: UpgradeStep) -> Bool {
        step.packageID?.contains(":cask:") == true
    }

    /// 通过国内镜像预下载 cask 文件到 brew 缓存。
    /// brew 发现缓存文件后会跳过下载。失败静默跳过，不影响原有流程。
    private func prefetchCask(jobID id: UUID, step: UpgradeStep, token: CommandCancellationToken) async {
        guard let caskName = step.packageName, !caskName.isEmpty else { return }
        guard step.packageID != nil else { return }
        guard token.isCancelled == false else { return }

        let brewPath: String
        do {
            brewPath = try await requireCommand("brew")
        } catch {
            return
        }

        let info = await CommandRunner.run(
            brewPath,
            arguments: ["info", "--cask", "--json=v2", caskName],
            timeout: 30
        )
        guard info.ok, let downloadInfo = CaskMirrorPrefetcher.resolveDownloadInfo(from: info.stdout, caskName: caskName) else {
            return
        }

        appendLog(id: id, stream: "system", text: "正在通过国内镜像预下载 \(caskName)…")
        updatePackageDetail(for: step, phaseText: "镜像预下载", downloadFraction: 0)

        let prefetched = await CaskMirrorPrefetcher.prefetch(info: downloadInfo) { fraction in
            Task { @MainActor in
                self.updatePackageDetail(for: step, phaseText: "镜像预下载 \(Int(fraction * 100))%", downloadFraction: fraction)
            }
        }

        if prefetched {
            appendLog(id: id, stream: "system", text: "镜像预下载完成，brew 将使用缓存安装。")
        } else {
            appendLog(id: id, stream: "system", text: "镜像预下载未成功，使用默认下载方式。")
        }
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
        if step.purpose == .staleCaskCleanup {
            host?.executorDidRemoveStaleCaskRecord(packageID: packageID)
        }
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

    private func markNeedsSudo(_ step: UpgradeStep) {
        guard let packageID = step.packageID, let packageName = step.packageName else { return }
        packageProgress[packageID] = PackageUpgradeProgress(
            packageID: packageID,
            packageName: packageName,
            status: .needsSudo,
            detail: "等待管理员授权升级"
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

    /// 直接设置进度项的阶段文本和下载百分比（用于镜像预下载阶段）。
    private func updatePackageDetail(for step: UpgradeStep, phaseText: String, downloadFraction: Double?) {
        guard let packageID = step.packageID, var progress = packageProgress[packageID] else { return }
        progress.phaseText = phaseText
        if let fraction = downloadFraction { progress.downloadFraction = fraction }
        progress.updatedAt = Date()
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
        MaintenanceFailureAnalyzer.failureAnalysis(command: command, code: code, output: output)
    }
}

// MARK: - Supporting types (moved from StewardModel)

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
