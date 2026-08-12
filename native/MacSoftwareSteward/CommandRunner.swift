import Foundation

struct CommandResult {
    var ok: Bool
    var code: Int32
    var stdout: String
    var stderr: String
    /// Foundation 报告的进程终止原因。macOS 上被信号杀死时 `code` 是原始信号号（如 SIGTERM=15），
    /// 而非 shell 的 128+信号号；因此判定信号死亡必须看 `terminationReason`，单看 `code` 不可靠。
    var terminationReason: Process.TerminationReason = .exit

    /// Whether the process was terminated by a signal (crash or timeout-kill)
    var wasSignaled: Bool {
        // `code < 0` 是本工具在进程启动失败时自造的哨兵值（见 `run()` 的 catch 分支）。
        terminationReason == .uncaughtSignal || code < 0
    }

    /// Human-readable signal description if the process was killed by a signal
    var signalDescription: String? {
        if code < 0 {
            return "进程启动失败"
        }
        guard terminationReason == .uncaughtSignal else { return nil }
        // 被信号杀死时 `code` 即原始信号号（1–31）。
        switch code {
        case 1: return "进程被挂起 (SIGHUP)"
        case 2: return "进程被中断 (SIGINT)"
        case 6: return "进程异常中止 (SIGABRT)"
        case 9: return "进程被强杀 (SIGKILL)"
        case 11: return "进程段错误崩溃 (SIGSEGV)"
        case 13: return "管道破裂 (SIGPIPE)"
        case 15: return "进程被终止 (SIGTERM)"
        default: return "进程被信号终止 (信号 \(code))"
        }
    }
}

struct StreamingCommandResult {
    var code: Int32
    var recentOutput: String
    var terminationReason: CommandTerminationReason = .exited

    /// Whether the process was terminated by a signal (crash)
    var wasSignaled: Bool {
        code < 0 || code > 128
    }
    /// Human-readable signal description if the process was killed by a signal
    var signalDescription: String? {
        if code < 0 {
            // Process was terminated by us (timeout)
            return "进程超时被终止"
        }
        // On Unix, exit code 128+signal means killed by signal
        let signalNum = code - 128
        if signalNum > 0 && signalNum < 32 {
            switch signalNum {
            case 1: return "进程被挂起 (SIGHUP)"
            case 2: return "进程被中断 (SIGINT)"
            case 6: return "进程异常中止 (SIGABRT)"
            case 9: return "进程被强杀 (SIGKILL)"
            case 11: return "进程段错误崩溃 (SIGSEGV)"
            case 13: return "管道破裂 (SIGPIPE)"
            case 15: return "进程被终止 (SIGTERM)"
            default: return "进程被信号终止 (信号 \(signalNum))"
            }
        }
        return nil
    }
}

enum CommandTerminationReason: String {
    case exited
    case timedOut
    case cancelled
    case launchFailed
}

final class CommandCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

enum CommandRunner {
    static let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    static func commandPath(_ command: String) async -> String? {
        let fallbacks = [
            "/opt/homebrew/bin/\(command)",
            "/usr/local/bin/\(command)",
            "/usr/bin/\(command)",
            "/bin/\(command)",
            "/usr/sbin/\(command)",
            "/sbin/\(command)"
        ]

        for fallback in fallbacks where FileManager.default.isExecutableFile(atPath: fallback) {
            return fallback
        }

        let result = await run("/usr/bin/env", arguments: ["which", command], timeout: 5)
        let found = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.ok && !found.isEmpty ? found : nil
    }

    static func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval = 60,
        environmentOverlay: [String: String] = [:]
    ) async -> CommandResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            let output = LockedOutput()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = processEnvironment(overlay: environmentOverlay)
            process.standardOutput = stdout
            process.standardError = stderr

            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                output.appendStdout(data)
            }

            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                output.appendStderr(data)
            }

            let finish: (Int32, Process.TerminationReason) -> Void = { code, reason in
                guard output.markFinished() else { return }

                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil

                let remainingOut = stdout.fileHandleForReading.readDataToEndOfFile()
                let remainingErr = stderr.fileHandleForReading.readDataToEndOfFile()
                output.appendStdout(remainingOut)
                output.appendStderr(remainingErr)
                let (finalOut, finalErr) = output.strings()

                continuation.resume(returning: CommandResult(
                    ok: code == 0,
                    code: code,
                    stdout: finalOut,
                    stderr: finalErr,
                    terminationReason: reason
                ))
            }

            process.terminationHandler = { finishedProcess in
                finish(finishedProcess.terminationStatus, finishedProcess.terminationReason)
            }

            do {
                try process.run()
            } catch {
                finish(-1, .exit)
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    if process.isRunning {
                        process.interrupt()
                    }
                }
            }
        }
    }

    static func runStreaming(
        _ executable: String,
        arguments: [String],
        onOutput: @escaping @Sendable (String, String) -> Void
    ) async -> Int32 {
        let result = await runStreamingDetailed(executable, arguments: arguments, onOutput: onOutput)
        return result.code
    }

    static func runStreamingDetailed(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval = 7200,
        cancellationToken: CommandCancellationToken? = nil,
        environmentOverlay: [String: String] = [:],
        onOutput: @escaping @Sendable (String, String) -> Void
    ) async -> StreamingCommandResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            let gate = FinishGate()
            let recentOutput = LockedRecentOutput()
            let terminationReason = LockedTerminationReason()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = processEnvironment(overlay: environmentOverlay)
            process.standardOutput = stdout
            process.standardError = stderr

            stdout.fileHandleForReading.readabilityHandler = { handle in
                emit(handle.availableData, stream: "stdout", recentOutput: recentOutput, onOutput: onOutput)
            }
            stderr.fileHandleForReading.readabilityHandler = { handle in
                emit(handle.availableData, stream: "stderr", recentOutput: recentOutput, onOutput: onOutput)
            }

            process.terminationHandler = { finishedProcess in
                guard gate.close() else { return }
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                emit(stdout.fileHandleForReading.readDataToEndOfFile(), stream: "stdout", recentOutput: recentOutput, onOutput: onOutput)
                emit(stderr.fileHandleForReading.readDataToEndOfFile(), stream: "stderr", recentOutput: recentOutput, onOutput: onOutput)
                continuation.resume(returning: StreamingCommandResult(
                    code: finishedProcess.terminationStatus,
                    recentOutput: recentOutput.text(),
                    terminationReason: terminationReason.value()
                ))
            }

            let requestTermination: @Sendable (CommandTerminationReason) -> Void = { reason in
                guard process.isRunning else { return }
                terminationReason.set(reason)
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    if process.isRunning {
                        process.interrupt()
                    }
                }
            }

            do {
                try process.run()
            } catch {
                guard gate.close() else { return }
                onOutput("stderr", error.localizedDescription)
                recentOutput.append(stream: "stderr", text: error.localizedDescription)
                continuation.resume(returning: StreamingCommandResult(
                    code: -1,
                    recentOutput: recentOutput.text(),
                    terminationReason: .launchFailed
                ))
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                requestTermination(.timedOut)
            }

            if let cancellationToken {
                DispatchQueue.global().async {
                    while process.isRunning {
                        if cancellationToken.isCancelled {
                            requestTermination(.cancelled)
                            return
                        }
                        Thread.sleep(forTimeInterval: 0.1)
                    }
                }
            }
        }
    }

    private static func emit(
        _ data: Data,
        stream: String,
        onOutput: @escaping @Sendable (String, String) -> Void
    ) {
        emit(data, stream: stream, recentOutput: nil, onOutput: onOutput)
    }

    private static func emit(
        _ data: Data,
        stream: String,
        recentOutput: LockedRecentOutput?,
        onOutput: @escaping @Sendable (String, String) -> Void
    ) {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
        for line in text.split(whereSeparator: \.isNewline) {
            let lineText = String(line)
            recentOutput?.append(stream: stream, text: lineText)
            onOutput(stream, lineText)
        }
    }

    private static func processEnvironment(overlay: [String: String] = [:]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = defaultPath
        environment["LC_ALL"] = "en_US.UTF-8"
        environment["LANG"] = "en_US.UTF-8"
        for (key, value) in overlay {
            environment[key] = value
        }
        return environment
    }
}

private final class LockedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var finished = false

    func appendStdout(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        stdout.append(data)
        lock.unlock()
    }

    func appendStderr(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        stderr.append(data)
        lock.unlock()
    }

    func markFinished() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        return true
    }

    func strings() -> (String, String) {
        lock.lock()
        defer { lock.unlock() }
        return (
            String(data: stdout, encoding: .utf8) ?? "",
            String(data: stderr, encoding: .utf8) ?? ""
        )
    }
}

private final class FinishGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isClosed = false

    func close() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return false }
        isClosed = true
        return true
    }
}

private final class LockedTerminationReason: @unchecked Sendable {
    private let lock = NSLock()
    private var reason: CommandTerminationReason = .exited

    func set(_ next: CommandTerminationReason) {
        lock.lock()
        if reason == .exited {
            reason = next
        }
        lock.unlock()
    }

    func value() -> CommandTerminationReason {
        lock.lock()
        defer { lock.unlock() }
        return reason
    }
}

private final class LockedRecentOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private let limit = 40

    func append(stream: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        lines.append("[\(stream)] \(trimmed)")
        if lines.count > limit {
            lines.removeFirst(lines.count - limit)
        }
        lock.unlock()
    }

    func text() -> String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}
