import Foundation

@main
struct HomebrewCaskDownloadSizeResolverTest {
    static func main() {
        let json = """
        {
          "casks": [
            {
              "token": "android-studio",
              "version": "2026.1.1.8,quail1",
              "url": "https://example.com/android-studio.dmg"
            }
          ]
        }
        """
        precondition(
            HomebrewCaskDownloadSizeResolver.caskURL(from: json, caskName: "android-studio") == "https://example.com/android-studio.dmg",
            "Expected cask URL to be parsed"
        )

        let okHeaders = """
        HTTP/2 200
        content-length: 1465394481
        x-identity-content-length: 1465394481
        """
        precondition(
            HomebrewCaskDownloadSizeResolver.expectedByteCount(fromHeaders: okHeaders) == 1_465_394_481,
            "Expected content-length to be parsed"
        )

        let partialHeaders = """
        HTTP/2 206
        content-length: 1
        content-range: bytes 0-0/1465394481
        """
        precondition(
            HomebrewCaskDownloadSizeResolver.expectedByteCount(fromHeaders: partialHeaders) == 1_465_394_481,
            "Expected content-range total to win over partial content-length"
        )
    }
}
