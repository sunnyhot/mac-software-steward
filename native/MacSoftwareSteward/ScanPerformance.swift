import Foundation

enum ScanPerformancePhase: String, Codable, CaseIterable, Hashable, Identifiable {
    case applications
    case brew
    case mas
    case classification
    case regularAppDiscovery
    case sparkleAppcast
    case total

    var id: String { rawValue }

    static let ordered: [ScanPerformancePhase] = [
        .applications,
        .brew,
        .mas,
        .classification,
        .regularAppDiscovery,
        .sparkleAppcast,
        .total
    ]

    var title: String {
        switch self {
        case .applications: return "本机应用"
        case .brew: return "Homebrew"
        case .mas: return "App Store"
        case .classification: return "关联来源"
        case .regularAppDiscovery: return "普通 App 检查"
        case .sparkleAppcast: return "Sparkle 更新源"
        case .total: return "总耗时"
        }
    }

    var symbol: String {
        switch self {
        case .applications: return "macwindow"
        case .brew: return "shippingbox"
        case .mas: return "app.badge"
        case .classification: return "link"
        case .regularAppDiscovery: return "doc.text.magnifyingglass"
        case .sparkleAppcast: return "sparkles"
        case .total: return "timer"
        }
    }
}

struct ScanPerformanceStage: Codable, Hashable, Identifiable {
    var phase: ScanPerformancePhase
    var durationMs: Int

    var id: ScanPerformancePhase { phase }
    var title: String { phase.title }
    var durationText: String { Self.formatDuration(durationMs) }

    func fraction(of totalMs: Int) -> Double {
        guard totalMs > 0, durationMs > 0 else { return 0 }
        return min(1, Double(durationMs) / Double(totalMs))
    }

    static func formatDuration(_ durationMs: Int) -> String {
        if durationMs < 1_000 {
            return "\(max(durationMs, 0)) ms"
        }
        let seconds = Double(durationMs) / 1_000
        return String(format: "%.2f s", seconds)
    }
}

struct ScanPerformanceSnapshot: Codable, Identifiable, Hashable {
    var id: UUID
    var scannedAt: Date
    var includeGreedy: Bool
    var stages: [ScanPerformanceStage]
    var applications: Int
    var brewFormulae: Int
    var brewCasks: Int
    var masApps: Int
    var outdated: Int
    var actionable: Int
    var applicationsSource: String
    var brewAvailable: Bool
    var masAvailable: Bool

    var totalMs: Int {
        stages.first(where: { $0.phase == .total })?.durationMs
            ?? stages.map(\.durationMs).reduce(0, +)
    }

    var measuredStages: [ScanPerformanceStage] {
        let byPhase = Dictionary(stages.map { ($0.phase, $0) }, uniquingKeysWith: { _, last in last })
        return ScanPerformancePhase.ordered
            .filter { $0 != .total }
            .compactMap { byPhase[$0] }
    }

    var slowestStage: ScanPerformanceStage? {
        measuredStages.max { lhs, rhs in
            lhs.durationMs < rhs.durationMs
        }
    }

    var countSummary: String {
        "\(applications) 个 App / \(brewFormulae + brewCasks) 个 Brew / \(masApps) 个 MAS"
    }

    static func empty(scannedAt: Date = Date()) -> ScanPerformanceSnapshot {
        ScanPerformanceSnapshot(
            id: UUID(),
            scannedAt: scannedAt,
            includeGreedy: false,
            stages: [ScanPerformanceStage(phase: .total, durationMs: 0)],
            applications: 0,
            brewFormulae: 0,
            brewCasks: 0,
            masApps: 0,
            outdated: 0,
            actionable: 0,
            applicationsSource: "",
            brewAvailable: false,
            masAvailable: false
        )
    }
}
