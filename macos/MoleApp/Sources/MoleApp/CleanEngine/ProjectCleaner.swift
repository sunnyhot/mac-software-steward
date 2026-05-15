import Foundation

/// Project Cleaner - Scans and cleans project build artifacts
/// Ported from lib/clean/project.sh (1,645 lines, 25 functions)
actor ProjectCleaner {
    // MARK: - Properties
    private let configuration: CleanEngineConfiguration
    private let fileManager = FileManager.default
    private let safeRemover: SafeRemover
    private let pathValidator: PathValidator
    private let whitelistManager: WhitelistManager
    private let protectionManager: ProtectionManager

    // MARK: - Project Indicators
    /// Files/directories that indicate a project root
    private let projectIndicators = [
        "package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
        "build.gradle", "settings.gradle", "gradlew", "pom.xml", "mvnw",
        "Cargo.toml", "Cargo.lock", "go.mod", "go.sum",
        "Gemfile", "Gemfile.lock", "composer.json", "composer.lock",
        "requirements.txt", "setup.py", "pyproject.toml", "poetry.lock",
        ".csproj", ".sln", ".vbproj", ".fsproj",
        "pubspec.yaml", "Podfile", "Cartfile",
        "mix.exs", "dub.json", "shard.yml",
        "project.clj", "build.boot", "deps.edn"
    ]

    /// Monorepo indicators (higher priority)
    private let monorepoIndicators = [
        "lerna.json", "turbo.json", "nx.json",
        ".gitmodules", "pnpm-workspace.yaml",
        "workspace.json", "rust-toolchain.toml"
    ]

    /// Build artifact directories to scan for
    private let artifactNames = [
        "node_modules", ".gradle", "build", "target", "out", "dist",
        "DerivedData", "Pods", ".next", ".nuxt", ".vite",
        ".webpack", "vendor", ".venv", "venv", ".virtualenv",
        "__pycache__", ".tox", ".mypy_cache", ".pytest_cache",
        ".build", "cmake-build-*", "CMakeFiles",
        ".cache", "tmp", "temp"
    ]

    // MARK: - Initialization
    init(
        configuration: CleanEngineConfiguration,
        safeRemover: SafeRemover,
        pathValidator: PathValidator,
        whitelistManager: WhitelistManager,
        protectionManager: ProtectionManager
    ) {
        self.configuration = configuration
        self.safeRemover = safeRemover
        self.pathValidator = pathValidator
        self.whitelistManager = whitelistManager
        self.protectionManager = protectionManager
    }

    // MARK: - Main Scan Interface
    func scanAllProjectArtifacts() async -> [CleanItem] {
        var allItems: [CleanItem] = []

        // Get search paths (default: ~/Developer, ~/Projects, etc.)
        let searchPaths = await getDefaultSearchPaths()

        for searchPath in searchPaths {
            let artifacts = await scanProjectArtifacts(in: searchPath)
            allItems.append(contentsOf: artifacts)
        }

        return allItems
    }

    // MARK: - Path Discovery
    private func getDefaultSearchPaths() async -> [String] {
        var paths: [String] = []

        let homeDir = fileManager.homeDirectoryForCurrentUser.path

        // Default search paths
        let defaultPaths = [
            "\(homeDir)/Developer",
            "\(homeDir)/Projects",
            "\(homeDir)/dev",
            "\(homeDir)/project",
            "\(homeDir)/workspace",
            "\(homeDir)/work",
            "\(homeDir)/src",
            "\(homeDir)/code"
        ]

        for path in defaultPaths {
            if fileManager.fileExists(atPath: path) {
                paths.append(path)
            }
        }

        // Scan home directory for project containers
        let homeContainers = await discoverProjectContainers(in: homeDir)
        paths.append(contentsOf: homeContainers)

        return paths
    }

    private func discoverProjectContainers(in rootPath: String) async -> [String] {
        var containers: [String] = []

        do {
            let contents = try fileManager.contentsOfDirectory(atPath: rootPath)

            for item in contents {
                // Skip hidden directories and system directories
                if item.hasPrefix(".") { continue }
                if item == "Library" || item == "Applications" ||
                   item == "Movies" || item == "Music" ||
                   item == "Pictures" || item == "Public" { continue }

                let itemPath = (rootPath as NSString).appendingPathComponent(item)

                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }

                // Check if this directory contains projects
                if await isProjectContainer(itemPath) {
                    containers.append(itemPath)
                }
            }
        } catch {
            // Ignore permission errors
        }

        return containers
    }

    private func isProjectContainer(_ path: String) async -> Bool {
        // Check if directory contains any project indicators
        for indicator in projectIndicators {
            let indicatorPath = (path as NSString).appendingPathComponent(indicator)
            if fileManager.fileExists(atPath: indicatorPath) {
                return true
            }
        }

        // Check subdirectories (depth 2)
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: path)
            for subDir in contents {
                if subDir.hasPrefix(".") { continue }

                let subPath = (path as NSString).appendingPathComponent(subDir)

                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: subPath, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }

                for indicator in projectIndicators {
                    let indicatorPath = (subPath as NSString).appendingPathComponent(indicator)
                    if fileManager.fileExists(atPath: indicatorPath) {
                        return true
                    }
                }
            }
        } catch {
            return false
        }

        return false
    }

    // MARK: - Artifact Scanning
    private func scanProjectArtifacts(in searchPath: String) async -> [CleanItem] {
        var artifacts: [CleanItem] = []

        guard fileManager.fileExists(atPath: searchPath) else { return artifacts }

        // Check if search path itself is a project root
        let isProjectRoot = await isProjectDirectory(searchPath)

        if isProjectRoot {
            // Scan direct child artifacts
            for artifactName in artifactNames {
                let artifactPath = (searchPath as NSString).appendingPathComponent(artifactName)
                if let artifact = await createCleanItemForArtifact(artifactPath) {
                    artifacts.append(artifact)
                }
            }
        }

        // Scan subdirectories for projects and artifacts
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: searchPath)

            for item in contents {
                if item.hasPrefix(".") { continue }

                let itemPath = (searchPath as NSString).appendingPathComponent(item)

                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }

                // Check if this is a project directory
                if await isProjectDirectory(itemPath) {
                    // Scan for artifacts in this project
                    for artifactName in artifactNames {
                        let artifactPath = (itemPath as NSString).appendingPathComponent(artifactName)
                        if let artifact = await createCleanItemForArtifact(artifactPath) {
                            artifacts.append(artifact)
                        }
                    }

                    // Scan one level deeper for nested projects
                    let nestedArtifacts = await scanNestedArtifacts(in: itemPath, depth: 1)
                    artifacts.append(contentsOf: nestedArtifacts)
                }
            }
        } catch {
            // Ignore permission errors
        }

        return artifacts
    }

    private func scanNestedArtifacts(in projectPath: String, depth: Int) async -> [CleanItem] {
        var artifacts: [CleanItem] = []

        guard depth <= 2 else { return artifacts } // Limit nested scanning

        do {
            let contents = try fileManager.contentsOfDirectory(atPath: projectPath)

            for item in contents {
                if item.hasPrefix(".") { continue }

                let itemPath = (projectPath as NSString).appendingPathComponent(item)

                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }

                // Skip known heavy directories
                if ["node_modules", "target", "build", "dist", "DerivedData", "Pods"].contains(item) {
                    continue
                }

                // Check if this is a nested project
                if await isProjectDirectory(itemPath) {
                    for artifactName in artifactNames {
                        let artifactPath = (itemPath as NSString).appendingPathComponent(artifactName)
                        if let artifact = await createCleanItemForArtifact(artifactPath) {
                            artifacts.append(artifact)
                        }
                    }

                    // Recurse one more level
                    let deeperArtifacts = await scanNestedArtifacts(in: itemPath, depth: depth + 1)
                    artifacts.append(contentsOf: deeperArtifacts)
                }
            }
        } catch {
            // Ignore permission errors
        }

        return artifacts
    }

    private func isProjectDirectory(_ path: String) async -> Bool {
        // Check for monorepo indicators first (higher priority)
        for indicator in monorepoIndicators {
            let indicatorPath = (path as NSString).appendingPathComponent(indicator)
            if fileManager.fileExists(atPath: indicatorPath) {
                return true
            }
        }

        // Check for regular project indicators
        for indicator in projectIndicators {
            let indicatorPath = (path as NSString).appendingPathComponent(indicator)
            if fileManager.fileExists(atPath: indicatorPath) {
                return true
            }
        }

        return false
    }

    // MARK: - Clean Item Creation
    private func createCleanItemForArtifact(_ path: String) async -> CleanItem? {
        guard fileManager.fileExists(atPath: path) else { return nil }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }

        // Calculate size
        let size = calculateDirectorySize(at: path)

        // Determine risk level based on artifact name
        let artifactName = (path as NSString).lastPathComponent
        let riskLevel = determineRiskLevel(for: artifactName)

        // Get last accessed date
        let lastAccessed = getLastAccessedDate(for: path)

        return CleanItem(
            path: path,
            size: size,
            type: isDirectory.boolValue ? .directory : .file,
            category: .developmentTools,
            riskLevel: riskLevel,
            lastAccessed: lastAccessed,
            isProtected: false,
            isWhitelisted: false
        )
    }

    private func determineRiskLevel(for artifactName: String) -> RiskLevel {
        // Low risk: clearly safe build artifacts
        let lowRiskArtifacts = [
            "node_modules", ".gradle", "target", "build",
            "DerivedData", "Pods", "__pycache__", ".tox",
            ".mypy_cache", ".pytest_cache", ".next", ".nuxt"
        ]

        // Medium risk: may contain some user data
        let mediumRiskArtifacts = [
            "vendor", ".venv", "venv", ".virtualenv",
            "dist", "out", ".webpack", ".vite"
        ]

        // High risk: ambiguous or potentially important
        let highRiskArtifacts = [
            "tmp", "temp", ".cache"
        ]

        if lowRiskArtifacts.contains(artifactName) {
            return .low
        } else if mediumRiskArtifacts.contains(artifactName) {
            return .medium
        } else if highRiskArtifacts.contains(artifactName) {
            return .high
        } else {
            return .medium // Default to medium
        }
    }

    // MARK: - Size Calculation
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

    private func getLastAccessedDate(for path: String) -> Date? {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            return attributes[.modificationDate] as? Date
        } catch {
            return nil
        }
    }

    // MARK: - Cleanup Operations
    func cleanArtifacts(_ artifacts: [CleanItem]) async -> [CleanResult] {
        return await safeRemover.batchRemove(artifacts)
    }

    // MARK: - Statistics and Analysis
    func getArtifactStatistics() async -> ProjectArtifactStatistics {
        let allArtifacts = await scanAllProjectArtifacts()

        let totalSize = allArtifacts.reduce(Int64(0)) { $0 + $1.size }

        let lowRiskCount = allArtifacts.filter { $0.riskLevel == .low }.count
        let mediumRiskCount = allArtifacts.filter { $0.riskLevel == .medium }.count
        let highRiskCount = allArtifacts.filter { $0.riskLevel == .high }.count

        // Group by artifact type
        var artifactTypeCounts: [String: Int] = [:]
        for artifact in allArtifacts {
            let artifactName = (artifact.path as NSString).lastPathComponent
            artifactTypeCounts[artifactName, default: 0] += 1
        }

        return ProjectArtifactStatistics(
            totalArtifactCount: allArtifacts.count,
            totalSizeBytes: totalSize,
            lowRiskCount: lowRiskCount,
            mediumRiskCount: mediumRiskCount,
            highRiskCount: highRiskCount,
            artifactTypeCounts: artifactTypeCounts
        )
    }

    func getProjectCount() async -> Int {
        let searchPaths = await getDefaultSearchPaths()
        var projectCount = 0

        for searchPath in searchPaths {
            projectCount += await countProjects(in: searchPath)
        }

        return projectCount
    }

    private func countProjects(in searchPath: String) async -> Int {
        var count = 0

        guard fileManager.fileExists(atPath: searchPath) else { return count }

        // Check if search path is a project
        if await isProjectDirectory(searchPath) {
            count += 1
        }

        // Count projects in subdirectories
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: searchPath)

            for item in contents {
                if item.hasPrefix(".") { continue }

                let itemPath = (searchPath as NSString).appendingPathComponent(item)

                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }

                if await isProjectDirectory(itemPath) {
                    count += 1
                }
            }
        } catch {
            // Ignore permission errors
        }

        return count
    }
}

// MARK: - Supporting Types
struct ProjectArtifactStatistics {
    let totalArtifactCount: Int
    let totalSizeBytes: Int64
    let lowRiskCount: Int
    let mediumRiskCount: Int
    let highRiskCount: Int
    let artifactTypeCounts: [String: Int]

    var formattedTotalSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSizeBytes)
    }
}