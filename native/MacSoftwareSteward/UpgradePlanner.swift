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
        let selectable = isSelectable(package, scan: scan, includeGreedy: includeGreedy)
        let selection: UpgradePlanSelection
        let skipReason: String

        if !selectable {
            selection = .notSelectable
            skipReason = nonSelectableReason(for: package, scan: scan)
        } else {
            switch policy {
            case .automatic, .askFirst:
                selection = .selected
                skipReason = ""
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
            riskLabels: riskLabels(for: package, scan: scan, includeGreedy: includeGreedy),
            skipReason: skipReason,
            package: selectable ? package : nil
        )
    }

    private static func isSelectable(_ package: UpdatablePackage, scan: ScanResult, includeGreedy: Bool) -> Bool {
        guard !isSourceUnavailable(package, scan: scan), !package.isPinned else {
            return false
        }

        return package.upgradeable || canRunGreedyCask(package, includeGreedy: includeGreedy)
    }

    private static func canRunGreedyCask(_ package: UpdatablePackage, includeGreedy: Bool) -> Bool {
        guard includeGreedy, case .brew(let brew) = package else {
            return false
        }

        return brew.kind == "cask" && brew.outdated
    }

    private static func riskLabels(for package: UpdatablePackage, scan: ScanResult, includeGreedy: Bool) -> [String] {
        var labels: [String] = []

        switch package {
        case .brew(let brew):
            if brew.kind == "cask", includeGreedy {
                labels.append("greedy cask")
            }
            if brew.autoUpdates {
                labels.append("auto_updates")
            }
            if brew.pinned {
                labels.append("pinned")
            }
            if brew.kind == "cask", scan.applications.items.contains(where: { $0.relatedPackageID == brew.id }) {
                labels.append("app may be running")
            }
            if !scan.brew.error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                labels.append("source warning")
            }

        case .mas:
            if !scan.mas.available {
                labels.append("mas unavailable")
            }
        }

        if package.currentVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            labels.append("unknown target version")
        }

        return labels
    }

    private static func isSourceUnavailable(_ package: UpdatablePackage, scan: ScanResult) -> Bool {
        switch package {
        case .brew:
            return !scan.brew.available
        case .mas:
            return !scan.mas.available
        }
    }

    private static func nonSelectableReason(for package: UpdatablePackage, scan: ScanResult) -> String {
        if package.isPinned {
            return "软件包已固定"
        }
        if isSourceUnavailable(package, scan: scan) {
            return "管理来源不可用"
        }
        if !package.upgradeable {
            return package.outdated ? "需要手动处理" : "无需升级"
        }

        return "当前不可执行"
    }

    private static func commandDisplay(for package: UpdatablePackage, includeGreedy: Bool) -> String {
        switch package {
        case .brew(let brew):
            if brew.kind == "cask" {
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
