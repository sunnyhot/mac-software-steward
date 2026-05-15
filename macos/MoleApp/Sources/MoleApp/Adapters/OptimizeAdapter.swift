import Foundation

struct OptimizeReport: Identifiable {
    let id = UUID()
    let results: [OptimizeEngine.OptimizeResult]
    let successCount: Int
    let failureCount: Int
    let totalSpaceSavedKB: Int
    let executionTime: TimeInterval

    var formattedSpaceSaved: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(totalSpaceSavedKB) * 1024)
    }
}

enum OptimizeAdapter {
    static func toReport(_ results: [OptimizeEngine.OptimizeResult]) -> OptimizeReport {
        let successCount = results.filter { $0.success }.count
        let failureCount = results.filter { !$0.success }.count
        let totalSpaceSavedKB = results.reduce(0) { $0 + $1.sizeSavedKB }
        let executionTime = results.reduce(0.0) { $0 + $1.executionTime }

        return OptimizeReport(
            results: results,
            successCount: successCount,
            failureCount: failureCount,
            totalSpaceSavedKB: totalSpaceSavedKB,
            executionTime: executionTime
        )
    }
}
