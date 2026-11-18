import Foundation

@main
struct UpgradeProgressAggregatorTest {
    static func main() {
        let firstID = UUID()
        let secondID = UUID()
        var jobs: [UUID: UpgradeProgress] = [
            firstID: UpgradeProgress(completed: 1, total: 2, failed: 0, currentPackage: "alpha"),
            secondID: UpgradeProgress(completed: 2, total: 4, failed: 1, currentPackage: "beta")
        ]
        let combined = UpgradeProgressAggregator.make(jobs)
        precondition(combined?.completed == 3)
        precondition(combined?.total == 6)
        precondition(combined?.failed == 1)
        precondition(combined?.currentPackage == "alpha 等 2 项")

        jobs[firstID] = UpgradeProgress(completed: 2, total: 2, failed: 0, currentPackage: nil)
        jobs.removeValue(forKey: firstID)
        let remaining = UpgradeProgressAggregator.make(jobs)
        precondition(remaining?.completed == 2)
        precondition(remaining?.total == 4)
        precondition(remaining?.failed == 1)
        precondition(remaining?.currentPackage == "beta")

        jobs.removeValue(forKey: secondID)
        precondition(UpgradeProgressAggregator.make(jobs) == nil)
    }
}
