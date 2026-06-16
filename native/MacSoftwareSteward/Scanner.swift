import Foundation

enum ScanPhase: String, CaseIterable {
    case systemProfiler = "正在扫描本机应用..."
    case brewInfo = "正在获取 Homebrew 信息..."
    case appStore = "正在扫描 App Store..."
    case classifying = "正在关联应用来源..."
    case finished = "扫描完成"

    var progress: Double {
        let total = ScanPhase.allCases.count
        guard let idx = ScanPhase.allCases.firstIndex(of: self) else { return 0 }
        return Double(idx) / Double(total - 1)
    }
}

enum SoftwareScanner {
    struct BrewInstalledPackagesResult {
        var packages: [(name: String, installedVersion: String)]
        var error: String
    }

    private struct TimedValue<Value> {
        var value: Value
        var stage: ScanPerformanceStage
    }

    private static func elapsedMs(since start: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(start) * 1000))
    }

    private static func timed<Value>(
        _ phase: ScanPerformancePhase,
        operation: () async -> Value
    ) async -> TimedValue<Value> {
        let started = Date()
        let value = await operation()
        return TimedValue(
            value: value,
            stage: ScanPerformanceStage(phase: phase, durationMs: elapsedMs(since: started))
        )
    }

    private static func timedSync<Value>(
        _ phase: ScanPerformancePhase,
        operation: () -> Value
    ) -> TimedValue<Value> {
        let started = Date()
        let value = operation()
        return TimedValue(
            value: value,
            stage: ScanPerformanceStage(phase: phase, durationMs: elapsedMs(since: started))
        )
    }

    static func scanAll(
        includeGreedy: Bool,
        regularAppNetworkPolicy: RegularAppNetworkPolicy = .declaredSourcesOnly,
        onPhaseChange: ((ScanPhase) -> Void)? = nil
    ) async -> ScanResult {
        let totalStarted = Date()

        onPhaseChange?(.systemProfiler)
        async let applicationsTask = timed(.applications) {
            await scanApplications()
        }
        onPhaseChange?(.brewInfo)
        async let brewTask = timed(.brew) {
            await scanBrew(includeGreedy: includeGreedy)
        }
        onPhaseChange?(.appStore)
        async let masTask = timed(.mas) {
            await scanMas()
        }

        let applicationsTimed = await applicationsTask
        let brewTimed = await brewTask
        let masTimed = await masTask

        var applications = applicationsTimed.value
        let brew = brewTimed.value
        let mas = masTimed.value

        onPhaseChange?(.classifying)
        let classificationTimed = timedSync(.classification) {
            classify(applications.items, brew: brew, mas: mas)
        }
        applications.items = classificationTimed.value

        let discoveryTimed = timedSync(.regularAppDiscovery) {
            attachUpdateCapabilities(to: applications.items)
        }
        applications.items = discoveryTimed.value

        let sparkleTimed = await timed(.sparkleAppcast) {
            await enrichRegularAppUpdates(
                applications.items,
                networkPolicy: regularAppNetworkPolicy
            )
        }
        applications.items = sparkleTimed.value

        let totalMs = elapsedMs(since: totalStarted)
        let scannedAt = Date()
        let summary = ScanSummary(
            applications: applications.items.count,
            brewFormulae: brew.formulae.count,
            brewCasks: brew.casks.count,
            masApps: mas.apps.count,
            outdated: brew.outdatedCount + mas.outdatedCount,
            actionable: brew.formulae.filter(\.upgradeable).count
                + brew.casks.filter(\.upgradeable).count
                + mas.apps.filter(\.upgradeable).count,
            scanMs: totalMs
        )
        let performance = ScanPerformanceSnapshot(
            id: UUID(),
            scannedAt: scannedAt,
            includeGreedy: includeGreedy,
            stages: [
                applicationsTimed.stage,
                brewTimed.stage,
                masTimed.stage,
                classificationTimed.stage,
                discoveryTimed.stage,
                sparkleTimed.stage,
                ScanPerformanceStage(phase: .total, durationMs: totalMs)
            ],
            applications: summary.applications,
            brewFormulae: summary.brewFormulae,
            brewCasks: summary.brewCasks,
            masApps: summary.masApps,
            outdated: summary.outdated,
            actionable: summary.actionable,
            applicationsSource: applications.source,
            brewAvailable: brew.available,
            masAvailable: mas.available
        )

        return ScanResult(
            scannedAt: scannedAt,
            includeGreedy: includeGreedy,
            summary: summary,
            applications: applications,
            brew: brew,
            mas: mas,
            performance: performance
        )
    }

    static func scanApplications() async -> ApplicationsScan {
        let result = await CommandRunner.run(
            "/usr/sbin/system_profiler",
            arguments: ["SPApplicationsDataType", "-json"],
            timeout: 120
        )

        guard result.ok, let data = result.stdout.data(using: .utf8) else {
            return await scanApplicationsByFind(reason: result.stderr)
        }

        do {
            let decoded = try JSONDecoder().decode(SystemProfilerPayload.self, from: data)
            let items = decoded.SPApplicationsDataType
                .compactMap(normalize)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if items.isEmpty {
                return await scanApplicationsByFind(reason: "system_profiler did not return application data.")
            }
            return ApplicationsScan(source: "system_profiler", ok: true, error: "", items: items)
        } catch {
            return await scanApplicationsByFind(reason: "system_profiler JSON parse failed: \(error.localizedDescription)")
        }
    }

    private struct BrewTaskOutput {
        let tag: String
        let result: CommandResult
    }

    static func scanBrew(includeGreedy: Bool) async -> BrewScan {
        guard let brewPath = await CommandRunner.commandPath("brew") else {
            return BrewScan(
                available: false,
                path: "",
                prefix: "",
                version: "",
                error: "Homebrew is not installed or not in PATH.",
                includeGreedy: includeGreedy,
                formulae: [],
                casks: []
            )
        }

        let timeout: TimeInterval = 30

        let results = await withTaskGroup(of: BrewTaskOutput.self) { group in
            group.addTask {
                BrewTaskOutput(tag: "version", result: await CommandRunner.run(brewPath, arguments: ["--version"], timeout: timeout))
            }
            group.addTask {
                BrewTaskOutput(tag: "prefix", result: await CommandRunner.run(brewPath, arguments: ["--prefix"], timeout: timeout))
            }
            group.addTask {
                BrewTaskOutput(tag: "formulaList", result: await CommandRunner.run(brewPath, arguments: ["list", "--formula", "--versions"], timeout: timeout))
            }
            group.addTask {
                BrewTaskOutput(tag: "caskList", result: await CommandRunner.run(brewPath, arguments: ["list", "--cask", "--versions"], timeout: timeout))
            }
            group.addTask {
                BrewTaskOutput(tag: "outdated", result: await CommandRunner.run(
                    brewPath,
                    arguments: ["outdated", "--json=v2"] + (includeGreedy ? ["--greedy"] : []),
                    timeout: timeout
                ))
            }

            var collected: [String: CommandResult] = [:]
            for await output in group {
                collected[output.tag] = output.result
            }
            return collected
        }

        let missingResult = CommandResult(ok: false, code: -1, stdout: "", stderr: "Homebrew scan task did not return a result.")
        let formulaList = results["formulaList"] ?? missingResult
        let caskList = results["caskList"] ?? missingResult
        let outdated = results["outdated"] ?? missingResult
        let caskNameList: CommandResult?
        if caskList.ok {
            caskNameList = nil
        } else {
            caskNameList = await CommandRunner.run(brewPath, arguments: ["list", "--cask", "-1"], timeout: timeout)
        }

        let formulaListResult = installedBrewPackages(primary: formulaList)
        let caskListResult = installedBrewPackages(primary: caskList, fallback: caskNameList)
        let installedFormulae = formulaListResult.packages
        let installedCasks = caskListResult.packages
        let outdatedPayload = parseBrewOutdated(outdated.stdout)
        let formulae = mergeBrew(installed: installedFormulae, outdated: outdatedPayload.formulae, kind: "formula")
        let casks = mergeBrew(installed: installedCasks, outdated: outdatedPayload.casks, kind: "cask")

        let errors = [
            formulaListResult.error,
            caskListResult.error,
            commandError(outdated)
        ]
            .filter { !$0.isEmpty }

        return BrewScan(
            available: true,
            path: brewPath,
            prefix: results["prefix"]?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            version: results["version"]?.stdout.components(separatedBy: .newlines).first ?? "",
            error: errors.joined(separator: "\n"),
            includeGreedy: includeGreedy,
            formulae: formulae,
            casks: casks
        )
    }

    static func scanMas() async -> MasScan {
        guard let masPath = await CommandRunner.commandPath("mas") else {
            return MasScan(
                available: false,
                path: "",
                error: "mas CLI is not installed. Install with: brew install mas",
                apps: []
            )
        }

        async let listTask = CommandRunner.run(masPath, arguments: ["list"], timeout: 60)
        async let outdatedTask = CommandRunner.run(masPath, arguments: ["outdated"], timeout: 60)
        let list = await listTask
        let outdated = await outdatedTask

        // Check for mas crashes (signal termination)
        var masErrors: [String] = []
        if list.wasSignaled {
            if let signalDesc = list.signalDescription {
                masErrors.append("mas list 命令崩溃：\(signalDesc)")
            } else {
                masErrors.append("mas list 命令异常退出 (exit code \(list.code))")
            }
            // If mas crashed, it's not usable - report as unavailable
            if list.code == 139 || list.code == 134 {
                // SIGSEGV or SIGABRT - mas needs App Store sign-in or is incompatible
                return MasScan(
                    available: false,
                    path: masPath,
                    error: "mas CLI 运行崩溃，可能需要在 App Store 中登录，或当前系统版本不兼容。请尝试在终端手动运行 `mas list` 检查。",
                    apps: []
                )
            }
        }
        if outdated.wasSignaled {
            if let signalDesc = outdated.signalDescription {
                masErrors.append("mas outdated 命令崩溃：\(signalDesc)")
            }
        }

        let outdatedById = Dictionary(outdated.stdout
            .components(separatedBy: .newlines)
            .compactMap(parseMasOutdatedLine)
            .map { ($0.appId, $0) }, uniquingKeysWith: { _, last in last })

        let apps: [MasApp] = list.stdout
            .components(separatedBy: .newlines)
            .compactMap { parseMasListLine($0) }
            .map { (app: MasApp) in
                var next = app
                if let pending = outdatedById[app.appId] {
                    next.currentVersion = pending.currentVersion
                    next.outdated = true
                    next.upgradeable = true
                }
                return next
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let stdErrors = [list, outdated]
            .filter { !$0.ok && !$0.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(\.stderr)
        
        masErrors.append(contentsOf: stdErrors)

        return MasScan(available: true, path: masPath, error: masErrors.joined(separator: "\n"), apps: apps)
    }

    private static func scanApplicationsByFind(reason: String) async -> ApplicationsScan {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let roots = [
            "/Applications",
            "\(home)/Applications",
            "/System/Applications",
            "/System/Applications/Utilities"
        ]

        let result = await CommandRunner.run(
            "/usr/bin/find",
            arguments: roots + ["-maxdepth", "3", "-type", "d", "-name", "*.app", "-prune", "-print"],
            timeout: 60
        )

        let items = result.stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { appPath in
                AppItem(
                    id: "app:\(appPath)",
                    name: URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent,
                    version: "",
                    availableVersion: "",
                    path: appPath,
                    source: guessSource(path: appPath, obtainedFrom: ""),
                    obtainedFrom: "",
                    architecture: "",
                    managedBy: "manual",
                    updateState: "unknown",
                    relatedPackageID: ""
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let error = result.ok ? reason : [reason, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        return ApplicationsScan(source: "find", ok: result.ok, error: error, items: items)
    }

    private static func normalize(_ item: SystemProfilerApp) -> AppItem? {
        let path = item.path ?? item.location ?? ""
        guard !path.isEmpty else { return nil }
        let name = item.name ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent

        return AppItem(
            id: "app:\(path)",
            name: name,
            version: item.version ?? item.shortVersion ?? "",
            availableVersion: "",
            path: path,
            source: guessSource(path: path, obtainedFrom: item.obtainedFrom ?? ""),
            obtainedFrom: item.obtainedFrom ?? "",
            architecture: item.architecture ?? item.kind ?? "",
            managedBy: "manual",
            updateState: "unknown",
            relatedPackageID: ""
        )
    }

    static func parseBrewVersionList(_ stdout: String) -> [(name: String, installedVersion: String)] {
        stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { line in
                let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
                guard let name = parts.first else { return nil }
                return (name, parts.dropFirst().joined(separator: ", "))
            }
    }

    static func installedBrewPackages(
        primary: CommandResult,
        fallback: CommandResult? = nil
    ) -> BrewInstalledPackagesResult {
        let primaryPackages = parseBrewVersionList(primary.stdout)
        if primary.ok {
            return BrewInstalledPackagesResult(packages: primaryPackages, error: "")
        }

        if let fallback, fallback.ok {
            return BrewInstalledPackagesResult(
                packages: parseBrewVersionList(fallback.stdout),
                error: ""
            )
        }

        let fallbackPackages = fallback.map { parseBrewVersionList($0.stdout) } ?? []
        let errors = [
            commandError(primary),
            fallback.map(commandError) ?? ""
        ]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return BrewInstalledPackagesResult(
            packages: primaryPackages.isEmpty ? fallbackPackages : primaryPackages,
            error: errors
        )
    }

    static func commandError(_ result: CommandResult) -> String {
        guard !result.ok else { return "" }
        return result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseBrewOutdated(_ stdout: String) -> (formulae: [[String: Any]], casks: [[String: Any]]) {
        guard let data = stdout.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], [])
        }
        return (
            object["formulae"] as? [[String: Any]] ?? [],
            object["casks"] as? [[String: Any]] ?? []
        )
    }

    static func mergeBrew(
        installed: [(name: String, installedVersion: String)],
        outdated: [[String: Any]],
        kind: String
    ) -> [BrewPackage] {
        let outdatedByName = Dictionary(outdated.compactMap { item -> (String, [String: Any])? in
            guard let name = item["name"] as? String else { return nil }
            return (name, item)
        }, uniquingKeysWith: { _, last in last })

        return installed.map { item in
            let pending = outdatedByName[item.name]
            let installedVersions = stringList(pending?["installed_versions"])
                ?? stringList(pending?["outdated_versions"])
                ?? [item.installedVersion].filter { !$0.isEmpty }
            let currentVersion = stringValue(pending?["current_version"]) ?? stringValue(pending?["newest_version"]) ?? ""
            let pinned = pending?["pinned"] as? Bool ?? false
            let autoUpdates = pending?["auto_updates"] as? Bool ?? false

            return BrewPackage(
                id: "brew:\(kind):\(item.name)",
                kind: kind,
                name: item.name,
                installedVersion: installedVersions.joined(separator: ", "),
                currentVersion: currentVersion,
                pinned: pinned,
                autoUpdates: autoUpdates,
                outdated: pending != nil,
                upgradeable: pending != nil && !pinned && !(kind == "cask" && autoUpdates)
            )
        }
        .sorted {
            if $0.outdated != $1.outdated { return $0.outdated && !$1.outdated }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func parseMasListLine(_ line: String) -> MasApp? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let firstSpace = trimmed.firstIndex(where: \.isWhitespace) else { return nil }
        let appId = String(trimmed[..<firstSpace])
        guard appId.allSatisfy(\.isNumber) else { return nil }

        let rest = trimmed[firstSpace...].trimmingCharacters(in: .whitespaces)
        var name = rest
        var version = ""

        if rest.hasSuffix(")"), let open = rest.lastIndex(of: "(") {
            name = rest[..<open].trimmingCharacters(in: .whitespaces)
            version = rest[rest.index(after: open)..<rest.index(before: rest.endIndex)]
                .trimmingCharacters(in: .whitespaces)
        }

        return MasApp(
            id: "mas:\(appId)",
            appId: appId,
            name: name,
            installedVersion: version,
            currentVersion: "",
            outdated: false,
            upgradeable: false
        )
    }

    static func parseMasOutdatedLine(_ line: String) -> MasApp? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains("(") {
            let parts = trimmed.components(separatedBy: "->").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if parts.count == 2,
               let firstSpace = parts[0].firstIndex(where: \.isWhitespace),
               let versionStart = parts[0].lastIndex(where: \.isWhitespace),
               firstSpace < versionStart {
                let appId = String(parts[0][..<firstSpace])
                let name = parts[0][parts[0].index(after: firstSpace)..<versionStart]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let installedVersion = String(parts[0][parts[0].index(after: versionStart)...])
                let app = MasApp(
                    id: "mas:\(appId)",
                    appId: appId,
                    name: name,
                    installedVersion: installedVersion,
                    currentVersion: parts[1],
                    outdated: true,
                    upgradeable: true
                )
                if app.appId.allSatisfy(\.isNumber), !app.name.isEmpty {
                    return app
                }
            }
        }

        guard var app = parseMasListLine(line) else { return nil }
        let parts = app.installedVersion.components(separatedBy: "->").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if parts.count == 2 {
            app.installedVersion = parts[0]
            app.currentVersion = parts[1]
        }
        app.outdated = true
        app.upgradeable = true
        return app
    }

    static func attachUpdateCapabilities(to apps: [AppItem]) -> [AppItem] {
        apps.map { app in
            var next = app
            let capability = RegularAppUpdateDiscovery.discover(appPath: app.path)
            next.updateCapability = capability
            if next.managedBy == "manual", capability.hasManualAction, next.updateState == "unknown" {
                next.updateState = "checkable"
            }
            return next
        }
    }

    static func classifyForTesting(_ apps: [AppItem], brew: BrewScan, mas: MasScan) -> [AppItem] {
        classify(apps, brew: brew, mas: mas)
    }

    typealias SparkleChecker = (String, String) async -> SparkleAppcastCheckResult

    static func enrichRegularAppUpdates(
        _ apps: [AppItem],
        networkPolicy: RegularAppNetworkPolicy,
        sparkleChecker: SparkleChecker = SparkleAppcastChecker.check
    ) async -> [AppItem] {
        guard networkPolicy != .localOnly else { return apps }

        var enriched: [AppItem] = []
        for app in apps {
            var next = app
            guard next.managedBy == "manual",
                  next.updateCapability.detector == .sparkle,
                  !next.updateCapability.feedURLString.isEmpty else {
                enriched.append(next)
                continue
            }

            let installedVersion = next.updateCapability.installedVersion.isEmpty
                ? next.version
                : next.updateCapability.installedVersion
            let result = await sparkleChecker(next.updateCapability.feedURLString, installedVersion)
            next.updateCapability.diagnostic = result.diagnostic
            if !result.availableVersion.isEmpty {
                next.availableVersion = result.availableVersion
                next.updateState = "outdated"
                next.updateCapability.summary = "Sparkle 发现新版本 \(result.availableVersion)"
            }
            enriched.append(next)
        }
        return enriched
    }

    private static func classify(_ apps: [AppItem], brew: BrewScan, mas: MasScan) -> [AppItem] {
        let caskByToken = Dictionary(brew.casks.map { (normalizeToken($0.name), $0) }, uniquingKeysWith: { _, last in last })
        let masByToken = Dictionary(mas.apps.map { (normalizeToken($0.name), $0) }, uniquingKeysWith: { _, last in last })

        return apps.map { app in
            var next = app
            let token = normalizeToken(app.name)
            if let cask = caskByToken[token] {
                next.managedBy = "brew-cask"
                next.updateState = cask.outdated ? "outdated" : "current"
                next.availableVersion = cask.currentVersion
                next.relatedPackageID = cask.id
            } else if let storeApp = masByToken[token] {
                next.managedBy = "mas"
                next.updateState = storeApp.outdated ? "outdated" : "current"
                next.availableVersion = storeApp.currentVersion
                next.relatedPackageID = storeApp.id
            } else if app.source == "Mac App Store" {
                next.managedBy = "mas"
                next.updateState = "unknown"
            }
            return next
        }
    }

    static func normalizeToken(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: ".app", with: "")
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func guessSource(path: String, obtainedFrom: String) -> String {
        let source = obtainedFrom.lowercased()
        if source.contains("app store") { return "Mac App Store" }
        if source.contains("identified developer") { return "Developer" }
        if source.contains("apple") { return "Apple" }
        if path.contains("/Cellar/") || path.contains("/Caskroom/") { return "Homebrew" }
        if path.hasPrefix("/System/") { return "Apple" }
        if path.hasPrefix("/Applications/") { return "Applications" }
        if path.contains("/Applications/") { return "User Applications" }
        return obtainedFrom.isEmpty ? "Unknown" : obtainedFrom
    }

    private static func stringList(_ value: Any?) -> [String]? {
        if let list = value as? [Any] {
            return list.compactMap { stringValue($0) }
        }
        if let value = stringValue(value), !value.isEmpty {
            return [value]
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        case let list as [Any]: return list.compactMap { stringValue($0) }.joined(separator: ", ")
        default: return nil
        }
    }
}

private struct SystemProfilerPayload: Decodable {
    var SPApplicationsDataType: [SystemProfilerApp]
}

private struct SystemProfilerApp: Decodable {
    var name: String?
    var version: String?
    var shortVersion: String?
    var path: String?
    var location: String?
    var obtainedFrom: String?
    var architecture: String?
    var kind: String?

    enum CodingKeys: String, CodingKey {
        case name = "_name"
        case version
        case shortVersion = "short_version"
        case path
        case location
        case obtainedFrom = "obtained_from"
        case architecture = "arch_kind"
        case kind
    }
}
