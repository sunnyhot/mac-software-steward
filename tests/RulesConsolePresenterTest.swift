import Foundation

@main
struct RulesConsolePresenterTest {
    static func main() {
        var profile = AutomationProfile.manualDefault
        profile.advancedModeEnabled = true
        profile.lowRiskAutoUpgradeEnabled = true
        profile.regularAppNetworkPolicy = .localOnly
        profile.autoRepairPolicy = .allowLowRisk

        let sections = RulesConsolePresenter.sections(profile: profile, includeGreedy: true)
        precondition(sections.map(\.title) == ["自动化策略", "风险规则", "恢复规则"])

        let policyRows = sections[0].rows
        precondition(policyRows.contains { row in
            row.title == "普通 App 联网策略"
                && row.status == "仅本地识别"
                && row.detail.contains("不访问外部页面")
        })
        precondition(policyRows.contains { row in
            row.title == "低风险自动升级" && row.status == "开启"
        })
        precondition(policyRows.contains { row in
            row.title == "包含 greedy cask" && row.status == "开启"
        })

        precondition(sections[1].rows.contains { row in
            row.title == "Cask 自更新保护" && row.status == "需确认"
        })
        precondition(sections[2].rows.contains { row in
            row.title == "自动修复 allowlist"
                && row.status == "仅低风险"
                && row.detail.contains("重新扫描")
        })

        let filtered = RulesConsolePresenter.sections(
            profile: profile,
            includeGreedy: true,
            category: .risk,
            query: "greedy"
        )
        precondition(filtered.map(\.title) == ["风险规则"])
        precondition(filtered[0].rows.map(\.title) == ["greedy 扫描范围"])
        precondition(filtered[0].rows[0].category == .risk)
        precondition(filtered[0].rows[0].detailItems.contains("开启后只扩大扫描可见性，不绕过升级风险策略。"))

        let noMatches = RulesConsolePresenter.sections(
            profile: profile,
            includeGreedy: true,
            category: .recovery,
            query: "Sparkle"
        )
        precondition(noMatches.isEmpty)
    }
}
