import Foundation

/// 每日巡检 agent 需要交给 GUI 应用代投的系统通知。
///
/// agent 由 launchd 以 helper 二进制方式启动，没有 LaunchServices 应用身份，
/// `UNUserNotificationCenter.requestAuthorization` 会直接抛
/// `UNErrorDomain` 错误 1（Notifications are not allowed for this application），
/// 因此巡检结束时把已决定的系统通知持久化到这里，由 GUI 应用下次启动时代投。
struct AutomationNotificationPayload: Codable, Equatable {
    var title: String
    var body: String
    var isUrgent: Bool
    var createdAt: Date

    var decision: AutomationNotificationDecision {
        AutomationNotificationDecision(title: title, body: body, isUrgent: isUrgent)
    }
}

enum AutomationNotificationPayloadStore {
    static var defaultFileURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
        return baseURL
            .appendingPathComponent("MacSoftwareSteward", isDirectory: true)
            .appendingPathComponent("pending-automation-notification.json")
    }

    static func save(
        _ decision: AutomationNotificationDecision,
        createdAt: Date = Date(),
        to fileURL: URL = defaultFileURL
    ) {
        let payload = AutomationNotificationPayload(
            title: decision.title,
            body: decision.body,
            isUrgent: decision.isUrgent,
            createdAt: createdAt
        )
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(payload).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Failed to save pending automation notification: \(error.localizedDescription)")
        }
    }

    static func load(from fileURL: URL = defaultFileURL) -> AutomationNotificationPayload? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(AutomationNotificationPayload.self, from: data)
    }

    static func clear(_ fileURL: URL = defaultFileURL) {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
