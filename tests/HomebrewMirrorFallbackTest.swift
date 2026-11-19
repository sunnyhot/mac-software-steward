import Foundation

@main
struct HomebrewMirrorFallbackTest {
    static func main() {
        precondition(
            HomebrewMirrorFallback.environmentOverlay["HOMEBREW_BOTTLE_DOMAIN"]
                == "https://ghcr.io/v2/homebrew/core"
        )
        precondition(
            HomebrewMirrorFallback.environmentOverlay["HOMEBREW_API_DOMAIN"]
                == "https://formulae.brew.sh/api"
        )
        precondition(HomebrewMirrorFallback.environmentOverlay["HOMEBREW_DOWNLOAD_CONCURRENCY"] == "1")
        precondition(
            HomebrewMirrorFallback.shouldUseDirectEndpoints(
                failureOutput: "Error: No such file or directory @ rb_file_s_rename - (/tmp/node.json.incomplete, /tmp/node.json)"
            )
        )
        precondition(
            !HomebrewMirrorFallback.shouldUseDirectEndpoints(
                failureOutput: "Error: SHA256 mismatch"
            )
        )
    }
}
