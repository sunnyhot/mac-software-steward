import Foundation
import UserNotifications

@MainActor
protocol AutomationNotificationDelivering {
    func deliver(_ decision: AutomationNotificationDecision) async
}

@MainActor
final class UserNotificationDispatcher: AutomationNotificationDelivering {
    private let center: UNUserNotificationCenter?

    init(center: UNUserNotificationCenter? = nil) {
        self.center = center
    }

    func deliver(_ decision: AutomationNotificationDecision) async {
        do {
            let center = center ?? UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = decision.title
            content.body = decision.body
            if decision.isUrgent {
                content.sound = .default
            }

            let request = UNNotificationRequest(
                identifier: "automation-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try await center.add(request)
        } catch {
            NSLog("Failed to deliver automation notification: \(error.localizedDescription)")
        }
    }
}
