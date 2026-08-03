import Foundation

/// 从 `MaintenanceExecutor` 提取的无状态命令解析逻辑。
///
/// 把可升级包解析成实际要执行的 `UpgradeCommand`，校验 Homebrew token，
/// 并在 PATH 中定位命令路径。不持有任何状态。
enum MaintenanceCommandResolver {
    static func command(for package: UpdatablePackage, includeGreedy: Bool) async throws -> UpgradeCommand {
        switch package {
        case .brew(let brewPackage):
            try validateBrewToken(brewPackage.name)
            let brew = try await requireCommand("brew")
            var args = ["upgrade"]
            if brewPackage.kind == "cask" {
                args.append("--cask")
                if includeGreedy || brewPackage.autoUpdates { args.append("--greedy") }
            }
            args.append(brewPackage.name)
            return UpgradeCommand(executable: brew, arguments: args, display: (["brew"] + args).joined(separator: " "))

        case .mas(let app):
            guard app.appId.allSatisfy(\.isNumber) else {
                throw StewardError.message("无效的 Mac App Store app id。")
            }
            let mas = try await requireCommand("mas")
            return UpgradeCommand(executable: mas, arguments: ["upgrade", app.appId], display: "mas upgrade \(app.appId)")
        }
    }

    static func requireCommand(_ command: String) async throws -> String {
        if let path = await CommandRunner.commandPath(command) {
            return path
        }
        throw StewardError.message("\(command) is not installed or not in PATH.")
    }

    static func validateBrewToken(_ token: String) throws {
        let pattern = "^[A-Za-z0-9][A-Za-z0-9@._+-]*$"
        if token.range(of: pattern, options: .regularExpression) == nil {
            throw StewardError.message("无效的 Homebrew token。")
        }
    }
}
