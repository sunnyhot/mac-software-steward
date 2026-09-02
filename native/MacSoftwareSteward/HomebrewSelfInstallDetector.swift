import Foundation

/// 2026-09-02:检测本应用是否由 Homebrew cask（sunnyhot/tap/mac-software-steward）安装。
/// brew 安装的本应用由 `brew upgrade` 管理，自更新只提示、不再覆盖安装——
/// 否则应用内覆盖会让 brew 认为 cask 被改动、两套更新互相打架。
/// 判定：Caskroom 里存在本 cask 的版本回执目录（Apple Silicon /opt/homebrew、
/// Intel /usr/local；不调 brew 命令、零开销。brew 卸载会移除该目录，检测自动失效）。
enum HomebrewSelfInstallDetector {
    static let caskToken = "mac-software-steward"

    static var defaultCaskroomRoots: [String] {
        ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"]
    }

    static func isManaged(caskroomRoots: [String] = defaultCaskroomRoots) -> Bool {
        caskroomRoots.contains { root in
            let tokenPath = (root as NSString).appendingPathComponent(caskToken)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: tokenPath, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return false }
            let versions = (try? FileManager.default.contentsOfDirectory(atPath: tokenPath)) ?? []
            return !versions.isEmpty
        }
    }
}
