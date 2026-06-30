import Foundation

enum DownloadAccelerationStrategyKind: String, Hashable {
    case direct
    case inheritedProxy
    case systemProxy
    case localProxy
}

struct DownloadAccelerationStrategy: Hashable {
    var kind: DownloadAccelerationStrategyKind
    var proxyURLString: String?

    var title: String {
        switch kind {
        case .direct: return "直连"
        case .inheritedProxy: return "环境代理"
        case .systemProxy: return "系统代理"
        case .localProxy: return "本地代理"
        }
    }

    var environmentOverlay: [String: String] {
        guard let proxyURLString, kind != .direct else { return [:] }
        return [
            "HTTP_PROXY": proxyURLString,
            "HTTPS_PROXY": proxyURLString,
            "ALL_PROXY": proxyURLString,
            "http_proxy": proxyURLString,
            "https_proxy": proxyURLString,
            "all_proxy": proxyURLString
        ]
    }

    var connectionProxyDictionary: [AnyHashable: Any] {
        guard let proxyURLString,
              let url = URL(string: proxyURLString),
              let host = url.host else { return [:] }
        let port = url.port ?? (url.scheme?.lowercased().hasPrefix("https") == true ? 443 : 80)
        return [
            "HTTPEnable": true,
            "HTTPProxy": host,
            "HTTPPort": port,
            "HTTPSEnable": true,
            "HTTPSProxy": host,
            "HTTPSPort": port
        ]
    }
}

struct DownloadAccelerationConfig: Hashable {
    var minimumObservedDuration: TimeInterval
    var stalledAfter: TimeInterval
    var slowBytesPerSecond: Double
    var requiredConsecutiveSlowSamples: Int
    var longRemainingTime: TimeInterval
    var smallDownloadLimitBytes: Int64
    var maxAttempts: Int
    var maxCacheCleanups: Int

    static let production = DownloadAccelerationConfig(
        minimumObservedDuration: 45,
        stalledAfter: 30,
        slowBytesPerSecond: 256 * 1024,
        requiredConsecutiveSlowSamples: 2,
        longRemainingTime: 20 * 60,
        smallDownloadLimitBytes: 1_000_000_000,
        maxAttempts: 3,
        maxCacheCleanups: 2
    )
}

struct DownloadSpeedSample: Hashable {
    var startedAt: Date
    var sampledAt: Date
    var byteCount: Int64
    var expectedByteCount: Int64?
    var speedBytesPerSecond: Double?
    var secondsSinceLastGrowth: TimeInterval
    var consecutiveSlowSamples: Int

    var observedDuration: TimeInterval {
        max(sampledAt.timeIntervalSince(startedAt), 0)
    }

    var estimatedRemainingTime: TimeInterval? {
        guard let expectedByteCount,
              let speedBytesPerSecond,
              speedBytesPerSecond > 0,
              expectedByteCount > byteCount else { return nil }
        return Double(expectedByteCount - byteCount) / speedBytesPerSecond
    }
}

enum SlowDownloadDecision: Hashable {
    case healthy
    case slow(String)
    case stalled(String)

    var isRetryable: Bool {
        switch self {
        case .healthy: return false
        case .slow, .stalled: return true
        }
    }

    var message: String {
        switch self {
        case .healthy: return ""
        case .slow(let message), .stalled(let message): return message
        }
    }
}

enum DownloadRetryDecision: Hashable {
    case retry(nextAttemptIndex: Int)
    case stop
}

enum DownloadAccelerationPolicy {
    static func rankedStrategies(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        systemProxyURLString: String? = nil,
        localProxyProbeResults: [Int: Bool] = [:]
    ) -> [DownloadAccelerationStrategy] {
        var strategies: [DownloadAccelerationStrategy] = []

        if let inherited = inheritedProxyURLString(from: environment) {
            strategies.append(DownloadAccelerationStrategy(kind: .inheritedProxy, proxyURLString: inherited))
        }

        if let systemProxyURLString,
           !systemProxyURLString.isEmpty,
           !strategies.contains(where: { $0.proxyURLString == systemProxyURLString }) {
            strategies.append(DownloadAccelerationStrategy(kind: .systemProxy, proxyURLString: systemProxyURLString))
        }

        for port in localProxyProbeResults.keys.sorted() where localProxyProbeResults[port] == true {
            let proxy = "http://127.0.0.1:\(port)"
            if !strategies.contains(where: { $0.proxyURLString == proxy }) {
                strategies.append(DownloadAccelerationStrategy(kind: .localProxy, proxyURLString: proxy))
            }
        }

        strategies.append(DownloadAccelerationStrategy(kind: .direct, proxyURLString: nil))
        return strategies
    }

    static func decision(for sample: DownloadSpeedSample, config: DownloadAccelerationConfig = .production) -> SlowDownloadDecision {
        if sample.secondsSinceLastGrowth >= config.stalledAfter {
            return .stalled("下载长时间没有增长")
        }

        guard sample.observedDuration >= config.minimumObservedDuration else {
            return .healthy
        }

        if let speed = sample.speedBytesPerSecond,
           speed < config.slowBytesPerSecond,
           sample.consecutiveSlowSamples >= config.requiredConsecutiveSlowSamples {
            return .slow("下载速度持续偏低")
        }

        if let expected = sample.expectedByteCount,
           expected <= config.smallDownloadLimitBytes,
           let remaining = sample.estimatedRemainingTime,
           remaining >= config.longRemainingTime {
            return .slow("预计剩余时间过长")
        }

        return .healthy
    }

    static func retryDecision(attemptIndex: Int, strategyCount: Int, maxAttempts: Int) -> DownloadRetryDecision {
        let next = attemptIndex + 1
        guard next < strategyCount, next < maxAttempts else { return .stop }
        return .retry(nextAttemptIndex: next)
    }

    private static func inheritedProxyURLString(from environment: [String: String]) -> String? {
        for key in ["HTTPS_PROXY", "https_proxy", "ALL_PROXY", "all_proxy", "HTTP_PROXY", "http_proxy"] {
            if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
