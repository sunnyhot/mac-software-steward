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

    func updateStatus(id: UUID, status: InboxStatus) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = status
        save()
    }

    func clearResolved() {
        items.removeAll { $0.status == .resolved }
        save()
    }

    func replaceAll(_ newItems: [InboxItem]) {
        items = newItems
        sortNewestFirst()
        save()
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
