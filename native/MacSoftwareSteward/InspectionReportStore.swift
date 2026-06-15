import Combine
import Foundation

enum InspectionReportTrigger: String, Codable, Hashable {
    case dailyAgent
    case manualRun

    var title: String {
        switch self {
        case .dailyAgent: return "每日巡检"
        case .manualRun: return "手动巡检"
        }
    }
}

enum InspectionReportStatus: String, Codable, Hashable {
    case succeeded
    case failed

    var title: String {
        switch self {
        case .succeeded: return "完成"
        case .failed: return "失败"
        }
    }
}

struct InspectionScanSummary: Codable, Hashable {
    var applications: Int
    var brewFormulae: Int
    var brewCasks: Int
    var masApps: Int
    var outdated: Int
    var actionable: Int
}

struct InspectionPackageRecord: Codable, Hashable {
    var packageID: String
    var packageName: String
    var source: String
}

struct InspectionSkippedRecord: Codable, Hashable {
    var packageID: String
    var packageName: String
    var reason: String
}

struct InspectionFailureRecord: Codable, Hashable {
    var message: String
    var commandDisplay: String
    var exitCode: Int32?
}

struct InspectionReportRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var trigger: InspectionReportTrigger
    var startedAt: Date
    var finishedAt: Date
    var status: InspectionReportStatus
    var scanSummary: InspectionScanSummary
    var automaticUpgrades: [InspectionPackageRecord]
    var skippedItems: [InspectionSkippedRecord]
    var failures: [InspectionFailureRecord]
    var inboxItemIDs: [UUID]
}

final class InspectionReportStore: ObservableObject {
    static let defaultFileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacSoftwareSteward", isDirectory: true)
            .appendingPathComponent("inspection-reports.json")
    }()

    @Published private(set) var reports: [InspectionReportRecord]

    private let fileURL: URL
    private let limit: Int

    init(fileURL: URL = InspectionReportStore.defaultFileURL, limit: Int = 50) {
        self.fileURL = fileURL
        self.limit = limit
        reports = Self.load(from: fileURL)
        trimToLimit()
    }

    func append(_ report: InspectionReportRecord) {
        reports.removeAll { $0.id == report.id }
        reports.insert(report, at: 0)
        sortNewestFirst()
        trimToLimit()
        save()
    }

    func reload() {
        reports = Self.load(from: fileURL)
        trimToLimit()
    }

    func clear() {
        reports.removeAll()
        save()
    }

    func replaceReports(_ newReports: [InspectionReportRecord]) {
        reports = newReports
        trimToLimit()
        save()
    }

    private func sortNewestFirst() {
        reports.sort { lhs, rhs in
            lhs.startedAt > rhs.startedAt
        }
    }

    private func trimToLimit() {
        sortNewestFirst()
        if reports.count > limit {
            reports.removeLast(reports.count - limit)
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
            let data = try encoder.encode(reports)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Failed to save inspection reports: \(error.localizedDescription)")
        }
    }

    private static func load(from url: URL) -> [InspectionReportRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reports = (try? decoder.decode([InspectionReportRecord].self, from: data)) ?? []
        return reports.sorted { $0.startedAt > $1.startedAt }
    }
}
