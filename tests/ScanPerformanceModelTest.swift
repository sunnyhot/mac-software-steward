import Foundation

@main
struct ScanPerformanceModelTest {
    static func main() {
        let stages = [
            ScanPerformanceStage(phase: .applications, durationMs: 250),
            ScanPerformanceStage(phase: .brew, durationMs: 700),
            ScanPerformanceStage(phase: .mas, durationMs: 100),
            ScanPerformanceStage(phase: .classification, durationMs: 30),
            ScanPerformanceStage(phase: .regularAppDiscovery, durationMs: 200),
            ScanPerformanceStage(phase: .sparkleAppcast, durationMs: 450),
            ScanPerformanceStage(phase: .total, durationMs: 1_800)
        ]
        let snapshot = ScanPerformanceSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!,
            scannedAt: Date(timeIntervalSince1970: 100),
            includeGreedy: true,
            stages: stages,
            applications: 12,
            brewFormulae: 4,
            brewCasks: 3,
            masApps: 2,
            outdated: 5,
            actionable: 4,
            applicationsSource: "system_profiler",
            brewAvailable: true,
            masAvailable: true
        )

        precondition(ScanPerformancePhase.applications.title == "本机应用")
        precondition(ScanPerformancePhase.sparkleAppcast.title == "Sparkle 更新源")
        precondition(ScanPerformancePhase.total.title == "总耗时")
        precondition(ScanPerformancePhase.ordered == [
            .applications,
            .brew,
            .mas,
            .classification,
            .regularAppDiscovery,
            .sparkleAppcast,
            .total
        ])

        precondition(snapshot.totalMs == 1_800)
        precondition(snapshot.measuredStages.map(\.phase) == [
            .applications,
            .brew,
            .mas,
            .classification,
            .regularAppDiscovery,
            .sparkleAppcast
        ])
        precondition(snapshot.slowestStage?.phase == .brew)
        precondition(snapshot.countSummary == "12 个 App / 7 个 Brew / 2 个 MAS")

        precondition(ScanPerformanceStage(phase: .brew, durationMs: 500).fraction(of: 2_000) == 0.25)
        precondition(ScanPerformanceStage(phase: .brew, durationMs: 500).fraction(of: 0) == 0)
        precondition(ScanPerformanceStage.formatDuration(999) == "999 ms")
        precondition(ScanPerformanceStage.formatDuration(1_250) == "1.25 s")

        let empty = ScanPerformanceSnapshot.empty(scannedAt: Date(timeIntervalSince1970: 200))
        precondition(empty.totalMs == 0)
        precondition(empty.slowestStage == nil)
    }
}
