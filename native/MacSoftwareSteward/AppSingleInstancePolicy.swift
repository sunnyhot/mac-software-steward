import Foundation

enum AppSingleInstancePolicy {
    static func shouldTerminateCurrent(
        currentProcessIdentifier: Int32,
        runningProcessIdentifiers: [Int32]
    ) -> Bool {
        let uniquePIDs = Set(runningProcessIdentifiers)
        guard uniquePIDs.count > 1, let oldestPID = uniquePIDs.min() else { return false }
        return currentProcessIdentifier != oldestPID
    }
}
