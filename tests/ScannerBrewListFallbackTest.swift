import Foundation

@main
struct ScannerBrewListFallbackTest {
    static func main() {
        let primary = CommandResult(
            ok: false,
            code: 1,
            stdout: "",
            stderr: "Error: Cask 'microsoft-powerpoint' is not installed.\n"
        )
        let fallback = CommandResult(
            ok: true,
            code: 0,
            stdout: "hiddenbar\nmicrosoft-powerpoint\n",
            stderr: ""
        )

        let result = SoftwareScanner.installedBrewPackages(primary: primary, fallback: fallback)
        let names = result.packages.map(\.name)
        let versions = result.packages.map(\.installedVersion)

        precondition(names == ["hiddenbar", "microsoft-powerpoint"], "Expected fallback cask names, got \(names)")
        precondition(versions == ["", ""], "Expected empty versions from name-only fallback, got \(versions)")
        precondition(result.error.isEmpty, "Fallback success should suppress primary error, got \(result.error)")
    }
}
