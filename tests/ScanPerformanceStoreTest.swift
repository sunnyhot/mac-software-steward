import Foundation

@main
struct ScanPerformanceStoreTest {
    static func main() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-performance-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let thirdID = UUID(uuidString: "00000000-0000-0000-0000-000000000203")!

        let store = ScanPerformanceStore(fileURL: url, limit: 2)
        precondition(store.records.isEmpty)

        store.append(makeSnapshot(id: firstID, scannedAt: 1, totalMs: 100))
        store.append(makeSnapshot(id: secondID, scannedAt: 3, totalMs: 300))
        precondition(store.records.map(\.id) == [secondID, firstID])

        store.append(makeSnapshot(id: firstID, scannedAt: 5, totalMs: 500))
        precondition(store.records.map(\.id) == [firstID, secondID])
        precondition(store.records.first?.totalMs == 500)

        store.append(makeSnapshot(id: thirdID, scannedAt: 4, totalMs: 400))
        precondition(store.records.map(\.id) == [firstID, thirdID])

        let reloaded = ScanPerformanceStore(fileURL: url, limit: 2)
        precondition(reloaded.records.map(\.id) == [firstID, thirdID])

        let replacement = [
            makeSnapshot(id: secondID, scannedAt: 2, totalMs: 200),
            makeSnapshot(id: thirdID, scannedAt: 6, totalMs: 600),
            makeSnapshot(id: firstID, scannedAt: 1, totalMs: 100)
        ]
        reloaded.replaceRecords(replacement)
        precondition(reloaded.records.map(\.id) == [thirdID, secondID])

        reloaded.clear()
        precondition(reloaded.records.isEmpty)

        let clearedReload = ScanPerformanceStore(fileURL: url, limit: 5)
        precondition(clearedReload.records.isEmpty)
    }

    private static func makeSnapshot(id: UUID, scannedAt: TimeInterval, totalMs: Int) -> ScanPerformanceSnapshot {
        ScanPerformanceSnapshot(
            id: id,
            scannedAt: Date(timeIntervalSince1970: scannedAt),
            includeGreedy: false,
            stages: [
                ScanPerformanceStage(phase: .applications, durationMs: totalMs / 2),
                ScanPerformanceStage(phase: .brew, durationMs: totalMs / 4),
                ScanPerformanceStage(phase: .total, durationMs: totalMs)
            ],
            applications: 1,
            brewFormulae: 1,
            brewCasks: 0,
            masApps: 0,
            outdated: 0,
            actionable: 0,
            applicationsSource: "test",
            brewAvailable: true,
            masAvailable: false
        )
    }
}
