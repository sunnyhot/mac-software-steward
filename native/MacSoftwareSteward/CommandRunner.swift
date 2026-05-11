import Foundation

struct CommandResult {
    var ok: Bool
    var code: Int32
    var stdout: String
    var stderr: String
}

struct StreamingCommandResult {
    var code: Int32
    var recentOutput: String
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

    static func run(_ executable: String, arguments: [String], timeout: TimeInterval = 60) async -> CommandResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            let output = LockedOutput()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = processEnvironment()
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

            let finish: (Int32) -> Void = { code in
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
                    stderr: finalErr
                ))
            }

            process.terminationHandler = { finishedProcess in
                finish(finishedProcess.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                finish(-1)
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
        onOutput: @escaping @Sendable (String, String) -> Void
    ) async -> StreamingCommandResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            let gate = FinishGate()
            let recentOutput = LockedRecentOutput()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = processEnvironment()
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
                    recentOutput: recentOutput.text()
                ))
            }

            do {
                try process.run()
            } catch {
                onOutput("stderr", error.localizedDescription)
                recentOutput.append(stream: "stderr", text: error.localizedDescription)
                continuation.resume(returning: StreamingCommandResult(
                    code: -1,
                    recentOutput: recentOutput.text()
                ))
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

    private static func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = defaultPath
        environment["LC_ALL"] = "en_US.UTF-8"
        environment["LANG"] = "en_US.UTF-8"
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
