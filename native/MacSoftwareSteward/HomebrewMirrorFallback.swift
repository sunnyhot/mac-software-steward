import Foundation

/// 仅在明确识别到镜像 manifest 重命名失败后，为单次重试提供官方端点。
/// 不写入用户环境，也不改变后续任务的镜像选择。
enum HomebrewMirrorFallback {
    static let environmentOverlay: [String: String] = [
        "HOMEBREW_BOTTLE_DOMAIN": "https://ghcr.io/v2/homebrew/core",
        "HOMEBREW_API_DOMAIN": "https://formulae.brew.sh/api",
        "HOMEBREW_DOWNLOAD_CONCURRENCY": "1",
    ]

    static func shouldUseDirectEndpoints(failureOutput: String) -> Bool {
        let output = failureOutput.lowercased()
        return output.contains("rb_file_s_rename") && output.contains(".incomplete")
    }
}
