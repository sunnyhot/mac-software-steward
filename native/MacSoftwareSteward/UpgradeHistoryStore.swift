import Combine
import Foundation

struct UpgradeHistoryRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var label: String
    var status: String
    var startedAt: Date?
    var finishedAt: Date?
    var commands: [String]
    var exitCode: Int32?
    var summary: String
}

final class UpgradeHistoryStore: ObservableObject {
    @Published private(set) var records: [UpgradeHistoryRecord]

    private let fileURL: URL
    private let limit: Int

    init(fileURL: URL = UpgradeHistoryStore.defaultFileURL, limit: Int = 50) {
        self.fileURL = fileURL
        self.limit = limit
        records = Self.load(from: fileURL)
    }

    func append(_ record: UpgradeHistoryRecord) {
        records.insert(record, at: 0)
        if records.count > limit {
            records.removeLast(records.count - limit)
        }
        save()
    }

    func clear() {
        records.removeAll()
        save()
    }

    func replaceRecords(_ newRecords: [UpgradeHistoryRecord]) {
        records = newRecords
        trimToLimit()
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Failed to save upgrade history: \(error.localizedDescription)")
        }
    }

    private func sortNewestFirst() {
        records.sort { lhs, rhs in
            (lhs.startedAt ?? .distantPast) > (rhs.startedAt ?? .distantPast)
        }
    }

    private func trimToLimit() {
        sortNewestFirst()
        if records.count > limit {
            records.removeLast(records.count - limit)
        }
    }

    private static func load(from url: URL) -> [UpgradeHistoryRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = (try? decoder.decode([UpgradeHistoryRecord].self, from: data)) ?? []
        return records.sorted { lhs, rhs in
            (lhs.startedAt ?? .distantPast) > (rhs.startedAt ?? .distantPast)
        }
    }

    static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacSoftwareSteward", isDirectory: true)
            .appendingPathComponent("upgrade-history.json")
    }
}
