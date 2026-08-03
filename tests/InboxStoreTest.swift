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

        // 扫描恢复正常后，旧的问题条目需要被主动清理。
        // 复现“扫描错误一直显示”的回归：扫描成功时 factory 不再生成 source:homebrew 条目，
        // 因此必须由 store 按残留 sourceID 退出，否则旧错误条目会永久残留。
        let staleBrewIssue = InboxItem(
            kind: .sourceIssue,
            severity: .warning,
            title: "Homebrew 来源需要处理",
            summary: "Homebrew 扫描遇到错误：boom",
            sourceID: "source:homebrew",
            createdAt: Date(timeIntervalSince1970: 40),
            actions: [
                InboxAction(title: "重新扫描", systemImage: "arrow.clockwise", kind: .rescan)
            ]
        )
        precondition(externalStore.add(staleBrewIssue) == true)
        precondition(externalStore.items.map(\.sourceID).contains("source:homebrew"))

        externalStore.retireSourceIssues(notPresentIn: ["source:mas"])
        precondition(!externalStore.items.contains { $0.sourceID == "source:homebrew" })
        precondition(externalStore.items.contains { $0.sourceID == "job:failed" })
        precondition(externalStore.items.contains { $0.sourceID == "app:/Applications/Sparkle.app" })

        let persistedAfterRetire = InboxStore(fileURL: url)
        precondition(!persistedAfterRetire.items.contains { $0.sourceID == "source:homebrew" })
    }
}
