import Foundation

/// 自更新失败版本记忆。
///
/// 用于打破"坏 release 导致无限重下"的循环：当某个版本的安装包校验或安装失败后，
/// 把该版本 + 资产 SHA256 记下来，后续自动检查若命中间一组 (version, sha256) 就跳过自动下载，
/// 只在 UI 上提示"该版本自动更新已暂停，可手动重试"。
///
/// - 当出现新版本（version 或 sha256 任一不同）时，旧记忆自动失效。
/// - 手动触发更新始终允许，不受记忆限制。
///
/// 该类型为纯值类型，不持有 UserDefaults，便于单测；持久化由 `AppUpdateModel` 负责。
struct AppUpdateFailureMemory: Equatable, Codable {
    /// 失败的版本号（已去掉 v 前缀），例如 "0.18.9"
    var version: String
    /// 失败时该版本安装包的 SHA256（小写十六进制），用于区分同一版本的多次重新打包
    var sha256: String
    /// 失败时间，仅用于展示和排序
    var failedAt: Date

    /// 判断给定版本 + SHA256 是否命中失败记忆，应跳过自动下载。
    /// `otherVersion` 应为去掉 v 前缀的纯版本号；`otherSHA256` 大小写不敏感。
    func shouldSkipAutoDownload(version otherVersion: String, sha256 otherSHA256: String) -> Bool {
        guard version == otherVersion else { return false }
        return sha256.lowercased() == otherSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
