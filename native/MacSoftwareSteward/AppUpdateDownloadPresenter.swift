import Foundation

struct AppUpdateDownloadPresentation: Hashable {
    var progressText: String
    var fraction: Double?
    var downloadedSizeText: String
    var totalDownloadSizeText: String?
    var downloadSpeedText: String?
}

enum AppUpdateDownloadPlanError: LocalizedError, Equatable {
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Release asset 下载地址无效。"
        }
    }
}

enum AppUpdateDownloadPresenter {
    static func request(
        assetName: String,
        downloadURLString: String,
        size: Int
    ) throws -> AcceleratedDownloadRequest {
        guard let url = URL(string: downloadURLString),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            throw AppUpdateDownloadPlanError.invalidURL
        }

        return AcceleratedDownloadRequest(
            url: url,
            destinationFileName: assetName,
            expectedByteCount: size > 0 ? Int64(size) : nil,
            operationName: "自更新下载"
        )
    }

    static func presentation(
        for progress: AcceleratedDownloadProgress,
        assetName: String
    ) -> AppUpdateDownloadPresentation {
        let expected = progress.expectedByteCount
        let fraction: Double?
        if let expected, expected > 0 {
            fraction = min(max(Double(progress.byteCount) / Double(expected), 0), 1)
        } else {
            fraction = nil
        }

        let speedText: String?
        if let speed = progress.speedBytesPerSecond, speed > 0 {
            speedText = ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s"
        } else {
            speedText = nil
        }

        return AppUpdateDownloadPresentation(
            progressText: "正在下载 \(assetName)...",
            fraction: fraction,
            downloadedSizeText: ByteCountFormatter.string(fromByteCount: progress.byteCount, countStyle: .file),
            totalDownloadSizeText: expected.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) },
            downloadSpeedText: speedText
        )
    }
}
