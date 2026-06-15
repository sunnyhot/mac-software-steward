import Foundation

struct RulesConsoleSection: Hashable {
    var title: String
    var summary: String
    var rows: [RulesConsoleRow]
}

struct RulesConsoleRow: Hashable, Identifiable {
    var id: String { title }
    var title: String
    var detail: String
    var symbol: String
    var status: String
}

enum RulesConsolePresenter {
    static func sections(profile: AutomationProfile, includeGreedy: Bool) -> [RulesConsoleSection] {
        [
            policySection(profile: profile, includeGreedy: includeGreedy),
            riskSection(includeGreedy: includeGreedy),
            recoverySection(profile: profile)
        ]
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
                    status: profile.regularAppNetworkPolicy.title
                ),
                RulesConsoleRow(
                    title: "低风险自动升级",
                    detail: "每日巡检只会自动执行已判定为低风险的升级项。",
                    symbol: "bolt.badge.checkmark",
                    status: enabledText(profile.lowRiskAutoUpgradeEnabled)
                ),
                RulesConsoleRow(
                    title: "自动修复",
                    detail: "失败恢复默认进入待处理；开启后只允许白名单内的低风险动作自动执行。",
                    symbol: "wrench.and.screwdriver",
                    status: profile.autoRepairPolicy.title
                ),
                RulesConsoleRow(
                    title: "包含 greedy cask",
                    detail: "开启后会把 auto_updates 或 latest Cask 纳入扫描，升级仍受风险规则约束。",
                    symbol: "shippingbox.and.arrow.backward",
                    status: enabledText(includeGreedy)
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
                    status: "需确认"
                ),
                RulesConsoleRow(
                    title: "固定版本保护",
                    detail: "已 pin 的 Formula 或 Cask 默认跳过自动升级。",
                    symbol: "pin",
                    status: "阻止"
                ),
                RulesConsoleRow(
                    title: "greedy 扫描范围",
                    detail: includeGreedy ? "当前会扫描 greedy Cask，但自动执行仍要通过低风险规则。" : "当前不扫描 greedy Cask。",
                    symbol: "slider.horizontal.3",
                    status: includeGreedy ? "扩大" : "标准"
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
                    status: profile.autoRepairPolicy == .allowLowRisk ? "仅低风险" : "关闭"
                ),
                RulesConsoleRow(
                    title: "防循环保护",
                    detail: "自动修复动作只执行一次；失败后继续进入待处理。",
                    symbol: "arrow.triangle.2.circlepath.circle",
                    status: "一次"
                ),
                RulesConsoleRow(
                    title: "人工兜底",
                    detail: "清理、重装、重试等恢复建议会写入待处理，由用户确认。",
                    symbol: "tray.and.arrow.down",
                    status: "待处理"
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
