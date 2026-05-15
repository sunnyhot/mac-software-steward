import Foundation

// MARK: - Batch Uninstaller
actor BatchUninstaller {

    // MARK: - Dependencies
    private let brewIntegration = BrewIntegration()
    private let safeRemover = SafeRemover()

    // MARK: - Public Methods

    /// Uninstall a single application
    func uninstallApp(_ app: AppInfo, residuals: [ResidualFile], dryRun: Bool = false) async throws -> UninstallResult {
        var errors: [String] = []
        var removedFiles: [ResidualFile] = []
        var freedSpace: Int64 = 0

        do {
            // Step 1: Stop launch services
            try await stopLaunchServices(for: app)

            // Step 2: Remove login items
            try await removeLoginItem(for: app)

            // Step 3: Handle Homebrew cask if applicable
            if app.isBrewCask, let caskName = app.brewCaskName {
                try await brewIntegration.uninstallCask(caskName, appPath: app.path)
                removedFiles.append(ResidualFile(
                    path: app.path,
                    size: app.size,
                    category: .other,
                    riskLevel: .safe,
                    description: "Homebrew cask application"
                ))
                freedSpace += app.size
            } else {
                // Step 4: Unregister app bundle
                try await unregisterBundle(for: app)

                // Step 5: Remove application bundle
                if !dryRun {
                    try await safeRemover.remove(at: app.path)
                    removedFiles.append(ResidualFile(
                        path: app.path,
                        size: app.size,
                        category: .other,
                        riskLevel: .safe,
                        description: "Application bundle"
                    ))
                    freedSpace += app.size
                }
            }

            // Step 6: Remove residual files
            for residual in residuals {
                do {
                    if !dryRun {
                        try await safeRemover.remove(at: residual.path)
                    }
                    removedFiles.append(residual)
                    freedSpace += residual.size
                } catch {
                    errors.append("Failed to remove \(residual.path.path): \(error.localizedDescription)")
                }
            }

            // Step 7: Refresh launch services
            try await refreshLaunchServices()

            return UninstallResult(
                app: app,
                removedFiles: removedFiles,
                freedSpace: freedSpace,
                success: errors.isEmpty,
                errors: errors
            )

        } catch {
            throw UninstallError.unknown(error)
        }
    }

    /// Batch uninstall multiple applications
    func batchUninstall(_ apps: [AppInfo], dryRun: Bool = false) async throws -> [UninstallResult] {
        var results: [UninstallResult] = []

        for app in apps {
            do {
                // Find residuals for this app
                let residuals = try await findResiduals(for: app)

                // Uninstall the app
                let result = try await uninstallApp(app, residuals: residuals, dryRun: dryRun)
                results.append(result)
            } catch {
                results.append(UninstallResult(
                    app: app,
                    removedFiles: [],
                    freedSpace: 0,
                    success: false,
                    errors: [error.localizedDescription]
                ))
            }
        }

        return results
    }

    // MARK: - Private Methods

    private func stopLaunchServices(for app: AppInfo) async throws {
        // Find and unload any launch agents/daemons for this app
        let launchAgentPaths = [
            "\(NSHomeDirectory())/Library/LaunchAgents",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons"
        ]

        for path in launchAgentPaths {
            if let agents = await findLaunchAgents(in: path, for: app) {
                for agent in agents {
                    try await unloadLaunchAgent(at: agent)
                }
            }
        }
    }

    private func findLaunchAgents(in path: String, for app: AppInfo) async -> [URL]? {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: path) else {
            return nil
        }

        var agents: [URL] = []
        let bundleIdPrefix = app.id.split(separator: ".").joined(separator: ".")

        do {
            let baseURL = URL(fileURLWithPath: path)
            if let enumerator = fileManager.enumerator(at: baseURL, includingPropertiesForKeys: nil) {
                for case let url as URL in enumerator {
                    let fileName = url.lastPathComponent

                    // Match launch agents/daemons with bundle ID prefix
                    if fileName.hasPrefix(bundleIdPrefix) || fileName.hasPrefix("com.\(app.id)") {
                        agents.append(url)
                    }
                }
            }
        } catch {
            return nil
        }

        return agents.isEmpty ? nil : agents
    }

    private func unloadLaunchAgent(at url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            func resumeOnce() {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume()
            }

            func resumeThrowingOnce(_ error: Error) {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(throwing: error)
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                task.arguments = ["bootout", url.path]

                do {
                    try task.run()
                    task.waitUntilExit()

                    if task.terminationStatus != 0 {
                        throw UninstallError.launchAgentUnloadFailed(url.path)
                    }

                    resumeOnce()
                } catch {
                    resumeThrowingOnce(error)
                }
            }
        }
    }

    private func removeLoginItem(for app: AppInfo) async throws {
        // Try SMAppService first (macOS 13+)
        if #available(macOS 13.0, *) {
            try await removeLoginItemModern(for: app)
        } else {
            try await removeLoginItemLegacy(for: app)
        }
    }

    @available(macOS 13.0, *)
    private func removeLoginItemModern(for app: AppInfo) async throws {
        // Use SMAppService for modern macOS versions
        // This requires the app to be a login item in the first place
        // Implementation would depend on the specific SMAppService API
    }

    private func removeLoginItemLegacy(for app: AppInfo) async throws {
        // Use LSSharedFileList for older macOS versions
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            func resumeOnce() {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume()
            }

            func resumeThrowingOnce(_ error: Error) {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(throwing: error)
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                task.arguments = [
                    "-e", "tell application \"System Events\" to get the name of every login item"
                ]

                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = Pipe()

                do {
                    try task.run()
                    task.waitUntilExit()

                    if task.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        if let loginItems = String(data: data, encoding: .utf8) {
                            // Parse and remove if found
                            let items = loginItems.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            if items.contains(app.name) {
                                // Remove the login item
                                let removeTask = Process()
                                removeTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                                removeTask.arguments = [
                                    "-e", "tell application \"System Events\" to delete login item \"\(app.name)\""
                                ]
                                try? removeTask.run()
                                removeTask.waitUntilExit()
                            }
                        }
                    }

                    resumeOnce()
                } catch {
                    resumeThrowingOnce(error)
                }
            }
        }
    }

    private func unregisterBundle(for app: AppInfo) async throws {
        // Use lsregister to unregister the app bundle
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            func resumeOnce() {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume()
            }

            func resumeThrowingOnce(_ error: Error) {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(throwing: error)
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
                task.arguments = ["-u", app.path.path]

                do {
                    try task.run()
                    task.waitUntilExit()
                    resumeOnce()
                } catch {
                    resumeThrowingOnce(error)
                }
            }
        }
    }

    private func refreshLaunchServices() async throws {
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            func resumeOnce() {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume()
            }

            func resumeThrowingOnce(_ error: Error) {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(throwing: error)
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
                task.arguments = ["-kill", "-seed"]

                do {
                    try task.run()
                    task.waitUntilExit()
                    resumeOnce()
                } catch {
                    resumeThrowingOnce(error)
                }
            }
        }
    }

    private func findResiduals(for app: AppInfo) async throws -> [ResidualFile] {
        let scanner = ResidualScanner()
        return try await scanner.findResidualFiles(bundleId: app.id, appName: app.name)
    }
}