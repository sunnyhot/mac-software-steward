import Foundation

// MARK: - Unified maintenance plan classification
//
// 把 ScanResult + RiskAssessor + UpgradePolicyStore + AutomationProfile 收敛为单一计划，
// 输出 4 种 disposition：automatic / confirmationRequired / reminderOnly / blocked。
// 设计依据：docs/superpowers/specs/2026-07-10-unified-maintenance-engine-dashboard-design.md
// 与现有 UpgradePlanner 并存，不替换它；本文件供维护引擎与总览页使用。

/// 单个包在一次维护运行中的处置分类。
enum MaintenancePlanDisposition: String, Codable, Hashable {
    /// 可执行 ∧ 低风险 ∧ 允许自动 ∧ 策略为自动 ∧ profile 开启低风险自动升级。
    case automatic
    /// 可执行，但风险或策略要求用户确认后才能执行。
    case confirmationRequired
    /// 仅提醒，不执行。策略为仅提醒，或普通 App 有手动 checker 但无安全命令。
    case reminderOnly
    /// 不可执行。策略为跳过、源不可用、已固定、不可升级、或风险判定阻止执行。
    case blocked

    var title: String {
        switch self {
        case .automatic: return "自动升级"
        case .confirmationRequired: return "需确认"
        case .reminderOnly: return "仅提醒"
        case .blocked: return "已阻止"
        }
    }

    /// 是否携带可执行的包与命令。blocked 永远不可执行。
    var isExecutable: Bool {
        switch self {
        case .automatic, .confirmationRequired: return true
        case .reminderOnly, .blocked: return false
        }
    }
}

/// 计划中的一项。
struct MaintenancePlanItem: Identifiable, Hashable {
    var packageID: String
    var packageName: String
    /// blocked 项没有可执行包，此处为 nil；UI 无法把 blocked 转成可执行。
    var package: UpdatablePackage?
    var disposition: MaintenancePlanDisposition
    var riskLevel: RiskLevel
    var automationDecision: AutomationDecision
    var effectivePolicy: UpgradePolicy
    /// 跳过/阻止/需确认的人类可读原因。
    var reasons: [String]
    /// 可执行时为展示用命令文本；blocked/reminder 为空或说明文案。
    var commandDisplay: String

    var id: String { packageID }

    /// 是否真正可执行（有包且 disposition 允许）。
    var isExecutable: Bool {
        package != nil && disposition.isExecutable
    }
}

/// 一次维护运行的完整计划。
struct MaintenancePlan: Equatable {
    var items: [MaintenancePlanItem]

    var automaticItems: [MaintenancePlanItem] { items.filter { $0.disposition == .automatic } }
    var confirmationItems: [MaintenancePlanItem] { items.filter { $0.disposition == .confirmationRequired } }
    var reminderItems: [MaintenancePlanItem] { items.filter { $0.disposition == .reminderOnly } }
    var blockedItems: [MaintenancePlanItem] { items.filter { $0.disposition == .blocked } }

    var hasAutomatic: Bool { !automaticItems.isEmpty }
    var hasConfirmation: Bool { !confirmationItems.isEmpty }

    static let empty = MaintenancePlan(items: [])
}

/// 无状态的统一计划构建器。
enum MaintenancePlanner {
    /// 从扫描结果构建统一计划。
    ///
    /// - Parameters:
    ///   - scan: 最新扫描结果。
    ///   - policyStore: 升级策略存储（读取用户覆盖与默认策略）。
    ///   - includeGreedy: 是否包含 greedy cask。
    ///   - profile: 自动化配置。`lowRiskAutoUpgradeEnabled` 控制 automatic 组是否为空。
    static func makePlan(
        scan: ScanResult,
        policyStore: UpgradePolicyStore,
        includeGreedy: Bool,
        profile: AutomationProfile
    ) -> MaintenancePlan {
        // 聚合所有可能需要关注的包（outdated 或 upgradeable）。
        let candidates: [UpdatablePackage] =
            scan.brew.formulae.filter { $0.outdated || $0.upgradeable }.map { .brew($0) }
            + scan.brew.casks.filter { $0.outdated || $0.upgradeable }.map { .brew($0) }
            + scan.mas.apps.filter { $0.outdated || $0.upgradeable }.map { .mas($0) }

        let items = candidates.compactMap { package -> MaintenancePlanItem? in
            makeItem(for: package, scan: scan, policyStore: policyStore, includeGreedy: includeGreedy, profile: profile)
        }

        // 排序：automatic → confirmation → reminder → blocked，组内按包名。
        return MaintenancePlan(items: items.sorted { a, b in
            let orderA = MaintenancePlanner.dispositionSortWeight(a.disposition)
            let orderB = MaintenancePlanner.dispositionSortWeight(b.disposition)
            if orderA != orderB { return orderA < orderB }
            return a.packageName.localizedStandardCompare(b.packageName) == .orderedAscending
        })
    }

    private static func makeItem(
        for package: UpdatablePackage,
        scan: ScanResult,
        policyStore: UpgradePolicyStore,
        includeGreedy: Bool,
        profile: AutomationProfile
    ) -> MaintenancePlanItem? {
        let risk = RiskAssessor.assess(package: package, scan: scan, includeGreedy: includeGreedy)
        let policy = policyStore.effectivePolicy(for: package, includeGreedy: includeGreedy)
        let commandDisplay = commandDisplayText(for: package)

        // 1. blocked：策略跳过、源不可用、固定、不可升级、风险阻止。
        if policy == .skip {
            return blockedItem(package: package, risk: risk, policy: policy, reason: "策略设置为跳过", commandDisplay: commandDisplay)
        }
        if risk.automationDecision == .blockExecution {
            return blockedItem(package: package, risk: risk, policy: policy, reason: blockedReason(for: risk), commandDisplay: commandDisplay)
        }
        if !package.upgradeable {
            // 不可执行且非 blocked-decision：归入 reminder（无法安全执行）。
            return reminderItem(package: package, risk: risk, policy: policy, reason: "当前不可执行升级", commandDisplay: commandDisplay)
        }

        // 2. reminderOnly：策略为仅提醒。
        if policy == .remindOnly {
            return reminderItem(package: package, risk: risk, policy: policy, reason: "策略设置为仅提醒", commandDisplay: commandDisplay)
        }

        // 3. automatic：低风险 ∧ 允许自动 ∧ 策略自动 ∧ profile 开启。
        //    profile.lowRiskAutoUpgradeEnabled 是总门控：关闭时所有项降级为需确认。
        if policy == .automatic
            && risk.level == .low
            && risk.automationDecision == .allowAutomatic
            && profile.lowRiskAutoUpgradeEnabled {
            return MaintenancePlanItem(
                packageID: package.id,
                packageName: package.name,
                package: package,
                disposition: .automatic,
                riskLevel: risk.level,
                automationDecision: risk.automationDecision,
                effectivePolicy: policy,
                reasons: [],
                commandDisplay: commandDisplay
            )
        }

        // 4. confirmationRequired：可执行，但风险或策略要求确认。
        //    覆盖：askFirst、requireConfirmation、majorVersion、profile 关闭低风险自动。
        var reasons: [String] = []
        if policy == .askFirst { reasons.append("策略要求确认") }
        if risk.automationDecision == .requireConfirmation { reasons.append(risk.summary.isEmpty ? "风险需确认" : risk.summary) }
        if policy == .automatic && !profile.lowRiskAutoUpgradeEnabled { reasons.append("低风险自动升级未开启") }
        if risk.level == .high && risk.automationDecision != .blockExecution { reasons.append("高风险，需确认") }
        if reasons.isEmpty { reasons.append("需要确认") }

        return MaintenancePlanItem(
            packageID: package.id,
            packageName: package.name,
            package: package,
            disposition: .confirmationRequired,
            riskLevel: risk.level,
            automationDecision: risk.automationDecision,
            effectivePolicy: policy,
            reasons: reasons,
            commandDisplay: commandDisplay
        )
    }

    // MARK: - Helpers

    private static func blockedItem(
        package: UpdatablePackage,
        risk: RiskAssessment,
        policy: UpgradePolicy,
        reason: String,
        commandDisplay: String
    ) -> MaintenancePlanItem {
        MaintenancePlanItem(
            packageID: package.id,
            packageName: package.name,
            package: nil,
            disposition: .blocked,
            riskLevel: risk.level,
            automationDecision: risk.automationDecision,
            effectivePolicy: policy,
            reasons: [reason],
            commandDisplay: commandDisplay
        )
    }

    private static func reminderItem(
        package: UpdatablePackage,
        risk: RiskAssessment,
        policy: UpgradePolicy,
        reason: String,
        commandDisplay: String
    ) -> MaintenancePlanItem {
        MaintenancePlanItem(
            packageID: package.id,
            packageName: package.name,
            package: package,
            disposition: .reminderOnly,
            riskLevel: risk.level,
            automationDecision: risk.automationDecision,
            effectivePolicy: policy,
            reasons: [reason],
            commandDisplay: commandDisplay
        )
    }

    private static func blockedReason(for risk: RiskAssessment) -> String {
        if risk.reasons.contains(.brewUnavailable) { return "Homebrew 不可用" }
        if risk.reasons.contains(.masUnavailable) { return "mas CLI 不可用" }
        if risk.reasons.contains(.pinned) { return "软件包已固定" }
        if risk.reasons.contains(.notUpgradeable) { return "当前不可执行升级" }
        return risk.summary.isEmpty ? "风险阻止执行" : risk.summary
    }

    private static func commandDisplayText(for package: UpdatablePackage) -> String {
        switch package {
        case .brew(let brewPackage):
            if brewPackage.manualUpdateOnly {
                return "应用内更新器"
            }
            return brewPackage.kind == "cask" ? "brew upgrade --cask \(brewPackage.name)" : "brew upgrade \(brewPackage.name)"
        case .mas(let app):
            return "mas upgrade \(app.appId)"
        }
    }

    private static func dispositionSortWeight(_ disposition: MaintenancePlanDisposition) -> Int {
        switch disposition {
        case .automatic: return 0
        case .confirmationRequired: return 1
        case .reminderOnly: return 2
        case .blocked: return 3
        }
    }
}
