import Foundation

enum InboxKindFilter: String, CaseIterable, Identifiable {
    case all
    case decisions
    case apps
    case failures
    case sources
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .decisions: return "升级决策"
        case .apps: return "应用更新"
        case .failures: return "失败恢复"
        case .sources: return "来源异常"
        case .permissions: return "权限"
        }
    }

    func matches(_ kind: InboxItemKind) -> Bool {
        switch self {
        case .all:
            return true
        case .decisions:
            return kind == .upgradeDecision
        case .apps:
            return kind == .appUpdate
        case .failures:
            return kind == .failureRecovery
        case .sources:
            return kind == .sourceIssue
        case .permissions:
            return kind == .permissionIssue
        }
    }
}

enum InboxSeverityFilter: String, CaseIterable, Identifiable {
    case all
    case critical
    case warning
    case info

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .critical: return "严重"
        case .warning: return "需确认"
        case .info: return "信息"
        }
    }

    func matches(_ severity: InboxSeverity) -> Bool {
        switch self {
        case .all:
            return true
        case .critical:
            return severity == .critical
        case .warning:
            return severity == .warning
        case .info:
            return severity == .info
        }
    }
}

enum InboxFilterPresenter {
    static func items(
        from items: [InboxItem],
        kind: InboxKindFilter,
        severity: InboxSeverityFilter
    ) -> [InboxItem] {
        items.filter { item in
            kind.matches(item.kind) && severity.matches(item.severity)
        }
    }
}
