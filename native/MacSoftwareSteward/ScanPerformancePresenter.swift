import Foundation

struct ScanPerformanceSummaryRow: Hashable {
    var totalText: String
    var slowestPhaseTitle: String
    var scannedAt: Date
    var countSummary: String
}

struct ScanPerformancePhaseRow: Identifiable, Hashable {
    var id: ScanPerformancePhase { phase }
    var phase: ScanPerformancePhase
    var title: String
    var durationText: String
    var percentText: String
    var fraction: Double
    var isSlowest: Bool
}

struct ScanPerformanceRecentRow: Identifiable, Hashable {
    var id: UUID
    var scannedAt: Date
    var totalText: String
    var slowestPhaseTitle: String
    var countSummary: String
}

struct ScanPerformanceDiagnosticHint: Hashable {
    var title: String
    var detail: String
    var symbol: String
}

enum ScanPerformancePresenter {
    static func summary(for records: [ScanPerformanceSnapshot]) -> ScanPerformanceSummaryRow? {
        guard let latest = records.first else { return nil }
        return ScanPerformanceSummaryRow(
            totalText: ScanPerformanceStage.formatDuration(latest.totalMs),
            slowestPhaseTitle: latest.slowestStage?.title ?? "无",
            scannedAt: latest.scannedAt,
            countSummary: latest.countSummary
        )
    }

    static func phaseRows(for snapshot: ScanPerformanceSnapshot) -> [ScanPerformancePhaseRow] {
        let total = snapshot.totalMs
        let slowest = snapshot.slowestStage?.phase
        return snapshot.measuredStages.map { stage in
            let fraction = stage.fraction(of: total)
            return ScanPerformancePhaseRow(
                phase: stage.phase,
                title: stage.title,
                durationText: stage.durationText,
                percentText: "\(Int((fraction * 100).rounded()))%",
                fraction: fraction,
                isSlowest: stage.phase == slowest
            )
        }
    }

    static func recentRows(for records: [ScanPerformanceSnapshot]) -> [ScanPerformanceRecentRow] {
        records.map { record in
            ScanPerformanceRecentRow(
                id: record.id,
                scannedAt: record.scannedAt,
                totalText: ScanPerformanceStage.formatDuration(record.totalMs),
                slowestPhaseTitle: record.slowestStage?.title ?? "无",
                countSummary: record.countSummary
            )
        }
    }

    static func diagnosticHint(for snapshot: ScanPerformanceSnapshot) -> ScanPerformanceDiagnosticHint {
        guard let slowest = snapshot.slowestStage else {
            return ScanPerformanceDiagnosticHint(title: "暂无瓶颈", detail: "没有可分析的阶段耗时。", symbol: "checkmark.circle")
        }
        let fraction = slowest.fraction(of: snapshot.totalMs)
        if fraction < 0.4 {
            return ScanPerformanceDiagnosticHint(title: "扫描耗时较均衡", detail: "没有单一阶段占用超过 40%。", symbol: "equal.circle")
        }
        switch slowest.phase {
        case .applications:
            return ScanPerformanceDiagnosticHint(title: "本机应用扫描较慢", detail: "system_profiler 在应用数量较多或系统负载较高时可能变慢。", symbol: "macwindow")
        case .regularAppDiscovery, .sparkleAppcast:
            return ScanPerformanceDiagnosticHint(title: "普通 App 更新检查较慢", detail: "普通 App 元数据读取或 Sparkle 更新源请求可能是瓶颈。", symbol: "sparkles")
        case .brew:
            return ScanPerformanceDiagnosticHint(title: "Homebrew 来源较慢", detail: "Homebrew 命令响应时间较长，可能受本机包数量或网络状态影响。", symbol: "shippingbox")
        case .mas:
            return ScanPerformanceDiagnosticHint(title: "App Store 来源较慢", detail: "mas 命令响应时间较长，可能受 App Store 登录状态或网络影响。", symbol: "app.badge")
        case .classification:
            return ScanPerformanceDiagnosticHint(title: "来源关联较慢", detail: "应用和管理来源的匹配耗时偏高，可以后续检查匹配规则。", symbol: "link")
        case .total:
            return ScanPerformanceDiagnosticHint(title: "扫描耗时较均衡", detail: "没有单一阶段占用超过 40%。", symbol: "equal.circle")
        }
    }
}
