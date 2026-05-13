import Foundation
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case updates = "可升级"
    case applications = "本机应用"
    case sources = "管理来源"
    case jobs = "任务日志"
    case settings = "设置"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .updates: return "arrow.triangle.2.circlepath"
        case .applications: return "macwindow"
        case .sources: return "tray.full"
        case .settings: return "gearshape"
        case .jobs: return "terminal"
        }
    }

    var usesSearch: Bool {
        switch self {
        case .updates, .applications, .sources:
            return true
        case .settings, .jobs:
            return false
        }
    }
}

enum JobStatus: String {
    case queued = "排队"
    case running = "运行中"
    case succeeded = "完成"
    case failed = "失败"
}

enum PackageUpgradeStatus: String, Hashable {
    case queued = "排队"
    case running = "升级中"
    case succeeded = "完成"
    case failed = "失败"
}

struct AppItem: Identifiable, Hashable {
    var id: String
    var name: String
    var version: String
    var availableVersion: String
    var path: String
    var source: String
    var obtainedFrom: String
    var architecture: String
    var managedBy: String
    var updateState: String
    var relatedPackageID: String
}

struct BrewPackage: Identifiable, Hashable {
    var id: String
    var kind: String
    var name: String
    var installedVersion: String
    var currentVersion: String
    var pinned: Bool
    var autoUpdates: Bool
    var outdated: Bool
    var upgradeable: Bool
}

struct MasApp: Identifiable, Hashable {
    var id: String
    var appId: String
    var name: String
    var installedVersion: String
    var currentVersion: String
    var outdated: Bool
    var upgradeable: Bool
}

struct ApplicationsScan {
    var source: String
    var ok: Bool
    var error: String
    var items: [AppItem]
}

struct BrewScan {
    var available: Bool
    var path: String
    var prefix: String
    var version: String
    var error: String
    var includeGreedy: Bool
    var formulae: [BrewPackage]
    var casks: [BrewPackage]

    var outdatedCount: Int {
        formulae.filter(\.outdated).count + casks.filter(\.outdated).count
    }
}

struct MasScan {
    var available: Bool
    var path: String
    var error: String
    var apps: [MasApp]

    var outdatedCount: Int {
        apps.filter(\.outdated).count
    }
}

struct ScanSummary {
    var applications: Int
    var brewFormulae: Int
    var brewCasks: Int
    var masApps: Int
    var outdated: Int
    var actionable: Int
    var scanMs: Int
}

struct ScanResult {
    var scannedAt: Date
    var includeGreedy: Bool
    var summary: ScanSummary
    var applications: ApplicationsScan
    var brew: BrewScan
    var mas: MasScan
}

enum UpdatablePackage: Identifiable, Hashable {
    case brew(BrewPackage)
    case mas(MasApp)

    var id: String {
        switch self {
        case .brew(let package): return package.id
        case .mas(let app): return app.id
        }
    }

    var name: String {
        switch self {
        case .brew(let package): return package.name
        case .mas(let app): return app.name
        }
    }

    var source: String {
        switch self {
        case .brew(let package): return package.kind == "cask" ? "Brew Cask" : "Brew Formula"
        case .mas: return "Mac App Store"
        }
    }

    var installedVersion: String {
        switch self {
        case .brew(let package): return package.installedVersion
        case .mas(let app): return app.installedVersion
        }
    }

    var currentVersion: String {
        switch self {
        case .brew(let package): return package.currentVersion
        case .mas(let app): return app.currentVersion
        }
    }

    var upgradeable: Bool {
        switch self {
        case .brew(let package): return package.upgradeable
        case .mas(let app): return app.upgradeable
        }
    }

    var outdated: Bool {
        switch self {
        case .brew(let package): return package.outdated
        case .mas(let app): return app.outdated
        }
    }

    var isPinned: Bool {
        if case .brew(let package) = self {
            return package.pinned
        }
        return false
    }

    var autoUpdates: Bool {
        if case .brew(let package) = self {
            return package.autoUpdates
        }
        return false
    }
}

struct UpgradeCommand: Hashable {
    var executable: String
    var arguments: [String]
    var display: String
}

struct UpgradeStep: Hashable {
    var command: UpgradeCommand
    var packageID: String?
    var packageName: String?
}

struct PackageUpgradeProgress: Hashable {
    var packageID: String
    var packageName: String
    var status: PackageUpgradeStatus
    var detail: String
    var failureSummary = ""
    var recoverySuggestion = ""
    var copyText = ""
    var updatedAt = Date()
}

struct LogLine: Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var stream: String
    var text: String
}

struct UpgradeJob: Identifiable, Hashable {
    var id = UUID()
    var label: String
    var status: JobStatus = .queued
    var createdAt = Date()
    var startedAt: Date?
    var finishedAt: Date?
    var exitCode: Int32?
    var commands: [String]
    var log: [LogLine] = []
}

struct JobNotice: Hashable {
    var title: String
    var detail: String
    var symbol: String
    var isFailure: Bool
}

struct UpgradeProgress: Hashable {
    var completed: Int
    var total: Int
    var failed: Int
    var currentPackage: String?

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var isRunning: Bool {
        completed < total
    }
}
