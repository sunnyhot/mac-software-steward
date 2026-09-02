import Foundation

@main
struct HomebrewSelfInstallDetectorTest {
    static func main() throws {
        // 有版本回执目录 → brew 管理
        let realRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Caskroom-real-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: realRoot) }
        try FileManager.default.createDirectory(
            atPath: realRoot + "/mac-software-steward/0.18.16",
            withIntermediateDirectories: true
        )
        precondition(HomebrewSelfInstallDetector.isManaged(caskroomRoots: [realRoot]))

        // 路径不存在 / token 目录为空 → 非 brew 管理
        let missing = "/tmp/not-exists-\(UUID().uuidString)"
        precondition(!HomebrewSelfInstallDetector.isManaged(caskroomRoots: [missing]))

        let emptyRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Caskroom-empty-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: emptyRoot) }
        try FileManager.default.createDirectory(
            atPath: emptyRoot + "/mac-software-steward",
            withIntermediateDirectories: true
        )
        precondition(!HomebrewSelfInstallDetector.isManaged(caskroomRoots: [emptyRoot]))

        // 任一 root 命中即 brew 管理
        precondition(HomebrewSelfInstallDetector.isManaged(caskroomRoots: [missing, realRoot]))

        print("HomebrewSelfInstallDetectorTest passed")
    }
}
