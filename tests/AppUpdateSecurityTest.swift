import Foundation

@main
struct AppUpdateSecurityTest {
    static func main() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("app-update-security-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try Data("hello".utf8).write(to: fileURL)

        let expected = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        let actual = try AppUpdateSecurity.sha256Hex(of: fileURL)
        precondition(actual == expected, "Expected SHA-256 \(expected), got \(actual)")

        try AppUpdateSecurity.verifySHA256(fileURL: fileURL, expectedSHA256: "  \(expected.uppercased())  ")

        do {
            try AppUpdateSecurity.verifySHA256(fileURL: fileURL, expectedSHA256: String(repeating: "0", count: 64))
            preconditionFailure("Expected mismatched SHA-256 to throw")
        } catch AppUpdateSecurityError.sha256Mismatch(let expected, let actual) {
            precondition(expected == String(repeating: "0", count: 64))
            precondition(actual == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        }
    }
}
