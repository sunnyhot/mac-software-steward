import Foundation

enum LocalSoftwareKind: String, CaseIterable, Identifiable, Hashable {
    case app
    case brewFormula
    case brewCask
    case appStore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app: return "App"
        case .brewFormula: return "Formula"
        case .brewCask: return "Cask"
        case .appStore: return "App Store"
        }
    }

    var sourceTitle: String {
        switch self {
        case .app: return "普通 App"
        case .brewFormula: return "Brew Formula"
        case .brewCask: return "Brew Cask"
        case .appStore: return "Mac App Store"
        }
    }

    var symbol: String {
        switch self {
        case .app: return "macwindow"
        case .brewFormula: return "cube.box"
        case .brewCask: return "shippingbox"
        case .appStore: return "bag"
        }
    }
}

enum LocalSoftwareFilter: String, CaseIterable, Identifiable, Hashable {
    case all = "全部"
    case app = "App"
    case formula = "Formula"
    case cask = "Cask"
    case appStore = "App Store"
    case upgradable = "可升级"

    var id: String { rawValue }
}

struct LocalSoftwareSummary: Equatable {
    var total: Int
    var app: Int
    var upgradable: Int
    var brew: Int
    var appStore: Int
}

struct LocalSoftwareRow: Identifiable, Hashable {
    var id: String
    var name: String
    var installedVersion: String
    var currentVersion: String
    var source: String
    var detail: String
    var kind: LocalSoftwareKind
    var isOutdated: Bool
    var isUpgradeable: Bool
    var isCheckable: Bool
    var isPinned: Bool
    var autoUpdates: Bool
    var package: UpdatablePackage?
    var app: AppItem?

    var searchText: String {
        [
            name,
            installedVersion,
            currentVersion,
            source,
            detail,
            kind.title,
            app?.path ?? "",
            app?.updateCapability.detector.title ?? "",
            app?.updateCapability.summary ?? ""
        ]
        .joined(separator: " ")
        .lowercased()
    }
}

enum LocalSoftwarePresenter {
    static func rows(from scan: ScanResult) -> [LocalSoftwareRow] {
        rows(applications: scan.applications.items, brew: scan.brew, mas: scan.mas)
    }

    static func rows(
        applications: [AppItem],
        brew: BrewScan,
        mas: MasScan
    ) -> [LocalSoftwareRow] {
        regularAppRows(from: applications)
            + brew.formulae.map { packageRow(from: $0, kind: .brewFormula) }
            + brew.casks.map { packageRow(from: $0, kind: .brewCask) }
            + mas.apps.map(appStoreRow(from:))
    }

    static func filteredRows(_ rows: [LocalSoftwareRow], filter: LocalSoftwareFilter) -> [LocalSoftwareRow] {
        rows.filter { row in
            switch filter {
            case .all:
                return true
            case .app:
                return row.kind == .app
            case .formula:
                return row.kind == .brewFormula
            case .cask:
                return row.kind == .brewCask
            case .appStore:
                return row.kind == .appStore
            case .upgradable:
                return row.isUpgradeable
            }
        }
    }

    static func summary(for rows: [LocalSoftwareRow]) -> LocalSoftwareSummary {
        LocalSoftwareSummary(
            total: rows.count,
            app: rows.filter { $0.kind == .app }.count,
            upgradable: rows.filter(\.isUpgradeable).count,
            brew: rows.filter { $0.kind == .brewFormula || $0.kind == .brewCask }.count,
            appStore: rows.filter { $0.kind == .appStore }.count
        )
    }

    private static func regularAppRows(from applications: [AppItem]) -> [LocalSoftwareRow] {
        ApplicationVisibilityPresenter.visibleApplications(applications)
            .filter { $0.managedBy == "manual" }
            .map { app in
                LocalSoftwareRow(
                    id: app.id,
                    name: app.name,
                    installedVersion: app.version,
                    currentVersion: app.availableVersion,
                    source: app.updateCapability.detector == .none
                        ? "普通 App"
                        : app.updateCapability.detector.title,
                    detail: app.path,
                    kind: .app,
                    isOutdated: app.updateState == "outdated" || !app.availableVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    isUpgradeable: false,
                    isCheckable: app.updateState == "checkable" || app.updateCapability.hasManualAction,
                    isPinned: false,
                    autoUpdates: false,
                    package: nil,
                    app: app
                )
            }
    }

    private static func packageRow(from package: BrewPackage, kind: LocalSoftwareKind) -> LocalSoftwareRow {
        let updatable = UpdatablePackage.brew(package)
        return LocalSoftwareRow(
            id: package.id,
            name: package.name,
            installedVersion: package.installedVersion,
            currentVersion: package.currentVersion,
            source: kind.sourceTitle,
            detail: package.pinned ? "已固定版本" : (package.autoUpdates ? "应用自带更新器" : kind.sourceTitle),
            kind: kind,
            isOutdated: package.outdated,
            isUpgradeable: package.upgradeable,
            isCheckable: false,
            isPinned: package.pinned,
            autoUpdates: package.autoUpdates,
            package: updatable,
            app: nil
        )
    }

    private static func appStoreRow(from app: MasApp) -> LocalSoftwareRow {
        let updatable = UpdatablePackage.mas(app)
        return LocalSoftwareRow(
            id: app.id,
            name: app.name,
            installedVersion: app.installedVersion,
            currentVersion: app.currentVersion,
            source: LocalSoftwareKind.appStore.sourceTitle,
            detail: "App Store ID \(app.appId)",
            kind: .appStore,
            isOutdated: app.outdated,
            isUpgradeable: app.upgradeable,
            isCheckable: false,
            isPinned: false,
            autoUpdates: false,
            package: updatable,
            app: nil
        )
    }
}
