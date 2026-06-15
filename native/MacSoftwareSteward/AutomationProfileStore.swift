import Combine
import Foundation

enum NotificationPolicy: String, Codable, CaseIterable, Identifiable {
    case decisionsAndFailures
    case everyInspection
    case everyAction
    case silent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .decisionsAndFailures: return "只在需要处理时通知"
        case .everyInspection: return "每次巡检后通知"
        case .everyAction: return "每个动作都通知"
        case .silent: return "静默记录"
        }
    }
}

enum RegularAppNetworkPolicy: String, Codable, CaseIterable, Identifiable {
    case declaredSourcesOnly
    case aggressive
    case localOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .declaredSourcesOnly: return "声明来源与受控接口"
        case .aggressive: return "积极检查公开页面"
        case .localOnly: return "仅本地识别"
        }
    }
}

enum AutoRepairPolicy: String, Codable, CaseIterable, Identifiable {
    case manualOnly
    case allowLowRisk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manualOnly: return "手动确认"
        case .allowLowRisk: return "允许低风险自动修复"
        }
    }
}

struct AutomationProfile: Codable, Equatable {
    var onboardingCompleted: Bool
    var automationEnabled: Bool
    var dailyInspectionEnabled: Bool
    var lowRiskAutoUpgradeEnabled: Bool
    var advancedModeEnabled: Bool
    var notificationPolicy: NotificationPolicy
    var regularAppNetworkPolicy: RegularAppNetworkPolicy
    var autoRepairPolicy: AutoRepairPolicy

    static let manualDefault = AutomationProfile(
        onboardingCompleted: false,
        automationEnabled: false,
        dailyInspectionEnabled: false,
        lowRiskAutoUpgradeEnabled: false,
        advancedModeEnabled: false,
        notificationPolicy: .decisionsAndFailures,
        regularAppNetworkPolicy: .declaredSourcesOnly,
        autoRepairPolicy: .manualOnly
    )
}

final class AutomationProfileStore: ObservableObject {
    static let defaultFileURL: URL = {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)

        return baseURL
            .appendingPathComponent("MacSoftwareSteward", isDirectory: true)
            .appendingPathComponent("automation-profile.json")
    }()

    @Published private(set) var profile: AutomationProfile

    private let fileURL: URL

    init(fileURL: URL = AutomationProfileStore.defaultFileURL) {
        self.fileURL = fileURL
        profile = Self.load(from: fileURL)
    }

    func completeOnboarding(enableAutomation: Bool) {
        profile.onboardingCompleted = true
        profile.automationEnabled = enableAutomation
        profile.dailyInspectionEnabled = enableAutomation
        profile.lowRiskAutoUpgradeEnabled = enableAutomation
        save()
    }

    func setAutomationEnabled(_ enabled: Bool) {
        profile.automationEnabled = enabled
        if !enabled {
            profile.lowRiskAutoUpgradeEnabled = false
        }
        save()
    }

    func setDailyInspectionEnabled(_ enabled: Bool) {
        profile.dailyInspectionEnabled = enabled
        save()
    }

    func setLowRiskAutoUpgradeEnabled(_ enabled: Bool) {
        profile.lowRiskAutoUpgradeEnabled = enabled
        if enabled {
            profile.automationEnabled = true
        }
        save()
    }

    func setAdvancedMode(_ enabled: Bool) {
        profile.advancedModeEnabled = enabled
        save()
    }

    func setNotificationPolicy(_ policy: NotificationPolicy) {
        profile.notificationPolicy = policy
        save()
    }

    func setRegularAppNetworkPolicy(_ policy: RegularAppNetworkPolicy) {
        profile.regularAppNetworkPolicy = policy
        save()
    }

    func setAutoRepairPolicy(_ policy: AutoRepairPolicy) {
        profile.autoRepairPolicy = policy
        save()
    }

    func replace(with newProfile: AutomationProfile) {
        profile = newProfile
        save()
    }

    private static func load(from fileURL: URL) -> AutomationProfile {
        guard let data = try? Data(contentsOf: fileURL) else {
            return .manualDefault
        }

        let decoder = JSONDecoder()
        return (try? decoder.decode(AutomationProfile.self, from: data)) ?? .manualDefault
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(profile)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Failed to save automation profile: \(error.localizedDescription)")
        }
    }
}
