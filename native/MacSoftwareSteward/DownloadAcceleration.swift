import Darwin
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

struct CommandAccelerationAttempt: Hashable {
    var strategies: [DownloadAccelerationStrategy]
    var attemptIndex: Int
    var maxAttempts: Int

    var currentStrategy: DownloadAccelerationStrategy {
        strategies[min(attemptIndex, max(strategies.count - 1, 0))]
    }

    var attemptText: String {
        "第 \(attemptIndex + 1)/\(min(maxAttempts, strategies.count)) 次"
    }

    func next() -> CommandAccelerationAttempt? {
        switch DownloadAccelerationPolicy.retryDecision(
            attemptIndex: attemptIndex,
            strategyCount: strategies.count,
            maxAttempts: maxAttempts
        ) {
        case .retry(let nextAttemptIndex):
            return CommandAccelerationAttempt(strategies: strategies, attemptIndex: nextAttemptIndex, maxAttempts: maxAttempts)
        case .stop:
            return nil
        }
    }
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

    static func shouldCleanPartialDownload(
        for decision: SlowDownloadDecision,
        cleanupCount: Int,
        maxCleanups: Int
    ) -> Bool {
        guard cleanupCount < maxCleanups else { return false }
        if case .stalled = decision {
            return true
        }
        return false
    }

    static func systemProxyURLString(from scutilOutput: String) -> String? {
        let lines = scutilOutput.components(separatedBy: .newlines)

        func value(for key: String) -> String? {
            for line in lines {
                let parts = line
                    .split(separator: ":", maxSplits: 1)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if parts.count == 2, parts[0] == key, !parts[1].isEmpty {
                    return parts[1]
                }
            }
            return nil
        }

        if value(for: "HTTPSEnable") == "1",
           let host = value(for: "HTTPSProxy"),
           let port = value(for: "HTTPSPort") {
            return "http://\(host):\(port)"
        }

        if value(for: "HTTPEnable") == "1",
           let host = value(for: "HTTPProxy"),
           let port = value(for: "HTTPPort") {
            return "http://\(host):\(port)"
        }

        return nil
    }

    static func localProxyProbeResults(
        ports: [Int] = [7890, 7897, 1080, 8080, 6152],
        timeout: TimeInterval = 0.2
    ) async -> [Int: Bool] {
        var results: [Int: Bool] = [:]
        for port in ports {
            results[port] = await canOpenLocalTCPConnection(port: port, timeout: timeout)
        }
        return results
    }

    static func defaultStrategies() async -> [DownloadAccelerationStrategy] {
        let systemProxy = await currentSystemProxyURLString()
        let localResults = await localProxyProbeResults()
        return rankedStrategies(
            environment: ProcessInfo.processInfo.environment,
            systemProxyURLString: systemProxy,
            localProxyProbeResults: localResults
        )
    }

    private static func inheritedProxyURLString(from environment: [String: String]) -> String? {
        for key in ["HTTPS_PROXY", "https_proxy", "ALL_PROXY", "all_proxy", "HTTP_PROXY", "http_proxy"] {
            if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func currentSystemProxyURLString() async -> String? {
        let result = await CommandRunner.run("/usr/sbin/scutil", arguments: ["--proxy"], timeout: 2)
        guard result.ok else { return nil }
        return systemProxyURLString(from: result.stdout)
    }

    private static func canOpenLocalTCPConnection(port: Int, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            let socketFD = socket(AF_INET, SOCK_STREAM, 0)
            guard socketFD >= 0 else {
                continuation.resume(returning: false)
                return
            }

            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = in_port_t(port).bigEndian
            inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)

            DispatchQueue.global().async {
                var addr = address
                let connected = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                    }
                }
                close(socketFD)
                continuation.resume(returning: connected)
            }
        }
    }
}
