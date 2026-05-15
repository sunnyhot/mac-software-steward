import Foundation

// MARK: - Homebrew Integration
actor BrewIntegration {

    // MARK: - Constants
    private let caskroomPaths = [
        "/opt/homebrew/Caskroom",
        "/usr/local/Caskroom"
    ]

    // MARK: - Public Methods

    /// Check if Homebrew is available
    func isHomebrewAvailable() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
                task.arguments = ["brew"]

                do {
                    try task.run()
                    task.waitUntilExit()
                    continuation.resume(returning: task.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Check if a cask is installed
    func isCaskInstalled(_ caskName: String) async -> Bool {
        guard await isHomebrewAvailable() else {
            return false
        }

        let result = await runBrewCommand(["list", "--cask"])
        let caskList = result.output.split(separator: "\n").map { String($0) }

        return caskList.contains(caskName)
    }

    /// Get the brew cask name for an app
    func getCaskName(for appPath: URL) async -> String? {
        guard await isHomebrewAvailable() else {
            return nil
        }

        let appName = appPath.lastPathComponent

        // Stage 1: Check resolved path
        if let caskName = await detectCaskViaResolvedPath(appPath) {
            return caskName
        }

        // Stage 2: Search Caskroom by app bundle name
        if let caskName = await detectCaskViaCaskroomSearch(appName) {
            return caskName
        }

        // Stage 3: Check if app_path is a direct symlink to Caskroom
        if let caskName = await detectCaskViaSymlinkCheck(appPath) {
            return caskName
        }

        // Stage 4: Query brew list --cask and verify with brew info
        if let caskName = await detectCaskViaBrewList(appPath, appName: appName) {
            return caskName
        }

        return nil
    }

    /// Uninstall a Homebrew cask
    func uninstallCask(_ caskName: String, appPath: URL? = nil) async throws {
        guard await isHomebrewAvailable() else {
            throw BrewError.homebrewNotAvailable
        }

        // Calculate timeout based on app size
        var timeout: TimeInterval = 300 // Default 5 minutes

        if let appPath = appPath {
            let size = await getDirectorySize(at: appPath)
            let sizeGB = Double(size) / (1024 * 1024 * 1024)

            if sizeGB > 15 {
                timeout = 900 // 15 minutes for very large apps
            } else if sizeGB > 5 {
                timeout = 600 // 10 minutes for large apps
            }
        }

        let arguments = ["uninstall", "--cask", "--zap", caskName]
        let result = await runBrewCommand(arguments, timeout: timeout)

        guard result.terminationStatus == 0 else {
            throw BrewError.uninstallFailed("Exit code: \(result.terminationStatus)")
        }

        // Verify removal
        let stillInstalled = await isCaskInstalled(caskName)
        if stillInstalled {
            throw BrewError.uninstallFailed("Cask still installed after uninstall")
        }

        if let appPath = appPath {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: appPath.path) {
                throw BrewError.uninstallFailed("App still exists after uninstall")
            }
        }
    }

    // MARK: - Private Detection Methods

    private func detectCaskViaResolvedPath(_ appPath: URL) async -> String? {
        let resolvedPath = resolvePath(appPath)
        return extractCaskToken(from: resolvedPath)
    }

    private func detectCaskViaCaskroomSearch(_ appName: String) async -> String? {
        var tokens: Set<String> = []

        for caskroomPath in caskroomPaths {
            guard let caskroomURL = URL(string: caskroomPath) else { continue }

            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: caskroomPath) else { continue }

            if let enumerator = fileManager.enumerator(at: caskroomURL, includingPropertiesForKeys: nil) {
                for case let url as URL in enumerator {
                    if url.lastPathComponent == appName {
                        if let token = extractCaskToken(from: url) {
                            tokens.insert(token)
                        }
                    }
                }
            }
        }

        // Only succeed if exactly one unique token found
        if tokens.count == 1, let token = tokens.first {
            // Verify it's actually installed
            if await isCaskInstalled(token) {
                return token
            }
        }

        return nil
    }

    private func detectCaskViaSymlinkCheck(_ appPath: URL) async -> String? {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: appPath.path) else {
            return nil
        }

        var isSymlink: AnyObject?
        do {
            try (appPath as NSURL).getResourceValue(&isSymlink, forKey: URLResourceKey.isSymbolicLinkKey)

            if let isSymlink = isSymlink as? Bool, isSymlink {
                let destination = try fileManager.destinationOfSymbolicLink(atPath: appPath.path)
                return extractCaskToken(from: URL(fileURLWithPath: destination))
            }
        } catch {
            return nil
        }

        return nil
    }

    private func detectCaskViaBrewList(_ appPath: URL, appName: String) async -> String? {
        let appNameLower = appName.replacingOccurrences(of: ".app", with: "").lowercased()

        let result = await runBrewCommand(["list", "--cask"])
        let caskList = result.output.split(separator: "\n").map { String($0) }

        guard let caskName = caskList.first(where: { $0 == appNameLower }) else {
            return nil
        }

        // Verify this cask actually owns this app path
        let verifyResult = await runBrewCommand(["info", "--cask", caskName])
        if verifyResult.output.contains(appPath.path) {
            return caskName
        }

        return nil
    }

    // MARK: - Helper Methods

    private func extractCaskToken(from url: URL) -> String? {
        let path = url.path

        // Check if path is inside Caskroom
        guard caskroomPaths.contains(where: { path.hasPrefix($0) }) else {
            return nil
        }

        // Extract token from path: /opt/homebrew/Caskroom/<token>/<version>/...
        if let caskroomIndex = path.range(of: "/Caskroom/") {
            let tokenStart = caskroomIndex.upperBound
            if let tokenEnd = path[tokenStart...].firstIndex(of: "/") {
                let token = String(path[tokenStart..<tokenEnd])

                // Validate token looks like a valid cask name
                let isValid = token.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil
                if isValid {
                    return token
                }
            }
        }

        return nil
    }

    private func resolvePath(_ url: URL) -> URL {
        let fileManager = FileManager.default

        do {
            var isSymlink: AnyObject?
            try (url as NSURL).getResourceValue(&isSymlink, forKey: URLResourceKey.isSymbolicLinkKey)

            if let isSymlink = isSymlink as? Bool, isSymlink {
                let destination = try fileManager.destinationOfSymbolicLink(atPath: url.path)

                // Convert relative symlinks to absolute paths
                if destination.hasPrefix("/") {
                    return URL(fileURLWithPath: destination)
                } else {
                    let baseDir = url.deletingLastPathComponent()
                    return baseDir.appendingPathComponent(destination)
                }
            }
        } catch {
            return url
        }

        return url
    }

    private func getDirectorySize(at url: URL) async -> Int64 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fileManager = FileManager.default

                var totalSize: Int64 = 0

                if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
                    for case let url as URL in enumerator {
                        if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
                           let fileSize = resourceValues.fileSize {
                            totalSize += Int64(fileSize)
                        }
                    }
                }

                continuation.resume(returning: totalSize)
            }
        }
    }

    private func runBrewCommand(_ arguments: [String], timeout: TimeInterval = 30.0) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/local/bin/brew")

                // Try alternative brew paths
                if task.executableURL == nil {
                    task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
                }

                task.arguments = arguments

                // Set environment variables
                var environment = ProcessInfo.processInfo.environment
                environment["HOMEBREW_NO_ENV_HINTS"] = "1"
                environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
                environment["NONINTERACTIVE"] = "1"
                task.environment = environment

                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = pipe

                do {
                    try task.run()

                    // Add timeout
                    let timeoutWorkItem = DispatchWorkItem {
                        task.terminate()
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

                    task.waitUntilExit()

                    timeoutWorkItem.cancel()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    continuation.resume(returning: ProcessResult(
                        output: output,
                        terminationStatus: Int(task.terminationStatus)
                    ))
                } catch {
                    continuation.resume(returning: ProcessResult(
                        output: "",
                        terminationStatus: -1
                    ))
                }
            }
        }
    }

    private struct ProcessResult {
        let output: String
        let terminationStatus: Int
    }
}

// MARK: - Brew Errors
enum BrewError: Error, LocalizedError {
    case homebrewNotAvailable
    case uninstallFailed(String)
    case caskNotFound(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .homebrewNotAvailable:
            return "Homebrew is not available"
        case .uninstallFailed(let message):
            return "Uninstall failed: \(message)"
        case .caskNotFound(let name):
            return "Cask not found: \(name)"
        case .timeout:
            return "Operation timed out"
        }
    }
}