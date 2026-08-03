import Foundation

@main
struct CaskMirrorPrefetcherTest {
    static func main() {
        // mirrorURL：仅 github.com 的 releases/download 走镜像。
        let githubRelease = URL(string: "https://github.com/aonez/Keka/releases/download/v1.6.7/Keka-1.6.7.dmg")!
        let mirrored = CaskMirrorPrefetcher.mirrorURL(for: githubRelease)
        precondition(mirrored?.absoluteString == "https://mirror.ghproxy.com/https://github.com/aonez/Keka/releases/download/v1.6.7/Keka-1.6.7.dmg")

        // 非 GitHub URL 不走镜像。
        let vendorURL = URL(string: "https://downloads.1password.com/mac/1Password-8.12.30-aarch64.zip")!
        precondition(CaskMirrorPrefetcher.mirrorURL(for: vendorURL) == nil, "非 GitHub URL 不应走镜像")

        // GitHub 但非 releases/download 也不走镜像。
        let githubNonRelease = URL(string: "https://github.com/owner/repo/blob/main/file.zip")!
        precondition(CaskMirrorPrefetcher.mirrorURL(for: githubNonRelease) == nil, "非 releases/download 的 GitHub URL 不应走镜像")

        // cacheFileName：SHA256(url) + -- + basename
        let url = URL(string: "https://github.com/aonez/Keka/releases/download/v1.6.7/Keka-1.6.7.dmg")!
        let cacheName = CaskMirrorPrefetcher.cacheFileName(for: url)
        precondition(cacheName != nil)
        precondition(cacheName!.hasSuffix("--Keka-1.6.7.dmg"), "缓存文件名应以 basename 结尾")
        // SHA256(url) 应是 64 位 hex 前缀。
        let prefix = cacheName!.split(separator: "-").first.map(String.init)
        precondition(prefix?.count == 64, "SHA256 前缀应为 64 位 hex，实际：\(prefix?.count ?? 0)")

        // resolveDownloadInfo：从 brew info JSON 提取 url + sha256。
        let infoJSON = """
        {"casks":[{"token":"keka","url":"https://github.com/aonez/Keka/releases/download/v1.6.7/Keka-1.6.7.dmg","sha256":"abc123"}]}
        """
        let info = CaskMirrorPrefetcher.resolveDownloadInfo(from: infoJSON, caskName: "keka")
        precondition(info?.url.absoluteString == "https://github.com/aonez/Keka/releases/download/v1.6.7/Keka-1.6.7.dmg")
        precondition(info?.sha256 == "abc123")

        // resolveDownloadInfo：token 不匹配时回退到第一个 cask。
        let multiJSON = """
        {"casks":[{"token":"other","url":"https://example.com/a.zip","sha256":"def"}]}
        """
        let fallback = CaskMirrorPrefetcher.resolveDownloadInfo(from: multiJSON, caskName: "keka")
        precondition(fallback?.url.absoluteString == "https://example.com/a.zip")

        // resolveDownloadInfo：无效 JSON 返回 nil。
        precondition(CaskMirrorPrefetcher.resolveDownloadInfo(from: "not json", caskName: "keka") == nil)

        // sha256Hex：对已知内容验证。
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("prefetch-test-\(UUID().uuidString).txt")
        try? "hello".write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }
        // SHA256("hello") = 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
        precondition(CaskMirrorPrefetcher.sha256Hex(of: tmpFile) == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }
}
