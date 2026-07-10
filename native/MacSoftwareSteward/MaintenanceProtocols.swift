import Foundation

// MARK: - Maintenance engine protocol boundaries
//
// 定义后续 Phase 2/3 要实现的协议。本文件只写协议与配套值类型，不写实现。
// 目的是固定执行/校验/恢复/租约的契约边界，让 StewardModel 门面、维护总览页、
// 后台 Agent 都能通过同一套接口与引擎交互。
// 设计依据：docs/superpowers/specs/2026-07-10-unified-maintenance-engine-dashboard-design.md

// MARK: - Execution

/// 单个包在一次执行中的结果。
struct MaintenancePackageOutcome: Hashable {
    var packageID: String
    var packageName: String
    /// 成功 / 失败 / 超时 / 取消 / 未启动（在队列中但被取消阻止启动）。
    var status: MaintenancePackageOutcomeStatus
    /// 失败时的可读摘要；成功时为空。
    var failureSummary: String
    /// 执行的命令展示文本（可复制到终端）。
    var commandDisplay: String

    var isExecuted: Bool {
        switch status {
        case .succeeded, .failed, .timedOut:
            return true
        case .cancelled, .neverStarted:
            return false
        }
    }
}

enum MaintenancePackageOutcomeStatus: String, Hashable {
    case succeeded
    case failed
    case timedOut
    /// 已启动执行后被用户取消。
    case cancelled
    /// 在队列中但被取消阻止启动，与 cancelled 区分。
    case neverStarted
}

/// 一次执行运行的完整结果。
struct MaintenanceExecutionResult: Hashable {
    var runID: UUID
    var trigger: MaintenanceRunTrigger
    /// 按包 ID 索引的逐包结果。
    var outcomes: [MaintenancePackageOutcome]
    /// 运行级别的错误（如租约冲突），区别于包级失败。
    var runLevelError: String?

    var succeededCount: Int { outcomes.filter { $0.status == .succeeded }.count }
    var failedCount: Int { outcomes.filter { $0.status == .failed }.count }
    var timedOutCount: Int { outcomes.filter { $0.status == .timedOut }.count }
    var cancelledCount: Int { outcomes.filter { $0.status == .cancelled }.count }
    var neverStartedCount: Int { outcomes.filter { $0.status == .neverStarted }.count }

    /// 是否有任何包被执行（成功或失败都算）。
    var anyExecuted: Bool { outcomes.contains { $0.isExecuted } }
}

/// 执行器对外暴露的只读快照，供 GUI/总览页展示当前执行状态。
struct MaintenanceExecutionSnapshot: Equatable {
    var isActive: Bool
    var activePackageIDs: [String]
    var queuedPackageIDs: [String]
    /// 当前包级进度（复用现有 PackageUpgradeProgress，保持 UI 兼容）。
    var packageProgresses: [String: PackageUpgradeProgress]
    /// 全局升级进度（已完成/总数）。
    var completedCount: Int
    var totalCount: Int
}

/// 执行器协议。Phase 2 由 MaintenanceExecutor 实现，Phase 1 不提供实现。
protocol MaintenanceExecuting {
    /// 执行计划中的可执行项。
    ///
    /// - Parameters:
    ///   - plan: 统一维护计划。
    ///   - trigger: 触发来源（智能维护 / 详细升级 / 每日巡检）。
    ///   - autoRepairProfile: 自动化配置，控制自动修复策略。
    ///   - inboxStore: 收件箱，用于发布失败恢复条目。
    /// - Returns: 执行结果。租约冲突或扫描失败时 runLevelError 非空。
    func execute(
        plan: MaintenancePlan,
        trigger: MaintenanceRunTrigger,
        autoRepairProfile: AutomationProfile,
        inboxStore: InboxStore?
    ) async -> MaintenanceExecutionResult

    /// 当前执行状态的只读快照。
    var executionSnapshot: MaintenanceExecutionSnapshot { get }

    /// 请求取消当前运行：停止新任务入队，并取消所有活跃命令。
    func cancel() async
}

// MARK: - Verification

/// 单个包的校验结果。
struct MaintenancePackageVerification: Hashable {
    var packageID: String
    /// 命令成功但版本仍 outdated → mismatch；包不在新扫描结果中 → notFound。
    var status: MaintenanceVerificationStatus
    var detail: String
}

enum MaintenanceVerificationStatus: String, Hashable {
    /// 命令成功且版本已确认升级。
    case verified
    /// 命令成功但版本仍 outdated（可能是部分升级或延迟）。
    case mismatch
    /// 包不在重扫结果中（可能已被移除）。
    case notFound
}

/// 校验结果集合。
struct MaintenanceVerificationResult: Hashable {
    /// 按包 ID 索引。
    var verifications: [String: MaintenancePackageVerification]
    var mismatchCount: Int { verifications.values.filter { $0.status == .mismatch }.count }
    var notFoundCount: Int { verifications.values.filter { $0.status == .notFound }.count }
}

/// 校验器协议。Phase 3 由 MaintenanceVerifier 实现。
protocol MaintenanceVerifying {
    /// 对已执行的包集合做重扫后校验。
    ///
    /// - Parameters:
    ///   - executedPackageIDs: 需要校验的包 ID（通常是一次 run 中 succeeded 的包）。
    ///   - scan: 重扫后的最新扫描结果。
    func verify(executedPackageIDs: Set<String>, scan: ScanResult) async -> MaintenanceVerificationResult
}

// MARK: - Recovery

/// 恢复动作协调器协议。Phase 3 由 MaintenanceRecoveryCoordinator 实现。
///
/// 复用现有 RecoveryActionPlanner + UpgradeFailureAnalyzer，输出重试/重扫/看日志/
/// 复制终端命令/开系统设置的恢复动作。自动修复仍由 AutomationProfile.autoRepairPolicy
/// + allowlist 控制（复用 AutoRepairDecider）。
protocol MaintenanceRecovering {
    /// 为某个失败包推导可执行的恢复动作列表。
    func recoveryActions(for progress: PackageUpgradeProgress) -> [RecoveryAction]
}

// MARK: - Lease

/// 一次跨进程维护租约。
struct MaintenanceLease: Hashable {
    var runID: UUID
    var pid: pid_t
    var processStartTime: Date
    var trigger: MaintenanceRunTrigger
    var createdAt: Date
}

/// 租约获取结果。
enum MaintenanceLeaseAcquisition: Hashable {
    /// 成功获取。
    case acquired(MaintenanceLease)
    /// 已有活跃租约持有。
    case conflict(existingLease: MaintenanceLease)
}

/// 跨进程维护租约协议。Phase 1 由 MaintenanceRunLease 实现（T4）。
///
/// GUI 应用与后台 Agent 共用同一套租约，确保同一时刻只有一个维护运行。
protocol MaintenanceRunLeasing {
    /// 尝试获取租约。
    func acquire(trigger: MaintenanceRunTrigger) -> MaintenanceLeaseAcquisition
    /// 释放租约（终态完成或有序取消时调用）。
    func release(_ lease: MaintenanceLease)
    /// 查询当前活跃租约（若存在）。
    func currentLease() -> MaintenanceLease?
}
