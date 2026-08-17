import Combine
import Foundation

enum UpgradePolicy: String, Codable, CaseIterable, Identifiable {
    case automatic
    case askFirst
    case remindOnly
    case skip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "自动升级"
        case .askFirst: return "确认后升级"
        case .remindOnly: return "仅提醒"
        case .skip: return "跳过"
        }
    }
}

final class UpgradePolicyStore: ObservableObject {
    static let defaultFileURL: URL = {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)

        return baseURL
            .appendingPathComponent("MacSoftwareSteward", isDirectory: true)
            .appendingPathComponent("upgrade-policies.json")
    }()

    @Published private(set) var overrides: [String: UpgradePolicy]

    private let fileURL: URL

    init(fileURL: URL = UpgradePolicyStore.defaultFileURL) {
        self.fileURL = fileURL
        overrides = Self.loadOverrides(from: fileURL)
    }

    func policyOverride(forPackageID packageID: String) -> UpgradePolicy? {
        overrides[packageID]
    }

    func set(_ policy: UpgradePolicy, forPackageID packageID: String) {
        overrides[packageID] = policy
        save()
    }

    func replaceOverrides(_ newOverrides: [String: UpgradePolicy]) {
        overrides = newOverrides
        save()
    }

    func effectivePolicy(for package: UpdatablePackage, includeGreedy: Bool) -> UpgradePolicy {
        if let override = overrides[package.id] {
            return override
        }

        // 默认策略统一为「自动升级」：formula、cask（含 greedy/auto_updates）、mas 一律自动。
        // 需要个别处理的软件在升级策略里单独设置「确认后升级 / 仅提醒 / 跳过」覆盖。
        return .automatic
    }

    private static func loadOverrides(from fileURL: URL) -> [String: UpgradePolicy] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let overrides = try? JSONDecoder().decode([String: UpgradePolicy].self, from: data)
        else {
            return [:]
        }

        return overrides
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(overrides)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Failed to save upgrade policies: \(error)")
        }
    }
}
