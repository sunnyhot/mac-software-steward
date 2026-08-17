import Foundation

@main
struct AutomationNotificationPayloadStoreTest {
    static func main() {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("MacSoftwareStewardPayloadStoreTest-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("pending-notification.json")

        // 文件不存在时 load 返回 nil
        precondition(AutomationNotificationPayloadStore.load(from: fileURL) == nil)

        let decision = AutomationNotificationDecision(
            title: "发现 2 个可升级项目",
            body: "打开“可升级”页面可查看并一键升级。",
            isUrgent: true
        )
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        AutomationNotificationPayloadStore.save(decision, createdAt: fixedDate, to: fileURL)

        // save 后 load 能还原出等价的决定
        guard let payload = AutomationNotificationPayloadStore.load(from: fileURL) else {
            preconditionFailure("payload should load after save")
        }
        precondition(payload.title == decision.title)
        precondition(payload.body == decision.body)
        precondition(payload.isUrgent == decision.isUrgent)
        precondition(payload.createdAt == fixedDate)
        precondition(payload.decision == decision)

        // clear 后文件被移除，load 再次返回 nil
        AutomationNotificationPayloadStore.clear(fileURL)
        precondition(AutomationNotificationPayloadStore.load(from: fileURL) == nil)

        // clear 对不存在的文件是幂等 no-op
        AutomationNotificationPayloadStore.clear(fileURL)
        precondition(AutomationNotificationPayloadStore.load(from: fileURL) == nil)

        print("AutomationNotificationPayloadStoreTest passed")
    }
}
