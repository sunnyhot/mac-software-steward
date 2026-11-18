import Foundation

@main
struct FormulaRepairCommandBuilderTest {
    static func main() throws {
        let command = FormulaRepairCommandBuilder.command(
            brewPath: "/opt/homebrew/bin/brew",
            formulaName: "merve"
        )
        precondition(command.executable == "/bin/sh")
        precondition(command.arguments.count == 2)
        let script = command.arguments[1]
        precondition(script.contains("uninstall --force 'merve'"))
        precondition(script.contains("install 'merve'"))
        precondition(script.contains("if "))
        precondition(script.contains("list --formula 'merve'"))
        precondition(script.contains("/usr/bin/grep -Fqi 'has multiple installed versions'"))
        precondition(script.contains("|| exit $?"))
        let uninstallIndex = script.range(of: "uninstall --force")!.lowerBound
        let installIndex = script.range(of: "install 'merve'")!.lowerBound
        precondition(uninstallIndex < installIndex)
        precondition(command.display.contains("brew uninstall --force merve && brew install merve"))

        let quoted = FormulaRepairCommandBuilder.command(
            brewPath: "/opt/homebrew/bin/brew",
            formulaName: "formula with space"
        )
        precondition(quoted.arguments[1].contains("'formula with space'"))
        try verifyNonzeroListTriggersUninstall()
    }

    private static func verifyNonzeroListTriggersUninstall() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("formula-repair-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let brewURL = root.appendingPathComponent("brew")
        let logURL = root.appendingPathComponent("actions.log")
        let fakeBrew = """
        #!/bin/sh
        if [ "$1" = "list" ]; then
          echo "Error: merve has multiple installed versions" >&2
          exit 1
        fi
        if [ "$1" = "uninstall" ]; then
          printf 'uninstall\n' >> \(SudoScriptBuilder.shellQuote(logURL.path))
          exit 0
        fi
        if [ "$1" = "install" ]; then
          printf 'install\n' >> \(SudoScriptBuilder.shellQuote(logURL.path))
          exit 0
        fi
        exit 99
        """
        try fakeBrew.write(to: brewURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brewURL.path)

        let command = FormulaRepairCommandBuilder.command(
            brewPath: brewURL.path,
            formulaName: "merve"
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        try process.run()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0)
        let actions = try String(contentsOf: logURL, encoding: .utf8)
        precondition(actions.contains("uninstall"), "A nonzero multi-version brew list must still uninstall")
        precondition(actions.contains("install"))
    }
}
