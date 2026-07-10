import Foundation

// MARK: - Workflow state machine
//
// 纯 Foundation 值类型，描述一次维护运行（扫描→评估→执行→校验→报告）的合法状态与转换。
// 不依赖 SwiftUI/AppKit/Combine，主应用与后台 Agent 均可编译复用。
// 设计依据：docs/superpowers/specs/2026-07-10-unified-maintenance-engine-dashboard-design.md

/// 维护运行的触发来源。
enum MaintenanceRunTrigger: String, Codable, Hashable {
    case smartMaintenance
    case detailedUpgrade
    case dailyInspection
}

/// 一次运行的最终结果摘要。计数由执行器在运行结束时填充。
struct MaintenanceRunSummary: Codable, Equatable {
    /// 计划阶段分类计数。
    var automaticCount = 0
    var confirmationCount = 0
    var reminderCount = 0
    var blockedCount = 0

    /// 执行结果计数。
    var succeededCount = 0
    var failedCount = 0
    var cancelledCount = 0
    var timedOutCount = 0
    /// 在队列中但被取消阻止启动的包，与已启动后取消的包区分。
    var neverStartedCount = 0

    /// 是否有任何一个包真正被执行（成功或失败都算）。
    var anyExecuted: Bool {
        succeededCount > 0 || failedCount > 0 || timedOutCount > 0
    }
}

/// 运行的终态分类，用于区分成功、部分成功、取消、失败和中断。
enum MaintenanceRunTerminalStatus: String, Codable, Hashable {
    /// 所有可执行项都成功且校验通过。
    case completed
    /// 部分包成功，但存在失败、超时或校验不一致。
    case partialSuccess
    /// 用户取消。
    case cancelled
    /// workflow 级失败（如扫描彻底失败），区别于包级失败。
    case failed
    /// 因崩溃或强退后遗留的 stale 租约，被标记为中断。
    case interrupted
}

/// 一次运行结束后的完整结果。
struct MaintenanceRunOutcome: Codable, Equatable {
    var runID: UUID
    var trigger: MaintenanceRunTrigger
    var startedAt: Date
    var finishedAt: Date
    var terminalStatus: MaintenanceRunTerminalStatus
    var summary: MaintenanceRunSummary

    init(
        runID: UUID = UUID(),
        trigger: MaintenanceRunTrigger,
        startedAt: Date = Date(),
        finishedAt: Date = Date(),
        terminalStatus: MaintenanceRunTerminalStatus,
        summary: MaintenanceRunSummary = MaintenanceRunSummary()
    ) {
        self.runID = runID
        self.trigger = trigger
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.terminalStatus = terminalStatus
        self.summary = summary
    }
}

/// 维护工作流的当前阶段。
///
/// 包级失败是 run 内的 outcome，不会把整条 workflow 推到 `.failed`；
/// 只有 workflow 级错误（如扫描彻底失败、租约冲突）才进入 `.failed`。
enum MaintenanceWorkflowPhase: Equatable {
    case idle
    case scanning
    case assessing
    case executingAutomatic
    case awaitingConfirmation
    case executingConfirmed
    case verifying
    case completed(MaintenanceRunOutcome)
    case cancelled(MaintenanceRunOutcome)
    case failed(String)

    /// 是否处于任何活跃（非 idle、非终态）阶段。
    var isActive: Bool {
        switch self {
        case .idle, .completed, .cancelled, .failed:
            return false
        default:
            return true
        }
    }

    /// 是否是终态（不会再发生转换）。
    var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .failed:
            return true
        default:
            return false
        }
    }
}

/// 驱动阶段转换的事件。
enum MaintenanceWorkflowEvent: Equatable {
    /// 进入扫描。
    case scanStarted
    /// 扫描完成，可以评估。
    case scanCompleted
    /// 评估完成，并携带计划分类计数，用于决定是否跳过空阶段。
    case assessmentCompleted(hasAutomatic: Bool, hasConfirmation: Bool)
    /// 自动组执行完成。
    case automaticExecutionCompleted
    /// 确认阶段结束（用户已处理待确认项：执行选中的、或推迟全部）。
    case confirmationResolved
    /// 升级页直接启动确认项执行。
    case confirmedExecutionStarted
    /// 校验完成。
    case verificationCompleted
    /// 用户请求取消。
    case cancelRequested
    /// workflow 级失败。
    case workflowFailed(String)

    static func == (lhs: MaintenanceWorkflowEvent, rhs: MaintenanceWorkflowEvent) -> Bool {
        switch (lhs, rhs) {
        case (.scanStarted, .scanStarted),
             (.scanCompleted, .scanCompleted),
             (.automaticExecutionCompleted, .automaticExecutionCompleted),
             (.confirmationResolved, .confirmationResolved),
             (.confirmedExecutionStarted, .confirmedExecutionStarted),
             (.verificationCompleted, .verificationCompleted),
             (.cancelRequested, .cancelRequested):
            return true
        case let (.assessmentCompleted(a1, c1), .assessmentCompleted(a2, c2)):
            return a1 == a2 && c1 == c2
        case let (.workflowFailed(m1), .workflowFailed(m2)):
            return m1 == m2
        default:
            return false
        }
    }
}

/// 无状态的状态机转换规则。
///
/// 所有合法转换在此编码；非法组合返回 nil。调用方据此决定是否推进。
/// 跳过规则：
/// - `awaitingConfirmation` 在无待确认项时跳过；
/// - `executingAutomatic` 在无 automatic 项时跳过。
///
/// 终态（completed/cancelled）需要携带一次运行的结果。核心不知道触发器与摘要，
/// 因此终态转换由调用方通过 `complete(trigger:summary:)` / `cancel(trigger:summary:)`
/// 显式构造；`transition` 只负责非终态推进与终态合法性校验。
enum MaintenanceWorkflowCore {
    /// 尝试用事件推进阶段。返回新阶段；若转换非法或终态不可推进则返回 nil。
    ///
    /// 对于需要结果的终态（completed/cancelled），本方法返回一个占位 outcome
    ///（trigger 用占位值、summary 为空），仅用于判定"该转换是否合法"以及测试状态机拓扑。
    /// 真正的执行器应使用 `complete(cancelled:)` 构造携带真实 trigger/summary 的终态。
    static func transition(from phase: MaintenanceWorkflowPhase, by event: MaintenanceWorkflowEvent) -> MaintenanceWorkflowPhase? {
        switch (phase, event) {
        // 终态不再转换。
        case (.completed, _), (.cancelled, _), (.failed, _):
            return nil

        // idle / 任何活跃态都允许开始扫描（重新触发）和取消、失败。
        case (.idle, .scanStarted):
            return .scanning
        case (.idle, .cancelRequested):
            return cancelledOutcome()

        case (.scanning, .scanCompleted):
            return .assessing
        case (.scanning, .cancelRequested):
            return cancelledOutcome()
        case (.scanning, .workflowFailed(let message)):
            return .failed(message)

        case (.assessing, .assessmentCompleted(let hasAutomatic, let hasConfirmation)):
            if hasAutomatic {
                return .executingAutomatic
            } else if hasConfirmation {
                return .awaitingConfirmation
            } else {
                // 既无自动项也无确认项：没有需要执行的，直接进入校验（会立即完成）。
                return .verifying
            }
        case (.assessing, .cancelRequested):
            return cancelledOutcome()
        case (.assessing, .workflowFailed(let message)):
            return .failed(message)

        case (.executingAutomatic, .automaticExecutionCompleted):
            // 自动组跑完后，若有待确认项则进入确认阶段，否则直接校验。
            // 注意：这里无法再知道是否有确认项，交由调用方在 automaticExecutionCompleted 前判断；
            // 默认推进到校验，确认阶段由更上层按计划重新决定。
            return .verifying
        case (.executingAutomatic, .cancelRequested):
            return cancelledOutcome()
        case (.executingAutomatic, .workflowFailed(let message)):
            return .failed(message)

        case (.awaitingConfirmation, .confirmationResolved):
            return .verifying
        case (.awaitingConfirmation, .confirmedExecutionStarted):
            return .executingConfirmed
        case (.awaitingConfirmation, .cancelRequested):
            return cancelledOutcome()

        case (.executingConfirmed, .automaticExecutionCompleted):
            return .verifying
        case (.executingConfirmed, .verificationCompleted):
            return .verifying
        case (.executingConfirmed, .cancelRequested):
            return cancelledOutcome()
        case (.executingConfirmed, .workflowFailed(let message)):
            return .failed(message)

        case (.verifying, .verificationCompleted):
            return completedOutcome()

        default:
            return nil
        }
    }

    /// 判定从 `phase` 出发，`event` 是否是合法转换。
    static func canTransition(from phase: MaintenanceWorkflowPhase, by event: MaintenanceWorkflowEvent) -> Bool {
        transition(from: phase, by: event) != nil
    }

    /// 构造一个 completed 终态。真正的 trigger/summary 由调用方提供。
    static func complete(trigger: MaintenanceRunTrigger, summary: MaintenanceRunSummary = MaintenanceRunSummary(), startedAt: Date = Date()) -> MaintenanceWorkflowPhase {
        .completed(MaintenanceRunOutcome(trigger: trigger, startedAt: startedAt, terminalStatus: .completed, summary: summary))
    }

    /// 构造一个 cancelled 终态。
    static func cancel(trigger: MaintenanceRunTrigger, summary: MaintenanceRunSummary = MaintenanceRunSummary(), startedAt: Date = Date()) -> MaintenanceWorkflowPhase {
        .cancelled(MaintenanceRunOutcome(trigger: trigger, startedAt: startedAt, terminalStatus: .cancelled, summary: summary))
    }

    /// 测试与拓扑判定用的占位终态。trigger 用 smartMaintenance、summary 为空。
    private static func completedOutcome() -> MaintenanceWorkflowPhase {
        .completed(MaintenanceRunOutcome(trigger: .smartMaintenance, terminalStatus: .completed))
    }

    private static func cancelledOutcome() -> MaintenanceWorkflowPhase {
        .cancelled(MaintenanceRunOutcome(trigger: .smartMaintenance, terminalStatus: .cancelled))
    }
}
