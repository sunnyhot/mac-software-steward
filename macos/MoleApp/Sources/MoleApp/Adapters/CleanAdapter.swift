import Foundation

struct CleanScanResult: Identifiable {
    let id = UUID()
    let items: [CleanItem]
    let totalSize: Int64
    let category: String

    var formattedTotalSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }
}

struct CleanReport: Identifiable {
    let id = UUID()
    let results: [CleanResult]
    let totalCleaned: Int64
    let successCount: Int
    let failureCount: Int

    var formattedTotalCleaned: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalCleaned)
    }
}

enum CleanAdapter {
    static func toScanResults(_ items: [CleanItem]) -> [CleanScanResult] {
        let grouped = Dictionary(grouping: items, by: { $0.category })

        return grouped.map { category, categoryItems in
            let totalSize = categoryItems.reduce(Int64(0)) { $0 + $1.size }
            return CleanScanResult(
                items: categoryItems,
                totalSize: totalSize,
                category: category.rawValue
            )
        }.sorted { $0.totalSize > $1.totalSize }
    }

    static func toReport(_ results: [CleanResult]) -> CleanReport {
        let totalCleaned = results.filter { $0.success }.reduce(Int64(0)) { $0 + $1.bytesFreed }
        let successCount = results.filter { $0.success }.count
        let failureCount = results.filter { !$0.success }.count

        return CleanReport(
            results: results,
            totalCleaned: totalCleaned,
            successCount: successCount,
            failureCount: failureCount
        )
    }
}
