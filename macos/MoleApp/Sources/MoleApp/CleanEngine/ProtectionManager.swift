import Foundation

actor ProtectionManager {
    private var protectedPaths: Set<String> = []

    private static let defaultProtectedPaths: Set<String> = [
        ".ssh", ".gnupg", ".gpg", ".password-store",
        "keychain", "Keychains"
    ]

    func isProtected(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        if Self.defaultProtectedPaths.contains(name) { return true }
        return protectedPaths.contains(path)
    }

    func addProtection(_ path: String) {
        protectedPaths.insert(path)
    }

    func removeProtection(_ path: String) {
        protectedPaths.remove(path)
    }
}
