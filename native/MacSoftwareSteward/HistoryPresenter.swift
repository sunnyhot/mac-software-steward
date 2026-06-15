import Foundation

enum HistoryKindFilter: String, CaseIterable, Identifiable {
    case all
    case inspection
    case upgrade
    case inbox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .inspection: return "巡检"
        case .upgrade: return "升级"
        case .inbox: return "待办"
        }
    }

    func matches(_ kind: HistoryEntryKind) -> Bool {
        switch self {
        case .all:
            return true
        case .inspection:
            return kind == .inspection
        case .upgrade:
            return kind == .upgrade
        case .inbox:
            return kind == .inbox
        }
    }
}

enum HistoryStatusFilter: String, CaseIterable, Identifiable {
    case all
    case succeeded
    case failed
    case ignored

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .succeeded: return "完成"
        case .failed: return "失败"
        case .ignored: return "已忽略"
        }
    }

    func matches(_ status: HistoryEntryStatus) -> Bool {
        switch self {
        case .all:
            return true
        case .succeeded:
            return status == .succeeded
        case .failed:
            return status == .failed
        case .ignored:
            return status == .ignored
        }
    }
}

enum HistoryEntryKind: String, Hashable {
    case inspection
    case upgrade
    case inbox

    var title: String {
        switch self {
        case .inspection: return "巡检"
        case .upgrade: return "升级"
        case .inbox: return "待办"
        }
    }

    var symbol: String {
        switch self {
        case .inspection: return "checklist"
        case .upgrade: return "arrow.triangle.2.circlepath"
        case .inbox: return "tray.and.arrow.down"
        }
    }
}

enum HistoryEntryStatus: String, Hashable {
    case succeeded
    case failed
    case ignored
    case pending

    var title: String {
        switch self {
        case .succeeded: return "完成"
        case .failed: return "失败"
        case .ignored: return "已忽略"
        case .pending: return "待处理"
        }
    }
}

struct HistoryDetailItem: Hashable {
    var title: String
    var value: String
    var symbol: String
}

struct HistoryEntry: Identifiable, Hashable {
    var id: String
    var kind: HistoryEntryKind
    var status: HistoryEntryStatus
    var title: String
    var summary: String
    var timestamp: Date
    var detailItems: [HistoryDetailItem]
}

enum HistoryPresenter {
    static func entries(
        reports: [InspectionReportRecord],
        records: [UpgradeHistoryRecord],
        kind: HistoryKindFilter,
        status: HistoryStatusFilter,
        query: String
    ) -> [HistoryEntry] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (reports.map(entry) + records.map(entry))
            .filter { kind.matches($0.kind) && status.matches($0.status) }
            .filter { entry in
                normalizedQuery.isEmpty || searchText(entry).contains(normalizedQuery)
            }
            .sorted { lhs, rhs in
                lhs.timestamp > rhs.timestamp
            }
    }

    private static func entry(from report: InspectionReportRecord) -> HistoryEntry {
        var detailItems: [HistoryDetailItem] = [
            HistoryDetailItem(title: "触发方式", value: report.trigger.title, symbol: "play.circle"),
            HistoryDetailItem(title: "扫描范围", value: scanText(report.scanSummary), symbol: "magnifyingglass"),
            HistoryDetailItem(title: "自动升级", value: "\(report.automaticUpgrades.count)", symbol: "bolt.badge.checkmark"),
            HistoryDetailItem(title: "跳过", value: "\(report.skippedItems.count)", symbol: "forward.end"),
            HistoryDetailItem(title: "待办", value: "\(report.inboxItemIDs.count)", symbol: "tray")
        ]

        detailItems.append(contentsOf: report.automaticUpgrades.prefix(3).map {
            HistoryDetailItem(title: "升级项", value: "\($0.packageName) · \($0.source)", symbol: "shippingbox")
        })
        detailItems.append(contentsOf: report.skippedItems.prefix(3).map {
            HistoryDetailItem(title: "跳过项", value: "\($0.packageName)：\($0.reason)", symbol: "forward.end")
        })
        detailItems.append(contentsOf: report.failures.prefix(3).map {
            HistoryDetailItem(title: "失败", value: $0.message, symbol: "exclamationmark.triangle")
        })

        return HistoryEntry(
            id: "inspection:\(report.id.uuidString)",
            kind: .inspection,
            status: report.status == .succeeded ? .succeeded : .failed,
            title: report.trigger.title,
            summary: inspectionSummary(report),
            timestamp: report.startedAt,
            detailItems: detailItems
        )
    }

    private static func entry(from record: UpgradeHistoryRecord) -> HistoryEntry {
        let kind: HistoryEntryKind = record.label.hasPrefix("处理待办：") ? .inbox : .upgrade
        let status = status(from: record.status)
        var detailItems: [HistoryDetailItem] = [
            HistoryDetailItem(title: "处理结果", value: record.status, symbol: "checklist")
        ]
        if let startedAt = record.startedAt {
            detailItems.append(HistoryDetailItem(title: "开始时间", value: dateText(startedAt), symbol: "clock"))
        }
        if let exitCode = record.exitCode {
            detailItems.append(HistoryDetailItem(title: "退出码", value: "\(exitCode)", symbol: "number"))
        }
        detailItems.append(contentsOf: record.commands.prefix(3).map {
            HistoryDetailItem(title: "命令", value: $0, symbol: "terminal")
        })

        return HistoryEntry(
            id: "history:\(record.id.uuidString)",
            kind: kind,
            status: status,
            title: record.label,
            summary: record.summary,
            timestamp: record.startedAt ?? record.finishedAt ?? .distantPast,
            detailItems: detailItems
        )
    }

    private static func status(from value: String) -> HistoryEntryStatus {
        switch value {
        case "完成":
            return .succeeded
        case "已忽略":
            return .ignored
        case "待处理":
            return .pending
        default:
            return .failed
        }
    }

    private static func scanText(_ summary: InspectionScanSummary) -> String {
        let homebrewCount = summary.brewFormulae + summary.brewCasks
        return "应用 \(summary.applications)，Homebrew \(homebrewCount)，MAS \(summary.masApps)，可操作 \(summary.actionable)"
    }

    private static func inspectionSummary(_ report: InspectionReportRecord) -> String {
        "\(scanText(report.scanSummary))，自动 \(report.automaticUpgrades.count)，跳过 \(report.skippedItems.count)，失败 \(report.failures.count)"
    }

    private static func searchText(_ entry: HistoryEntry) -> String {
        ([entry.kind.title, entry.status.title, entry.title, entry.summary] + entry.detailItems.flatMap { [$0.title, $0.value] })
            .joined(separator: " ")
            .lowercased()
    }

    private static func dateText(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
