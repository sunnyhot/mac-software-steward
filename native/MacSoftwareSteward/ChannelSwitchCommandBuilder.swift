import Foundation

/// 将渠道切换编排成一个原子命令：只有旧 cask 卸载成功后才安装目标渠道。
enum ChannelSwitchCommandBuilder {
    static func command(brewPath: String, sourceToken: String, targetToken: String) -> UpgradeCommand {
        let brew = SudoScriptBuilder.shellQuote(brewPath)
        let sourceCheck = "\(brew) list --cask \(SudoScriptBuilder.shellQuote(sourceToken)) >/dev/null 2>&1"
        let uninstall = "\(brew) uninstall --cask --force \(SudoScriptBuilder.shellQuote(sourceToken))"
        let install = "\(brew) install --cask \(SudoScriptBuilder.shellQuote(targetToken))"
        // 卸载与安装必须保持顺序，但重试时不能重复卸载已经移除的源渠道。
        let script = """
        if \(sourceCheck); then
          \(uninstall) || exit $?
        fi
        \(install)
        """
        return UpgradeCommand(
            executable: "/bin/sh",
            arguments: ["-c", script],
            display: "brew uninstall --cask --force \(sourceToken) && brew install --cask \(targetToken)"
        )
    }
}
