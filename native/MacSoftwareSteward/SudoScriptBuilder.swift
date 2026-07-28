import Foundation

/// 把同批次所有需要 sudo 的 cask 拼成一条 osascript 脚本。
///
/// 格式（parser 据此解析，改动需同步 SudoScriptParser）：
///   do shell script "<body>" with administrator privileges
/// body 每行：`<brewPath> upgrade --cask <name>; echo "__RC_<i>_$?__"`
/// body 前置 `export PATH=...; export HOME=...;` 透传最小环境给 root shell。
/// 语句间用 `;`（非 `&&`），单条失败不阻断后续，实现失败隔离。
enum SudoScriptBuilder {
    /// 生成 AppleScript 脚本字符串（osascript -e 的内容）。
    static func script(brewPath: String, packageNames: [String], pathEnv: String, homeEnv: String) -> String {
        var lines: [String] = []
        lines.append("export PATH=\(pathEnv)")
        lines.append("export HOME=\(homeEnv)")
        for (index, name) in packageNames.enumerated() {
            // 标记下标从 1 开始，与 parser 约定一致。
            let markerNumber = index + 1
            lines.append("\(brewPath) upgrade --cask \(name); echo \"__RC_\(markerNumber)_$?__\"")
        }
        let body = lines.joined(separator: "\n")
        return "do shell script \"\(body)\" with administrator privileges"
    }

    /// 把脚本包装成 osascript 的参数列表。
    static func osaArguments(_ script: String) -> [String] {
        ["-e", script]
    }
}
