import Foundation

@main
struct AcceleratedDownloaderTest {
    static func main() async throws {
        let strategies = [
            DownloadAccelerationStrategy(kind: .inheritedProxy, proxyURLString: "http://127.0.0.1:7890"),
            DownloadAccelerationStrategy(kind: .direct, proxyURLString: nil)
        ]
        let request = AcceleratedDownloadRequest(
            url: URL(string: "https://example.com/app.zip")!,
            destinationFileName: "app.zip",
            expectedByteCount: 10,
            operationName: "测试下载"
        )
        var attempts: [String] = []
        var statuses: [String] = []
        let finalURL = try await AcceleratedDownloader.download(
            request,
            strategies: strategies,
            config: DownloadAccelerationConfig(
                minimumObservedDuration: 1,
                stalledAfter: 1,
                slowBytesPerSecond: 1,
                requiredConsecutiveSlowSamples: 1,
                longRemainingTime: 1,
                smallDownloadLimitBytes: 100,
                maxAttempts: 2,
                maxCacheCleanups: 0
            ),
            runner: { attempt, progress in
                attempts.append(attempt.strategy.title)
                progress(AcceleratedDownloadProgress(
                    byteCount: 1,
                    expectedByteCount: 10,
                    speedBytesPerSecond: 1,
                    statusText: "采样"
                ))
                if attempt.index == 0 {
                    throw AcceleratedDownloadError.retryable("模拟慢下载")
                }
                return URL(fileURLWithPath: "/tmp/app.zip")
            },
            onProgress: { progress in
                precondition(progress.byteCount == 1)
            },
            onStatus: { status in
                statuses.append(status)
            }
        )

        precondition(finalURL.path == "/tmp/app.zip")
        precondition(attempts == ["环境代理", "直连"], "Unexpected attempts: \(attempts)")
        precondition(statuses.contains { $0.contains("模拟慢下载") })

        attempts.removeAll()
        statuses.removeAll()
        let timeoutRecoveredURL = try await AcceleratedDownloader.download(
            request,
            strategies: strategies,
            config: DownloadAccelerationConfig(
                minimumObservedDuration: 1,
                stalledAfter: 1,
                slowBytesPerSecond: 1,
                requiredConsecutiveSlowSamples: 1,
                longRemainingTime: 1,
                smallDownloadLimitBytes: 100,
                maxAttempts: 2,
                maxCacheCleanups: 0
            ),
            runner: { attempt, _ in
                attempts.append(attempt.strategy.title)
                if attempt.index == 0 {
                    throw URLError(.timedOut)
                }
                return URL(fileURLWithPath: "/tmp/app-timeout-recovered.zip")
            },
            onStatus: { status in
                statuses.append(status)
            }
        )

        precondition(timeoutRecoveredURL.path == "/tmp/app-timeout-recovered.zip")
        precondition(attempts == ["环境代理", "直连"], "Unexpected timeout attempts: \(attempts)")
        precondition(statuses.contains { $0.contains("网络连接超时") })
        precondition(AcceleratedDownloadError.retryableMessage(from: URLError(.badURL)) == nil)
    }
}
