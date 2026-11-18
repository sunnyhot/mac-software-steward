import Foundation

/// 把同批次需要 sudo 的命令拼成一条 osascript 脚本。
///
/// 保留每个命令的 executable 与完整参数，避免清理、安装等操作在提权时
/// 被错误地重建成 upgrade。每个命令后追加独立的 __RC__ 标记，供 parser
/// 将结果映射回原始步骤。
enum SudoScriptBuilder {
    static func script(commands: [UpgradeCommand], pathEnv: String, homeEnv: String) -> String {
        var lines = [
            "export PATH=\(shellQuote(pathEnv))",
            "export HOME=\(shellQuote(homeEnv))"
        ]

        for (index, command) in commands.enumerated() {
            let markerNumber = index + 1
            let shellCommand = ([command.executable] + command.arguments)
                .map(shellQuote)
                .joined(separator: " ")
            lines.append("\(shellCommand); echo \"__RC_\(markerNumber)_$?__\"")
        }

        let body = lines.joined(separator: "\n")
        let appleScriptBody = body
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(appleScriptBody)\" with administrator privileges"
    }

    /// 单个 shell token 使用单引号保护；内部的单引号按 POSIX 规则拆成
    /// 结束引号 + 转义单引号 + 重新打开引号。
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func osaArguments(_ script: String) -> [String] {
        ["-e", script]
    }
}
