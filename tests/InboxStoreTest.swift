import Foundation

@main
struct InboxStoreTest {
    static func main() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("inbox-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let firstID = UUID()
        let secondID = UUID()
        let first = InboxItem(
            id: firstID,
            kind: .upgradeDecision,
            severity: .warning,
            title: "Node 需要确认",
            summary: "检测到 major 版本升级。",
            sourceID: "brew:formula:node",
            createdAt: Date(timeIntervalSince1970: 10),
            status: .pending,
            actions: [
                InboxAction(title: "查看升级", systemImage: "arrow.down.circle", kind: .openUpdates)
            ]
        )
        let second = InboxItem(
            id: secondID,
            kind: .failureRecovery,
            severity: .critical,
            title: "升级失败",
            summary: "Homebrew 返回非零退出码。",
            sourceID: "job:failed",
            createdAt: Date(timeIntervalSince1970: 20),
            status: .pending,
            actions: [
                InboxAction(title: "查看日志", systemImage: "terminal", kind: .openJobs)
            ]
        )

        let store = InboxStore(fileURL: url)
        precondition(store.items.isEmpty)
        store.add(first)
        store.add(second)
        precondition(store.items.map(\.id) == [secondID, firstID])
        precondition(store.pendingItems.count == 2)

        store.updateStatus(id: firstID, status: .resolved)
        precondition(store.items.first(where: { $0.id == firstID })?.status == .resolved)
        precondition(store.pendingItems.map(\.id) == [secondID])

        let reloaded = InboxStore(fileURL: url)
        precondition(reloaded.items.map(\.id) == [secondID, firstID])
        precondition(reloaded.items.first(where: { $0.id == firstID })?.status == .resolved)

        reloaded.clearResolved()
        precondition(reloaded.items.map(\.id) == [secondID])
    }
}
