import Foundation

enum RiskLevel: String, Codable, Hashable {
    case low
    case medium
    case high

    var title: String {
        switch self {
        case .low: return "低风险"
        case .medium: return "需确认"
        case .high: return "高风险"
        }
    }
}

enum AutomationDecision: String, Codable, Hashable {
    case allowAutomatic
    case requireConfirmation
    case blockExecution
}

enum RiskReason: String, Codable, Hashable {
    case pinned
    case greedyCask
    case autoUpdates
    case appMayBeRunning
    case sourceWarning
    case masUnavailable
    case brewUnavailable
    case unknownTargetVersion
    case notUpgradeable
    case majorVersion

    var label: String {
        switch self {
        case .pinned: return "pinned"
        case .greedyCask: return "greedy cask"
        case .autoUpdates: return "auto_updates"
        case .appMayBeRunning: return "app may be running"
        case .sourceWarning: return "source warning"
        case .masUnavailable: return "mas unavailable"
        case .brewUnavailable: return "brew unavailable"
        case .unknownTargetVersion: return "unknown target version"
        case .notUpgradeable: return "not upgradeable"
        case .majorVersion: return "major version"
        }
    }

    var summary: String {
        switch self {
        case .pinned: return "软件包已固定"
        case .greedyCask: return "greedy cask 可能覆盖自动更新类应用"
        case .autoUpdates: return "应用声明会自行更新"
        case .appMayBeRunning: return "关联应用可能正在运行"
        case .sourceWarning: return "管理来源存在警告"
        case .masUnavailable: return "mas CLI 不可用"
        case .brewUnavailable: return "Homebrew 不可用"
        case .unknownTargetVersion: return "目标版本未知"
        case .notUpgradeable: return "当前不可执行升级"
        case .majorVersion: return "检测到 major 版本变化"
        }
    }
}

struct RiskAssessment: Codable, Hashable {
    var packageID: String
    var level: RiskLevel
    var reasons: [RiskReason]
    var automationDecision: AutomationDecision

    var labels: [String] {
        reasons.map(\.label)
    }

    var summary: String {
        reasons.map(\.summary).joined(separator: "；")
    }
}

enum RiskAssessor {
    static func assess(package: UpdatablePackage, scan: ScanResult, includeGreedy: Bool) -> RiskAssessment {
        let reasons = riskReasons(for: package, scan: scan, includeGreedy: includeGreedy)
        let decision = automationDecision(for: package, reasons: reasons, includeGreedy: includeGreedy)
        let level = riskLevel(for: reasons, decision: decision)

        return RiskAssessment(
            packageID: package.id,
            level: level,
            reasons: reasons,
            automationDecision: decision
        )
    }

    private static func riskReasons(
        for package: UpdatablePackage,
        scan: ScanResult,
        includeGreedy: Bool
    ) -> [RiskReason] {
        var reasons: [RiskReason] = []

        switch package {
        case .brew(let brew):
            if !scan.brew.available {
                reasons.append(.brewUnavailable)
            }
            if brew.pinned {
                reasons.append(.pinned)
            }
            if brew.kind == "cask", includeGreedy {
                reasons.append(.greedyCask)
            }
            if brew.autoUpdates {
                reasons.append(.autoUpdates)
            }
            if brew.kind == "cask", scan.applications.items.contains(where: { $0.relatedPackageID == brew.id }) {
                reasons.append(.appMayBeRunning)
            }
            if !scan.brew.error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                reasons.append(.sourceWarning)
            }
            if !package.upgradeable && !canRunGreedyCask(package, includeGreedy: includeGreedy) {
                reasons.append(.notUpgradeable)
            }

        case .mas:
            if !scan.mas.available {
                reasons.append(.masUnavailable)
            }
            if !package.upgradeable {
                reasons.append(.notUpgradeable)
            }
        }

        if package.currentVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons.append(.unknownTargetVersion)
        }
        if isMajorVersionChange(installed: package.installedVersion, current: package.currentVersion) {
            reasons.append(.majorVersion)
        }

        return Array(Set(reasons)).sorted { $0.label < $1.label }
    }

    private static func automationDecision(
        for package: UpdatablePackage,
        reasons: [RiskReason],
        includeGreedy: Bool
    ) -> AutomationDecision {
        if reasons.contains(.brewUnavailable) ||
            reasons.contains(.masUnavailable) ||
            reasons.contains(.pinned) ||
            (reasons.contains(.notUpgradeable) && !canRunGreedyCask(package, includeGreedy: includeGreedy)) {
            return .blockExecution
        }

        if reasons.isEmpty {
            return .allowAutomatic
        }
        return .requireConfirmation
    }

    private static func riskLevel(for reasons: [RiskReason], decision: AutomationDecision) -> RiskLevel {
        if decision == .blockExecution ||
            reasons.contains(.majorVersion) ||
            reasons.contains(.pinned) ||
            reasons.contains(.brewUnavailable) ||
            reasons.contains(.masUnavailable) {
            return .high
        }

        return reasons.isEmpty ? .low : .medium
    }

    private static func canRunGreedyCask(_ package: UpdatablePackage, includeGreedy: Bool) -> Bool {
        guard includeGreedy, case .brew(let brew) = package else {
            return false
        }

        return brew.kind == "cask" && brew.outdated
    }

    private static func isMajorVersionChange(installed: String, current: String) -> Bool {
        guard let installedMajor = majorVersion(in: installed),
              let currentMajor = majorVersion(in: current) else {
            return false
        }

        return currentMajor > installedMajor
    }

    private static func majorVersion(in version: String) -> Int? {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = trimmed.split(whereSeparator: { !$0.isNumber }).first else {
            return nil
        }
        return Int(token)
    }
}
