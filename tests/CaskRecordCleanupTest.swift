import Foundation

@main
struct CaskRecordCleanupTest {
    static func main() throws {
        let command = try CaskRecordCleanup.command(
            caskName: "bartender",
            caskroomPath: "/opt/homebrew/Caskroom"
        )
        precondition(command.executable == "/bin/rm")
        precondition(command.arguments == ["-rf", "--", "/opt/homebrew/Caskroom/bartender"])
        precondition(!command.display.contains("--zap"))
        precondition(!command.display.contains("uninstall"))

        let guarded = try CaskRecordCleanup.command(
            caskName: "bartender",
            caskroomPath: "/opt/homebrew/Caskroom",
            expectedAppPaths: ["/Applications/Bartender 7.app"]
        )
        precondition(guarded.executable == "/bin/sh")
        precondition(guarded.arguments[1].contains("[ -e '/Applications/Bartender 7.app' ]"))
        precondition(guarded.arguments[1].contains("exit 75"))
        precondition(guarded.arguments[1].contains("/bin/rm -rf --"))
        precondition(CaskRecordCleanup.appReappearedExitCode == 75)

        let channelCommand = try CaskRecordCleanup.command(
            caskName: "mos@beta",
            caskroomPath: "/opt/homebrew/Caskroom/"
        )
        precondition(channelCommand.arguments.last == "/opt/homebrew/Caskroom/mos@beta")

        for invalid in ["", ".", "..", "foo/bar", "foo\\bar", "../bartender"] {
            do {
                _ = try CaskRecordCleanup.command(caskName: invalid, caskroomPath: "/opt/homebrew/Caskroom")
                preconditionFailure("unsafe cask name accepted: \(invalid)")
            } catch {
                // expected
            }
        }

        for invalidRoot in ["/", "relative/Caskroom"] {
            do {
                _ = try CaskRecordCleanup.command(caskName: "bartender", caskroomPath: invalidRoot)
                preconditionFailure("unsafe caskroom accepted: \(invalidRoot)")
            } catch {
                // expected
            }
        }
    }
}
