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
        isScanning = false
    }

    func upgrade(_ package: UpdatablePackage) async {
        do {
            let command = try await command(for: package)
            startJob(label: "升级 \(package.name)", commands: [command])
            selectedTab = .jobs
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func upgradeAll() async {
        do {
            var commands: [UpgradeCommand] = []
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
                    commands.append(UpgradeCommand(executable: brew, arguments: ["update"], display: "brew update"))
                }
                if brewUpdates.contains(where: { $0.kind == "formula" }) {
                    commands.append(UpgradeCommand(executable: brew, arguments: ["upgrade"], display: "brew upgrade"))
                }
                if brewUpdates.contains(where: { $0.kind == "cask" }) {
                    let args = ["upgrade", "--cask"] + (includeGreedy ? ["--greedy"] : [])
                    commands.append(UpgradeCommand(executable: brew, arguments: args, display: (["brew"] + args).joined(separator: " ")))
                }
            }

            if !masUpdates.isEmpty {
                let mas = try await requireCommand("mas")
                commands.append(UpgradeCommand(executable: mas, arguments: ["upgrade"], display: "mas upgrade"))
            }

            guard !commands.isEmpty else {
                throw StewardError.message("没有可升级的可管理软件。")
            }

            startJob(label: "一键升级可管理软件", commands: commands)
            selectedTab = .jobs
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
        let job = UpgradeJob(label: label, commands: commands.map(\.display))
        jobs.insert(job, at: 0)
        let id = job.id

        Task {
            await runJob(id: id, commands: commands, rescanAfterSuccess: rescanAfterSuccess)
        }
    }

    private func runJob(id: UUID, commands: [UpgradeCommand], rescanAfterSuccess: Bool) async {
        updateJob(id) {
            $0.status = .running
            $0.startedAt = Date()
            $0.log.append(LogLine(stream: "system", text: "开始：\($0.label)"))
        }

        for command in commands {
            appendLog(id: id, stream: "command", text: "$ \(command.display)")
            let code = await CommandRunner.runStreaming(command.executable, arguments: command.arguments) { stream, text in
                Task { @MainActor in
                    self.appendLog(id: id, stream: stream, text: text)
                }
            }

            if code != 0 {
                updateJob(id) {
                    $0.status = .failed
                    $0.exitCode = code
                    $0.finishedAt = Date()
                    $0.log.append(LogLine(stream: "system", text: "失败：\(command.display)，退出码 \(code)"))
                }
                return
            }
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
