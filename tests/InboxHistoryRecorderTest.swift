import Foundation

@main
struct InboxHistoryRecorderTest {
    static func main() {
        let item = InboxItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            kind: .sourceIssue,
            severity: .warning,
            title: "Homebrew 来源需要处理",
            summary: "未检测到 Homebrew。",
            sourceID: "source:homebrew",
            createdAt: Date(timeIntervalSince1970: 10),
            status: .pending,
            actions: [
                InboxAction(title: "查看来源", systemImage: "tray.full", kind: .openSources)
            ]
        )

        let resolved = InboxHistoryRecorder.record(
            for: item,
            status: .resolved,
            handledAt: Date(timeIntervalSince1970: 20)
        )
        precondition(resolved.label == "处理待办：Homebrew 来源需要处理")
        precondition(resolved.status == "完成")
        precondition(resolved.startedAt == Date(timeIntervalSince1970: 20))
        precondition(resolved.finishedAt == Date(timeIntervalSince1970: 20))
        precondition(resolved.commands.isEmpty)
        precondition(resolved.exitCode == nil)
        precondition(resolved.summary == "收件箱事项已完成：未检测到 Homebrew。")

        let ignored = InboxHistoryRecorder.record(
            for: item,
            status: .ignored,
            handledAt: Date(timeIntervalSince1970: 30)
        )
        precondition(ignored.status == "已忽略")
        precondition(ignored.summary == "收件箱事项已忽略：未检测到 Homebrew。")
    }
}
