import Foundation

enum RiskInboxFactory {
    static func items(from rows: [UpgradePlanRow]) -> [InboxItem] {
        rows
            .filter { $0.automationDecision == .requireConfirmation }
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
