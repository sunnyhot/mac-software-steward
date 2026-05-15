import Foundation
import AppKit

/// Hint Engine - Generates intelligent cleaning recommendations
/// Ported from lib/clean/hints.sh (824 lines, 21 functions)
actor HintEngine {
    // MARK: - Properties
    private let configuration: CleanEngineConfiguration
    private let fileManager = FileManager.default
    private let pathValidator: PathValidator
    private let whitelistManager: WhitelistManager

    // MARK: - Known Safe Dot Directories
    /// Dot directories that are known to be safe and should not be flagged
    private let knownSafeDotDirectories = [
        // Shell
        ".bash_history", ".bash_profile", ".bash_sessions", ".bashrc",
        ".zshrc", ".zsh_history", ".zsh_sessions", ".zprofile", ".zshenv", ".zlogout", ".zcompdump",
        ".profile", ".inputrc", ".hushlogin",
        ".oh-my-zsh", ".zinit", ".zplug", ".antigen", ".p10k.zsh",
        ".config", ".local", ".cache",
        // Nix Store - CRITICAL: Never scan or suggest cleaning Nix Store
        ".nix", ".nix-profile", ".nix-defexpr", ".nix-gc", ".nix-log",
        // Security
        ".ssh", ".gnupg", ".gpg", ".password-store",
        // Git
        ".gitconfig", ".gitignore_global", ".git-credentials", ".gitattributes_global",
        // Language tools
        ".pyenv", ".rbenv", ".nvm", ".nodenv", ".goenv", ".jenv",
        ".rustup", ".cargo", ".ghcup", ".stack", ".cabal",
        ".sdkman", ".jabba", ".asdf", ".mise", ".rtx", ".volta", ".fnm",
        ".deno", ".bun",
        // Package managers
        ".npm", ".yarn", ".pnpm", ".bundle", ".gem",
        ".composer", ".nuget", ".pub-cache",
        ".m2", ".gradle", ".sbt", ".ivy2", ".lein",
        ".hex", ".mix", ".opam", ".cpan", ".cpanm",
        ".conda", ".virtualenvs", ".pipx",
        // Nix Package Manager (CRITICAL: Never delete /nix or .nix directories)
        ".nix",
        // Cloud / DevOps
        ".docker", ".kube", ".minikube", ".helm",
        ".aws", ".azure", ".terraform", ".vagrant",
        // Editors / IDEs
        ".vim", ".vimrc", ".viminfo", ".emacs", ".emacs.d", ".doom.d", ".nano", ".nanorc",
        ".vscode", ".cursor", ".atom",
        // AI tools
        ".claude", ".copilot", ".ollama",
        // macOS system
        ".Trash", ".Trashes", ".CFUserTextEncoding", ".DS_Store", ".cups", ".dropbox",
        // Mobile / native dev
        ".android", ".cocoapods", ".fastlane", ".expo", ".react-native", ".swiftpm",
        // Terminal / misc
        ".tmux", ".screen", ".wget-hsts", ".curlrc", ".netrc", ".wgetrc",
        ".putty", ".lesshst", ".python_history", ".node_repl_history",
        ".irb_history", ".pry_history",
        ".jupyter", ".ipython", ".matplotlib", ".keras", ".torch",
        ".psql_history", ".mysql_history", ".sqlite_history", ".rediscli_history", ".mongo", ".dbshell",
        // Homebrew / VCS
        ".homebrew", ".hg", ".hgrc", ".svn", ".bazaar",
        // Fly.io / Gemini
        ".fly", ".gemini"
    ]

    // MARK: - Hint Categories
    enum HintCategory: String, CaseIterable {
        case systemData = "System Data"
        case projectArtifact = "Project Artifacts"
        case launchAgent = "Launch Agents"
        case orphanDotfile = "Orphan Dotfiles"
    }

    // MARK: - Initialization
    init(
        configuration: CleanEngineConfiguration,
        pathValidator: PathValidator,
        whitelistManager: WhitelistManager
    ) {
        self.configuration = configuration
        self.pathValidator = pathValidator
        self.whitelistManager = whitelistManager
    }

    // MARK: - Main Hint Generation
    func generateAllHints() async -> [CleanHint] {
        var allHints: [CleanHint] = []

        // Generate hints for each category
        let systemDataHints = await generateSystemDataHints()
        allHints.append(contentsOf: systemDataHints)

        let projectArtifactHints = await generateProjectArtifactHints()
        allHints.append(contentsOf: projectArtifactHints)

        let launchAgentHints = await generateLaunchAgentHints()
        allHints.append(contentsOf: launchAgentHints)

        let orphanDotfileHints = await generateOrphanDotfileHints()
        allHints.append(contentsOf: orphanDotfileHints)

        return allHints
    }

    // MARK: - System Data Hints
    private func generateSystemDataHints() async -> [CleanHint] {
        var hints: [CleanHint] = []

        let homeDir = fileManager.homeDirectoryForCurrentUser.path

        // System data locations to check
        let systemDataChecks = [
            ("Xcode DerivedData", "\(homeDir)/Library/Developer/Xcode/DerivedData"),
            ("Xcode Archives", "\(homeDir)/Library/Developer/Xcode/Archives"),
            ("iPhone Backups", "\(homeDir)/Library/Application Support/MobileSync/Backup"),
            ("Simulator Data", "\(homeDir)/Library/Developer/CoreSimulator/Devices"),
            ("Docker Desktop Data", "\(homeDir)/Library/Containers/com.docker.docker/Data"),
            ("Mail Data", "\(homeDir)/Library/Mail")
        ]

        for (name, path) in systemDataChecks {
            if let hint = await createSystemDataHint(name: name, path: path) {
                hints.append(hint)
            }
        }

        return hints
    }

    private func createSystemDataHint(name: String, path: String) async -> CleanHint? {
        guard fileManager.fileExists(atPath: path) else { return nil }

        let size = calculateDirectorySize(at: path)

        // Only create hint for substantial data (> 2GB)
        guard size > 2 * 1024 * 1024 * 1024 else { return nil }

        return CleanHint(
            category: .systemData,
            title: "\(name) (\(formatBytes(size)))",
            description: "Large \(name) directory detected",
            path: path,
            sizeBytes: size,
            riskLevel: .low,
            recommendedAction: "Review and clean if not needed",
            canAutomaticallyClean: true
        )
    }

    // MARK: - Project Artifact Hints
    private func generateProjectArtifactHints() async -> [CleanHint] {
        var hints: [CleanHint] = []

        let homeDir = fileManager.homeDirectoryForCurrentUser.path

        // Common project directories
        let projectDirectories = [
            "\(homeDir)/Developer",
            "\(homeDir)/Projects",
            "\(homeDir)/dev",
            "\(homeDir)/code"
        ]

        for projectDir in projectDirectories {
            guard fileManager.fileExists(atPath: projectDir) else { continue }

            let projectHints = await scanProjectArtifactsHints(in: projectDir)
            hints.append(contentsOf: projectHints)
        }

        return hints
    }

    private func scanProjectArtifactsHints(in projectDir: String) async -> [CleanHint] {
        var hints: [CleanHint] = []

        // Common artifact patterns
        let artifactPatterns = [
            ("node_modules", "Node.js dependencies"),
            ("target", "Java/Cargo build artifacts"),
            (".gradle", "Gradle cache"),
            ("build", "Build output"),
            ("DerivedData", "Xcode build data"),
            ("Pods", "CocoaPods dependencies"),
            ("__pycache__", "Python cache"),
            (".tox", "Python test environments"),
            (".venv", "Python virtual environment"),
            ("vendor", "PHP/Go dependencies")
        ]

        for (artifactName, description) in artifactPatterns {
            let artifactHints = await findArtifactsNamed(artifactName, in: projectDir, description: description)
            hints.append(contentsOf: artifactHints)

            // Limit hints per category to avoid overwhelming results
            if hints.count >= 12 {
                break
            }
        }

        return hints
    }

    private func findArtifactsNamed(_ artifactName: String, in rootPath: String, description: String) async -> [CleanHint] {
        var hints: [CleanHint] = []
        var foundCount = 0
        let maxArtifacts = 3

        // Search for artifacts (limited depth for performance)
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: rootPath),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsSubdirectoryDescendants]
        ) else {
            return hints
        }

        for case let fileURL as URL in enumerator {
            guard foundCount < maxArtifacts else { break }

            let path = fileURL.path
            let lastComponent = (path as NSString).lastPathComponent

            if lastComponent == artifactName {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }

                // CRITICAL: Skip Nix Store paths to prevent catastrophic deletion
                if path.contains("/nix/") || path.contains("/.nix") {
                    continue
                }

                let size = calculateDirectorySize(at: path)

                // Only hint for substantial artifacts (> 100MB)
                guard size > 100 * 1024 * 1024 else { continue }

                let hint = CleanHint(
                    category: .projectArtifact,
                    title: "\(artifactName) (\(formatBytes(size)))",
                    description: description,
                    path: path,
                    sizeBytes: size,
                    riskLevel: .low,
                    recommendedAction: "Consider cleaning if project is inactive",
                    canAutomaticallyClean: false
                )

                hints.append(hint)
                foundCount += 1
            }
        }

        return hints
    }

    // MARK: - Launch Agent Hints
    private func generateLaunchAgentHints() async -> [CleanHint] {
        var hints: [CleanHint] = []

        let homeDir = fileManager.homeDirectoryForCurrentUser.path
        let launchAgentsDir = "\(homeDir)/Library/LaunchAgents"

        guard fileManager.fileExists(atPath: launchAgentsDir) else { return hints }

        do {
            let contents = try fileManager.contentsOfDirectory(atPath: launchAgentsDir)

            for plistFile in contents {
                guard plistFile.hasSuffix(".plist") else { continue }

                // Skip Apple launch agents
                if plistFile.hasPrefix("com.apple.") { continue }

                let plistPath = (launchAgentsDir as NSString).appendingPathComponent(plistFile)

                if let hint = await analyzeLaunchAgentPlist(plistPath) {
                    hints.append(hint)
                }

                // Limit hints
                if hints.count >= 3 {
                    break
                }
            }
        } catch {
            // Ignore permission errors
        }

        return hints
    }

    private func analyzeLaunchAgentPlist(_ plistPath: String) async -> CleanHint? {
        // Check if the plist exists and can be read
        guard fileManager.fileExists(atPath: plistPath) else { return nil }

        do {
            let plistData = try Data(contentsOf: URL(fileURLWithPath: plistPath))
            guard let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else {
                return nil
            }

            // Extract program path
            var programPath: String?
            if let programArguments = plist["ProgramArguments"] as? [String], !programArguments.isEmpty {
                programPath = programArguments[0]
            } else if let program = plist["Program"] as? String {
                programPath = program
            }

            // Check if the program still exists
            if let program = programPath {
                if !fileManager.fileExists(atPath: program) {
                    // Program missing - potential stale launch agent
                    let fileName = (plistPath as NSString).lastPathComponent

                    return CleanHint(
                        category: .launchAgent,
                        title: "Stale Launch Agent: \(fileName)",
                        description: "Launch agent pointing to missing program",
                        path: plistPath,
                        sizeBytes: 0,
                        riskLevel: .medium,
                        recommendedAction: "Review and remove if no longer needed",
                        canAutomaticallyClean: false
                    )
                }
            }

            // Check for associated bundle existence
            if let associatedBundles = plist["AssociatedBundleIdentifiers"] as? [String], !associatedBundles.isEmpty {
                for bundleId in associatedBundles {
                    let appInstalled = await isAppInstalled(bundleId: bundleId)
                    if !appInstalled {
                        let fileName = (plistPath as NSString).lastPathComponent

                        return CleanHint(
                            category: .launchAgent,
                            title: "Orphaned Launch Agent: \(fileName)",
                            description: "Launch agent for uninstalled app: \(bundleId)",
                            path: plistPath,
                            sizeBytes: 0,
                            riskLevel: .medium,
                            recommendedAction: "Safe to remove if app is no longer in use",
                            canAutomaticallyClean: false
                        )
                    }
                }
            }

        } catch {
            // Ignore plist parsing errors
        }

        return nil
    }

    private func isAppInstalled(bundleId: String) async -> Bool {
        // Use NSWorkspace directly - simpler and more reliable approach
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
    }

    // MARK: - Orphan Dotfile Hints
    private func generateOrphanDotfileHints() async -> [CleanHint] {
        var hints: [CleanHint] = []

        let homeDir = fileManager.homeDirectoryForCurrentUser.path

        do {
            let contents = try fileManager.contentsOfDirectory(atPath: homeDir)

            for item in contents {
                guard item.hasPrefix(".") else { continue }

                let itemPath = (homeDir as NSString).appendingPathComponent(item)

                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }

                // Skip known safe directories
                if knownSafeDotDirectories.contains(item) { continue }

                // Check if this might be an orphan dotfile
                if let hint = await analyzeOrphanDotfile(item, path: itemPath) {
                    hints.append(hint)
                }

                // Limit hints
                if hints.count >= 5 {
                    break
                }
            }
        } catch {
            // Ignore permission errors
        }

        return hints
    }

    private func analyzeOrphanDotfile(_ name: String, path: String) async -> CleanHint? {
        // Remove the leading dot for analysis
        let bareName = String(name.dropFirst())

        // Check if there's a corresponding binary in PATH
        let hasBinary = await commandExists(bareName)
        if hasBinary { return nil } // Tool still installed

        // Check if there's a corresponding GUI app
        let hasApp = await guiAppExists(named: bareName)
        if hasApp { return nil } // App still installed

        // Check modification time (only flag if > 60 days old)
        if let modDate = getModificationDate(for: path) {
            let daysSinceModified = Date().timeIntervalSince(modDate) / 86400
            guard daysSinceModified > 60 else { return nil }
        }

        // Calculate size
        let size = calculateDirectorySize(at: path)

        // This might be an orphan dotfile
        return CleanHint(
            category: .orphanDotfile,
            title: "Potential Orphan: \(name) (\(formatBytes(size)))",
            description: "Dot directory with no corresponding binary or app found",
            path: path,
            sizeBytes: size,
            riskLevel: .medium,
            recommendedAction: "Review carefully before removing - may contain user data",
            canAutomaticallyClean: false
        )
    }

    private func commandExists(_ command: String) async -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [command]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func guiAppExists(named appName: String) async -> Bool {
        // Check common application directories
        let appDirs = [
            "/Applications",
            "/Applications/Setapp",
            "\(fileManager.homeDirectoryForCurrentUser.path)/Applications"
        ]

        for appDir in appDirs {
            let appPath = (appDir as NSString).appendingPathComponent("\(appName).app")
            if fileManager.fileExists(atPath: appPath) {
                return true
            }
        }

        // Check Homebrew casks
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/local/bin/brew")
        task.arguments = ["list", "--cask"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return output.contains(appName)
            }
        } catch {
            // Ignore errors
        }

        return false
    }

    // MARK: - Utility Methods
    private func calculateDirectorySize(at path: String) -> Int64 {
        var totalSize: Int64 = 0

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey],
            options: []
        ) else {
            return 0
        }

        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            } catch {
                continue
            }
        }

        return totalSize
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func getModificationDate(for path: String) -> Date? {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            return attributes[.modificationDate] as? Date
        } catch {
            return nil
        }
    }
}

// MARK: - Supporting Types
struct CleanHint: Identifiable, Sendable {
    let id = UUID()
    let category: HintEngine.HintCategory
    let title: String
    let description: String
    let path: String
    let sizeBytes: Int64
    let riskLevel: RiskLevel
    let recommendedAction: String
    let canAutomaticallyClean: Bool

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }
}