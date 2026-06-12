import Foundation

@main
struct ScannerNormalizeTokenTest {
    static func main() {
        precondition(SoftwareScanner.normalizeToken("Visual Studio Code.app") == "visual-studio-code")
        precondition(SoftwareScanner.normalizeToken("Microsoft_Outlook 16.109") == "microsoft-outlook-16-109")
        precondition(SoftwareScanner.normalizeToken("  IINA++  ") == "iina")

        let repeated = (0..<1_000).map { _ in SoftwareScanner.normalizeToken("Arc.app") }
        precondition(Set(repeated) == ["arc"], "Normalization should be deterministic without shared mutable cache")
    }
}
