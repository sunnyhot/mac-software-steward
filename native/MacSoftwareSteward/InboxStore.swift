import Combine
import Foundation

enum InboxItemKind: String, Codable, CaseIterable, Identifiable {
    case upgradeDecision
    case appUpdate
    case failureRecovery
    case sourceIssue
    case permissionIssue
    case automationIssue

    var id: String { rawValue }
}

enum InboxSeverity: String, Codable, CaseIterable, Identifiable {
    case info
    case warning
    case critical

    var id: String { rawValue }
}

enum InboxStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case resolved
    case ignored

    var id: String { rawValue }
}

enum InboxActionKind: String, Codable, CaseIterable, Identifiable {
    case openUpdates
    case openApplications
    case openSources
    case openJobs
    case openRules
    case openSettings
    case rescan
    case retryPackage
    case copyRecoveryCommand
    case openStorageSettings

    var id: String { rawValue }
}

struct InboxAction: Codable, Hashable {
    var title: String
    var systemImage: String
    var kind: InboxActionKind
}

struct InboxItem: Codable, Identifiable, Hashable {
    var id: UUID
    var kind: InboxItemKind
    var severity: InboxSeverity
    var title: String
    var summary: String
    var sourceID: String?
    var createdAt: Date
    var status: InboxStatus
    var actions: [InboxAction]

    init(
        id: UUID = UUID(),
        kind: InboxItemKind,
        severity: InboxSeverity,
        title: String,
        summary: String,
        sourceID: String? = nil,
        createdAt: Date = Date(),
        status: InboxStatus = .pending,
        actions: [InboxAction] = []
    ) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.title = title
        self.summary = summary
        self.sourceID = sourceID
        self.createdAt = createdAt
        self.status = status
        self.actions = actions
    }
}

final class InboxStore: ObservableObject {
    static let defaultFileURL: URL = {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)

        return baseURL
            .appendingPathComponent("MacSoftwareSteward", isDirectory: true)
            .appendingPathComponent("inbox.json")
    }()

    @Published private(set) var items: [InboxItem]

    private let fileURL: URL

    init(fileURL: URL = InboxStore.defaultFileURL) {
        self.fileURL = fileURL
        items = Self.load(from: fileURL)
    }

    var pendingItems: [InboxItem] {
        items.filter { $0.status == .pending }
    }

    @discardableResult
    func add(_ item: InboxItem) -> Bool {
        let replacesExisting: Bool
        if let sourceID = item.sourceID, !sourceID.isEmpty {
            replacesExisting = items.contains { existing in
                existing.kind == item.kind && existing.sourceID == sourceID
            }
            items.removeAll { existing in
                existing.kind == item.kind && existing.sourceID == sourceID
            }
        } else {
            replacesExisting = items.contains { $0.id == item.id }
        }
        items.removeAll { $0.id == item.id }
        items.append(item)
        sortNewestFirst()
        save()
        return !replacesExisting
    }

    /// 批量添加条目，只在末尾保存一次。
    /// 避免在 scanSoftware 的循环里逐条 add 导致每条都全量 encode + 写盘。
    @discardableResult
    func addAll(_ newItems: [InboxItem]) -> [InboxItem] {
        guard !newItems.isEmpty else { return [] }
        var appended: [InboxItem] = []
        for item in newItems {
            if let sourceID = item.sourceID, !sourceID.isEmpty {
                let isNew = !items.contains { existing in
                    existing.kind == item.kind && existing.sourceID == sourceID
                }
                items.removeAll { existing in
                    existing.kind == item.kind && existing.sourceID == sourceID
                }
                if isNew { appended.append(item) }
            } else if !items.contains(where: { $0.id == item.id }) {
                appended.append(item)
            }
            items.removeAll { $0.id == item.id }
            items.append(item)
        }
        sortNewestFirst()
        save()
        return appended
    }

    func updateStatus(id: UUID, status: InboxStatus) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = status
        save()
    }

    func clearResolved() {
        items.removeAll { $0.status == .resolved }
        save()
    }

    /// 主动退出已不存在的来源问题条目。
    ///
    /// 扫描恢复正常后，`SourceIssueInboxFactory` 不再为对应来源生成条目，
    /// 仅靠 `add(_:)` 无法清除旧条目（没有新条目触发覆盖）。
    /// 调用方传入本次扫描仍存在的来源 sourceID 集合，
    /// 其余 `sourceIssue` 条目会被移除，避免错误提示永久残留。
    func retireSourceIssues(notPresentIn presentSourceIDs: Set<String>) {
        let before = items.count
        items.removeAll { item in
            item.kind == .sourceIssue
                && item.sourceID.map { !presentSourceIDs.contains($0) } ?? false
        }
        guard items.count != before else { return }
        save()
    }

    /// 移除指定包的「需要确认升级」类条目。
    ///
    /// 自动升级成功后调用：包已升级，不应再挂着需要确认的待办。
    /// 升级失败时保留条目，用户仍可在收件箱看到并重试。
    func removeUpgradeDecisions(packageIDs: Set<String>) {
        let before = items.count
        items.removeAll { item in
            guard item.kind == .upgradeDecision, let sourceID = item.sourceID else { return false }
            let prefix = "upgrade:"
            let packageID = sourceID.hasPrefix(prefix) ? String(sourceID.dropFirst(prefix.count)) : sourceID
            return packageIDs.contains(packageID)
        }
        guard items.count != before else { return }
        save()
    }

    func reload() {
        items = Self.load(from: fileURL)
    }

    private func sortNewestFirst() {
        items.sort { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }
    }

    private static func load(from fileURL: URL) -> [InboxItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let items = (try? decoder.decode([InboxItem].self, from: data)) ?? []
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Failed to save inbox items: \(error.localizedDescription)")
        }
    }
}
