import Foundation

@main
struct AppUpdateFailureMemoryTest {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let memory = AppUpdateFailureMemory(version: "0.18.9", sha256: "ABCDEF0123", failedAt: now)

        // 1. 命中：同一 version + 同一 sha256（大小写不敏感）应跳过自动下载
        precondition(
            memory.shouldSkipAutoDownload(version: "0.18.9", sha256: "abcdef0123"),
            "同一 version+sha256（大小写不同）应命中失败记忆"
        )

        // 2. 版本不同：不跳过（新版本出现）
        precondition(
            !memory.shouldSkipAutoDownload(version: "0.18.10", sha256: "ABCDEF0123"),
            "不同版本不应命中记忆"
        )

        // 3. 同版本但 sha256 不同（重新打包）：不跳过
        precondition(
            !memory.shouldSkipAutoDownload(version: "0.18.9", sha256: "9999999999"),
            "同版本但 sha256 不同（已重新打包）不应命中记忆"
        )

        // 4. 空白 sha256 容错
        precondition(
            memory.shouldSkipAutoDownload(version: "0.18.9", sha256: "  ABCDEF0123  "),
            "带空白的 sha256 应被归一化后命中"
        )

        // 5. 版本带 v 前缀不应命中（记忆存的是去前缀的纯版本号）
        precondition(
            !memory.shouldSkipAutoDownload(version: "v0.18.9", sha256: "ABCDEF0123"),
            "带 v 前缀的版本号不应命中（记忆使用去前缀版本）"
        )

        // 6. Codable 往返：持久化不丢失字段
        let decoded = try! JSONDecoder().decode(
            AppUpdateFailureMemory.self,
            from: try! JSONEncoder().encode(memory)
        )
        precondition(decoded == memory, "Codable 编解码往返应保持相等")
        precondition(decoded.failedAt == now, "failedAt 应在编解码后保留")

        // 7. 验证核心场景：坏 release 的 SHA 不匹配导致循环时，记忆能拦截
        //    模拟 v0.18.9 发布了错误的 SHA → 第一次失败记下 → 第二次自动检查命中 → 跳过
        let badReleaseSHA = "8f29da20573132357fb9d74e82af743a442e7a213b7bc3ec0cdfac323baacb16"
        let memoryFromFailure = AppUpdateFailureMemory(version: "0.18.9", sha256: badReleaseSHA, failedAt: now)
        precondition(
            memoryFromFailure.shouldSkipAutoDownload(version: "0.18.9", sha256: badReleaseSHA),
            "坏 release 失败后，同 (version, sha) 的再次自动检查应被拦截"
        )
        //    修复后重新上传了正确 SHA 的 latest.json → manifest 的 sha 变了 → 不再命中 → 恢复下载
        let fixedReleaseSHA = "d095d078cb13459fadcd5c4b141b313e2be73142cb46056f67aa606b1517eb7c"
        precondition(
            !memoryFromFailure.shouldSkipAutoDownload(version: "0.18.9", sha256: fixedReleaseSHA),
            "修复后 sha256 改变，应恢复自动下载"
        )

        print("AppUpdateFailureMemoryTest passed")
    }
}
