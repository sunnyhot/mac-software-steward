import AppKit
import Foundation

@MainActor
final class StewardModel: ObservableObject {
    @Published var selectedTab: AppTab = .updates
    @Published var scan: ScanResult?
    @Published var isScanning = false
    @Published var includeGreedy = true
    @Published var runBrewUpdate = true
    @Published var query = ""
    @Published var errorMessage = ""
    @Published var jobs: [UpgradeJob] = []
    @Published var dailyInspectionEnabled = false
    @Published var dailyHour = 9
    @Published var dailyMinute = 0
    @Published var dailyLog = ""
    @Published var dailyLaunchAgentPath = DailyInspectionScheduler.launchAgentURL.path
    @Published var dailyLogPath = DailyInspectionScheduler.logURL.path
    @Published var packageProgress: [String: PackageUpgradeProgress] = [:]
    @Published var maxConcurrentUpgrades: Int = UserDefaults.standard.object(forKey: "maxConcurrentUpgrades") as? Int ?? 3 {
        didSet { UserDefaults.standard.set(maxConcurrentUpgrades, forKey: "maxConcurrentUpgrades") }
    }

    private var activeJobCount = 0
    private var pendingJobQueue: [(id: UUID, steps: [UpgradeStep], rescanAfterSuccess: Bool)] = []
    @Published var upgradeProgress: UpgradeProgress?

    init() {
        refreshDailyInspectionStatus()
    }

    var availableUpdates: [UpdatablePackage] {
        guard let scan else { return [] }
        return (scan.brew.formulae.filter(\.upgradeable).map(UpdatablePackage.brew)
            + scan.brew.casks.filter(\.upgradeable).map(UpdatablePackage.brew)
            + scan.mas.apps.filter(\.upgradeable).map(UpdatablePackage.mas))
            .filter { package in
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

        if let job = jobs.first(where: { $0.status == .failed }) {
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
        isScanning = true
        errorMessage = ""
        let result = await SoftwareScanner.scanAll(includeGreedy: includeGreedy)
        scan = result
        prunePackageProgress(keeping: result)
        isScanning = false
    }

    func upgrade(_ package: UpdatablePackage) async {
        guard !isPackageActive(package.id) else { return }
        do {
            let command = try await command(for: package)
            enqueueJob(label: "升级 \(package.name)", steps: [
                UpgradeStep(command: command, packageID: package.id, packageName: package.name)
            ], rescanAfterSuccess: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 重试升级某个包（清除失败状态后重新执行）
    func retryPackage(_ packageID: String) async {
        // 清除旧的失败状态
        packageProgress.removeValue(forKey: packageID)
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
    }

    func upgradeAll() async {
        do {
            var steps: [UpgradeStep] = []
            let brewUpdates = availableUpdates.compactMap { package -> BrewPackage? in
                guard !isPackageActive(package.id) else { return nil }
                if case .brew(let brewPackage) = package, brewPackage.upgradeable { return brewPackage }
                return nil
            }
            let masUpdates = availableUpdates.compactMap { package -> MasApp? in
                guard !isPackageActive(package.id) else { return nil }
                if case .mas(let app) = package, app.upgradeable { return app }
                return nil
            }

            if !brewUpdates.isEmpty {
                let brew = try await requireCommand("brew")
                if runBrewUpdate {
                    let update = UpgradeCommand(executable: brew, arguments: ["update"], display: "brew update")
                    steps.append(UpgradeStep(command: update, packageID: nil, packageName: nil))
                }
                for package in brewUpdates {
                    let updatable = UpdatablePackage.brew(package)
                    let command = try await command(for: updatable)
                    steps.append(UpgradeStep(command: command, packageID: updatable.id, packageName: updatable.name))
                }
            }

            for app in masUpdates {
                let updatable = UpdatablePackage.mas(app)
                let command = try await command(for: updatable)
                steps.append(UpgradeStep(command: command, packageID: updatable.id, packageName: updatable.name))
            }

            guard !steps.isEmpty else {
                throw StewardError.message("没有可升级的可管理软件。")
            }

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

        for step in steps {
            let command = step.command
            markRunning(step)
            if step.packageName != nil {
                updateUpgradeProgress(currentPackage: step.packageName)
            }
            appendLog(id: id, stream: "command", text: "$ \(command.display)")
            let result = await CommandRunner.runStreamingDetailed(command.executable, arguments: command.arguments) { stream, text in
                Task { @MainActor in
                    self.appendLog(id: id, stream: stream, text: text)
                    self.updatePackageDetail(for: step, stream: stream, text: text)
                }
            }
            let code = result.code

            if code != 0 {
                failedCount += 1
                if firstErrorCode == nil { firstErrorCode = code }
                let analysis = failureAnalysis(command: command.display, code: code, output: result.recentOutput)
                markFailed(step, analysis: analysis)
                updateJob(id) {
                    $0.log.append(LogLine(stream: "system", text: "失败：\(command.display)，退出码 \(code)"))
                }
            } else {
                markSucceeded(step)
            }

            if step.packageID != nil {
                completedSteps += 1
                updateUpgradeProgress(completed: completedSteps, failed: failedCount, currentPackage: nil)
            }
        }

        updateJob(id) {
            if failedCount > 0 {
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

        upgradeProgress = nil

        if rescanAfterSuccess {
            await scanSoftware()
        }
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
            detail: step.command.display
        )
    }

    private func markSucceeded(_ step: UpgradeStep) {
        guard let packageID = step.packageID, let packageName = step.packageName else { return }
        packageProgress[packageID] = PackageUpgradeProgress(
            packageID: packageID,
            packageName: packageName,
            status: .succeeded,
            detail: "升级完成"
        )
    }

    private func markFailed(_ step: UpgradeStep, analysis: FailureAnalysis) {
        guard let packageID = step.packageID, let packageName = step.packageName else { return }
        packageProgress[packageID] = PackageUpgradeProgress(
            packageID: packageID,
            packageName: packageName,
            status: .failed,
            detail: analysis.summary,
            failureSummary: analysis.summary,
            recoverySuggestion: analysis.suggestion,
            copyText: analysis.copyText,
            recoveryAction: analysis.action
        )
    }

    private func updatePackageDetail(for step: UpgradeStep, stream: String, text: String) {
        guard let packageID = step.packageID, var progress = packageProgress[packageID] else { return }
        guard progress.status == .running else { return }
        progress.detail = "[\(stream)] \(text)"
        progress.updatedAt = Date()
        packageProgress[packageID] = progress
    }

    private func failureAnalysis(command: String, code: Int32, output: String) -> FailureAnalysis {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary: String
        let suggestion: String
        let action: FailureActionType?

        if let hint = knownFailureHint(in: trimmed) {
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

        return FailureAnalysis(summary: summary, suggestion: suggestion, action: action, copyText: copyText)
    }

    private func knownFailureHint(in output: String) -> FailureHint? {
        let lowercased = output.lowercased()

        // 1. 应用正在运行
        if lowercased.contains("is currently running") || lowercased.contains("app is running") || lowercased.contains("application is running") {
            return FailureHint(
                summary: "该应用正在运行中，无法被替换。",
                suggestion: "请先关闭该应用（可在 Dock 栏右键退出，或按 ⌘+Q），然后点击「重试」。",
                action: .quitAndRetry
            )
        }

        // 2. 应用已存在（Cask 覆盖冲突）
        if lowercased.contains("already exists") || lowercased.contains("it seems there is already an app") || lowercased.contains("app already exists") {
            return FailureHint(
                summary: "目标位置已存在同名应用，无法直接覆盖安装。",
                suggestion: "请先关闭该应用，然后点击「重试」重新覆盖安装。",
                action: .reimport
            )
        }

        // 3. 权限不足
        if lowercased.contains("permission denied") || lowercased.contains("operation not permitted") || lowercased.contains("eacces") {
            return FailureHint(
                summary: "没有写入权限，无法完成安装。",
                suggestion: "请尝试点击「重试」。如果仍然失败，可在「系统设置 > 隐私与安全性」中检查 Homebrew 的磁盘访问权限。",
                action: .repairPerms
            )
        }

        // 4. 校验失败（缓存损坏）
        if lowercased.contains("checksum mismatch") || lowercased.contains("sha256 mismatch") {
            return FailureHint(
                summary: "下载的文件校验不通过，可能是缓存损坏。",
                suggestion: "请点击「重试」，系统会自动清理缓存后重新下载。",
                action: .cleanup
            )
        }

        // 5. 网络/下载超时
        if lowercased.contains("timeout") || lowercased.contains("timed out") || lowercased.contains("connection refused") || lowercased.contains("could not resolve") || lowercased.contains("network") || (lowercased.contains("curl") && lowercased.contains("error")) {
            return FailureHint(
                summary: "网络连接出现问题，下载失败。",
                suggestion: "请检查网络连接是否正常，然后点击「重试」。如果使用代理，请确认代理配置正确。",
                action: .checkNetwork
            )
        }

        // 6. 磁盘空间不足
        if lowercased.contains("no space left") || lowercased.contains("disk full") || lowercased.contains("not enough space") || lowercased.contains("enospc") {
            return FailureHint(
                summary: "磁盘空间不足，无法完成下载和安装。",
                suggestion: "请清理磁盘空间后再试。可以在「系统设置 > 通用 > 储存空间」中查看和清理。",
                action: .freeDisk
            )
        }

        // 7. 版本冲突/依赖问题
        if lowercased.contains("version conflict") || lowercased.contains("conflicting") || (lowercased.contains("depends on") && lowercased.contains("not installed")) || lowercased.contains("broken") || lowercased.contains("dependency") {
            return FailureHint(
                summary: "存在依赖关系问题，无法直接升级。",
                suggestion: "请点击「重试」。如果持续失败，可以先在「管理来源」页面更新 Homebrew 本身，再重新扫描。",
                action: .rescan
            )
        }

        // 8. 文件/工具不存在
        if lowercased.contains("no such file or directory") || lowercased.contains("not found") {
            return FailureHint(
                summary: "所需的文件或工具未找到。",
                suggestion: "请点击「重新扫描」刷新软件列表后再试。如果仍然失败，该软件可能已被卸载。",
                action: .rescan
            )
        }

        // 9. 下载被中断
        if lowercased.contains("download") && (lowercased.contains("interrupted") || lowercased.contains("failed") || lowercased.contains("incomplete")) {
            return FailureHint(
                summary: "下载过程中被中断，文件不完整。",
                suggestion: "请点击「重试」重新下载。",
                action: .retry
            )
        }

        return nil
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
}

private struct FailureAnalysis {
    var summary: String
    var suggestion: String
    var action: FailureActionType?
    var copyText: String
}

private struct FailureHint {
    var summary: String
    var suggestion: String
    var action: FailureActionType
}

enum StewardError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}
