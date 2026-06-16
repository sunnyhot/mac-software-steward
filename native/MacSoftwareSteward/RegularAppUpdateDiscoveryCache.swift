import Combine
import Foundation

struct RegularAppUpdateDiscoveryCacheMetadata: Codable, Hashable {
    var modifiedAt: TimeInterval
    var size: UInt64
}

struct RegularAppUpdateDiscoveryCacheRecord: Codable, Identifiable, Hashable {
    var id: String { appPath }
    var appPath: String
    var metadata: RegularAppUpdateDiscoveryCacheMetadata
    var capability: AppUpdateCapability
    var lastSeenAt: Date
}

final class RegularAppUpdateDiscoveryCache: ObservableObject {
    static let cacheVersion = 1
    static let defaultFileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacSoftwareSteward", isDirectory: true)
            .appendingPathComponent("regular-app-discovery-cache.json")
    }()

    @Published private(set) var records: [RegularAppUpdateDiscoveryCacheRecord]

    private let fileURL: URL
    private let limit: Int

    init(fileURL: URL = RegularAppUpdateDiscoveryCache.defaultFileURL, limit: Int = 1000) {
        self.fileURL = fileURL
        self.limit = limit
        records = Self.load(from: fileURL)
        trimToLimit()
    }

    func capability(
        for appPath: String,
        loader: (String) -> AppUpdateCapability = RegularAppUpdateDiscovery.discover
    ) -> AppUpdateCapability {
        guard let metadata = Self.metadata(for: appPath) else {
            remove(appPath)
            save()
            return .none
        }

        if let index = records.firstIndex(where: { $0.appPath == appPath }),
           records[index].metadata == metadata {
            records[index].lastSeenAt = Date()
            trimToLimit()
            save()
            return records[index].capability
        }

        let capability = loader(appPath)
        let record = RegularAppUpdateDiscoveryCacheRecord(
            appPath: appPath,
            metadata: metadata,
            capability: capability,
            lastSeenAt: Date()
        )
        upsert(record)
        save()
        return capability
    }

    func reload() {
        records = Self.load(from: fileURL)
        trimToLimit()
    }

    func clear() {
        records.removeAll()
        save()
    }

    private func upsert(_ record: RegularAppUpdateDiscoveryCacheRecord) {
        remove(record.appPath)
        records.insert(record, at: 0)
        trimToLimit()
    }

    private func remove(_ appPath: String) {
        records.removeAll { $0.appPath == appPath }
    }

    private func sortNewestFirst() {
        records.sort { lhs, rhs in
            lhs.lastSeenAt > rhs.lastSeenAt
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
            let data = try encoder.encode(CacheFile(version: Self.cacheVersion, records: records))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Failed to save regular app discovery cache: \(error.localizedDescription)")
        }
    }

    private static func load(from url: URL) -> [RegularAppUpdateDiscoveryCacheRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(CacheFile.self, from: data),
              file.version == cacheVersion else {
            NSLog("Failed to load regular app discovery cache.")
            return []
        }
        return file.records.sorted { lhs, rhs in
            lhs.lastSeenAt > rhs.lastSeenAt
        }
    }

    private static func metadata(for appPath: String) -> RegularAppUpdateDiscoveryCacheMetadata? {
        let plistURL = URL(fileURLWithPath: appPath)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: plistURL.path),
              let modifiedAt = attributes[.modificationDate] as? Date,
              let size = (attributes[.size] as? NSNumber)?.uint64Value else {
            return nil
        }
        return RegularAppUpdateDiscoveryCacheMetadata(
            modifiedAt: modifiedAt.timeIntervalSince1970,
            size: size
        )
    }

    private struct CacheFile: Codable {
        var version: Int
        var records: [RegularAppUpdateDiscoveryCacheRecord]
    }
}
