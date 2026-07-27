import Foundation

// MARK: - Maintenance Dashboard Presenter
//
// 把引擎状态 + 持久化 run 映射为维护总览页的稳定 UI 模型。
// 纯 Foundation，无命令执行，可不渲染 SwiftUI 视图单独测试。
// 设计依据：docs/superpowers/specs/2026-07-10-unified-maintenance-engine-dashboard-design.md

/// 总览页的健康标题分类。
enum MaintenanceDashboardHealth: Equatable {
    /// 尚未扫描，处于就绪态。
    case ready
    /// 正在扫描。
    case scanning
    /// 正在执行升级。
    case executing
    /// 全部已最新。
    case allClear
    /// 有可自动处理的项目。
    case hasAutomatic
    /// 有需确认的项目。
    case needsConfirmation
    /// 有失败需处理。
    case hasFailures
}

/// 总览页的 metric 卡片数据。
struct MaintenanceDashboardMetric: Identifiable, Equatable {
    var id: String
    var title: String
    var value: Int
    /// 文本值（优先于 value 显示），用于"下次巡检"等非数字 metric。
    var textValue: String?
    var symbol: String
    var tintRole: MaintenanceStatusTintRole
}

/// 优先任务行。
struct MaintenanceDashboardTaskRow: Identifiable, Equatable {
    var id: String
    var packageName: String
    var disposition: MaintenancePlanDisposition
    var detail: String
}

/// 总览页的完整展示模型。
struct MaintenanceDashboardPresentation: Equatable {
    var health: MaintenanceDashboardHealth
    var healthTitle: String
    var healthDetail: String
    var healthSymbol: String
    var healthTintRole: MaintenanceStatusTintRole
    var metrics: [MaintenanceDashboardMetric]
    var priorityTasks: [MaintenanceDashboardTaskRow]
    var lastRunSummary: String?
    var canStartSmartMaintenance: Bool
}

enum MaintenanceDashboardPresenter {
    static func presentation(
        hasScanned: Bool,
        isScanning: Bool,
        isExecuting: Bool,
        plan: MaintenancePlan?,
        failedCount: Int,
        lastHistoryRecord: UpgradeHistoryRecord?,
        nextInspectionText: String?
    ) -> MaintenanceDashboardPresentation {
        // 健康判定优先级：扫描中 > 执行中 > 失败 > 有自动项 > 有确认项 > 全部最新 > 就绪
        let health: MaintenanceDashboardHealth
        if isScanning {
            health = .scanning
        } else if isExecuting {
            health = .executing
        } else if failedCount > 0 {
            health = .hasFailures
        } else if !hasScanned {
            health = .ready
        } else if let plan, plan.hasAutomatic {
            health = .hasAutomatic
        } else if let plan, plan.hasConfirmation {
            health = .needsConfirmation
        } else {
            health = .allClear
        }

        let (healthTitle, healthDetail, healthSymbol, healthTintRole) = healthPresentation(
            health: health,
            plan: plan,
            failedCount: failedCount
        )

        // Metrics
        let automaticCount = plan?.automaticItems.count ?? 0
        let confirmationCount = plan?.confirmationItems.count ?? 0
        let managedCount = (plan?.items.count ?? 0)
        let metrics: [MaintenanceDashboardMetric] = [
            MaintenanceDashboardMetric(id: "managed", title: "管理软件", value: managedCount, textValue: nil, symbol: "shippingbox", tintRole: .neutral),
            MaintenanceDashboardMetric(id: "automatic", title: "可自动升级", value: automaticCount, textValue: nil, symbol: "bolt.circle", tintRole: .accent),
            MaintenanceDashboardMetric(id: "confirmation", title: "需确认", value: confirmationCount, textValue: nil, symbol: "hand.raised", tintRole: .attention),
            MaintenanceDashboardMetric(id: "nextInspection", title: "下次巡检", value: 0, textValue: nextInspectionText, symbol: "calendar", tintRole: .neutral)
        ]

        // Priority tasks：automatic + confirmation（最多 5 条）
        var priorityTasks: [MaintenanceDashboardTaskRow] = []
        if let plan {
            for item in plan.automaticItems.prefix(3) {
                priorityTasks.append(MaintenanceDashboardTaskRow(
                    id: item.packageID,
                    packageName: item.packageName,
                    disposition: item.disposition,
                    detail: item.commandDisplay
                ))
            }
            for item in plan.confirmationItems.prefix(2) {
                priorityTasks.append(MaintenanceDashboardTaskRow(
                    id: item.packageID,
                    packageName: item.packageName,
                    disposition: item.disposition,
                    detail: item.reasons.first ?? "需要确认"
                ))
            }
        }

        // 最近一次维护摘要
        var lastRunSummary: String? = nil
        if let lastHistoryRecord {
            let timestamp = lastHistoryRecord.finishedAt ?? lastHistoryRecord.startedAt
            let dateText = timestamp.map(formattedDate) ?? "最近"
            lastRunSummary = "\(dateText) \(lastHistoryRecord.label)：\(lastHistoryRecord.summary)"
        }

        return MaintenanceDashboardPresentation(
            health: health,
            healthTitle: healthTitle,
            healthDetail: healthDetail,
            healthSymbol: healthSymbol,
            healthTintRole: healthTintRole,
            metrics: metrics,
            priorityTasks: priorityTasks,
            lastRunSummary: lastRunSummary,
            canStartSmartMaintenance: !isScanning && !isExecuting
        )
    }

    private static func healthPresentation(
        health: MaintenanceDashboardHealth,
        plan: MaintenancePlan?,
        failedCount: Int
    ) -> (title: String, detail: String, symbol: String, tintRole: MaintenanceStatusTintRole) {
        switch health {
        case .ready:
            return ("准备就绪", "点击「开始智能维护」扫描并升级本机软件", "checkmark.shield", .neutral)
        case .scanning:
            return ("正在扫描", "正在检查本机软件更新状态", "magnifyingglass", .scanning)
        case .executing:
            return ("正在维护", "正在自动升级低风险软件", "bolt.circle", .accent)
        case .hasFailures:
            return ("有 \(failedCount) 个失败需处理", "失败项保留在列表中，可重试或查看日志", "exclamationmark.triangle", .failure)
        case .hasAutomatic:
            let count = plan?.automaticItems.count ?? 0
            return ("发现 \(count) 个可自动升级", "点击「开始智能维护」自动处理低风险项", "arrow.down.circle", .attention)
        case .needsConfirmation:
            let count = plan?.confirmationItems.count ?? 0
            return ("\(count) 个升级需确认", "部分软件需要你确认后才能升级", "hand.raised", .attention)
        case .allClear:
            return ("维护状态良好", "所有管理软件均为最新", "checkmark.seal", .success)
        }
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
