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
        var scan = await SoftwareScanner.scanAll(includeGreedy: includeGreedy)
        print("[scan] 应用 \(scan.summary.applications)，formula \(scan.summary.brewFormulae)，cask \(scan.summary.brewCasks)，可操作升级 \(scan.summary.actionable)")

        let policyStore = UpgradePolicyStore()
        let profile = AutomationProfileStore().profile
        let inboxStore = InboxStore()
        var failures: [InspectionFailureRecord] = []
        var cleanedPackages: [UpdatablePackage] = []
        var cleanedPackageIDs: Set<String> = []

        // 先清理已确认无 App 的残留，再生成升级计划，避免同一 cask 被误当成升级项。
        let cleanupCandidates = autoUpgrade
            ? SmartMaintenancePolicy.automaticStaleCleanupCandidates(scan: scan, profile: profile)
            : []
        if !cleanupCandidates.isEmpty {
            if let brew = await CommandRunner.commandPath("brew") {
                for cask in cleanupCandidates {
                    guard BrewCaskCleanupDetector.hasStaleInstallRecord(expectedAppPaths: cask.expectedAppPaths) else {
                        print("[skip] \(cask.name): App 文件已重新出现，不再自动清理")
                        continue
                    }
                    let cleanupCommand: UpgradeCommand
                    do {
                        cleanupCommand = try await CaskRecordCleanup.command(
                            brewPath: brew,
                            caskName: cask.name,
                            expectedAppPaths: cask.expectedAppPaths
                        )
                    } catch {
                        print("[error] \(cask.name): 无法构造安全安装记录清理命令：\(error.localizedDescription)")
                        failures.append(InspectionFailureRecord(
                            message: "无法构造安全安装记录清理命令",
                            commandDisplay: "brew --caskroom",
                            exitCode: 1
                        ))
                        continue
                    }
                    let display = cleanupCommand.display
                    let result = await runWithRetry(
                        executable: cleanupCommand.executable,
                        arguments: cleanupCommand.arguments,
                        display: display,
                        timeout: 600,
                        allowsRetry: false
                    )
                    // 安装记录清理不是幂等下载任务：无论退出码如何都先验证 receipt，
                    // 非零但已删除视为部分完成，绝不为重试而再次删除。
                    let verification = await CommandRunner.run(
                        brew,
                        arguments: ["list", "--cask", cask.name],
                        timeout: 30
                    )
                    let receiptRemoved = CaskReceiptVerification.isRemoved(verification)
                    if receiptRemoved {
                        scan = SmartMaintenancePolicy.removingCasks(packageIDs: [cask.id], from: scan)
                        if result.code == 0 {
                            cleanedPackages.append(.brew(cask))
                            cleanedPackageIDs.insert(cask.id)
                            print("[cleanup] \(cask.name): Homebrew 残留记录已移除并验证")
                        } else {
                            let message = "receipt 已移除，但清理命令返回 \(result.code)，部分阶段可能未完成"
                            failures.append(InspectionFailureRecord(
                                message: message,
                                commandDisplay: display,
                                exitCode: result.code
                            ))
                            inboxStore.add(InboxItem(
                                kind: .failureRecovery,
                                severity: .warning,
                                title: "\(cask.name) 清理部分完成",
                                summary: "\(message)。请查看日志确认剩余阶段，无需重复卸载。",
                                sourceID: cask.id,
                                actions: [InboxAction(title: "查看日志", systemImage: "terminal", kind: .openJobs)]
                            ))
                            print("[warn] \(cask.name): \(message)")
                        }
                    } else {
                        let message = result.code == 0
                            ? "清理后仍无法确认 Homebrew receipt 已移除"
                            : "自动清理 Homebrew 残留记录失败"
                        print("[error] \(cask.name): \(message)，退出码 \(result.code)")
                        failures.append(InspectionFailureRecord(
                            message: message,
                            commandDisplay: display,
                            exitCode: result.code
                        ))
                    }
                }
            } else {
                print("[error] 发现 \(cleanupCandidates.count) 个可安全清理的残留记录，但找不到 brew")
                for cask in cleanupCandidates {
                    failures.append(InspectionFailureRecord(
                        message: "无法自动清理 \(cask.name)：找不到 brew",
                        commandDisplay: "brew --caskroom",
                        exitCode: 1
                    ))
                }
            }
            if !cleanedPackageIDs.isEmpty {
                inboxStore.resolveRecoveryItems(packageIDs: cleanedPackageIDs)
                inboxStore.removeUpgradeDecisions(packageIDs: cleanedPackageIDs)
            }
        }

        // 使用统一 MaintenancePlanner 分类，与总览页/升级页保持一致的 automatic 判定。
        let plan = MaintenancePlanner.makePlan(scan: scan, policyStore: policyStore, includeGreedy: includeGreedy, profile: profile)
        let automaticPackages = plan.automaticItems.compactMap(\.package)
        // 同时用旧 UpgradePlanner 生成 rows，供巡检报告和 inbox 发布使用（向后兼容）。
        let rows = UpgradePlanner.makePlan(scan: scan, policyStore: policyStore, includeGreedy: includeGreedy)
        var succeededUpgradePackages: [UpdatablePackage] = []
        var succeededPackageIDs: Set<String> = []
        // 最终剩余可升级项按真实成功结果计算；失败的自动项仍需保留给后续处理。
        func remainingUpgradeCount() -> Int {
            rows.filter { $0.canExecute && !succeededPackageIDs.contains($0.packageID) }.count
        }
        func remainingActionableCount() -> Int {
            let upgradeIDs = Set(rows.filter {
                $0.canExecute && !succeededPackageIDs.contains($0.packageID)
            }.map(\.packageID))
            let recoveryIDs = Set(inboxStore.pendingItems.filter {
                ($0.kind == .failureRecovery || $0.kind == .permissionIssue) && $0.sourceID != nil
            }.compactMap(\.sourceID))
            return upgradeIDs.union(recoveryIDs).count
        }
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
                    automaticPackages: succeededUpgradePackages,
                    automaticCleanupPackages: cleanedPackages,
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
                    availableUpgradeCount: remainingUpgradeCount()
                )
            } else {
                notificationDecision = AutomationNotificationDecider.failureDecision(
                    policy: profile.notificationPolicy,
                    failures: failures,
                    succeededActionCount: succeededUpgradeCount,
                    availableUpgradeCount: remainingActionableCount()
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
            if remainingUpgradeCount() > 0 {
                print("[system] 检测到 \(remainingUpgradeCount()) 项可升级，但均需确认或不符合自动升级条件，本次未自动升级")
            } else {
                print("[system] 未发现需要升级的软件")
            }
            await finish(
                failures.isEmpty ? 0 : 1,
                failures: failures,
                succeededUpgradeCount: cleanedPackageIDs.count
            )
        }

        print("[updates] formula: \(formulaUpdates.map(\.name).joined(separator: ", "))")
        print("[updates] cask: \(caskUpdates.map(\.name).joined(separator: ", "))")
        print("[updates] mas: \(masUpdates.map(\.name).joined(separator: ", "))")

        guard autoUpgrade else {
            print("[system] 已禁用自动升级，仅完成巡检")
            await finish(
                failures.isEmpty ? 0 : 1,
                failures: failures,
                succeededUpgradeCount: cleanedPackageIDs.count
            )
        }

        // 升级前预下载 cask 文件到 brew 缓存（镜像/直链改写，失败静默回退默认下载）。
        if !caskUpdates.isEmpty, let brew = await CommandRunner.commandPath("brew") {
            for cask in caskUpdates {
                let info = await CommandRunner.run(
                    brew,
                    arguments: ["info", "--cask", "--json=v2", cask.name],
                    timeout: 30
                )
                guard info.ok,
                      let downloadInfo = CaskMirrorPrefetcher.resolveDownloadInfo(from: info.stdout, caskName: cask.name)
                else { continue }
                let prefetched = await CaskMirrorPrefetcher.prefetch(info: downloadInfo)
                print(prefetched
                    ? "[prefetch] \(cask.name) 已预下载到 brew 缓存"
                    : "[prefetch] \(cask.name) 预下载未成功，回退默认下载")
            }
        }

        // (可执行文件, 参数, 展示文本, 包 ID)。包 ID 用于升级成功后移除对应收件箱待办。
        var commands: [(executable: String, arguments: [String], display: String, packageID: String?)] = []

        if !formulaUpdates.isEmpty || !caskUpdates.isEmpty {
            if let brew = await CommandRunner.commandPath("brew") {
                if runBrewUpdate {
                    let result = await runWithRetry(
                        executable: brew,
                        arguments: ["update"],
                        display: "brew update"
                    )
                    let code = result.code
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
        for command in commands {
            let result = await runWithRetry(
                executable: command.executable,
                arguments: command.arguments,
                display: command.display
            )
            let code = result.code
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
                    if let package = automaticPackages.first(where: { $0.id == packageID }) {
                        succeededUpgradePackages.append(package)
                    }
                }
            }
        }

        // 自动升级成功的包不再需要「需要确认升级」收件箱待办，移除避免残留误导。
        if !succeededPackageIDs.isEmpty {
            inboxStore.resolveRecoveryItems(packageIDs: succeededPackageIDs)
            inboxStore.removeUpgradeDecisions(packageIDs: succeededPackageIDs)
        }

        let succeededActionCount = succeededUpgradeCount + cleanedPackageIDs.count
        if failures.isEmpty {
            print("[system] 每日巡检自动处理完成：升级 \(succeededUpgradeCount) 项，清理 \(cleanedPackageIDs.count) 项")
            await finish(0, succeededUpgradeCount: succeededActionCount)
        } else {
            print("[system] 每日巡检处理完成：成功 \(succeededActionCount) 项（升级 \(succeededUpgradeCount)，清理 \(cleanedPackageIDs.count)），失败 \(failures.count) 项")
            await finish(1, failures: failures, succeededUpgradeCount: succeededActionCount)
        }
    }

    private static func runWithRetry(
        executable: String,
        arguments: [String],
        display: String,
        timeout: TimeInterval = 7200,
        allowsRetry: Bool = true
    ) async -> StreamingCommandResult {
        var retryAttempt = 0
        while true {
            if retryAttempt == 0 {
                print("[command] $ \(display)")
            } else {
                print("[command] $ \(display)（第 \(retryAttempt + 1) 次尝试）")
            }
            let result = await CommandRunner.runStreamingDetailed(
                executable,
                arguments: arguments,
                timeout: timeout
            ) { stream, text in
                print("[\(stream)] \(text)")
            }
            guard allowsRetry && TransientFailureRetryPolicy.shouldRetry(
                code: result.code,
                output: result.recentOutput,
                terminationReason: result.terminationReason,
                retryAttempt: retryAttempt
            ) else { return result }

            let delay = TransientFailureRetryPolicy.delay(retryAttempt: retryAttempt)
            print("[retry] \(display)：检测到临时故障，\(Int(delay)) 秒后自动重试（\(retryAttempt + 1)/\(TransientFailureRetryPolicy.maxRetries)）")
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            retryAttempt += 1
        }
    }
}
