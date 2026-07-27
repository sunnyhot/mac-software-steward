import Foundation

enum UpgradeProgressPresenter {
    static func phaseDurationText(for progress: PackageUpgradeProgress, now: Date = Date()) -> String {
        let phase = progress.phaseText.isEmpty ? progress.status.rawValue : progress.phaseText
        return "\(phase)持续 \(durationText(from: progress.updatedAt, to: now))"
    }

    static func lastUpdateText(for progress: PackageUpgradeProgress, now: Date = Date()) -> String {
        "最近输出 \(durationText(from: progress.updatedAt, to: now))前"
    }

    static func accelerationHint(for progress: PackageUpgradeProgress) -> String? {
        guard let status = progress.accelerationStatusText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !status.isEmpty else { return nil }
        let strategy = progress.accelerationStrategyText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let attempt = progress.accelerationAttemptText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !strategy.isEmpty, !attempt.isEmpty {
            return "\(status)：\(strategy)（\(attempt)）"
        }
        if !strategy.isEmpty {
            return "\(status)：\(strategy)"
        }
        if !attempt.isEmpty {
            return "\(status)（\(attempt)）"
        }
        return status
    }

    static func staleHint(for progress: PackageUpgradeProgress, now: Date = Date()) -> String? {
        guard progress.status == .running else { return nil }
        if accelerationHint(for: progress) != nil {
            return nil
        }
        let elapsed = now.timeIntervalSince(progress.updatedAt)
        guard elapsed >= 120 else { return nil }
        return "超过 \(durationText(from: progress.updatedAt, to: now))没有新输出，可能在等待下载、安装或系统授权。"
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
