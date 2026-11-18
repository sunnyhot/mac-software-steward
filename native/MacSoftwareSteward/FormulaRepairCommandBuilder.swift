import Foundation

/// Homebrew 对多版本安装记录建议的显式修复：先卸载全部旧版本，再安装当前版本。
enum FormulaRepairCommandBuilder {
    static func command(brewPath: String, formulaName: String) -> UpgradeCommand {
        let brew = SudoScriptBuilder.shellQuote(brewPath)
        let formula = SudoScriptBuilder.shellQuote(formulaName)
        let sourceCheck = "\(brew) list --formula \(formula) 2>&1 | /usr/bin/grep -Fqi 'has multiple installed versions'"
        let script = """
        if \(sourceCheck); then
          \(brew) uninstall --force \(formula) || exit $?
        fi
        \(brew) install \(formula)
        """
        return UpgradeCommand(
            executable: "/bin/sh",
            arguments: ["-c", script],
            display: "brew uninstall --force \(formulaName) && brew install \(formulaName)"
        )
    }
}
