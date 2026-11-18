import Foundation

/// 统一解释 brew list 的验证结果，避免 Agent 与 GUI 对“已删除”判断不一致。
enum CaskReceiptVerification {
    static func isRemoved(_ result: CommandResult) -> Bool {
        guard !result.ok else { return false }
        let output = "\(result.stdout)\n\(result.stderr)".lowercased()
        return output.contains("no such cask")
            || output.contains("not installed")
            || output.contains("no cask")
    }
}
