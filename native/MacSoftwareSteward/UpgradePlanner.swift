import Foundation

enum UpgradePlanSelection: String, Codable, Hashable {
    case selected
    case notSelected
    case notSelectable
}

struct UpgradePlanRow: Identifiable, Hashable {
    var packageID: String
    var packageName: String
    var source: String
    var installedVersion: String
    var currentVersion: String
    var commandDisplay: String
    var policy: UpgradePolicy
    var selection: UpgradePlanSelection
    var riskLabels: [String]
    var skipReason: String
    var package: UpdatablePackage?
    var riskLevel: RiskLevel = .low
    var riskSummary: String = ""
    var automationDecision: AutomationDecision = .allowAutomatic

    var id: String { packageID }

    var canExecute: Bool {
        selection != .notSelectable && package != nil
    }
}

enum UpgradePlanner {
    static func makePlan(
        scan: ScanResult,
        policyStore: UpgradePolicyStore,
        includeGreedy: Bool
    ) -> [UpgradePlanRow] {
        let packages = scan.brew.formulae.map(UpdatablePackage.brew)
            + scan.brew.casks.map(UpdatablePackage.brew)
            + scan.mas.apps.map(UpdatablePackage.mas)

        return packages
            .compactMap { row(for: $0, scan: scan, policyStore: policyStore, includeGreedy: includeGreedy) }
            .sorted { lhs, rhs in
                let lhsRank = sortRank(lhs.selection)
                let rhsRank = sortRank(rhs.selection)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }

                return lhs.packageName.localizedCaseInsensitiveCompare(rhs.packageName) == .orderedAscending
            }
    }

    private static func row(
        for package: UpdatablePackage,
        scan: ScanResult,
        policyStore: UpgradePolicyStore,
        includeGreedy: Bool
    ) -> UpgradePlanRow? {
        guard package.outdated || package.upgradeable else { return nil }

        let policy = policyStore.effectivePolicy(for: package, includeGreedy: includeGreedy)
        let risk = RiskAssessor.assess(package: package, scan: scan, includeGreedy: includeGreedy)
        let selectable = risk.automationDecision != .blockExecution
        let selection: UpgradePlanSelection
        let skipReason: String

        if !selectable {
            selection = .notSelectable
            skipReason = nonSelectableReason(for: package, scan: scan, risk: risk)
        } else {
            switch policy {
            case .automatic, .askFirst:
                if risk.automationDecision == .requireConfirmation {
                    selection = .notSelected
                    skipReason = "需确认：\(risk.summary)"
                } else {
                    selection = .selected
                    skipReason = ""
                }
            case .remindOnly:
                selection = .notSelected
                skipReason = "策略设置为仅提醒"
            case .skip:
                selection = .notSelected
                skipReason = "策略设置为跳过"
            }
        }

        return UpgradePlanRow(
            packageID: package.id,
            packageName: package.name,
            source: package.source,
            installedVersion: package.installedVersion,
            currentVersion: package.currentVersion,
            commandDisplay: commandDisplay(for: package, includeGreedy: includeGreedy),
            policy: policy,
            selection: selection,
            riskLabels: risk.labels,
            skipReason: skipReason,
            package: selectable ? package : nil,
            riskLevel: risk.level,
            riskSummary: risk.summary,
            automationDecision: risk.automationDecision
        )
    }

    private static func isSourceUnavailable(_ package: UpdatablePackage, scan: ScanResult) -> Bool {
        switch package {
        case .brew:
            return !scan.brew.available
        case .mas:
            return !scan.mas.available
        }
    }

    private static func nonSelectableReason(for package: UpdatablePackage, scan: ScanResult, risk: RiskAssessment) -> String {
        if package.isPinned {
            return "软件包已固定"
        }
        if isSourceUnavailable(package, scan: scan) {
            return "管理来源不可用"
        }
        if !risk.summary.isEmpty {
            return risk.summary
        }
        if !package.upgradeable {
            return package.manualUpdateOnly ? "应用自带更新器发现新版本" : (package.outdated ? "需要手动处理" : "无需升级")
        }

        return "当前不可执行"
    }

    private static func commandDisplay(for package: UpdatablePackage, includeGreedy: Bool) -> String {
        switch package {
        case .brew(let brew):
            if brew.kind == "cask" {
                if brew.manualUpdateOnly {
                    return "应用内更新器"
                }
                var parts = ["brew", "upgrade", "--cask"]
                if includeGreedy {
                    parts.append("--greedy")
                }
                parts.append(brew.name)
                return parts.joined(separator: " ")
            }

            return "brew upgrade \(brew.name)"

        case .mas(let app):
            return "mas upgrade \(app.appId)"
        }
    }

    private static func sortRank(_ selection: UpgradePlanSelection) -> Int {
        switch selection {
        case .selected:
            return 0
        case .notSelected:
            return 1
        case .notSelectable:
            return 2
        }
    }
}
