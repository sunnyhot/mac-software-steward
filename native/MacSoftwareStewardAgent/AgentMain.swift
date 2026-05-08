import Foundation

@main
struct MacSoftwareStewardAgent {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.first == "daily-check" else {
            print("Usage: MacSoftwareStewardAgent daily-check [--auto-upgrade] [--greedy] [--brew-update]")
            Foundation.exit(2)
        }

        let autoUpgrade = arguments.contains("--auto-upgrade")
        let includeGreedy = arguments.contains("--greedy")
        let runBrewUpdate = arguments.contains("--brew-update")
        let startedAt = ISO8601DateFormatter().string(from: Date())

        print("[system] \(startedAt) 每日巡检开始")
        let scan = await SoftwareScanner.scanAll(includeGreedy: includeGreedy)
        print("[scan] 应用 \(scan.summary.applications)，formula \(scan.summary.brewFormulae)，cask \(scan.summary.brewCasks)，可操作升级 \(scan.summary.actionable)")

        let formulaUpdates = scan.brew.formulae.filter { $0.upgradeable }
        let caskUpdates = scan.brew.casks.filter { $0.upgradeable }
        let masUpdates = scan.mas.apps.filter { $0.upgradeable }

        guard !formulaUpdates.isEmpty || !caskUpdates.isEmpty || !masUpdates.isEmpty else {
            print("[system] 未发现可自动升级的软件")
            Foundation.exit(0)
        }

        print("[updates] formula: \(formulaUpdates.map(\.name).joined(separator: ", "))")
        print("[updates] cask: \(caskUpdates.map(\.name).joined(separator: ", "))")
        print("[updates] mas: \(masUpdates.map(\.name).joined(separator: ", "))")

        guard autoUpgrade else {
            print("[system] 已禁用自动升级，仅完成巡检")
            Foundation.exit(0)
        }

        var commands: [(String, [String], String)] = []

        if !formulaUpdates.isEmpty || !caskUpdates.isEmpty {
            guard let brew = await CommandRunner.commandPath("brew") else {
                print("[error] 发现 Homebrew 更新，但找不到 brew")
                Foundation.exit(1)
            }
            if runBrewUpdate {
                commands.append((brew, ["update"], "brew update"))
            }
            if !formulaUpdates.isEmpty {
                commands.append((brew, ["upgrade"], "brew upgrade"))
            }
            if !caskUpdates.isEmpty {
                let args = ["upgrade", "--cask"] + (includeGreedy ? ["--greedy"] : [])
                commands.append((brew, args, (["brew"] + args).joined(separator: " ")))
            }
        }

        if !masUpdates.isEmpty {
            if let mas = await CommandRunner.commandPath("mas") {
                commands.append((mas, ["upgrade"], "mas upgrade"))
            } else {
                print("[warn] 发现 Mac App Store 更新，但 mas CLI 不可用，已跳过")
            }
        }

        for command in commands {
            print("[command] $ \(command.2)")
            let code = await CommandRunner.runStreaming(command.0, arguments: command.1) { stream, text in
                print("[\(stream)] \(text)")
            }
            if code != 0 {
                print("[error] 命令失败：\(command.2)，退出码 \(code)")
                Foundation.exit(Int32(code))
            }
        }

        print("[system] 每日巡检自动升级完成")
        Foundation.exit(0)
    }
}
