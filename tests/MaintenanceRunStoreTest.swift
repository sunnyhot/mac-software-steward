import Foundation

@main
struct MaintenanceRunStoreTest {
    static func main() {
        // 每次用独立临时文件，避免互相干扰。
        func makeStore() -> MaintenanceRunStore {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("maintenance-run-store-\(UUID().uuidString).json")
            return MaintenanceRunStore(fileURL: url, limit: 3)
        }

        func makeRecord(id: String, startedAt: TimeInterval, terminalStatus: MaintenanceRunTerminalStatus = .completed) -> MaintenanceRunRecord {
            MaintenanceRunRecord(
                schemaVersion: MaintenanceRunStore.currentSchemaVersion,
                id: UUID(uuidString: id)!,
                trigger: .smartMaintenance,
                startedAt: Date(timeIntervalSince1970: startedAt),
                finishedAt: Date(timeIntervalSince1970: startedAt + 10),
                terminalStatus: terminalStatus,
                scanSummary: InspectionScanSummary(applications: 1, brewFormulae: 2, brewCasks: 3, masApps: 4, outdated: 5, actionable: 6),
                sourceAvailability: MaintenanceRunSourceAvailability(homebrewAvailable: true, masAvailable: false, homebrewError: nil, masError: nil),
                automaticCount: 1, confirmationCount: 0, reminderCount: 0, blockedCount: 0,
                succeededCount: 1, failedCount: 0, timedOutCount: 0, cancelledCount: 0, neverStartedCount: 0,
                packages: []
            )
        }

        // MARK: append + latestRecord
        let store = makeStore()
        precondition(store.records.isEmpty, "新 store 应为空")

        let r1 = makeRecord(id: "00000000-0000-0000-0000-000000000001", startedAt: 100)
        store.append(r1)
        precondition(store.records.count == 1, "append 后应有 1 条")
        precondition(store.latestRecord?.id == r1.id, "latestRecord 应为 r1")

        let r2 = makeRecord(id: "00000000-0000-0000-0000-000000000002", startedAt: 200)
        store.append(r2)
        precondition(store.records.count == 2)
        precondition(store.latestRecord?.id == r2.id, "latestRecord 应为 r2（更新的）")
        precondition(store.records.map(\.startedAt) == [Date(timeIntervalSince1970: 200), Date(timeIntervalSince1970: 100)], "应按时间倒序")

        // MARK: 有界历史（limit=3）
        let r3 = makeRecord(id: "00000000-0000-0000-0000-000000000003", startedAt: 300)
        let r4 = makeRecord(id: "00000000-0000-0000-0000-000000000004", startedAt: 400)
        store.append(r3)
        store.append(r4)
        precondition(store.records.count == 3, "limit=3 应只保留 3 条")
        precondition(store.records.first?.id == r4.id, "最新的 r4 应在首位")
        precondition(store.records.last?.id == r2.id, "r1 应被裁掉，r2 在末尾")

        // MARK: round trip（从磁盘重新加载）
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("maintenance-run-store-rt-\(UUID().uuidString).json")
        let store1 = MaintenanceRunStore(fileURL: storeURL, limit: 10)
        let rtRecord = makeRecord(id: "00000000-0000-0000-0000-000000000010", startedAt: 500, terminalStatus: .partialSuccess)
        store1.append(rtRecord)
        let store2 = MaintenanceRunStore(fileURL: storeURL, limit: 10)
        precondition(store2.records.count == 1, "重新加载应有 1 条")
        precondition(store2.records.first?.id == rtRecord.id, "round trip id 匹配")
        precondition(store2.records.first?.terminalStatus == .partialSuccess, "round trip terminalStatus 匹配")

        // MARK: 损坏文件不崩溃
        let corruptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("maintenance-run-store-corrupt-\(UUID().uuidString).json")
        try! Data("not json".utf8).write(to: corruptURL)
        let corruptStore = MaintenanceRunStore(fileURL: corruptURL, limit: 10)
        precondition(corruptStore.records.isEmpty, "损坏文件应返回空，不崩溃")

        // MARK: clear
        store1.clear()
        precondition(store1.records.isEmpty, "clear 后应为空")

        print("MaintenanceRunStoreTest passed")
    }
}
