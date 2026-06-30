import Foundation

@main
struct AppUpdateModelAccelerationTest {
    @MainActor
    static func main() async throws {
        let strategies = [
            DownloadAccelerationStrategy(kind: .inheritedProxy, proxyURLString: "http://127.0.0.1:7890"),
            DownloadAccelerationStrategy(kind: .direct, proxyURLString: nil)
        ]
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("self-update-download-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: output) }

        var attemptTitles: [String] = []
        let model = AppUpdateModel(
            session: .shared,
            downloadStrategiesProvider: { strategies },
            acceleratedDownloadRunner: { attempt, progress in
                attemptTitles.append(attempt.strategy.title)
                progress(AcceleratedDownloadProgress(
                    byteCount: 100,
                    expectedByteCount: 200,
                    speedBytesPerSecond: 50,
                    statusText: "正在下载"
                ))
                if attempt.index == 0 {
                    throw AcceleratedDownloadError.retryable("模拟慢下载")
                }
                try Data("downloaded".utf8).write(to: output)
                return output
            }
        )

        let downloaded = try await model.downloadReleaseAssetForSelfUpdate(
            assetName: "MacSoftwareSteward.zip",
            downloadURLString: "https://example.com/MacSoftwareSteward.zip",
            size: 200
        )

        try await Task.sleep(nanoseconds: 50_000_000)

        precondition(attemptTitles == ["环境代理", "直连"], "Unexpected attempts: \(attemptTitles)")
        precondition(FileManager.default.fileExists(atPath: downloaded.path))
        let downloadedText = try String(contentsOf: downloaded, encoding: .utf8)
        precondition(downloadedText == "downloaded")
        precondition(abs((model.downloadFraction ?? 0) - 0.5) < 0.001)
        precondition(model.downloadedSizeText?.isEmpty == false)
        precondition(model.totalDownloadSizeText?.isEmpty == false)
        precondition(model.downloadSpeedText?.hasSuffix("/s") == true)
        precondition(model.progress.contains("MacSoftwareSteward.zip"))
    }
}
