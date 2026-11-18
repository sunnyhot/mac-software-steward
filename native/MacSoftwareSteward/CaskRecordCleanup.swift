import Foundation

/// 仅清理 Homebrew 的安装记录，不执行 cask 的完整卸载脚本。
/// 适用于 App 已被用户删除、但 Caskroom 仍有 receipt 的场景。
enum CaskRecordCleanup {
    /// 专用跳过码：授权或排队期间 App 重新出现，不执行 rm，也不计为成功。
    static let appReappearedExitCode: Int32 = 75

    static func command(
        brewPath: String,
        caskName: String,
        expectedAppPaths: [String] = []
    ) async throws -> UpgradeCommand {
        let result = await CommandRunner.run(brewPath, arguments: ["--caskroom"], timeout: 30)
        guard result.ok else {
            throw StewardError.message("无法读取 Homebrew Caskroom 路径：\(result.stderr)")
        }
        guard let caskroom = result.stdout
            .split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) else {
            throw StewardError.message("Homebrew 没有返回有效的 Caskroom 路径。")
        }
        return try command(
            caskName: caskName,
            caskroomPath: caskroom,
            expectedAppPaths: expectedAppPaths
        )
    }

    static func command(
        caskName: String,
        caskroomPath: String,
        expectedAppPaths: [String] = []
    ) throws -> UpgradeCommand {
        guard !caskName.isEmpty,
              caskName != ".",
              caskName != "..",
              !caskName.contains("/"),
              !caskName.contains("\\"),
              !caskName.contains("\0") else {
            throw StewardError.message("Cask 名称不安全，拒绝清理安装记录。")
        }

        guard caskroomPath.hasPrefix("/"), !caskroomPath.contains("\0") else {
            throw StewardError.message("Caskroom 路径不安全，拒绝清理安装记录。")
        }
        let root = URL(fileURLWithPath: caskroomPath).standardizedFileURL
        guard root.path.hasPrefix("/"), root.path != "/", !root.path.contains("\0") else {
            throw StewardError.message("Caskroom 路径不安全，拒绝清理安装记录。")
        }
        let target = root.appendingPathComponent(caskName, isDirectory: true).standardizedFileURL
        guard target.path != root.path,
              target.deletingLastPathComponent().path == root.path else {
            throw StewardError.message("安装记录路径超出 Caskroom，拒绝清理。")
        }

        let rm = "/bin/rm -rf -- \(SudoScriptBuilder.shellQuote(target.path))"
        let paths = expectedAppPaths.filter { !$0.isEmpty }
        guard !paths.isEmpty else {
            return UpgradeCommand(
                executable: "/bin/rm",
                arguments: ["-rf", "--", target.path],
                display: rm
            )
        }

        // 检查紧贴实际删除命令，覆盖密码框和其他任务等待期间的重装竞态。
        let existenceChecks = paths
            .map { "[ -e \(SudoScriptBuilder.shellQuote($0)) ]" }
            .joined(separator: " || ")
        let script = """
        if \(existenceChecks); then
          printf '%s\n' 'App 已重新出现，跳过安装记录清理' >&2
          exit \(appReappearedExitCode)
        fi
        \(rm)
        """
        return UpgradeCommand(
            executable: "/bin/sh",
            arguments: ["-c", script],
            display: rm
        )
    }
}
