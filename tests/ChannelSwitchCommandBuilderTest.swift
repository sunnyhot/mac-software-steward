import Foundation

@main
struct ChannelSwitchCommandBuilderTest {
    static func main() {
        let command = ChannelSwitchCommandBuilder.command(
            brewPath: "/opt/homebrew/bin/brew",
            sourceToken: "mos",
            targetToken: "mos@beta"
        )
        precondition(command.executable == "/bin/sh")
        precondition(command.arguments.count == 2)
        let script = command.arguments[1]
        precondition(script.contains("uninstall --cask --force 'mos'"))
        precondition(script.contains("install --cask 'mos@beta'"))
        precondition(script.contains("if "))
        precondition(script.contains("list --cask 'mos'"))
        precondition(script.contains("|| exit $?"))
        let uninstallIndex = script.range(of: "uninstall")!.lowerBound
        let installIndex = script.range(of: "install")!.lowerBound
        precondition(uninstallIndex < installIndex)
        precondition(command.display.contains("mos@beta"))

        let quoted = ChannelSwitchCommandBuilder.command(
            brewPath: "/opt/homebrew/bin/brew",
            sourceToken: "token with space",
            targetToken: "mos@beta"
        )
        precondition(quoted.arguments[1].contains("'token with space'"))
    }
}
