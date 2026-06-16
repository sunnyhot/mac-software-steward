import Combine
import Foundation

final class ScanPerformanceStore: ObservableObject {
    static let defaultFileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacSoftwareSteward", isDirectory: true)
            .appendingPathComponent("scan-performance.json")
    }()

    @Published private(set) var records: [ScanPerformanceSnapshot]

    private let fileURL: URL
    private let limit: Int

    init(fileURL: URL = ScanPerformanceStore.defaultFileURL, limit: Int = 50) {
        self.fileURL = fileURL
        self.limit = limit
        records = Self.load(from: fileURL)
        trimToLimit()
    }

    func append(_ record: ScanPerformanceSnapshot) {
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        trimToLimit()
        save()
    }

    func reload() {
        records = Self.load(from: fileURL)
        trimToLimit()
    }

    func clear() {
        records.removeAll()
        save()
    }

    func replaceRecords(_ newRecords: [ScanPerformanceSnapshot]) {
        records = newRecords
        trimToLimit()
        save()
    }

    private func sortNewestFirst() {
        records.sort { lhs, rhs in
            lhs.scannedAt > rhs.scannedAt
        }
    }

    private func trimToLimit() {
        sortNewestFirst()
        if records.count > limit {
            records.removeLast(records.count - limit)
        }
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
            NSLog("Failed to save scan performance records: \(error.localizedDescription)")
        }
    }

    private static func load(from url: URL) -> [ScanPerformanceSnapshot] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = (try? decoder.decode([ScanPerformanceSnapshot].self, from: data)) ?? []
        return records.sorted { lhs, rhs in
            lhs.scannedAt > rhs.scannedAt
        }
    }
}
