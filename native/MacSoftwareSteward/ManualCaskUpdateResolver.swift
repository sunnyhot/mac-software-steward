import Foundation

enum ManualCaskUpdateResolutionKind: Hashable {
    case switchChannel
    case openOfficialUpdate
}

struct ManualCaskUpdateResolution: Hashable {
    var kind: ManualCaskUpdateResolutionKind
    var actionTitle: String
    var explanation: String
    var targetCaskToken: String = ""
    var targetVersion: String
    var officialURLString: String
}

enum ManualCaskUpdateResolver {
    static func resolution(for package: UpdatablePackage) -> ManualCaskUpdateResolution? {
        guard case .brew(let brew) = package,
              brew.kind == "cask",
              brew.manualUpdateOnly else {
            return nil
        }

        if let channel = prereleaseChannel(in: brew.currentVersion), !brew.name.contains("@") {
            let displayChannel = channel == "canary" ? "Canary" : channel.capitalized
            return ManualCaskUpdateResolution(
                kind: .switchChannel,
                actionTitle: "切换到 \(displayChannel)",
                explanation: "当前 Homebrew 配方没有 \(brew.currentVersion)，但可以切换到 \(displayChannel) 渠道。",
                targetCaskToken: "\(brew.name)@\(channel)",
                targetVersion: brew.currentVersion,
                officialURLString: brew.advisoryURLString
            )
        }

        return ManualCaskUpdateResolution(
            kind: .openOfficialUpdate,
            actionTitle: "打开官方更新",
            explanation: "Homebrew 尚未收录 \(brew.currentVersion)，再次执行 brew upgrade 不会生效。请使用应用内更新或官方安装包。",
            targetVersion: brew.currentVersion,
            officialURLString: brew.advisoryURLString
        )
    }

    static func caskVersion(fromBrewInfoJSON stdout: String, token: String) -> String? {
        guard let data = stdout.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casks = object["casks"] as? [[String: Any]] else {
            return nil
        }
        let cask = casks.first { item in
            let fullToken = item["full_token"] as? String
            let shortToken = fullToken?.split(separator: "/").last.map(String.init)
            return (item["token"] as? String) == token
                || fullToken == token
                || shortToken == token
        }
        return cask?["version"] as? String
    }

    static func versionsMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizedVersion(lhs)
        let right = normalizedVersion(rhs)
        if left == right { return true }
        // Homebrew cask 可能在预发布后追加日期/构建号，例如
        // mos@beta 的 4.3.0-beta-20260820.1 对应 Appcast 的 4.3.0-beta。
        return hasNumericBuildSuffix(left, base: right) || hasNumericBuildSuffix(right, base: left)
    }

    private static func hasNumericBuildSuffix(_ candidate: String, base: String) -> Bool {
        let prefix = base + "-"
        guard candidate.hasPrefix(prefix) else { return false }
        let suffix = String(candidate.dropFirst(prefix.count))
        return suffix.range(of: #"^\d+(?:\.\d+)*$"#, options: .regularExpression) != nil
    }

    private static func prereleaseChannel(in version: String) -> String? {
        let value = version.lowercased()
        if value.contains("canary") { return "canary" }
        if value.contains("nightly") { return "nightly" }
        if value.contains("alpha") { return "alpha" }
        if value.contains("beta") || value.range(of: #"(?:^|[-.])rc(?:[-.]|\d)"#, options: .regularExpression) != nil {
            return "beta"
        }
        return nil
    }

    private static func normalizedVersion(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("v"), trimmed.dropFirst().first?.isNumber == true {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }
}
