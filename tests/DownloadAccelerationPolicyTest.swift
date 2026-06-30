import Foundation

@main
struct DownloadAccelerationPolicyTest {
    static func main() {
        let environment = [
            "HTTPS_PROXY": "http://127.0.0.1:7890",
            "ALL_PROXY": "socks5://127.0.0.1:7891"
        ]
        let strategies = DownloadAccelerationPolicy.rankedStrategies(
            environment: environment,
            systemProxyURLString: "http://127.0.0.1:8080",
            localProxyProbeResults: [7890: true, 7897: false, 1080: true]
        )

        precondition(strategies.first?.kind == .inheritedProxy, "Inherited proxy should rank first when present")
        precondition(strategies.contains { $0.kind == .systemProxy && $0.proxyURLString == "http://127.0.0.1:8080" })
        precondition(strategies.contains { $0.kind == .localProxy && $0.proxyURLString == "http://127.0.0.1:1080" })
        precondition(strategies.last?.kind == .direct, "Direct fallback should be kept last")

        let overlay = strategies[0].environmentOverlay
        precondition(overlay["HTTPS_PROXY"] == "http://127.0.0.1:7890")
        precondition(overlay["https_proxy"] == "http://127.0.0.1:7890")

        let config = DownloadAccelerationConfig(
            minimumObservedDuration: 10,
            stalledAfter: 8,
            slowBytesPerSecond: 256 * 1024,
            requiredConsecutiveSlowSamples: 2,
            longRemainingTime: 20 * 60,
            smallDownloadLimitBytes: 1_000_000_000,
            maxAttempts: 3,
            maxCacheCleanups: 2
        )

        let healthy = DownloadSpeedSample(
            startedAt: Date(timeIntervalSince1970: 0),
            sampledAt: Date(timeIntervalSince1970: 12),
            byteCount: 20_000_000,
            expectedByteCount: 40_000_000,
            speedBytesPerSecond: 2_000_000,
            secondsSinceLastGrowth: 1,
            consecutiveSlowSamples: 0
        )
        precondition(DownloadAccelerationPolicy.decision(for: healthy, config: config) == .healthy)

        let slow = DownloadSpeedSample(
            startedAt: Date(timeIntervalSince1970: 0),
            sampledAt: Date(timeIntervalSince1970: 45),
            byteCount: 2_000_000,
            expectedByteCount: 100_000_000,
            speedBytesPerSecond: 100_000,
            secondsSinceLastGrowth: 2,
            consecutiveSlowSamples: 2
        )
        precondition(DownloadAccelerationPolicy.decision(for: slow, config: config).isRetryable)

        let stalled = DownloadSpeedSample(
            startedAt: Date(timeIntervalSince1970: 0),
            sampledAt: Date(timeIntervalSince1970: 20),
            byteCount: 10_000_000,
            expectedByteCount: 100_000_000,
            speedBytesPerSecond: 0,
            secondsSinceLastGrowth: 10,
            consecutiveSlowSamples: 0
        )
        precondition(DownloadAccelerationPolicy.decision(for: stalled, config: config) == .stalled("下载长时间没有增长"))

        precondition(DownloadAccelerationPolicy.retryDecision(attemptIndex: 0, strategyCount: 3, maxAttempts: 3) == .retry(nextAttemptIndex: 1))
        precondition(DownloadAccelerationPolicy.retryDecision(attemptIndex: 2, strategyCount: 3, maxAttempts: 3) == .stop)
    }
}
