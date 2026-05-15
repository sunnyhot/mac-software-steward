import Foundation

actor WhitelistManager {
    private var whitelistedPaths: Set<String> = []

    func addToWhitelist(_ path: String) {
        whitelistedPaths.insert(path)
    }

    func removeFromWhitelist(_ path: String) {
        whitelistedPaths.remove(path)
    }

    func isWhitelisted(_ path: String) -> Bool {
        whitelistedPaths.contains(path)
    }

    func allWhitelistedPaths() -> Set<String> {
        whitelistedPaths
    }
}
