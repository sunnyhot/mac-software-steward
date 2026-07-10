import Foundation

@main
struct MaintenanceWorkflowStateTest {
    static func main() {
        // MARK: 合法转换推进
        assertEqual(MaintenanceWorkflowCore.transition(from: .idle, by: .scanStarted), .scanning, "idle → scanning")
        assertEqual(MaintenanceWorkflowCore.transition(from: .scanning, by: .scanCompleted), .assessing, "scanning → assessing")

        // 评估后按计划分流
        assertEqual(
            MaintenanceWorkflowCore.transition(from: .assessing, by: .assessmentCompleted(hasAutomatic: true, hasConfirmation: true)),
            .executingAutomatic,
            "有自动项 → executingAutomatic"
        )
        assertEqual(
            MaintenanceWorkflowCore.transition(from: .assessing, by: .assessmentCompleted(hasAutomatic: false, hasConfirmation: true)),
            .awaitingConfirmation,
            "无自动项有确认项 → awaitingConfirmation"
        )
        assertEqual(
            MaintenanceWorkflowCore.transition(from: .assessing, by: .assessmentCompleted(hasAutomatic: false, hasConfirmation: false)),
            .verifying,
            "无自动无确认 → 直接 verifying（跳过执行）"
        )

        // 自动执行完成后进入校验
        assertEqual(MaintenanceWorkflowCore.transition(from: .executingAutomatic, by: .automaticExecutionCompleted), .verifying, "executingAutomatic → verifying")

        // 确认阶段
        assertEqual(MaintenanceWorkflowCore.transition(from: .awaitingConfirmation, by: .confirmationResolved), .verifying, "awaitingConfirmation → verifying")
        assertEqual(MaintenanceWorkflowCore.transition(from: .awaitingConfirmation, by: .confirmedExecutionStarted), .executingConfirmed, "awaitingConfirmation → executingConfirmed")

        // 确认执行完成后校验
        assertEqual(MaintenanceWorkflowCore.transition(from: .executingConfirmed, by: .automaticExecutionCompleted), .verifying, "executingConfirmed → verifying")

        // 校验完成 → 终态 completed
        let completedResult = MaintenanceWorkflowCore.transition(from: .verifying, by: .verificationCompleted)
        guard case .completed(let completedOutcome) = completedResult else {
            preconditionFailure("verifying → completed，得到 \(String(describing: completedResult))")
        }
        assertEqual(completedOutcome.terminalStatus, .completed, "completed outcome 终态正确")

        // MARK: 终态不可再转换
        assertNil(MaintenanceWorkflowCore.transition(from: .completed(MaintenanceRunOutcome(trigger: .smartMaintenance, terminalStatus: .completed)), by: .scanStarted), "completed 不可再转换")
        assertNil(MaintenanceWorkflowCore.transition(from: .cancelled(MaintenanceRunOutcome(trigger: .smartMaintenance, terminalStatus: .cancelled)), by: .scanStarted), "cancelled 不可再转换")
        assertNil(MaintenanceWorkflowCore.transition(from: .failed("扫描失败"), by: .scanStarted), "failed 不可再转换")

        // MARK: 非法转换返回 nil
        assertNil(MaintenanceWorkflowCore.transition(from: .idle, by: .scanCompleted), "idle 不能直接 scanCompleted")
        assertNil(MaintenanceWorkflowCore.transition(from: .idle, by: .verificationCompleted), "idle 不能直接校验")
        assertNil(MaintenanceWorkflowCore.transition(from: .scanning, by: .automaticExecutionCompleted), "scanning 不能直接执行完成")
        assertNil(MaintenanceWorkflowCore.transition(from: .verifying, by: .scanStarted), "verifying 不能回到 scanning")

        // MARK: 任意活跃态可取消
        let cancelledFromScanning = MaintenanceWorkflowCore.transition(from: .scanning, by: .cancelRequested)
        guard case .cancelled(let cancelledOutcome) = cancelledFromScanning else {
            preconditionFailure("scanning → cancelled，得到 \(String(describing: cancelledFromScanning))")
        }
        assertEqual(cancelledOutcome.terminalStatus, .cancelled, "取消终态正确")

        let cancelledFromAssessing = MaintenanceWorkflowCore.transition(from: .assessing, by: .cancelRequested)
        guard case .cancelled = cancelledFromAssessing else {
            preconditionFailure("assessing → cancelled，得到 \(String(describing: cancelledFromAssessing))")
        }

        let cancelledFromExecuting = MaintenanceWorkflowCore.transition(from: .executingAutomatic, by: .cancelRequested)
        guard case .cancelled = cancelledFromExecuting else {
            preconditionFailure("executingAutomatic → cancelled，得到 \(String(describing: cancelledFromExecuting))")
        }

        let cancelledFromConfirming = MaintenanceWorkflowCore.transition(from: .awaitingConfirmation, by: .cancelRequested)
        guard case .cancelled = cancelledFromConfirming else {
            preconditionFailure("awaitingConfirmation → cancelled，得到 \(String(describing: cancelledFromConfirming))")
        }

        // idle 取消（用户在尚未开始时点取消）也应是合法的 cancelled 终态。
        let cancelledFromIdle = MaintenanceWorkflowCore.transition(from: .idle, by: .cancelRequested)
        guard case .cancelled = cancelledFromIdle else {
            preconditionFailure("idle → cancelled，得到 \(String(describing: cancelledFromIdle))")
        }

        // MARK: workflow 级失败
        let failedResult = MaintenanceWorkflowCore.transition(from: .scanning, by: .workflowFailed("扫描彻底失败"))
        guard case .failed(let message) = failedResult else {
            preconditionFailure("scanning → failed，得到 \(String(describing: failedResult))")
        }
        assertEqual(message, "扫描彻底失败", "failed 携带错误信息")

        // MARK: 活跃态与终态判定
        precondition(MaintenanceWorkflowPhase.idle.isActive == false, "idle 非活跃")
        precondition(MaintenanceWorkflowPhase.scanning.isActive, "scanning 活跃")
        precondition(MaintenanceWorkflowPhase.executingAutomatic.isActive, "executingAutomatic 活跃")
        precondition(MaintenanceWorkflowPhase.awaitingConfirmation.isActive, "awaitingConfirmation 活跃")
        precondition(MaintenanceWorkflowPhase.completed(MaintenanceRunOutcome(trigger: .smartMaintenance, terminalStatus: .completed)).isActive == false, "completed 非活跃")

        precondition(MaintenanceWorkflowPhase.idle.isTerminal == false, "idle 非终态")
        precondition(MaintenanceWorkflowPhase.scanning.isTerminal == false, "scanning 非终态")
        precondition(MaintenanceWorkflowPhase.completed(MaintenanceRunOutcome(trigger: .smartMaintenance, terminalStatus: .completed)).isTerminal, "completed 终态")
        precondition(MaintenanceWorkflowPhase.cancelled(MaintenanceRunOutcome(trigger: .smartMaintenance, terminalStatus: .cancelled)).isTerminal, "cancelled 终态")
        precondition(MaintenanceWorkflowPhase.failed("x").isTerminal, "failed 终态")

        // MARK: MaintenanceRunSummary
        var empty = MaintenanceRunSummary()
        precondition(empty.anyExecuted == false, "空 summary 不应有执行")
        empty.succeededCount = 1
        precondition(empty.anyExecuted, "有成功项应算已执行")
        empty.succeededCount = 0
        empty.failedCount = 1
        precondition(empty.anyExecuted, "有失败项应算已执行")

        print("MaintenanceWorkflowStateTest passed")
    }

    // MARK: - Assertions

    private static func assertEqual(_ actual: MaintenanceWorkflowPhase?, _ expected: MaintenanceWorkflowPhase, _ message: String) {
        guard let actual else {
            preconditionFailure("\(message)：期望 \(expected)，得到 nil")
        }
        precondition(actual == expected, "\(message)：期望 \(expected)，得到 \(actual)")
    }

    private static func assertEqual(_ actual: MaintenanceRunTerminalStatus, _ expected: MaintenanceRunTerminalStatus, _ message: String) {
        precondition(actual == expected, "\(message)：期望 \(expected.rawValue)，得到 \(actual.rawValue)")
    }

    private static func assertEqual(_ actual: String, _ expected: String, _ message: String) {
        precondition(actual == expected, "\(message)：期望 \(expected)，得到 \(actual)")
    }

    private static func assertNil(_ value: MaintenanceWorkflowPhase?, _ message: String) {
        precondition(value == nil, "\(message)：期望 nil，得到 \(String(describing: value))")
    }
}
