import Foundation

@main
struct ScanPerformancePresenterTest {
    static func main() {
        let snapshot = ScanPerformanceSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
            scannedAt: Date(timeIntervalSince1970: 100),
            includeGreedy: true,
            stages: [
                ScanPerformanceStage(phase: .applications, durationMs: 400),
                ScanPerformanceStage(phase: .brew, durationMs: 100),
                ScanPerformanceStage(phase: .mas, durationMs: 50),
                ScanPerformanceStage(phase: .classification, durationMs: 20),
                ScanPerformanceStage(phase: .regularAppDiscovery, durationMs: 80),
                ScanPerformanceStage(phase: .sparkleAppcast, durationMs: 1_200),
                ScanPerformanceStage(phase: .total, durationMs: 2_000)
            ],
            applications: 10,
            brewFormulae: 3,
            brewCasks: 2,
            masApps: 1,
            outdated: 4,
            actionable: 3,
            applicationsSource: "system_profiler",
            brewAvailable: true,
            masAvailable: false
        )

        let summary = ScanPerformancePresenter.summary(for: [snapshot])
        precondition(summary?.totalText == "2.00 s")
        precondition(summary?.slowestPhaseTitle == "Sparkle 更新源")
        precondition(summary?.countSummary == "10 个 App / 5 个 Brew / 1 个 MAS")

        let rows = ScanPerformancePresenter.phaseRows(for: snapshot)
        precondition(rows.map(\.title) == [
            "本机应用",
            "Homebrew",
            "App Store",
            "关联来源",
            "普通 App 检查",
            "Sparkle 更新源"
        ])
        precondition(rows.last?.isSlowest == true)
        precondition(rows.last?.percentText == "60%")

        let hint = ScanPerformancePresenter.diagnosticHint(for: snapshot)
        precondition(hint.title == "普通 App 更新检查较慢")
        precondition(hint.detail.contains("Sparkle"))

        precondition(ScanPerformancePresenter.summary(for: []) == nil)
        precondition(ScanPerformancePresenter.recentRows(for: [snapshot]).count == 1)
    }
}
