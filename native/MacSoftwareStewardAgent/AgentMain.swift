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
        // 与 GUI「一键升级」一致的可执行升级集合（排除本轮已自动处理的项）。
        // 巡检结束时用它通知「发现 N 个可升级项目」，避免与一键升级口径不一致：
        // 自动升级只处理 automatic 项，但"检测到升级"应包括所有 canExecute 项（如需确认的 cask）。
        let automaticPackageIDs = Set(automaticPackages.map(\.id))
        let availableUpgradeCount = rows.filter { $0.canExecute && !automaticPackageIDs.contains($0.packageID) }.count
        let inboxStore = InboxStore()
        let inboxItemIDs = DailyInspectionInboxPublisher.publish(scan: scan, rows: rows, to: inboxStore)
        let publishedInboxItems = inboxStore.items.filter { inboxItemIDs.contains($0.id) }
        // 「需要确认升级」类收件箱条目与 availableUpgradeCount 指向同一批升级，
        // 通知决策时剔除它们，避免同一批升级被重复计数。
        let notificationInboxItems = publishedInboxItems.filter { item in
            !(item.sourceID?.hasPrefix("upgrade:") ?? false)
        }

        func finish(
            _ exitCode: Int32,
            failures: [InspectionFailureRecord] = [],
            succeededUpgradeCount: Int = 0
        ) async -> Never {
            InspectionReportStore().append(
                InspectionReportBuilder.makeReport(
                    trigger: .dailyAgent,
                    startedAt: startedAtDate,
                    finishedAt: Date(),
                    scan: scan,
                    rows: rows,
                    automaticPackages: automaticPackages,
                    inboxItemIDs: inboxItemIDs,
                    failures: failures
                )
            )

            let notificationDecision: AutomationNotificationDecision?
            if failures.isEmpty {
                notificationDecision = AutomationNotificationDecider.decision(
                    policy: profile.notificationPolicy,
                    newInboxItems: notificationInboxItems,
                    automaticUpgradeCount: succeededUpgradeCount,
                    availableUpgradeCount: availableUpgradeCount
                )
            } else {
                notificationDecision = AutomationNotificationDecider.failureDecision(
                    policy: profile.notificationPolicy,
                    failures: failures
                )
            }
            if let notificationDecision {
                // agent 由 launchd 启动，无 LaunchServices 应用身份，直接投递系统通知
                // 会抛 UNErrorDomain 错误 1；改为持久化，由 GUI 应用下次启动时代投。
                AutomationNotificationPayloadStore.save(notificationDecision)
            }
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
            if availableUpgradeCount > 0 {
                print("[system] 检测到 \(availableUpgradeCount) 项可升级，但均需确认或不符合自动升级条件，本次未自动升级")
            } else {
                print("[system] 未发现需要升级的软件")
            }
            await finish(0)
        }

        print("[updates] formula: \(formulaUpdates.map(\.name).joined(separator: ", "))")
        print("[updates] cask: \(caskUpdates.map(\.name).joined(separator: ", "))")
        print("[updates] mas: \(masUpdates.map(\.name).joined(separator: ", "))")

        guard autoUpgrade else {
            print("[system] 已禁用自动升级，仅完成巡检")
            await finish(0)
        }

        // (可执行文件, 参数, 展示文本, 包 ID)。包 ID 用于升级成功后移除对应收件箱待办。
        var commands: [(executable: String, arguments: [String], display: String, packageID: String?)] = []
        var failures: [InspectionFailureRecord] = []

        if !formulaUpdates.isEmpty || !caskUpdates.isEmpty {
            if let brew = await CommandRunner.commandPath("brew") {
                if runBrewUpdate {
                    print("[command] $ brew update")
                    let code = await CommandRunner.runStreaming(brew, arguments: ["update"]) { stream, text in
                        print("[\(stream)] \(text)")
                    }
                    if code != 0 {
                        print("[warn] brew update 失败，退出码 \(code)；继续使用当前元数据处理其余项目")
                        failures.append(
                            InspectionFailureRecord(
                                message: "brew update 失败，已继续处理其他项目",
                                commandDisplay: "brew update",
                                exitCode: code
                            )
                        )
                    }
                }
                for formula in formulaUpdates {
                    let args = ["upgrade", formula.name]
                    commands.append((brew, args, (["brew"] + args).joined(separator: " "), formula.id))
                }
                for cask in caskUpdates {
                    let args = ["upgrade", "--cask"] + (includeGreedy ? ["--greedy"] : []) + [cask.name]
                    commands.append((brew, args, (["brew"] + args).joined(separator: " "), cask.id))
                }
            } else {
                print("[error] 发现 Homebrew 更新，但找不到 brew")
                failures.append(
                    InspectionFailureRecord(
                        message: "发现 Homebrew 更新，但找不到 brew",
                        commandDisplay: "brew",
                        exitCode: 1
                    )
                )
            }
        }

        if !masUpdates.isEmpty {
            if let mas = await CommandRunner.commandPath("mas") {
                for app in masUpdates {
                    let args = ["upgrade", app.appId]
                    commands.append((mas, args, (["mas"] + args).joined(separator: " "), app.id))
                }
            } else {
                print("[warn] 发现 Mac App Store 更新，但 mas CLI 不可用，已跳过")
                failures.append(
                    InspectionFailureRecord(
                        message: "mas CLI 不可用，已跳过 Mac App Store 更新",
                        commandDisplay: "mas",
                        exitCode: nil
                    )
                )
            }
        }

        var succeededUpgradeCount = 0
        var succeededPackageIDs: Set<String> = []
        for command in commands {
            print("[command] $ \(command.display)")
            let code = await CommandRunner.runStreaming(command.executable, arguments: command.arguments) { stream, text in
                print("[\(stream)] \(text)")
            }
            if code != 0 {
                print("[error] 命令失败：\(command.display)，退出码 \(code)")
                failures.append(
                    InspectionFailureRecord(
                        message: "命令失败",
                        commandDisplay: command.display,
                        exitCode: code
                    )
                )
            } else {
                succeededUpgradeCount += 1
                if let packageID = command.packageID {
                    succeededPackageIDs.insert(packageID)
                }
            }
        }

        // 自动升级成功的包不再需要「需要确认升级」收件箱待办，移除避免残留误导。
        if !succeededPackageIDs.isEmpty {
            inboxStore.removeUpgradeDecisions(packageIDs: succeededPackageIDs)
        }

        if failures.isEmpty {
            print("[system] 每日巡检自动升级完成")
            await finish(0, succeededUpgradeCount: succeededUpgradeCount)
        } else {
            print("[system] 每日巡检处理完成：成功 \(succeededUpgradeCount) 项，失败 \(failures.count) 项")
            await finish(1, failures: failures, succeededUpgradeCount: succeededUpgradeCount)
        }
    }
}
