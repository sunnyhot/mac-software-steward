import Foundation

/// Development Tools Cleaner
/// Handles cleaning of development tool caches and build artifacts
actor DevToolsCleaner {
    // MARK: - Properties
    private let configuration: CleanEngineConfiguration
    private let fileManager = FileManager.default
    private let safeRemover: SafeRemover
    private let pathValidator: PathValidator
    private let whitelistManager: WhitelistManager
    private let protectionManager: ProtectionManager

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
    func scanAllDevTools() async -> [CleanItem] {
        var allItems: [CleanItem] = []

        // Package Manager Caches
        allItems.append(contentsOf: await scanNpmCaches())
        allItems.append(contentsOf: await scanPnpmCaches())
        allItems.append(contentsOf: await scanYarnCaches())
        allItems.append(contentsOf: await scanBunCaches())
        allItems.append(contentsOf: await scanPipCaches())
        allItems.append(contentsOf: await scanPoetryCaches())
        allItems.append(contentsOf: await scanCondaCaches())
        allItems.append(contentsOf: await scanUvCaches())
        allItems.append(contentsOf: await scanGoCaches())
        allItems.append(contentsOf: await scanCargoCaches())
        allItems.append(contentsOf: await scanRustupToolchains())
        allItems.append(contentsOf: await scanGemCaches())
        allItems.append(contentsOf: await scanBundlerCaches())
        allItems.append(contentsOf: await scanHomebrewCaches())
        allItems.append(contentsOf: await scanMavenCaches())

        // Development Tool Caches
        allItems.append(contentsOf: await scanXcodeDeviceSupport())
        allItems.append(contentsOf: await scanXcodeSimulators())
        allItems.append(contentsOf: await scanXcodeDerivedData())
        allItems.append(contentsOf: await scanXcodeArchives())
        allItems.append(contentsOf: await scanXcodeDocCache())
        allItems.append(contentsOf: await scanAndroidNdk())
        allItems.append(contentsOf: await scanDockerBuildx())
        allItems.append(contentsOf: await scanNixStore())
        allItems.append(contentsOf: await scanAwsCli())
        allItems.append(contentsOf: await scanGcloudCli())
        allItems.append(contentsOf: await scanAzCli())
        allItems.append(contentsOf: await scanKubectl())

        // Frontend Tool Caches
        allItems.append(contentsOf: await scanNodeGyp())
        allItems.append(contentsOf: await scanViteCache())
        allItems.append(contentsOf: await scanWebpackCache())
        allItems.append(contentsOf: await scanEslintCache())
        allItems.append(contentsOf: await scanPrettierCache())
        allItems.append(contentsOf: await scanTypescriptCache())
        allItems.append(contentsOf: await scanElectronCache())
        allItems.append(contentsOf: await scanTurboCache())

        // Python Tool Caches
        allItems.append(contentsOf: await scanPytestCache())
        allItems.append(contentsOf: await scanMypyCache())
        allItems.append(contentsOf: await scanJupyterCache())
        allItems.append(contentsOf: await scanHuggingfaceCache())
        allItems.append(contentsOf: await scanPytorchCache())
        allItems.append(contentsOf: await scanTensorflowCache())

        // Miscellaneous
        allItems.append(contentsOf: await scanDarwinUserRuntime())
        allItems.append(contentsOf: await scanMailDownloads())
        allItems.append(contentsOf: await scanIncompleteDownloads())
        allItems.append(contentsOf: await scanMacOSInstallers())
        allItems.append(contentsOf: await scanWandbCache())

        return allItems
    }

    // MARK: - Package Manager Caches

    func scanNpmCaches() async -> [CleanItem] {
        var items: [CleanItem] = []

        let npmCachePaths = [
            "~/.npm/_cacache",
            "~/.npm/_npx",
            "~/.npm/_logs",
            "~/.npm/_prebuilds",
            "~/Library/Caches/npm"
        ]

        for path in npmCachePaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "npm cache"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    func scanPnpmCaches() async -> [CleanItem] {
        var items: [CleanItem] = []

        let pnpmPaths = [
            "~/Library/pnpm/store",
            "~/.pnpm-store"
        ]

        for path in pnpmPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "pnpm cache"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    func scanYarnCaches() async -> [CleanItem] {
        var items: [CleanItem] = []

        let yarnPaths = [
            "~/.yarn/cache",
            "~/Library/Caches/Yarn",
            "~/.yarn/berry/cache",
            "~/.yarn/global/cache"
        ]

        for path in yarnPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "Yarn cache"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    func scanBunCaches() async -> [CleanItem] {
        var items: [CleanItem] = []

        let bunPaths = [
            "~/.bun/install/cache",
            "~/.bun/cache"
        ]

        for path in bunPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "Bun cache"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    func scanPipCaches() async -> [CleanItem] {
        var items: [CleanItem] = []

        let pipPaths = [
            "~/Library/Caches/pip",
            "~/.cache/pip",
            "~/.pip/cache"
        ]

        for path in pipPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "pip cache"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    func scanPoetryCaches() async -> [CleanItem] {
        var items: [CleanItem] = []

        let poetryPaths = [
            "~/Library/Caches/pypoetry",
            "~/.cache/pypoetry"
        ]

        for path in poetryPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "Poetry cache"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    func scanCondaCaches() async -> [CleanItem] {
        var items: [CleanItem] = []

        let condaPaths = [
            "~/.conda/pkgs",
            "~/anaconda3/pkgs",
            "~/miniconda3/pkgs",
            "~/miniforge3/pkgs",
            "~/mambaforge/pkgs"
        ]

        for path in condaPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "Conda package cache"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    func scanUvCaches() async -> [CleanItem] {
        var items: [CleanItem] = []

        let uvPaths = [
            "~/.cache/uv",
            "~/.uv/cache"
        ]

        for path in uvPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "uv cache"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    func scanGoCaches() async -> [CleanItem] {
        var items: [CleanItem] = []

        // Try to get Go environment variables
        let goBuildCache = await getGoEnvVar("GOCACHE") ?? "~/Library/Caches/go-build"
        let goModCache = await getGoEnvVar("GOMODCACHE") ?? "~/go/pkg/mod"

        for path in [goBuildCache, goModCache] {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "Go cache"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    func scanCargoCaches() async -> [CleanItem] {
        var items: [CleanItem] = []

        let cargoPaths = [
            "~/.cargo/registry",
            "~/.cargo/git"
        ]

        for path in cargoPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "Cargo cache"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    func scanRustupToolchains() async -> [CleanItem] {
        var items: [CleanItem] = []

        // This would need more sophisticated logic to determine which toolchains are old
        let rustupPath = NSString(string: "~/.rustup/toolchains").expandingTildeInPath

        if let directoryContents = try? fileManager.contentsOfDirectory(
            at: URL(fileURLWithPath: rustupPath),
            includingPropertiesForKeys: nil
        ) {
            for toolchainURL in directoryContents {
                if let cleanItem = await createCleanItemIfNeeded(
                    path: toolchainURL.path,
                    category: .developmentTools,
                    description: "Rustup toolchain"
                ) {
                    items.append(cleanItem)
                }
            }
        }

        return items
    }

    func scanGemCaches() async -> [CleanItem] {
        var items: [CleanItem] = []

        let gemPaths = [
            "~/.gem",
            "~/Library/Caches/gem"
        ]

        for path in gemPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "Gem cache"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    func scanBundlerCaches() async -> [CleanItem] {
        var items: [CleanItem] = []

        let bundlerPaths = [
            "~/vendor/bundle",
            "~/.bundle/cache"
        ]

        for path in bundlerPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "Bundler cache"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    func scanHomebrewCaches() async -> [CleanItem] {
        var items: [CleanItem] = []

        // Find brew executable
        let brewPaths = [
            "/opt/homebrew/bin/brew",  // Apple Silicon Homebrew
            "/usr/local/bin/brew",      // Intel Homebrew
            "/home/linuxbrew/.linuxbrew/bin/brew" // Linux Homebrew
        ]

        var brewExecutable: String?
        for path in brewPaths {
            if fileManager.fileExists(atPath: path) {
                brewExecutable = path
                break
            }
        }

        // If not found in common paths, try 'which brew'
        if brewExecutable == nil {
            brewExecutable = await findExecutable("brew")
        }

        guard let executable = brewExecutable else {
            // If brew not found, fall back to scanning cache directories directly
            let homebrewCachePaths = [
                "~/Library/Caches/Homebrew",
                "/usr/local/var/homebrew",
                "/opt/homebrew/var/homebrew"
            ]

            for path in homebrewCachePaths {
                let expandedPath = NSString(string: path).expandingTildeInPath
                if fileManager.fileExists(atPath: expandedPath) {
                    if let cleanItem = await createCleanItemIfNeeded(
                        path: expandedPath,
                        category: .developmentTools,
                        description: "Homebrew cache"
                    ) {
                        items.append(cleanItem)
                    }
                }
            }

            return items
        }

        // Use brew cleanup --prune=all --dry-run to get cache information
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = ["cleanup", "--prune=all", "--dry-run"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            // Since brew cleanup doesn't give us detailed cache size info,
            // we'll still scan the cache directory for size information
            let homebrewCachePaths = [
                "~/Library/Caches/Homebrew",
                "/usr/local/var/homebrew",
                "/opt/homebrew/var/homebrew"
            ]

            for path in homebrewCachePaths {
                let expandedPath = NSString(string: path).expandingTildeInPath
                if fileManager.fileExists(atPath: expandedPath) {
                    if let cleanItem = await createCleanItemIfNeeded(
                        path: expandedPath,
                        category: .developmentTools,
                        description: "Homebrew cache (cleanable with brew cleanup)"
                    ) {
                        items.append(cleanItem)
                    }
                }
            }
        } catch {
            // If brew command fails, fall back to directory scanning
        }

        return items
    }

    func scanMavenCaches() async -> [CleanItem] {
        var items: [CleanItem] = []

        let mavenPaths = [
            "~/.m2/repository",
            "~/Library/Caches/maven"
        ]

        for path in mavenPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "Maven cache"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    // MARK: - Development Tool Caches

    func scanXcodeDeviceSupport() async -> [CleanItem] {
        var items: [CleanItem] = []

        let deviceSupportPath = NSString(
            string: "~/Library/Developer/Xcode/iOS DeviceSupport"
        ).expandingTildeInPath

        if let directoryContents = try? fileManager.contentsOfDirectory(
            at: URL(fileURLWithPath: deviceSupportPath),
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) {
            // Sort by modification date and keep only the 2 most recent
            let sortedContents = directoryContents.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                return date1 > date2
            }

            // Skip the 2 most recent, mark the rest for cleaning
            for (index, url) in sortedContents.enumerated() {
                if index >= 2 { // Keep only the 2 most recent
                    if let cleanItem = await createCleanItemIfNeeded(
                        path: url.path,
                        category: .developmentTools,
                        description: "Xcode Device Support (old version)"
                    ) {
                        items.append(cleanItem)
                    }
                }
            }
        }

        return items
    }

    func scanXcodeSimulators() async -> [CleanItem] {
        var items: [CleanItem] = []

        let simulatorPaths = [
            "~/Library/Developer/CoreSimulator/Caches",
            "~/Library/Developer/CoreSimulator/Devices"
        ]

        for path in simulatorPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "Xcode Simulator cache"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    func scanXcodeDerivedData() async -> [CleanItem] {
        var items: [CleanItem] = []

        let derivedDataPath = NSString(string: "~/Library/Developer/Xcode/DerivedData").expandingTildeInPath

        if let cleanItem = await createCleanItemIfNeeded(
            path: derivedDataPath,
            category: .developmentTools,
            description: "Xcode DerivedData"
        ) {
            items.append(cleanItem)
        }

        return items
    }

    func scanXcodeArchives() async -> [CleanItem] {
        var items: [CleanItem] = []

        let archivesPath = NSString(string: "~/Library/Developer/Xcode/Archives").expandingTildeInPath

        if let cleanItem = await createCleanItemIfNeeded(
            path: archivesPath,
            category: .developmentTools,
            description: "Xcode Archives"
        ) {
            items.append(cleanItem)
        }

        return items
    }

    func scanXcodeDocCache() async -> [CleanItem] {
        var items: [CleanItem] = []

        let docPaths = [
            "~/Library/Developer/Shared/Documentation/DocSets",
            "~/Library/Caches/com.apple.dt.Xcode"
        ]

        for path in docPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "Xcode documentation cache"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    func scanAndroidNdk() async -> [CleanItem] {
        var items: [CleanItem] = []

        let androidPaths = [
            "~/.android/ndk-bundle",
            "~/Library/Android/sdk/ndk"
        ]

        for path in androidPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "Android NDK"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    func scanDockerBuildx() async -> [CleanItem] {
        var items: [CleanItem] = []

        let dockerPaths = [
            "~/Library/Containers/com.docker.docker/Data",
            "~/.docker/buildx"
        ]

        for path in dockerPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "Docker BuildX cache"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    func scanNixStore() async -> [CleanItem] {
        var items: [CleanItem] = []

        // Check if nix-collect-garbage command exists
        guard let nixPath = await findExecutable("nix-collect-garbage") else {
            return items
        }

        // Instead of directly deleting gcroots/profiles directories (which can break nix),
        // we'll use nix-collect-garbage -d command to safely clean the nix store
        let task = Process()
        task.executableURL = URL(fileURLWithPath: nixPath)
        task.arguments = ["--dry-run"] // Dry run to calculate potential space

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            // Since nix-collect-garbage doesn't give us size info directly,
            // we'll return a procedural item that will use the command during cleanup
            let nixItem = CleanItem(
                path: "/nix/var/nix/store", // This is just a placeholder path
                size: 0, // Size cannot be determined safely without actually running gc
                type: .directory,
                category: .developmentTools,
                riskLevel: .medium, // Nix GC is generally safe but can affect package availability
                lastAccessed: nil,
                isProtected: false,
                isWhitelisted: false
            )
            items.append(nixItem)
        } catch {
            // If nix-collect-garbage fails, return empty
        }

        return items
    }

    private func findExecutable(_ name: String) async -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [name]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                return output
            }
        } catch {
            return nil
        }

        return nil
    }

    func scanAwsCli() async -> [CleanItem] {
        var items: [CleanItem] = []

        let awsPath = NSString(string: "~/.aws/cli/cache").expandingTildeInPath

        if let cleanItem = await createCleanItemIfNeeded(
            path: awsPath,
            category: .developmentTools,
            description: "AWS CLI cache"
        ) {
            items.append(cleanItem)
        }

        return items
    }

    func scanGcloudCli() async -> [CleanItem] {
        var items: [CleanItem] = []

        // Only clean the cache directory, not the entire gcloud config which contains auth credentials
        let gcloudCachePath = NSString(string: "~/.config/gcloud/.cache").expandingTildeInPath

        if let cleanItem = await createCleanItemIfNeeded(
            path: gcloudCachePath,
            category: .developmentTools,
            description: "Google Cloud CLI cache"
        ) {
            items.append(cleanItem)
        }

        return items
    }

    func scanAzCli() async -> [CleanItem] {
        var items: [CleanItem] = []

        // Only clean the cache directory, not the entire Azure CLI config which contains login tokens
        let azureCachePath = NSString(string: "~/.azure/cli.cache").expandingTildeInPath

        if let cleanItem = await createCleanItemIfNeeded(
            path: azureCachePath,
            category: .developmentTools,
            description: "Azure CLI cache"
        ) {
            items.append(cleanItem)
        }

        return items
    }

    func scanKubectl() async -> [CleanItem] {
        var items: [CleanItem] = []

        let kubectlPath = NSString(string: "~/.kube/cache").expandingTildeInPath

        if let cleanItem = await createCleanItemIfNeeded(
            path: kubectlPath,
            category: .developmentTools,
            description: "kubectl cache"
        ) {
            items.append(cleanItem)
        }

        return items
    }

    // MARK: - Frontend Tool Caches

    func scanNodeGyp() async -> [CleanItem] {
        var items: [CleanItem] = []

        let nodeGypPath = NSString(string: "~/.node-gyp").expandingTildeInPath

        if let cleanItem = await createCleanItemIfNeeded(
            path: nodeGypPath,
            category: .developmentTools,
            description: "node-gyp cache"
        ) {
            items.append(cleanItem)
        }

        return items
    }

    func scanViteCache() async -> [CleanItem] {
        var items: [CleanItem] = []

        let vitePaths = [
            "~/.vite",
            "~/node_modules/.vite"
        ]

        for path in vitePaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "Vite cache"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    func scanWebpackCache() async -> [CleanItem] {
        var items: [CleanItem] = []

        let webpackPaths = [
            "~/.webpack/cache",
            "~/node_modules/.webpack"
        ]

        for path in webpackPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "Webpack cache"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    func scanEslintCache() async -> [CleanItem] {
        var items: [CleanItem] = []

        let eslintPath = NSString(string: "~/.cache/eslint").expandingTildeInPath

        if let cleanItem = await createCleanItemIfNeeded(
            path: eslintPath,
            category: .developmentTools,
            description: "ESLint cache"
        ) {
            items.append(cleanItem)
        }

        return items
    }

    func scanPrettierCache() async -> [CleanItem] {
        var items: [CleanItem] = []

        let prettierPath = NSString(string: "~/.cache/prettier").expandingTildeInPath

        if let cleanItem = await createCleanItemIfNeeded(
            path: prettierPath,
            category: .developmentTools,
            description: "Prettier cache"
        ) {
            items.append(cleanItem)
        }

        return items
    }

    func scanTypescriptCache() async -> [CleanItem] {
        var items: [CleanItem] = []

        let typescriptPath = NSString(string: "~/.cache/typescript").expandingTildeInPath

        if let cleanItem = await createCleanItemIfNeeded(
            path: typescriptPath,
            category: .developmentTools,
            description: "TypeScript cache"
        ) {
            items.append(cleanItem)
        }

        return items
    }

    func scanElectronCache() async -> [CleanItem] {
        var items: [CleanItem] = []

        let electronPaths = [
            "~/Library/Caches/electron",
            "~/Library/Caches/electron-builder"
        ]

        for path in electronPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "Electron cache"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    func scanTurboCache() async -> [CleanItem] {
        var items: [CleanItem] = []

        let turboPaths = [
            "~/.turbo",
            "~/node_modules/.turbo"
        ]

        for path in turboPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "Turborepo cache"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    // MARK: - Python Tool Caches

    func scanPytestCache() async -> [CleanItem] {
        var items: [CleanItem] = []

        let pytestPath = NSString(string: "~/.pytest_cache").expandingTildeInPath

        if let cleanItem = await createCleanItemIfNeeded(
            path: pytestPath,
            category: .developmentTools,
            description: "Pytest cache"
        ) {
            items.append(cleanItem)
        }

        return items
    }

    func scanMypyCache() async -> [CleanItem] {
        var items: [CleanItem] = []

        let mypyPaths = [
            "~/.cache/mypy",
            "~/.mypy_cache"
        ]

        for path in mypyPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "MyPy cache"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    func scanJupyterCache() async -> [CleanItem] {
        var items: [CleanItem] = []

        let jupyterPaths = [
            "~/.jupyter/runtime",
            "~/.local/share/jupyter"
        ]

        for path in jupyterPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if let cleanItem = await createCleanItemIfNeeded(
                path: expandedPath,
                category: .developmentTools,
                description: "Jupyter cache"
            ) {
                items.append(cleanItem)
            }
        }

        return items
    }

    func scanHuggingfaceCache() async -> [CleanItem] {
        var items: [CleanItem] = []

        let hfPath = NSString(string: "~/.cache/huggingface").expandingTildeInPath

        if let cleanItem = await createCleanItemIfNeeded(
            path: hfPath,
            category: .developmentTools,
            description: "Hugging Face cache"
        ) {
            items.append(cleanItem)
        }

        return items
    }

    func scanPytorchCache() async -> [CleanItem] {
        var items: [CleanItem] = []

        let torchPath = NSString(string: "~/.cache/torch").expandingTildeInPath

        if let cleanItem = await createCleanItemIfNeeded(
            path: torchPath,
            category: .developmentTools,
            description: "PyTorch cache"
        ) {
            items.append(cleanItem)
        }

        return items
    }

    func scanTensorflowCache() async -> [CleanItem] {
        var items: [CleanItem] = []

        let tfPath = NSString(string: "~/.cache/tensorflow").expandingTildeInPath

        if let cleanItem = await createCleanItemIfNeeded(
            path: tfPath,
            category: .developmentTools,
            description: "TensorFlow cache"
        ) {
            items.append(cleanItem)
        }

        return items
    }

    // MARK: - Miscellaneous

    func scanDarwinUserRuntime() async -> [CleanItem] {
        var items: [CleanItem] = []

        let darwinPath = NSString(string: "~/Library/Caches/com.apple.dt.Xcode").expandingTildeInPath

        if let cleanItem = await createCleanItemIfNeeded(
            path: darwinPath,
            category: .developmentTools,
            description: "Darwin user runtime"
        ) {
            items.append(cleanItem)
        }

        return items
    }

    func scanMailDownloads() async -> [CleanItem] {
        return []
    }

    func scanIncompleteDownloads() async -> [CleanItem] {
        return []
    }

    func scanMacOSInstallers() async -> [CleanItem] {
        return []
    }

    func scanWandbCache() async -> [CleanItem] {
        var items: [CleanItem] = []

        let wandbPath = NSString(string: "~/.cache/wandb").expandingTildeInPath

        if let cleanItem = await createCleanItemIfNeeded(
            path: wandbPath,
            category: .developmentTools,
            description: "Weights & Biases cache"
        ) {
            items.append(cleanItem)
        }

        return items
    }

    // MARK: - Helper Methods

    private func createCleanItemIfNeeded(
        path: String,
        category: CleanItemCategory,
        description: String
    ) async -> CleanItem? {
        guard fileManager.fileExists(atPath: path) else {
            return nil
        }

        var isDirectory: ObjCBool = false
        let fileExists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
        let isDir = fileExists && isDirectory.boolValue

        let size = calculateSize(at: path)

        return CleanItem(
            path: path,
            size: size,
            type: isDir ? .directory : .file,
            category: category,
            riskLevel: .low,
            lastAccessed: nil,
            isProtected: false,
            isWhitelisted: false
        )
    }

    private func calculateSize(at path: String) -> Int64 {
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

    private func getGoEnvVar(_ key: String) async -> String? {
        // Try to find Go executable dynamically instead of hardcoding
        let goPaths = [
            "/opt/homebrew/bin/go",  // Apple Silicon Homebrew
            "/usr/local/bin/go",      // Intel Homebrew
            "/usr/local/go/bin/go",   // Manual installation
            "/usr/bin/go",            // System Go
            "~/.go/bin/go"            // User Go installation
        ]

        var goExecutable: String?
        for path in goPaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if fileManager.fileExists(atPath: expandedPath) {
                goExecutable = expandedPath
                break
            }
        }

        // If not found in common paths, try 'which go'
        if goExecutable == nil {
            goExecutable = await findExecutable("go")
        }

        guard let executable = goExecutable else {
            return nil
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = ["env", key]

        let pipe = Pipe()
        task.standardOutput = pipe

        let outputPipe = Pipe()
        task.standardError = outputPipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                return output
            }
        } catch {
            // If go command fails, return nil
        }

        return nil
    }
}