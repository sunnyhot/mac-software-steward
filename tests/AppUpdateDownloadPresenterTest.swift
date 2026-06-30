import Foundation

@main
struct AppUpdateDownloadPresenterTest {
    static func main() throws {
        let request = try AppUpdateDownloadPresenter.request(
            assetName: "MacSoftwareSteward.zip",
            downloadURLString: "https://example.com/MacSoftwareSteward.zip",
            size: 200
        )

        precondition(request.url.absoluteString == "https://example.com/MacSoftwareSteward.zip")
        precondition(request.destinationFileName == "MacSoftwareSteward.zip")
        precondition(request.expectedByteCount == 200)
        precondition(request.operationName == "自更新下载")

        let presentation = AppUpdateDownloadPresenter.presentation(
            for: AcceleratedDownloadProgress(
                byteCount: 50,
                expectedByteCount: 200,
                speedBytesPerSecond: 25,
                statusText: "正在下载"
            ),
            assetName: "MacSoftwareSteward.zip"
        )

        precondition(abs((presentation.fraction ?? 0) - 0.25) < 0.001)
        precondition(presentation.progressText == "正在下载 MacSoftwareSteward.zip...")
        precondition(!presentation.downloadedSizeText.isEmpty)
        precondition(presentation.totalDownloadSizeText?.isEmpty == false)
        precondition(presentation.downloadSpeedText?.hasSuffix("/s") == true)

        do {
            _ = try AppUpdateDownloadPresenter.request(
                assetName: "bad.zip",
                downloadURLString: "file:///tmp/bad.zip",
                size: 0
            )
            preconditionFailure("Expected non-network URL to be rejected")
        } catch AppUpdateDownloadPlanError.invalidURL {
        }
    }
}
