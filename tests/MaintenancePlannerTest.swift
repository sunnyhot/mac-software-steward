import Foundation

@main
struct MaintenancePlannerTest {
    static func main() {
        // 用不存在的临时 fileURL 初始化 policyStore，避免读到本机真实用户的策略文件。
        let cleanPolicyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("maintenance-planner-policy-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cleanPolicyURL) }
        func cleanStore() -> UpgradePolicyStore { UpgradePolicyStore(fileURL: cleanPolicyURL) }
        // MARK: 基础包工厂
        // 一个标准的低风险 formula（minor 版本变化）：outdated + upgradeable，默认策略 automatic。
        let lowRiskFormula = brewFormula(id: "brew:formula:jq", name: "jq", kind: "formula", outdated: true, upgradeable: true)
        // 一个 pinned cask：会被 blockExecution。
        let pinnedCask = brewPackage(id: "brew:cask:pinned", name: "pinned", kind: "cask", outdated: true, upgradeable: true, pinned: true)
        // 一个 major 版本变化的 formula：默认策略 automatic，风险仅作展示 → automatic。
        let majorFormula = BrewPackage(id: "brew:formula:bigjump", kind: "formula", name: "bigjump", installedVersion: "1.0", currentVersion: "2.0", pinned: false, autoUpdates: false, outdated: true, upgradeable: true)
        // 一个 mas app：默认策略 automatic → automatic。
        let masAppItem = masApp(id: "mas:things", name: "Things", outdated: true, upgradeable: true)

        // MARK: profile.lowRiskAutoUpgradeEnabled = true 的完整分类
        let profileOn = AutomationProfile(
            dailyInspectionEnabled: true,
            lowRiskAutoUpgradeEnabled: true,
            notificationPolicy: .decisionsAndFailures,
            regularAppNetworkPolicy: .declaredSourcesOnly,
            autoRepairPolicy: .manualOnly
        )

        let planOn = MaintenancePlanner.makePlan(
            scan: scanWith(formulae: [lowRiskFormula, majorFormula], casks: [pinnedCask], masApps: [masAppItem]),
            policyStore: cleanStore(),
            includeGreedy: false,
            profile: profileOn
        )

        // jq → automatic（低风险 formula，profile 开启）
        let jqItem = planOn.items.first { $0.packageID == "brew:formula:jq" }
        precondition(jqItem?.disposition == .automatic, "jq 应为 automatic，得到 \(String(describing: jqItem?.disposition))")
        precondition(jqItem?.isExecutable == true, "automatic 应可执行")
        precondition(jqItem?.package != nil, "automatic 应携带包")

        // pinned cask → blocked
        let pinnedItem = planOn.items.first { $0.packageID == "brew:cask:pinned" }
        precondition(pinnedItem?.disposition == .blocked, "pinned 应为 blocked，得到 \(String(describing: pinnedItem?.disposition))")
        precondition(pinnedItem?.package == nil, "blocked 不应携带可执行包")
        precondition(pinnedItem?.isExecutable == false, "blocked 不可执行")

        // major 版本 formula → automatic（默认策略 automatic，风险仅展示）
        let majorItem = planOn.items.first { $0.packageID == "brew:formula:bigjump" }
        precondition(majorItem?.disposition == .automatic, "major 版本 formula 应为 automatic，得到 \(String(describing: majorItem?.disposition))")

        // mas app → automatic（默认策略 automatic）
        let masItem = planOn.items.first { $0.packageID == "mas:things" }
        precondition(masItem?.disposition == .automatic, "mas 应为 automatic，得到 \(String(describing: masItem?.disposition))")

        // 分组计数：全部默认 automatic，仅 pinned 为 blocked
        precondition(planOn.hasAutomatic, "应有 automatic 项")
        precondition(planOn.hasConfirmation == false, "默认策略下不应有 confirmation 项")
        precondition(planOn.reminderItems.isEmpty, "默认策略下不应有 reminder 项")
        precondition(planOn.blockedItems.count == 1, "应有 1 个 blocked，得到 \(planOn.blockedItems.count)")

        // 用户显式覆盖为「确认后升级」→ confirmationRequired
        let askFirstStore = UpgradePolicyStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("maintenance-planner-askfirst-\(UUID().uuidString).json"))
        askFirstStore.set(.askFirst, forPackageID: "mas:things")
        let planAskFirst = MaintenancePlanner.makePlan(
            scan: scanWith(formulae: [], casks: [], masApps: [masAppItem]),
            policyStore: askFirstStore,
            includeGreedy: false,
            profile: profileOn
        )
        let masAskFirst = planAskFirst.items.first { $0.packageID == "mas:things" }
        precondition(masAskFirst?.disposition == .confirmationRequired, "askFirst 覆盖应为 confirmationRequired，得到 \(String(describing: masAskFirst?.disposition))")
        precondition(masAskFirst?.reasons.contains("策略要求确认") == true, "askFirst 覆盖应带「策略要求确认」理由")

        // 排序：automatic 在 confirmation 之前
        let automaticIndex = planOn.items.firstIndex { $0.disposition == .automatic }
        let confirmationIndex = planOn.items.firstIndex { $0.disposition == .confirmationRequired }
        if let ai = automaticIndex, let ci = confirmationIndex {
            precondition(ai < ci, "automatic 应排在 confirmation 之前")
        }

        // MARK: profile.lowRiskAutoUpgradeEnabled = false → automatic 降级为 confirmation
        var profileOff = profileOn
        profileOff.lowRiskAutoUpgradeEnabled = false

        let planOff = MaintenancePlanner.makePlan(
            scan: scanWith(formulae: [lowRiskFormula], casks: [], masApps: []),
            policyStore: cleanStore(),
            includeGreedy: false,
            profile: profileOff
        )

        let jqOff = planOff.items.first { $0.packageID == "brew:formula:jq" }
        precondition(jqOff?.disposition == .confirmationRequired, "profile 关闭时 jq 应降级为 confirmationRequired，得到 \(String(describing: jqOff?.disposition))")
        precondition(planOff.hasAutomatic == false, "profile 关闭时不应有 automatic 项")

        // MARK: 策略覆盖（每个 store 用独立临时文件，避免互相污染）
        func isolatedStore() -> UpgradePolicyStore {
            UpgradePolicyStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("maintenance-planner-iso-\(UUID().uuidString).json"))
        }

        let skipStore = isolatedStore()
        skipStore.set(.skip, forPackageID: "brew:formula:jq")
        let planSkip = MaintenancePlanner.makePlan(
            scan: scanWith(formulae: [lowRiskFormula], casks: [], masApps: []),
            policyStore: skipStore,
            includeGreedy: false,
            profile: profileOn
        )
        let jqSkip = planSkip.items.first { $0.packageID == "brew:formula:jq" }
        precondition(jqSkip?.disposition == .blocked, "skip 策略应为 blocked，得到 \(String(describing: jqSkip?.disposition))")

        let remindStore = isolatedStore()
        remindStore.set(.remindOnly, forPackageID: "brew:formula:jq")
        let planRemind = MaintenancePlanner.makePlan(
            scan: scanWith(formulae: [lowRiskFormula], casks: [], masApps: []),
            policyStore: remindStore,
            includeGreedy: false,
            profile: profileOn
        )
        let jqRemind = planRemind.items.first { $0.packageID == "brew:formula:jq" }
        precondition(jqRemind?.disposition == .reminderOnly, "remindOnly 策略应为 reminderOnly，得到 \(String(describing: jqRemind?.disposition))")
        precondition(jqRemind?.isExecutable == false, "reminderOnly 不可执行")

        // MARK: 空计划
        let emptyScan = scanWith(formulae: [], casks: [], masApps: [])
        let emptyPlan = MaintenancePlanner.makePlan(scan: emptyScan, policyStore: cleanStore(), includeGreedy: false, profile: profileOn)
        precondition(emptyPlan.items.isEmpty, "空扫描应产出空计划")
        precondition(emptyPlan.hasAutomatic == false && emptyPlan.hasConfirmation == false, "空计划无 automatic/confirmation")

        // MARK: blocked 永不进 automatic（交叉验证：blockExecution 的包即使策略设 automatic 仍 blocked）
        let blockedByRiskStore = isolatedStore()
        // pinnedCask 默认无 override → effectivePolicy 取决于 cask 规则；但 blockExecution 来自 RiskAssessor。
        // 强行给它设 automatic 覆盖，验证 risk block 优先。
        blockedByRiskStore.set(.automatic, forPackageID: "brew:cask:pinned")
        let planBlockedByRisk = MaintenancePlanner.makePlan(
            scan: scanWith(formulae: [], casks: [pinnedCask], masApps: []),
            policyStore: blockedByRiskStore,
            includeGreedy: false,
            profile: profileOn
        )
        let blockedByRiskItem = planBlockedByRisk.items.first { $0.packageID == "brew:cask:pinned" }
        precondition(blockedByRiskItem?.disposition == .blocked, "blockExecution 应优先于策略 automatic，得到 \(String(describing: blockedByRiskItem?.disposition))")

        // MARK: 不可升级的包（upgradeable=false, outdated=true, 非 greedy）→ blocked
        // RiskAssessor 把 notUpgradeable + 非 greedy 判为 blockExecution，Planner 据此归入 blocked。
        let notUpgradable = brewPackage(id: "brew:cask:manual", name: "manual", kind: "cask", outdated: true, upgradeable: false, autoUpdates: false)
        let planManual = MaintenancePlanner.makePlan(
            scan: scanWith(formulae: [], casks: [notUpgradable], masApps: []),
            policyStore: cleanStore(),
            includeGreedy: false,
            profile: profileOn
        )
        let manualItem = planManual.items.first { $0.packageID == "brew:cask:manual" }
        precondition(manualItem?.disposition == .blocked, "不可升级(非greedy)应为 blocked，得到 \(String(describing: manualItem?.disposition))")

        print("MaintenancePlannerTest passed")
    }

    // MARK: - Factories

    private static func brewFormula(id: String, name: String, kind: String, outdated: Bool, upgradeable: Bool) -> BrewPackage {
        // 用 minor 版本变化（1.6 → 1.7），避免触发 majorVersion 风险检测。
        BrewPackage(id: id, kind: kind, name: name, installedVersion: "1.6", currentVersion: "1.7", pinned: false, autoUpdates: false, outdated: outdated, upgradeable: upgradeable)
    }

    private static func brewPackage(id: String, name: String, kind: String, outdated: Bool, upgradeable: Bool, pinned: Bool = false, autoUpdates: Bool = false) -> BrewPackage {
        BrewPackage(id: id, kind: kind, name: name, installedVersion: "1.0", currentVersion: "2.0", pinned: pinned, autoUpdates: autoUpdates, outdated: outdated, upgradeable: upgradeable)
    }

    private static func masApp(id: String, name: String, outdated: Bool, upgradeable: Bool) -> MasApp {
        MasApp(id: id, appId: "999", name: name, installedVersion: "1.0", currentVersion: "2.0", outdated: outdated, upgradeable: upgradeable)
    }

    private static func scanWith(formulae: [BrewPackage], casks: [BrewPackage], masApps: [MasApp]) -> ScanResult {
        let outdated = formulae.filter(\.outdated).count + casks.filter(\.outdated).count + masApps.filter(\.outdated).count
        return ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: false,
            summary: ScanSummary(applications: 0, brewFormulae: formulae.count, brewCasks: casks.count, masApps: masApps.count, outdated: outdated, actionable: 0, scanMs: 1),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
            brew: BrewScan(available: true, path: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew", version: "Homebrew 5", error: "", includeGreedy: false, formulae: formulae, casks: casks),
            mas: MasScan(available: !masApps.isEmpty, path: masApps.isEmpty ? "" : "/opt/homebrew/bin/mas", error: "", apps: masApps)
        )
    }
}
