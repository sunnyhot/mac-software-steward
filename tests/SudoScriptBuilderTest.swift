import Foundation

@main
struct SudoScriptBuilderTest {
    static func main() {
        let brew = "/opt/homebrew/bin/brew"
        let cleanup = UpgradeCommand(
            executable: brew,
            arguments: ["uninstall", "--cask", "--force", "bartender"],
            display: "brew uninstall --cask --force bartender"
        )
        let cleanupScript = SudoScriptBuilder.script(
            commands: [cleanup],
            pathEnv: "/opt/homebrew/bin:/usr/bin",
            homeEnv: "/Users/test"
        )

        precondition(cleanupScript.contains("'/opt/homebrew/bin/brew' 'uninstall' '--cask' '--force' 'bartender'"))
        precondition(!cleanupScript.contains("'upgrade' '--cask' 'bartender'"))
        precondition(cleanupScript.contains("export PATH='/opt/homebrew/bin:/usr/bin'"))
        precondition(cleanupScript.contains("export HOME='/Users/test'"))
        precondition(cleanupScript.contains("__RC_1_$?__"))
        precondition(cleanupScript.contains("with administrator privileges"))
        assertCompiles(cleanupScript)

        let upgrade = UpgradeCommand(
            executable: brew,
            arguments: ["upgrade", "--cask", "--greedy", "warp"],
            display: "brew upgrade --cask --greedy warp"
        )
        let install = UpgradeCommand(
            executable: brew,
            arguments: ["install", "--cask", "token-with space"],
            display: "brew install --cask token-with space"
        )
        let mixedScript = SudoScriptBuilder.script(
            commands: [upgrade, install],
            pathEnv: "/usr/bin",
            homeEnv: "/Users/test"
        )
        precondition(mixedScript.contains("'upgrade' '--cask' '--greedy' 'warp'"))
        precondition(mixedScript.contains("'install' '--cask' 'token-with space'"))
        precondition(mixedScript.contains("__RC_1_$?__"))
        precondition(mixedScript.contains("__RC_2_$?__"))
        assertCompiles(mixedScript)

        let quotedHome = "/Users/O'Brien"
        let quotedScript = SudoScriptBuilder.script(
            commands: [cleanup],
            pathEnv: "/usr/bin",
            homeEnv: quotedHome
        )
        precondition(quotedScript.contains("O"))
        precondition(quotedScript.contains("Brien"))
        assertCompiles(quotedScript)

        precondition(SudoScriptBuilder.shellQuote("a'b") == "'a'\\''b'")
        precondition(SudoScriptBuilder.shellQuote("") == "''")
        for value in ["O'Brien", "token with spaces", "$HOME", ""] {
            assertShellRoundTrip(value)
        }
        precondition(SudoScriptBuilder.osaArguments(cleanupScript) == ["-e", cleanupScript])

        let emptyScript = SudoScriptBuilder.script(commands: [], pathEnv: "/usr/bin", homeEnv: "/Users/test")
        precondition(!emptyScript.contains("__RC_"))
        assertCompiles(emptyScript)
    }

    /// 只用 /bin/sh + printf 验证参数逐字往返，不执行 brew 或管理员命令。
    private static func assertShellRoundTrip(_ value: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf '%s' \(SudoScriptBuilder.shellQuote(value))"]
        let output = Pipe()
        process.standardOutput = output
        do {
            try process.run()
        } catch {
            preconditionFailure("Failed to launch /bin/sh: \(error)")
        }
        process.waitUntilExit()
        precondition(process.terminationStatus == 0)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let decoded = String(data: data, encoding: .utf8)
        precondition(decoded == value, "Shell round trip failed for \(value): \(decoded ?? "nil")")
    }

    /// 仅编译，不运行 AppleScript，因此不会请求密码或执行任何 brew 命令。
    private static func assertCompiles(_ source: String, file: StaticString = #file, line: UInt = #line) {
        var error: NSDictionary?
        let compiled = NSAppleScript(source: source)?.compileAndReturnError(&error) ?? false
        precondition(compiled, "AppleScript must compile: \(error ?? [:])", file: file, line: line)
    }
}
