import Foundation

@main
struct UpgradeHistoryStoreTest {
    static func main() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = UpgradeHistoryStore(fileURL: url, limit: 2)

        store.append(UpgradeHistoryRecord(id: UUID(), label: "one", status: "完成", startedAt: Date(timeIntervalSince1970: 1), finishedAt: Date(timeIntervalSince1970: 2), commands: ["brew upgrade one"], exitCode: 0, summary: "ok"))
        store.append(UpgradeHistoryRecord(id: UUID(), label: "two", status: "失败", startedAt: Date(timeIntervalSince1970: 3), finishedAt: Date(timeIntervalSince1970: 4), commands: ["brew upgrade two"], exitCode: 1, summary: "failed"))
        store.append(UpgradeHistoryRecord(id: UUID(), label: "three", status: "完成", startedAt: Date(timeIntervalSince1970: 5), finishedAt: Date(timeIntervalSince1970: 6), commands: ["brew upgrade three"], exitCode: 0, summary: "ok"))

        precondition(store.records.count == 2)
        precondition(store.records.first?.label == "three")

        let reloaded = UpgradeHistoryStore(fileURL: url, limit: 2)
        precondition(reloaded.records.count == 2)
        precondition(reloaded.records.map(\.label) == ["three", "two"])

        let replacement = [
            UpgradeHistoryRecord(id: UUID(), label: "older", status: "失败", startedAt: Date(timeIntervalSince1970: 7), finishedAt: Date(timeIntervalSince1970: 8), commands: ["brew upgrade older"], exitCode: 1, summary: "failed"),
            UpgradeHistoryRecord(id: UUID(), label: "newer", status: "完成", startedAt: Date(timeIntervalSince1970: 9), finishedAt: Date(timeIntervalSince1970: 10), commands: ["brew upgrade newer"], exitCode: 0, summary: "ok"),
            UpgradeHistoryRecord(id: UUID(), label: "trimmed", status: "完成", startedAt: Date(timeIntervalSince1970: 6), finishedAt: Date(timeIntervalSince1970: 7), commands: ["brew upgrade trimmed"], exitCode: 0, summary: "ok")
        ]
        reloaded.replaceRecords(replacement)
        precondition(reloaded.records.map(\.label) == ["newer", "older"])

        let replacementReloaded = UpgradeHistoryStore(fileURL: url, limit: 5)
        precondition(replacementReloaded.records.map(\.label) == ["newer", "older"])
    }
}
