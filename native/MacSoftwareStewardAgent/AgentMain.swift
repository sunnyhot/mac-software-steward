import Foundation

@main
struct MacSoftwareStewardAgent {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.first == "daily-check" else {
            print("Usage: MacSoftwareStewardAgent daily-check [--auto-upgrade] [--greedy] [--brew-update]")
            Foundation.exit(2)
        }

        let autoUpgrade = arguments.contains("--auto-upgrade")
        let includeGreedy = arguments.contains("--greedy")
        let runBrewUpdate = arguments.contains("--brew-update")
        let startedAtDate = Date()
        let startedAt = ISO8601DateFormatter().string(from: startedAtDate)

        print("[system] \(startedAt) 每日巡检开始")
        let scan = await SoftwareScanner.scanAll(includeGreedy: includeGreedy)
        print("[scan] 应用 \(scan.summary.applications)，formula \(scan.summary.brewFormulae)，cask \(scan.summary.brewCasks)，可操作升级 \(scan.summary.actionable)")

        let policyStore = UpgradePolicyStore()
        let rows = UpgradePlanner.makePlan(scan: scan, policyStore: policyStore, includeGreedy: includeGreedy)
        let automaticPackages = DailyUpgradePolicy.automaticPackages(from: rows)
        func writeReportAndExit(_ exitCode: Int32, failure: InspectionFailureRecord? = nil) -> Never {
            InspectionReportStore().append(
                InspectionReportBuilder.makeReport(
                    trigger: .dailyAgent,
                    startedAt: startedAtDate,
                    finishedAt: Date(),
                    scan: scan,
                    rows: rows,
                    automaticPackages: automaticPackages,
                    failure: failure
                )
            )
            Foundation.exit(exitCode)
        }

        let formulaUpdates = automaticPackages.compactMap { package -> BrewPackage? in
            if case .brew(let brew) = package, brew.kind == "formula" { return brew }
            return nil
        }
        let caskUpdates = automaticPackages.compactMap { package -> BrewPackage? in
            if case .brew(let brew) = package, brew.kind == "cask" { return brew }
            return nil
        }
        let masUpdates = automaticPackages.compactMap { package -> MasApp? in
            if case .mas(let app) = package { return app }
            return nil
        }
        let skipped = rows.filter { $0.policy != .automatic || !$0.canExecute }
        for row in skipped {
            let reason = row.skipReason.isEmpty ? row.policy.title : row.skipReason
            print("[skip] \(row.packageName): \(reason)")
        }

        guard !formulaUpdates.isEmpty || !caskUpdates.isEmpty || !masUpdates.isEmpty else {
            print("[system] 未发现可自动升级的软件")
            writeReportAndExit(0)
        }

        print("[updates] formula: \(formulaUpdates.map(\.name).joined(separator: ", "))")
        print("[updates] cask: \(caskUpdates.map(\.name).joined(separator: ", "))")
        print("[updates] mas: \(masUpdates.map(\.name).joined(separator: ", "))")

        guard autoUpgrade else {
            print("[system] 已禁用自动升级，仅完成巡检")
            writeReportAndExit(0)
        }

        var commands: [(String, [String], String)] = []

        if !formulaUpdates.isEmpty || !caskUpdates.isEmpty {
            guard let brew = await CommandRunner.commandPath("brew") else {
                print("[error] 发现 Homebrew 更新，但找不到 brew")
                writeReportAndExit(
                    1,
                    failure: InspectionFailureRecord(
                        message: "发现 Homebrew 更新，但找不到 brew",
                        commandDisplay: "brew",
                        exitCode: 1
                    )
                )
            }
            if runBrewUpdate {
                commands.append((brew, ["update"], "brew update"))
            }
            for formula in formulaUpdates {
                let args = ["upgrade", formula.name]
                commands.append((brew, args, (["brew"] + args).joined(separator: " ")))
            }
            for cask in caskUpdates {
                let args = ["upgrade", "--cask"] + (includeGreedy ? ["--greedy"] : []) + [cask.name]
                commands.append((brew, args, (["brew"] + args).joined(separator: " ")))
            }
        }

        if !masUpdates.isEmpty {
            if let mas = await CommandRunner.commandPath("mas") {
                for app in masUpdates {
                    let args = ["upgrade", app.appId]
                    commands.append((mas, args, (["mas"] + args).joined(separator: " ")))
                }
            } else {
                print("[warn] 发现 Mac App Store 更新，但 mas CLI 不可用，已跳过")
            }
        }

        for command in commands {
            print("[command] $ \(command.2)")
            let code = await CommandRunner.runStreaming(command.0, arguments: command.1) { stream, text in
                print("[\(stream)] \(text)")
            }
            if code != 0 {
                print("[error] 命令失败：\(command.2)，退出码 \(code)")
                writeReportAndExit(
                    code,
                    failure: InspectionFailureRecord(
                        message: "命令失败",
                        commandDisplay: command.2,
                        exitCode: code
                    )
                )
            }
        }

        print("[system] 每日巡检自动升级完成")
        writeReportAndExit(0)
    }
}
