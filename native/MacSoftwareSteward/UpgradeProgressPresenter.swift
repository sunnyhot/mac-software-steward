import Foundation

enum UpgradeProgressPresenter {
    static func summaryText(
        progress: UpgradeProgress,
        packageProgress: [PackageUpgradeProgress],
        now: Date = Date()
    ) -> String {
        let runningCount = packageProgress.filter { $0.status == .running }.count
        let queuedCount = packageProgress.filter { $0.status == .queued }.count
        let attentionCount = packageProgress.filter { progress in
            switch progress.status {
            case .failed, .timedOut, .cancelled, .warning:
                return true
            case .queued, .running, .succeeded:
                return false
            }
        }.count

        var parts: [String] = []
        if runningCount > 0 { parts.append("\(runningCount) 个执行中") }
        if queuedCount > 0 { parts.append("\(queuedCount) 个排队") }
        if attentionCount > 0 { parts.append("\(attentionCount) 个需处理") }

        if parts.isEmpty {
            let remaining = max(progress.total - progress.completed, 0)
            if remaining > 0 {
                parts.append("\(remaining) 个待处理")
            } else {
                parts.append("全部步骤已处理")
            }
        }

        if let staleRunningCount = staleRunningCount(in: packageProgress, now: now), staleRunningCount > 0 {
            parts.append("\(staleRunningCount) 个长时间无输出")
        }

        return parts.joined(separator: " · ")
    }

    static func phaseDurationText(for progress: PackageUpgradeProgress, now: Date = Date()) -> String {
        let phase = progress.phaseText.isEmpty ? progress.status.rawValue : progress.phaseText
        return "\(phase)持续 \(durationText(from: progress.updatedAt, to: now))"
    }

    static func lastUpdateText(for progress: PackageUpgradeProgress, now: Date = Date()) -> String {
        "最近输出 \(durationText(from: progress.updatedAt, to: now))前"
    }

    static func staleHint(for progress: PackageUpgradeProgress, now: Date = Date()) -> String? {
        guard progress.status == .running else { return nil }
        let elapsed = now.timeIntervalSince(progress.updatedAt)
        guard elapsed >= 120 else { return nil }
        return "超过 \(durationText(from: progress.updatedAt, to: now))没有新输出，可能在等待下载、安装或系统授权。"
    }

    private static func staleRunningCount(in progress: [PackageUpgradeProgress], now: Date) -> Int? {
        let count = progress.filter { item in
            item.status == .running && now.timeIntervalSince(item.updatedAt) >= 120
        }.count
        return count == 0 ? nil : count
    }

    private static func durationText(from start: Date, to end: Date) -> String {
        let seconds = max(Int(end.timeIntervalSince(start)), 0)
        if seconds < 60 {
            return "不到 1 分钟"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) 分钟"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours) 小时"
        }
        return "\(hours) 小时 \(remainingMinutes) 分钟"
    }
}
