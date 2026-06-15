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
        precondition(store.add(first) == true)
        precondition(store.add(second) == true)
        precondition(store.add(second) == false)
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

        let foregroundStore = InboxStore(fileURL: url)
        precondition(foregroundStore.items.map(\.id) == [secondID])

        let externalID = UUID()
        let externalItem = InboxItem(
            id: externalID,
            kind: .appUpdate,
            severity: .info,
            title: "Sparkle 可更新",
            summary: "后台巡检发现普通 App 更新。",
            sourceID: "app:/Applications/Sparkle.app",
            createdAt: Date(timeIntervalSince1970: 30),
            status: .pending,
            actions: [
                InboxAction(title: "查看应用", systemImage: "macwindow", kind: .openApplications)
            ]
        )
        let externalStore = InboxStore(fileURL: url)
        precondition(externalStore.add(externalItem) == true)

        foregroundStore.reload()
        precondition(foregroundStore.items.map(\.id) == [externalID, secondID])
    }
}
