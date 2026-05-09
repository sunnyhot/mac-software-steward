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

    init() {
        refreshDailyInspectionStatus()
    }

    var availableUpdates: [UpdatablePackage] {
        guard let scan else { return [] }
        return scan.brew.formulae.filter(\.outdated).map(UpdatablePackage.brew)
            + scan.brew.casks.filter(\.outdated).map(UpdatablePackage.brew)
            + scan.mas.apps.filter(\.outdated).map(UpdatablePackage.mas)
    }

    var hasRunningJob: Bool {
        jobs.contains { $0.status == .queued || $0.status == .running }
    }

    var canInstallMasCLI: Bool {
        scan?.brew.available == true && scan?.mas.available == false
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
        do {
            let command = try await command(for: package)
            startJob(label: "升级 \(package.name)", steps: [
                UpgradeStep(command: command, packageID: package.id, packageName: package.name)
            ], rescanAfterSuccess: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func upgradeAll() async {
        do {
            var steps: [UpgradeStep] = []
            let brewUpdates = availableUpdates.compactMap { package -> BrewPackage? in
                if case .brew(let brewPackage) = package, brewPackage.upgradeable { return brewPackage }
                return nil
            }
            let masUpdates = availableUpdates.compactMap { package -> MasApp? in
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

            startJob(label: "一键升级可管理软件", steps: steps, rescanAfterSuccess: true)
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

        Task {
            await runJob(id: id, steps: steps, rescanAfterSuccess: rescanAfterSuccess)
        }
    }

    private func runJob(id: UUID, steps: [UpgradeStep], rescanAfterSuccess: Bool) async {
        updateJob(id) {
            $0.status = .running
            $0.startedAt = Date()
            $0.log.append(LogLine(stream: "system", text: "开始：\($0.label)"))
        }

        for (index, step) in steps.enumerated() {
            let command = step.command
            markRunning(step)
            appendLog(id: id, stream: "command", text: "$ \(command.display)")
            let code = await CommandRunner.runStreaming(command.executable, arguments: command.arguments) { stream, text in
                Task { @MainActor in
                    self.appendLog(id: id, stream: stream, text: text)
                    self.updatePackageDetail(for: step, stream: stream, text: text)
                }
            }

            if code != 0 {
                markFailed(step, detail: "退出码 \(code)")
                markPendingFailed(Array(steps.dropFirst(index + 1)), detail: "前一步失败，未执行")
                updateJob(id) {
                    $0.status = .failed
                    $0.exitCode = code
                    $0.finishedAt = Date()
                    $0.log.append(LogLine(stream: "system", text: "失败：\(command.display)，退出码 \(code)"))
                }
                return
            }

            markSucceeded(step)
        }

        updateJob(id) {
            $0.status = .succeeded
            $0.exitCode = 0
            $0.finishedAt = Date()
            $0.log.append(LogLine(stream: "system", text: "完成"))
        }

        if rescanAfterSuccess {
            await scanSoftware()
        }
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

    private func markFailed(_ step: UpgradeStep, detail: String) {
        guard let packageID = step.packageID, let packageName = step.packageName else { return }
        packageProgress[packageID] = PackageUpgradeProgress(
            packageID: packageID,
            packageName: packageName,
            status: .failed,
            detail: detail
        )
    }

    private func markPendingFailed(_ steps: [UpgradeStep], detail: String) {
        for step in steps {
            guard let packageID = step.packageID,
                  packageProgress[packageID]?.status == .queued else { continue }
            markFailed(step, detail: detail)
        }
    }

    private func updatePackageDetail(for step: UpgradeStep, stream: String, text: String) {
        guard let packageID = step.packageID, var progress = packageProgress[packageID] else { return }
        guard progress.status == .running else { return }
        progress.detail = "[\(stream)] \(text)"
        progress.updatedAt = Date()
        packageProgress[packageID] = progress
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

enum StewardError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}
