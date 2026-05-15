import Foundation
import os.log

/// Process execution manager with support for sudo operations
actor ProcessManager {
    private let logger = Logger(subsystem: "com.mole.process", category: "ProcessManager")

    /// Execute a command without sudo
    func execute(command: String, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            let resumeOnce: (ProcessError?) -> Void = { error in
                guard !hasResumed else { return }
                hasResumed = true

                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }

            Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = arguments

                let outputPipe = Pipe()
                let errorPipe = Pipe()

                process.standardOutput = outputPipe
                process.standardError = errorPipe

                self.logger.debug("Executing command: \(command) with arguments: \(arguments)")

                do {
                    try process.run()

                    // Use async wait to avoid blocking actor
                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        self.logger.error("Command failed with exit code \(process.terminationStatus): \(errorMessage)")
                        resumeOnce(.commandFailed(exitCode: process.terminationStatus, message: errorMessage))
                    } else {
                        self.logger.debug("Command executed successfully")
                        resumeOnce(nil)
                    }
                } catch {
                    self.logger.error("Failed to execute command: \(error.localizedDescription)")
                    resumeOnce(.executionFailed(message: error.localizedDescription))
                }
            }
        }
    }

    /// Execute a command with sudo privileges
    func executeWithSudo(command: String, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            let resumeOnce: (ProcessError?) -> Void = { error in
                guard !hasResumed else { return }
                hasResumed = true

                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }

            Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                process.arguments = ["-n", command] + arguments

                let outputPipe = Pipe()
                let errorPipe = Pipe()

                process.standardOutput = outputPipe
                process.standardError = errorPipe

                self.logger.debug("Executing sudo command: \(command) with arguments: \(arguments)")

                do {
                    try process.run()

                    // Use async wait to avoid blocking actor
                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        self.logger.error("Sudo command failed with exit code \(process.terminationStatus): \(errorMessage)")
                        resumeOnce(.sudoFailed(exitCode: process.terminationStatus, message: errorMessage))
                    } else {
                        self.logger.debug("Sudo command executed successfully")
                        resumeOnce(nil)
                    }
                } catch {
                    self.logger.error("Failed to execute sudo command: \(error.localizedDescription)")
                    resumeOnce(.executionFailed(message: error.localizedDescription))
                }
            }
        }
    }

    /// Execute a command and return its output
    func executeWithOutput(command: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            let resumeOnce: (Result<String, ProcessError>) -> Void = { result in
                guard !hasResumed else { return }
                hasResumed = true

                switch result {
                case .success(let output):
                    continuation.resume(returning: output)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = arguments

                let outputPipe = Pipe()
                let errorPipe = Pipe()

                process.standardOutput = outputPipe
                process.standardError = errorPipe

                self.logger.debug("Executing command with output: \(command) with arguments: \(arguments)")

                do {
                    try process.run()

                    // Use async wait to avoid blocking actor
                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        self.logger.error("Command failed with exit code \(process.terminationStatus): \(errorMessage)")
                        resumeOnce(.failure(.commandFailed(exitCode: process.terminationStatus, message: errorMessage)))
                    } else {
                        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(data: outputData, encoding: .utf8) ?? ""
                        self.logger.debug("Command executed successfully, output length: \(output.count)")
                        resumeOnce(.success(output))
                    }
                } catch {
                    self.logger.error("Failed to execute command: \(error.localizedDescription)")
                    resumeOnce(.failure(.executionFailed(message: error.localizedDescription)))
                }
            }
        }
    }

    /// Execute a command with sudo and return its output
    func executeWithSudoOutput(command: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            let resumeOnce: (Result<String, ProcessError>) -> Void = { result in
                guard !hasResumed else { return }
                hasResumed = true

                switch result {
                case .success(let output):
                    continuation.resume(returning: output)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                process.arguments = ["-n", command] + arguments

                let outputPipe = Pipe()
                let errorPipe = Pipe()

                process.standardOutput = outputPipe
                process.standardError = errorPipe

                self.logger.debug("Executing sudo command with output: \(command) with arguments: \(arguments)")

                do {
                    try process.run()

                    // Use async wait to avoid blocking actor
                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        self.logger.error("Sudo command failed with exit code \(process.terminationStatus): \(errorMessage)")
                        resumeOnce(.failure(.sudoFailed(exitCode: process.terminationStatus, message: errorMessage)))
                    } else {
                        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(data: outputData, encoding: .utf8) ?? ""
                        self.logger.debug("Sudo command executed successfully, output length: \(output.count)")
                        resumeOnce(.success(output))
                    }
                } catch {
                    self.logger.error("Failed to execute sudo command: \(error.localizedDescription)")
                    resumeOnce(.failure(.executionFailed(message: error.localizedDescription)))
                }
            }
        }
    }
}

/// Process execution errors
enum ProcessError: LocalizedError {
    case executionFailed(message: String)
    case commandFailed(exitCode: Int32, message: String)
    case sudoFailed(exitCode: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case let .executionFailed(message):
            return "Process execution failed: \(message)"
        case let .commandFailed(exitCode, message):
            return "Command failed with exit code \(exitCode): \(message)"
        case let .sudoFailed(exitCode, message):
            return "Sudo command failed with exit code \(exitCode): \(message)"
        }
    }
}