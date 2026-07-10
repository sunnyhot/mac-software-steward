import Combine
import Foundation

// MARK: - Maintenance Run Record + Store
//
// 版本化的维护运行记录，存储每次维护 run 的触发来源、时间、终态、计划分类、
// 逐包执行/校验/失败/恢复结果，以及 dashboard 计数。
// 照搬 InspectionReportStore 的原子写、有界历史、损坏不阻塞启动惯例。
// 设计依据：docs/superpowers/specs/2026-07-10-unified-maintenance-engine-dashboard-design.md

/// 单个执行包在一次 run 中的完整结果记录。
struct MaintenanceRunPackageRecord: Codable, Identifiable, Hashable {
    var packageID: String
    var packageName: String
    var disposition: String
    var outcome: String
    var verificationStatus: String?
    var failureSummary: String?
    var commandDisplay: String?

    var id: String { packageID }
}

/// 每个来源（Homebrew / Mac App Store）在一次 run 中的可用性。
struct MaintenanceRunSourceAvailability: Codable, Hashable {
    var homebrewAvailable: Bool
    var masAvailable: Bool
    var homebrewError: String?
    var masError: String?
}

/// 一次维护运行的完整记录。
struct MaintenanceRunRecord: Codable, Identifiable, Hashable {
    var schemaVersion: Int
    var id: UUID
    var trigger: MaintenanceRunTrigger
    var startedAt: Date
    var finishedAt: Date
    var terminalStatus: MaintenanceRunTerminalStatus
    var scanSummary: InspectionScanSummary
    var sourceAvailability: MaintenanceRunSourceAvailability
    /// 计划分类计数。
    var automaticCount: Int
    var confirmationCount: Int
    var reminderCount: Int
    var blockedCount: Int
    /// 执行结果计数。
    var succeededCount: Int
    var failedCount: Int
    var timedOutCount: Int
    var cancelledCount: Int
    var neverStartedCount: Int
    /// 逐包记录（仅执行过的包）。
    var packages: [MaintenanceRunPackageRecord]
}

final class MaintenanceRunStore: ObservableObject {
    static let currentSchemaVersion = 1

    static let defaultFileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacSoftwareSteward", isDirectory: true)
            .appendingPathComponent("maintenance-runs.json")
    }()

    @Published private(set) var records: [MaintenanceRunRecord]

    private let fileURL: URL
    private let limit: Int

    init(fileURL: URL = MaintenanceRunStore.defaultFileURL, limit: Int = 50) {
        self.fileURL = fileURL
        self.limit = limit
        records = Self.load(from: fileURL)
        trimToLimit()
    }

    func append(_ record: MaintenanceRunRecord) {
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        sortNewestFirst()
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

    func replaceRecords(_ newRecords: [MaintenanceRunRecord]) {
        records = newRecords
        trimToLimit()
        save()
    }

    /// 最近一次完成的 run（任意终态）。
    var latestRecord: MaintenanceRunRecord? {
        records.first
    }

    private func sortNewestFirst() {
        records.sort { $0.startedAt > $1.startedAt }
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
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Failed to save maintenance runs: \(error.localizedDescription)")
        }
    }

    private static func load(from url: URL) -> [MaintenanceRunRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = (try? decoder.decode([MaintenanceRunRecord].self, from: data)) ?? []
        return records.sorted { $0.startedAt > $1.startedAt }
    }
}
