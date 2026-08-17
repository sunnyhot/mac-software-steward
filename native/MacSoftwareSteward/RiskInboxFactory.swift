import Foundation

enum RiskInboxFactory {
    static func items(from rows: [UpgradePlanRow]) -> [InboxItem] {
        rows
            // 默认策略为自动升级后，requireConfirmation 但已预选的项会被自动处理，
            // 不再生成「需要确认升级」待办，避免收件箱与自动升级行为互相矛盾。
            .filter { $0.automationDecision == .requireConfirmation && $0.selection == .notSelected }
            .map { row in
                InboxItem(
                    kind: .upgradeDecision,
                    severity: row.riskLevel == .high ? .warning : .info,
                    title: "\(row.packageName) 需要确认升级",
                    summary: row.riskSummary.isEmpty ? "该升级需要手动确认。" : row.riskSummary,
                    sourceID: "upgrade:\(row.packageID)",
                    actions: [
                        InboxAction(title: "查看升级计划", systemImage: "arrow.down.circle", kind: .openUpdates)
                    ]
                )
            }
    }
}
