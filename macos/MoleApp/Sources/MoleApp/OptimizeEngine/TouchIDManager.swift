import Foundation
import LocalAuthentication
import os.log

/// Manager for Touch ID sudo configuration using LocalAuthentication framework
actor TouchIDManager {
    private let logger = Logger(subsystem: "com.mole.touchid", category: "TouchIDManager")
    private let fileManager = FileManager.default
    private let processManager = ProcessManager()

    // Touch ID configuration paths
    private let pamSudoFile = "/etc/pam.d/sudo"
    private let pamSudoLocalFile = "/etc/pam.d/sudo_local"
    private let pamTidLine = "auth       sufficient     pam_tid.so"

    /// Result type for Touch ID operations
    struct TouchIDResult: Sendable {
        let operation: String
        let success: Bool
        let message: String
        let requiresAuth: Bool
    }

    /// Touch ID configuration status
    struct TouchIDStatus: Sendable {
        let isSupported: Bool
        let isConfigured: Bool
        let isEnabledForSudo: Bool
        let biometryType: LABiometryType
        let hasEnrolledFingerprints: Bool
    }

    /// Check if Touch ID is supported on this device
    func isTouchIDSupported() async -> Bool {
        let context = LAContext()
        var error: NSError?

        let supported = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        if let error = error {
            logger.error("Touch ID not supported: \(error.localizedDescription)")
            return false
        }

        logger.info("Touch ID supported: \(supported)")
        return supported
    }

    /// Check if Touch ID is configured and has enrolled fingerprints
    func isTouchIDConfigured() async -> Bool {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            logger.error("Touch ID not available: \(error?.localizedDescription ?? "Unknown error")")
            return false
        }

        // Check if any fingerprints are enrolled
        let configured = context.biometryType != .none

        logger.info("Touch ID configured: \(configured)")
        return configured
    }

    /// Get comprehensive Touch ID status
    func getTouchIDStatus() async -> TouchIDStatus {
        let context = LAContext()
        var error: NSError?

        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let biometryType = context.biometryType

        let isSupported = canEvaluate && biometryType != .none
        let isConfigured = isSupported && hasEnrolledFingerprints()
        let isEnabledForSudo = await isTouchIDEnabledForSudo()

        return TouchIDStatus(
            isSupported: isSupported,
            isConfigured: isConfigured,
            isEnabledForSudo: isEnabledForSudo,
            biometryType: biometryType,
            hasEnrolledFingerprints: hasEnrolledFingerprints()
        )
    }

    /// Check if Touch ID is enabled for sudo
    func isTouchIDEnabledForSudo() async -> Bool {
        // Check sudo_local first (macOS 13.0+ preferred location)
        if fileManager.fileExists(atPath: pamSudoLocalFile) {
            if let content = try? String(contentsOfFile: pamSudoLocalFile, encoding: .utf8) {
                let enabled = content.contains(pamTidLine)
                logger.info("Touch ID for sudo enabled (sudo_local): \(enabled)")
                return enabled
            }
        }

        // Fallback to standard sudo file
        guard fileManager.fileExists(atPath: pamSudoFile) else {
            logger.info("PAM sudo file not found")
            return false
        }

        if let content = try? String(contentsOfFile: pamSudoFile, encoding: .utf8) {
            let enabled = content.contains(pamTidLine)
            logger.info("Touch ID for sudo enabled: \(enabled)")
            return enabled
        }

        return false
    }

    /// Enable Touch ID for sudo authentication
    func enableTouchIDForSudo() async throws -> TouchIDResult {
        logger.info("Enabling Touch ID for sudo")

        // First verify Touch ID is available
        guard await isTouchIDConfigured() else {
            logger.error("Touch ID not configured")
            return TouchIDResult(
                operation: "Enable Touch ID for Sudo",
                success: false,
                message: "Touch ID is not configured or no fingerprints enrolled",
                requiresAuth: false
            )
        }

        // Authenticate the user before making system changes
        let authenticated = await authenticateUser()
        guard authenticated else {
            logger.error("User authentication failed")
            return TouchIDResult(
                operation: "Enable Touch ID for Sudo",
                success: false,
                message: "User authentication failed",
                requiresAuth: true
            )
        }

        do {
            // Try to use sudo_local first (macOS 13.0+)
            if await enableTouchIDInSudoLocal() {
                logger.info("Touch ID enabled via sudo_local")
                return TouchIDResult(
                    operation: "Enable Touch ID for Sudo",
                    success: true,
                    message: "Touch ID enabled for sudo authentication",
                    requiresAuth: false
                )
            }

            // Fallback to standard sudo file
            if await enableTouchIDInSudoFile() {
                logger.info("Touch ID enabled via sudo file")
                return TouchIDResult(
                    operation: "Enable Touch ID for Sudo",
                    success: true,
                    message: "Touch ID enabled for sudo authentication",
                    requiresAuth: false
                )
            }

            logger.error("Failed to enable Touch ID")
            return TouchIDResult(
                operation: "Enable Touch ID for Sudo",
                success: false,
                message: "Failed to enable Touch ID for sudo",
                requiresAuth: false
            )
        } catch {
            logger.error("Error enabling Touch ID: \(error.localizedDescription)")
            return TouchIDResult(
                operation: "Enable Touch ID for Sudo",
                success: false,
                message: "Error enabling Touch ID: \(error.localizedDescription)",
                requiresAuth: false
            )
        }
    }

    /// Disable Touch ID for sudo authentication
    func disableTouchIDForSudo() async throws -> TouchIDResult {
        logger.info("Disabling Touch ID for sudo")

        // Authenticate the user before making system changes
        let authenticated = await authenticateUser()
        guard authenticated else {
            logger.error("User authentication failed")
            return TouchIDResult(
                operation: "Disable Touch ID for Sudo",
                success: false,
                message: "User authentication failed",
                requiresAuth: true
            )
        }

        do {
            // Try sudo_local first
            if fileManager.fileExists(atPath: pamSudoLocalFile) {
                try await disableTouchIDInSudoLocal()
                logger.info("Touch ID disabled in sudo_local")
                return TouchIDResult(
                    operation: "Disable Touch ID for Sudo",
                    success: true,
                    message: "Touch ID disabled for sudo authentication",
                    requiresAuth: false
                )
            }

            // Fallback to standard sudo file
            if fileManager.fileExists(atPath: pamSudoFile) {
                try await disableTouchIDInSudoFile()
                logger.info("Touch ID disabled in sudo file")
                return TouchIDResult(
                    operation: "Disable Touch ID for Sudo",
                    success: true,
                    message: "Touch ID disabled for sudo authentication",
                    requiresAuth: false
                )
            }

            logger.error("No PAM sudo files found")
            return TouchIDResult(
                operation: "Disable Touch ID for Sudo",
                success: false,
                message: "No PAM sudo configuration files found",
                requiresAuth: false
            )
        } catch {
            logger.error("Error disabling Touch ID: \(error.localizedDescription)")
            return TouchIDResult(
                operation: "Disable Touch ID for Sudo",
                success: false,
                message: "Error disabling Touch ID: \(error.localizedDescription)",
                requiresAuth: false
            )
        }
    }

    // MARK: - Private Helper Methods

    /// Authenticate user with biometrics
    private func authenticateUser() async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedReason = "Authenticate to enable Touch ID for sudo"

        do {
            let result = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Authenticate to enable Touch ID for sudo"
            )
            logger.info("User authentication successful: \(result)")
            return result
        } catch {
            logger.error("Authentication failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Enable Touch ID in sudo_local file (macOS 13.0+)
    private func enableTouchIDInSudoLocal() async -> Bool {
        do {
            // Check if file exists, if not create it
            if !fileManager.fileExists(atPath: pamSudoLocalFile) {
                let content = """
                # sudo_local: local configuration for sudo
                # This file is managed by Mole - Touch ID Manager
                # Touch ID is enabled for sudo authentication

                \(pamTidLine)
                """

                guard let data = content.data(using: .utf8) else { return false }

                // Use Process to create the file with sudo
                let tempFile = "/tmp/sudo_local_mole_temp"
                try data.write(to: URL(fileURLWithPath: tempFile))

                try await processManager.executeWithSudo(
                    command: "cp",
                    arguments: [tempFile, pamSudoLocalFile]
                )

                try await processManager.executeWithSudo(
                    command: "chmod",
                    arguments: ["644", pamSudoLocalFile]
                )

                // Clean up temp file
                try? fileManager.removeItem(atPath: tempFile)

                return true
            } else {
                // File exists, check if Touch ID line is already there
                if let content = try? String(contentsOfFile: pamSudoLocalFile, encoding: .utf8) {
                    if content.contains(pamTidLine) {
                        logger.info("Touch ID already enabled in sudo_local")
                        return true
                    }

                    // Add the Touch ID line
                    let updatedContent = content + "\n" + pamTidLine + "\n"

                    guard let data = updatedContent.data(using: .utf8) else { return false }

                    // Use Process to write the file with sudo
                    let tempFile = "/tmp/sudo_local_mole_temp"
                    try data.write(to: URL(fileURLWithPath: tempFile))

                    try await processManager.executeWithSudo(
                        command: "cp",
                        arguments: [tempFile, pamSudoLocalFile]
                    )

                    // Clean up temp file
                    try? fileManager.removeItem(atPath: tempFile)

                    return true
                }
            }
        } catch {
            logger.error("Failed to enable Touch ID in sudo_local: \(error.localizedDescription)")
            return false
        }

        return false
    }

    /// Enable Touch ID in standard sudo file
    private func enableTouchIDInSudoFile() async -> Bool {
        do {
            guard let content = try? String(contentsOfFile: pamSudoFile, encoding: .utf8) else {
                logger.error("Cannot read sudo file")
                return false
            }

            // Check if Touch ID line is already there
            if content.contains(pamTidLine) {
                logger.info("Touch ID already enabled in sudo file")
                return true
            }

            // Find the first "auth sufficient" line and add Touch ID line before it
            let lines = content.components(separatedBy: "\n")
            var updatedLines: [String] = []
            var inserted = false

            for line in lines {
                if !inserted && line.contains("auth") && line.contains("sufficient") {
                    updatedLines.append(pamTidLine)
                    updatedLines.append(line)
                    inserted = true
                } else {
                    updatedLines.append(line)
                }
            }

            // If we didn't find a good place to insert, append at the end
            if !inserted {
                updatedLines.append(pamTidLine)
            }

            let updatedContent = updatedLines.joined(separator: "\n")

            guard let data = updatedContent.data(using: .utf8) else { return false }

            // Use Process to write the file with sudo
            let tempFile = "/tmp/sudo_mole_temp"
            try data.write(to: URL(fileURLWithPath: tempFile))

            try await processManager.executeWithSudo(
                command: "cp",
                arguments: [tempFile, pamSudoFile]
            )

            // Clean up temp file
            try? fileManager.removeItem(atPath: tempFile)

            return true
        } catch {
            logger.error("Failed to enable Touch ID in sudo file: \(error.localizedDescription)")
            return false
        }
    }

    /// Disable Touch ID in sudo_local file
    private func disableTouchIDInSudoLocal() async throws {
        guard let content = try? String(contentsOfFile: pamSudoLocalFile, encoding: .utf8) else {
            return
        }

        // Remove the Touch ID line
        let updatedContent = content
            .components(separatedBy: "\n")
            .filter { !$0.contains(pamTidLine) }
            .joined(separator: "\n")

        guard let data = updatedContent.data(using: .utf8) else { return }

        // Use Process to write the file with sudo
        let tempFile = "/tmp/sudo_local_mole_temp"
        try data.write(to: URL(fileURLWithPath: tempFile))

        try await processManager.executeWithSudo(
            command: "cp",
            arguments: [tempFile, pamSudoLocalFile]
        )

        // Clean up temp file
        try? fileManager.removeItem(atPath: tempFile)
    }

    /// Disable Touch ID in standard sudo file
    private func disableTouchIDInSudoFile() async throws {
        guard let content = try? String(contentsOfFile: pamSudoFile, encoding: .utf8) else {
            return
        }

        // Remove the Touch ID line
        let updatedContent = content
            .components(separatedBy: "\n")
            .filter { !$0.contains(pamTidLine) }
            .joined(separator: "\n")

        guard let data = updatedContent.data(using: .utf8) else { return }

        // Use Process to write the file with sudo
        let tempFile = "/tmp/sudo_mole_temp"
        try data.write(to: URL(fileURLWithPath: tempFile))

        try await processManager.executeWithSudo(
            command: "cp",
            arguments: [tempFile, pamSudoFile]
        )

        // Clean up temp file
        try? fileManager.removeItem(atPath: tempFile)
    }

    /// Check if user has enrolled fingerprints
    private func hasEnrolledFingerprints() -> Bool {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }

        // Check if we can actually evaluate the policy (which requires enrolled fingerprints)
        return context.biometryType == .touchID || context.biometryType == .faceID
    }
}