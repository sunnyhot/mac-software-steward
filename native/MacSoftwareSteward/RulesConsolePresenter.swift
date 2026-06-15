import Foundation

struct RulesConsoleSection: Hashable {
    var title: String
    var summary: String
    var rows: [RulesConsoleRow]
}

enum RulesConsoleCategory: String, CaseIterable, Identifiable, Hashable {
    case all
    case policy
    case risk
    case recovery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .policy: return "自动化"
        case .risk: return "风险"
        case .recovery: return "恢复"
        }
    }

    func matches(_ row: RulesConsoleRow) -> Bool {
        self == .all || row.category == self
    }
}

struct RulesConsoleRow: Hashable, Identifiable {
    var id: String { title }
    var title: String
    var detail: String
    var symbol: String
    var status: String
    var category: RulesConsoleCategory
    var detailItems: [String]
}

enum RulesConsolePresenter {
    static func sections(
        profile: AutomationProfile,
        includeGreedy: Bool,
        category: RulesConsoleCategory = .all,
        query: String = ""
    ) -> [RulesConsoleSection] {
        baseSections(profile: profile, includeGreedy: includeGreedy)
            .compactMap { section in
                let rows = filteredRows(section.rows, category: category, query: query)
                guard !rows.isEmpty else { return nil }
                return RulesConsoleSection(title: section.title, summary: section.summary, rows: rows)
            }
    }

    private static func baseSections(profile: AutomationProfile, includeGreedy: Bool) -> [RulesConsoleSection] {
        [
            policySection(profile: profile, includeGreedy: includeGreedy),
            riskSection(includeGreedy: includeGreedy),
            recoverySection(profile: profile)
        ]
    }

    private static func filteredRows(
        _ rows: [RulesConsoleRow],
        category: RulesConsoleCategory,
        query: String
    ) -> [RulesConsoleRow] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return rows.filter { row in
            guard category.matches(row) else { return false }
            guard !normalizedQuery.isEmpty else { return true }
            return row.searchText.contains(normalizedQuery)
        }
    }

    private static func policySection(profile: AutomationProfile, includeGreedy: Bool) -> RulesConsoleSection {
        RulesConsoleSection(
            title: "自动化策略",
            summary: "当前生效的扫描、升级与修复开关。",
            rows: [
                RulesConsoleRow(
                    title: "普通 App 联网策略",
                    detail: networkPolicyDetail(profile.regularAppNetworkPolicy),
                    symbol: "network",
                    status: profile.regularAppNetworkPolicy.title,
                    category: .policy,
                    detailItems: [
                        "默认只访问应用声明的更新源或受控接口。",
                        "仅本地识别会跳过普通 App 联网版本检查。",
                        "积极检查会扩大到公开厂商页面，仍只记录诊断和提示。"
                    ]
                ),
                RulesConsoleRow(
                    title: "低风险自动升级",
                    detail: "每日巡检只会自动执行已判定为低风险的升级项。",
                    symbol: "bolt.badge.checkmark",
                    status: enabledText(profile.lowRiskAutoUpgradeEnabled),
                    category: .policy,
                    detailItems: [
                        "自动执行前仍会经过风险评估和单包策略。",
                        "高风险、需确认、固定版本或权限异常不会静默执行。"
                    ]
                ),
                RulesConsoleRow(
                    title: "自动修复",
                    detail: "失败恢复默认进入待处理；开启后只允许白名单内的低风险动作自动执行。",
                    symbol: "wrench.and.screwdriver",
                    status: profile.autoRepairPolicy.title,
                    category: .policy,
                    detailItems: [
                        "自动修复只覆盖 allowlist 中的低风险恢复动作。",
                        "清理、重装、重试等动作会继续进入待处理。"
                    ]
                ),
                RulesConsoleRow(
                    title: "包含 greedy cask",
                    detail: "开启后会把 auto_updates 或 latest Cask 纳入扫描，升级仍受风险规则约束。",
                    symbol: "shippingbox.and.arrow.backward",
                    status: enabledText(includeGreedy),
                    category: .policy,
                    detailItems: [
                        "greedy 影响扫描可见范围，不等于允许自动升级。",
                        "auto_updates/latest Cask 仍会标记为需确认。"
                    ]
                )
            ]
        )
    }

    private static func riskSection(includeGreedy: Bool) -> RulesConsoleSection {
        RulesConsoleSection(
            title: "风险规则",
            summary: "升级计划中始终保留人工确认的边界。",
            rows: [
                RulesConsoleRow(
                    title: "Cask 自更新保护",
                    detail: "auto_updates 或 latest Cask 不直接自动升级，避免覆盖应用自身更新节奏。",
                    symbol: "exclamationmark.shield",
                    status: "需确认",
                    category: .risk,
                    detailItems: [
                        "Cask 自带更新器时，Homebrew 版本可能不是用户期望的升级路径。",
                        "该规则会进入升级计划，但默认需要用户确认。"
                    ]
                ),
                RulesConsoleRow(
                    title: "固定版本保护",
                    detail: "已 pin 的 Formula 或 Cask 默认跳过自动升级。",
                    symbol: "pin",
                    status: "阻止",
                    category: .risk,
                    detailItems: [
                        "pin 通常表示用户明确冻结版本。",
                        "解除 pin 后才会重新进入正常升级策略。"
                    ]
                ),
                RulesConsoleRow(
                    title: "greedy 扫描范围",
                    detail: includeGreedy ? "当前会扫描 greedy Cask，但自动执行仍要通过低风险规则。" : "当前不扫描 greedy Cask。",
                    symbol: "slider.horizontal.3",
                    status: includeGreedy ? "扩大" : "标准",
                    category: .risk,
                    detailItems: [
                        "开启后只扩大扫描可见性，不绕过升级风险策略。",
                        "关闭时会降低普通用户看到的噪音。"
                    ]
                )
            ]
        )
    }

    private static func recoverySection(profile: AutomationProfile) -> RulesConsoleSection {
        RulesConsoleSection(
            title: "恢复规则",
            summary: "失败恢复动作按风险分层进入自动或待处理路径。",
            rows: [
                RulesConsoleRow(
                    title: "自动修复 allowlist",
                    detail: "当前白名单只允许重新扫描一类低风险恢复动作自动执行。",
                    symbol: "checklist.checked",
                    status: profile.autoRepairPolicy == .allowLowRisk ? "仅低风险" : "关闭",
                    category: .recovery,
                    detailItems: [
                        "allowlist 保持很小，避免把破坏性恢复动作放到后台执行。",
                        "自动修复失败后会继续进入待处理。"
                    ]
                ),
                RulesConsoleRow(
                    title: "防循环保护",
                    detail: "自动修复动作只执行一次；失败后继续进入待处理。",
                    symbol: "arrow.triangle.2.circlepath.circle",
                    status: "一次",
                    category: .recovery,
                    detailItems: [
                        "同一问题不会无限重试。",
                        "保留历史记录便于用户判断是否需要手动处理。"
                    ]
                ),
                RulesConsoleRow(
                    title: "人工兜底",
                    detail: "清理、重装、重试等恢复建议会写入待处理，由用户确认。",
                    symbol: "tray.and.arrow.down",
                    status: "待处理",
                    category: .recovery,
                    detailItems: [
                        "恢复建议会带可复制命令或跳转入口。",
                        "处理或忽略都会写入历史。"
                    ]
                )
            ]
        )
    }

    private static func networkPolicyDetail(_ policy: RegularAppNetworkPolicy) -> String {
        switch policy {
        case .declaredSourcesOnly:
            return "只访问应用声明的 Sparkle appcast 和受控更新接口。"
        case .aggressive:
            return "允许访问公开厂商页面来尝试识别普通 App 更新。"
        case .localOnly:
            return "不访问外部页面，只根据本机元数据识别普通 App。"
        }
    }

    private static func enabledText(_ enabled: Bool) -> String {
        enabled ? "开启" : "关闭"
    }
}

private extension RulesConsoleRow {
    var searchText: String {
        ([title, detail, status, category.title] + detailItems)
            .joined(separator: " ")
            .lowercased()
    }
}
