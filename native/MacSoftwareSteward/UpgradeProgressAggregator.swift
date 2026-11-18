import Foundation

/// 将彼此独立的 job 进度合成为全局展示进度。
/// 一个 job 完成后只移除自己的贡献，不会清空其他运行中 job。
enum UpgradeProgressAggregator {
    static func make(_ jobs: [UUID: UpgradeProgress]) -> UpgradeProgress? {
        guard !jobs.isEmpty else { return nil }
        let currentPackages = jobs.values.compactMap(\.currentPackage).sorted()
        let currentPackage: String?
        if let first = currentPackages.first {
            currentPackage = currentPackages.count > 1
                ? "\(first) 等 \(currentPackages.count) 项"
                : first
        } else {
            currentPackage = nil
        }
        return UpgradeProgress(
            completed: jobs.values.reduce(0) { $0 + $1.completed },
            total: jobs.values.reduce(0) { $0 + $1.total },
            failed: jobs.values.reduce(0) { $0 + $1.failed },
            currentPackage: currentPackage
        )
    }
}
