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
        let profile = AutomationProfileStore().profile
        // 使用统一 MaintenancePlanner 分类，与总览页/升级页保持一致的 automatic 判定。
        let plan = MaintenancePlanner.makePlan(scan: scan, policyStore: policyStore, includeGreedy: includeGreedy, profile: profile)
        let automaticPackages = plan.automaticItems.compactMap(\.package)
        // 同时用旧 UpgradePlanner 生成 rows，供巡检报告和 inbox 发布使用（向后兼容）。
        let rows = UpgradePlanner.makePlan(scan: scan, policyStore: policyStore, includeGreedy: includeGreedy)
        let inboxStore = InboxStore()
        let inboxItemIDs = DailyInspectionInboxPublisher.publish(scan: scan, rows: rows, to: inboxStore)

        func writeReportAndExit(_ exitCode: Int32, failure: InspectionFailureRecord? = nil) -> Never {
            InspectionReportStore().append(
                InspectionReportBuilder.makeReport(
                    trigger: .dailyAgent,
                    startedAt: startedAtDate,
                    finishedAt: Date(),
                    scan: scan,
                    rows: rows,
                    automaticPackages: automaticPackages,
                    inboxItemIDs: inboxItemIDs,
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
        // 跳过的包：不是 automatic 的计划项。
        for item in plan.items where item.disposition != .automatic {
            let reason = item.reasons.first ?? item.disposition.title
            print("[skip] \(item.packageName): \(reason)")
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
