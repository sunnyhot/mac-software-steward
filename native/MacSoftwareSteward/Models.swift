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
    case overview = "维护总览"
    case inbox = "待处理"
    case updates = "可升级"
    case applications = "本机软件"
    case sources = "管理来源"
    case rules = "自动化策略"
    case history = "历史"
    case performance = "性能"
    case jobs = "任务日志"
    case settings = "设置"

    var id: String { rawValue }

    static func visibleTabs(advancedModeEnabled: Bool) -> [AppTab] {
        if advancedModeEnabled {
            return [.overview, .updates, .applications, .rules, .jobs, .settings]
        }
        return [.overview, .applications, .settings]
    }

    var symbol: String {
        switch self {
        case .overview: return "shield.lefthalf.filled"
        case .inbox: return "tray.and.arrow.down"
        case .updates: return "arrow.triangle.2.circlepath"
        case .applications: return "macwindow"
        case .sources: return "tray.full"
        case .rules: return "list.bullet.clipboard"
        case .history: return "clock.arrow.circlepath"
        case .performance: return "speedometer"
        case .settings: return "gearshape"
        case .jobs: return "terminal"
        }
    }

    var usesSearch: Bool {
        switch self {
        case .updates, .applications, .sources:
            return true
        case .overview, .inbox, .rules, .history, .performance, .settings, .jobs:
            return false
        }
    }
}

enum JobStatus: String {
    case queued = "排队"
    case running = "运行中"
    case succeeded = "完成"
    case failed = "失败"
    case cancelled = "已取消"
    case timedOut = "超时"
    case warning = "需确认"
}

enum PackageUpgradeStatus: String, Hashable {
    case queued = "排队"
    case running = "升级中"
    case succeeded = "完成"
    case failed = "失败"
    case cancelled = "已取消"
    case timedOut = "超时"
    case warning = "需确认"
}

enum AppUpdateDetectorKind: String, Codable, Hashable {
    case none
    case sparkle
    case chromeKeystone
    case adobeUpdater
    case jetBrainsToolbox
    case microsoftAutoUpdate
    case unknownUpdater

    var title: String {
        switch self {
        case .none: return "无"
        case .sparkle: return "Sparkle"
        case .chromeKeystone: return "Chrome Keystone"
        case .adobeUpdater: return "Adobe"
        case .jetBrainsToolbox: return "JetBrains"
        case .microsoftAutoUpdate: return "Microsoft"
        case .unknownUpdater: return "内置更新器"
        }
    }
}

enum DetectionConfidence: String, Codable, Hashable {
    case none
    case low
    case medium
    case high
}

enum AppUpdateActionKind: String, Codable, Hashable {
    case openApp
    case openUpdater
    case revealInFinder
    case directReplace
}

struct AppUpdateAction: Codable, Hashable {
    var kind: AppUpdateActionKind
    var title: String
    var systemImage: String
}

struct AppUpdateCapability: Codable, Hashable {
    var detector: AppUpdateDetectorKind
    var confidence: DetectionConfidence
    var feedURLString: String
    var installedVersion: String
    var summary: String
    var actions: [AppUpdateAction] = []
    var diagnostic: String
    var downloadURLString: String?

    static let none = AppUpdateCapability(
        detector: .none,
        confidence: .none,
        feedURLString: "",
        installedVersion: "",
        summary: "",
        actions: [],
        diagnostic: "",
        downloadURLString: nil
    )

    var hasManualAction: Bool {
        detector != .none
    }
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
    var updateCapability: AppUpdateCapability = .none
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
    var manualUpdateOnly: Bool = false
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
    var performance: ScanPerformanceSnapshot = .empty()
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

    var manualUpdateOnly: Bool {
        if case .brew(let package) = self {
            return package.manualUpdateOnly
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

/// 用户可执行的恢复操作类型
enum FailureActionType: String, Hashable {
    case retry          /// 重试升级
    case openLog        /// 查看完整日志
    case quitAndRetry   /// 退出应用后重试
    case reimport       /// 重新导入/覆盖安装
    case cleanup        /// 清理缓存后重试
    case repairPerms    /// 修复权限后重试
    case rescan         /// 重新扫描
    case checkNetwork   /// 检查网络
    case freeDisk       /// 释放磁盘空间
    case retryInTerminal /// 在终端中手动运行
}

enum RecoveryActionKind: String, Codable, Hashable {
    case retryPackage
    case openUpdates
    case openJobs
    case rescan
    case openStorageSettings
    case copyTerminalCommand
}

struct RecoveryAction: Codable, Hashable {
    var kind: RecoveryActionKind
    var title: String
    var systemImage: String
    var allowsAutomaticRepair: Bool = false
}

struct PackageUpgradeProgress: Hashable, Identifiable {
    var packageID: String
    var packageName: String

    var id: String { packageID }
    var status: PackageUpgradeStatus
    var detail: String
    var phaseText = ""
    var failureSummary = ""
    var recoverySuggestion = ""
    var copyText = ""
    var recoveryAction: FailureActionType? = nil
    var lastFailedCommand = ""
    var updatedAt = Date()
    /// 下载进度百分比（0.0 ~ 1.0），nil 表示无法获取
    var downloadFraction: Double? = nil
    /// 下载大小描述（如 "12.3 MB / 45.6 MB"）
    var downloadSizeText: String? = nil
    /// 下载速度描述（如 "2.1 MB/s"）
    var downloadSpeedText: String? = nil
    /// 下载剩余时间描述（如 "剩余 12 分钟"）
    var downloadTimeRemainingText: String? = nil
    /// 自动下载加速状态描述。
    var accelerationStatusText: String? = nil
    /// 当前使用的下载策略描述。
    var accelerationStrategyText: String? = nil
    /// 当前重试次数描述。
    var accelerationAttemptText: String? = nil
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
