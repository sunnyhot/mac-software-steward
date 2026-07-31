# Download Acceleration Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a shared automatic download acceleration and slow-download recovery layer for Homebrew, `mas`, app self-update, direct replacement downloads, and daily helper commands.

**Architecture:** Add focused pure policy helpers in a new `DownloadAcceleration.swift`, then wire them into command execution and URLSession downloads through small integration points. Keep source-specific recovery scoped: Homebrew cache cleanup only touches the matching cask `.incomplete`, URLSession retries happen inside an `AcceleratedDownloader`, and UI status is derived from existing progress models.

**Tech Stack:** Swift 5, Foundation, SwiftUI/AppKit for existing UI only, `Process`, `URLSessionDownloadDelegate`, existing single-file Swift tests through `scripts/test-native.sh`.

## Global Constraints

- Native SwiftUI/AppKit app under `native/MacSoftwareSteward/`; no Xcode project.
- Build and tests run through `npm test` and `npm run build`.
- User-facing UI copy is Chinese; code identifiers stay English.
- Do not permanently change global system proxy, Homebrew config, user shell files, or Homebrew mirrors.
- Keep external tools such as `brew` and `mas` as the actual installers.
- Prefer focused pure helpers over adding more responsibility to `StewardModel.swift`.
- Avoid live network calls, package managers, LaunchAgent writes, and destructive commands in tests.
- Add new tests to `scripts/test-native.sh` with only the source files they need.
- Retry attempts must be bounded and cannot loop forever.

---

## File Structure

- Create `native/MacSoftwareSteward/DownloadAcceleration.swift`: strategy models, environment overlays, proxy dictionaries, slow/stall decisions, retry planning, and small formatting helpers.
- Create `tests/DownloadAccelerationPolicyTest.swift`: deterministic tests for strategy ranking, proxy environment overlays, slow/stall detection, and retry limits.
- Modify `native/MacSoftwareSteward/CommandRunner.swift`: accept optional `environmentOverlay` for `run` and `runStreamingDetailed`.
- Modify `tests/CommandRunnerControlTest.swift`: verify a child process sees the overlay without changing default environment behavior.
- Modify `native/MacSoftwareSteward/HomebrewDownloadMonitor.swift`: expose matching incomplete file lookup and package-scoped cleanup.
- Modify `tests/HomebrewDownloadMonitorTest.swift`: verify cleanup only removes matching cask incomplete files.
- Modify `native/MacSoftwareSteward/Models.swift`: add optional acceleration status fields to `PackageUpgradeProgress`.
- Modify `native/MacSoftwareSteward/UpgradeProgressPresenter.swift`: add acceleration hint formatting and stale-hint suppression while an acceleration retry is active.
- Modify `tests/UpgradeProgressPresenterTest.swift`: verify acceleration copy.
- Modify `native/MacSoftwareSteward/Views/UpdatesView.swift`: render acceleration status in running package rows.
- Modify `native/MacSoftwareSteward/StewardModel.swift`: rank strategies, run command attempts with overlays, request retries from Homebrew slow/stall monitoring, and log automatic recovery actions.
- Create `native/MacSoftwareSteward/AcceleratedDownloader.swift`: shared URLSession download wrapper with strategy retry and progress callbacks.
- Create `tests/AcceleratedDownloaderTest.swift`: fake-runner tests for retry order, status callbacks, and bounded attempts.
- Modify `native/MacSoftwareSteward/AppUpdater.swift`: use `AcceleratedDownloader` for release asset downloads and publish acceleration status in existing progress text.
- Modify `native/MacSoftwareSteward/ManualAppReplacementInstaller.swift`: add a small helper for destination file naming.
- Modify `native/MacSoftwareSteward/StewardModel.swift` direct replacement path: use `AcceleratedDownloader` instead of `URLSession.shared.download(for:)`, and expose a compact direct replacement status string.
- Modify `native/MacSoftwareSteward/Views/ApplicationsView.swift`: show the compact direct replacement status next to the existing direct replacement controls.
- Modify `scripts/test-native.sh`: add new test targets and include new source files in affected existing test targets.

## Task 1: Core Acceleration Policy Models

**Files:**
- Create: `native/MacSoftwareSteward/DownloadAcceleration.swift`
- Create: `tests/DownloadAccelerationPolicyTest.swift`
- Modify: `scripts/test-native.sh`

**Interfaces:**
- Produces: `DownloadAccelerationStrategy`, `DownloadAccelerationConfig`, `DownloadSpeedSample`, `SlowDownloadDecision`, `DownloadAccelerationPolicy`.
- Produces: `DownloadAccelerationPolicy.rankedStrategies(environment:systemProxyURLString:localProxyProbeResults:) -> [DownloadAccelerationStrategy]`.
- Produces: `DownloadAccelerationPolicy.decision(for:config:) -> SlowDownloadDecision`.
- Produces: `DownloadAccelerationPolicy.retryDecision(attemptIndex:strategyCount:maxAttempts:) -> DownloadRetryDecision`.

- [ ] **Step 1: Write the failing test**

Add `tests/DownloadAccelerationPolicyTest.swift`:

```swift
import Foundation

@main
struct DownloadAccelerationPolicyTest {
    static func main() {
        let environment = [
            "HTTPS_PROXY": "http://127.0.0.1:7890",
            "ALL_PROXY": "socks5://127.0.0.1:7891"
        ]
        let strategies = DownloadAccelerationPolicy.rankedStrategies(
            environment: environment,
            systemProxyURLString: "http://127.0.0.1:8080",
            localProxyProbeResults: [7890: true, 7897: false, 1080: true]
        )

        precondition(strategies.first?.kind == .inheritedProxy, "Inherited proxy should rank first when present")
        precondition(strategies.contains { $0.kind == .systemProxy && $0.proxyURLString == "http://127.0.0.1:8080" })
        precondition(strategies.contains { $0.kind == .localProxy && $0.proxyURLString == "http://127.0.0.1:1080" })
        precondition(strategies.last?.kind == .direct, "Direct fallback should be kept last")

        let overlay = strategies[0].environmentOverlay
        precondition(overlay["HTTPS_PROXY"] == "http://127.0.0.1:7890")
        precondition(overlay["https_proxy"] == "http://127.0.0.1:7890")

        let config = DownloadAccelerationConfig(
            minimumObservedDuration: 10,
            stalledAfter: 8,
            slowBytesPerSecond: 256 * 1024,
            requiredConsecutiveSlowSamples: 2,
            longRemainingTime: 20 * 60,
            smallDownloadLimitBytes: 1_000_000_000,
            maxAttempts: 3,
            maxCacheCleanups: 2
        )

        let healthy = DownloadSpeedSample(
            startedAt: Date(timeIntervalSince1970: 0),
            sampledAt: Date(timeIntervalSince1970: 12),
            byteCount: 20_000_000,
            expectedByteCount: 40_000_000,
            speedBytesPerSecond: 2_000_000,
            secondsSinceLastGrowth: 1,
            consecutiveSlowSamples: 0
        )
        precondition(DownloadAccelerationPolicy.decision(for: healthy, config: config) == .healthy)

        let slow = DownloadSpeedSample(
            startedAt: Date(timeIntervalSince1970: 0),
            sampledAt: Date(timeIntervalSince1970: 45),
            byteCount: 2_000_000,
            expectedByteCount: 100_000_000,
            speedBytesPerSecond: 100_000,
            secondsSinceLastGrowth: 2,
            consecutiveSlowSamples: 2
        )
        precondition(DownloadAccelerationPolicy.decision(for: slow, config: config).isRetryable)

        let stalled = DownloadSpeedSample(
            startedAt: Date(timeIntervalSince1970: 0),
            sampledAt: Date(timeIntervalSince1970: 20),
            byteCount: 10_000_000,
            expectedByteCount: 100_000_000,
            speedBytesPerSecond: 0,
            secondsSinceLastGrowth: 10,
            consecutiveSlowSamples: 0
        )
        precondition(DownloadAccelerationPolicy.decision(for: stalled, config: config) == .stalled("下载长时间没有增长"))

        precondition(DownloadAccelerationPolicy.retryDecision(attemptIndex: 0, strategyCount: 3, maxAttempts: 3) == .retry(nextAttemptIndex: 1))
        precondition(DownloadAccelerationPolicy.retryDecision(attemptIndex: 2, strategyCount: 3, maxAttempts: 3) == .stop)
    }
}
```

Add this target near `CommandRunnerControlTest` in `scripts/test-native.sh`:

```bash
run_test DownloadAccelerationPolicyTest \
  "$SRC/DownloadAcceleration.swift" \
  "$TESTS/DownloadAccelerationPolicyTest.swift"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test`

Expected: FAIL while building `DownloadAccelerationPolicyTest` with an error like `cannot find 'DownloadAccelerationPolicy' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `native/MacSoftwareSteward/DownloadAcceleration.swift`:

```swift
import Foundation

enum DownloadAccelerationStrategyKind: String, Hashable {
    case direct
    case inheritedProxy
    case systemProxy
    case localProxy
}

struct DownloadAccelerationStrategy: Hashable {
    var kind: DownloadAccelerationStrategyKind
    var proxyURLString: String?

    var title: String {
        switch kind {
        case .direct: return "直连"
        case .inheritedProxy: return "环境代理"
        case .systemProxy: return "系统代理"
        case .localProxy: return "本地代理"
        }
    }

    var environmentOverlay: [String: String] {
        guard let proxyURLString, kind != .direct else { return [:] }
        return [
            "HTTP_PROXY": proxyURLString,
            "HTTPS_PROXY": proxyURLString,
            "ALL_PROXY": proxyURLString,
            "http_proxy": proxyURLString,
            "https_proxy": proxyURLString,
            "all_proxy": proxyURLString
        ]
    }

    var connectionProxyDictionary: [AnyHashable: Any] {
        guard let proxyURLString,
              let url = URL(string: proxyURLString),
              let host = url.host else { return [:] }
        let port = url.port ?? (url.scheme?.lowercased().hasPrefix("https") == true ? 443 : 80)
        return [
            kCFNetworkProxiesHTTPEnable as String: true,
            kCFNetworkProxiesHTTPProxy as String: host,
            kCFNetworkProxiesHTTPPort as String: port,
            kCFNetworkProxiesHTTPSEnable as String: true,
            kCFNetworkProxiesHTTPSProxy as String: host,
            kCFNetworkProxiesHTTPSPort as String: port
        ]
    }
}

struct DownloadAccelerationConfig: Hashable {
    var minimumObservedDuration: TimeInterval
    var stalledAfter: TimeInterval
    var slowBytesPerSecond: Double
    var requiredConsecutiveSlowSamples: Int
    var longRemainingTime: TimeInterval
    var smallDownloadLimitBytes: Int64
    var maxAttempts: Int
    var maxCacheCleanups: Int

    static let production = DownloadAccelerationConfig(
        minimumObservedDuration: 45,
        stalledAfter: 30,
        slowBytesPerSecond: 256 * 1024,
        requiredConsecutiveSlowSamples: 2,
        longRemainingTime: 20 * 60,
        smallDownloadLimitBytes: 1_000_000_000,
        maxAttempts: 3,
        maxCacheCleanups: 2
    )
}

struct DownloadSpeedSample: Hashable {
    var startedAt: Date
    var sampledAt: Date
    var byteCount: Int64
    var expectedByteCount: Int64?
    var speedBytesPerSecond: Double?
    var secondsSinceLastGrowth: TimeInterval
    var consecutiveSlowSamples: Int

    var observedDuration: TimeInterval {
        max(sampledAt.timeIntervalSince(startedAt), 0)
    }

    var estimatedRemainingTime: TimeInterval? {
        guard let expectedByteCount,
              let speedBytesPerSecond,
              speedBytesPerSecond > 0,
              expectedByteCount > byteCount else { return nil }
        return Double(expectedByteCount - byteCount) / speedBytesPerSecond
    }
}

enum SlowDownloadDecision: Hashable {
    case healthy
    case slow(String)
    case stalled(String)

    var isRetryable: Bool {
        switch self {
        case .healthy: return false
        case .slow, .stalled: return true
        }
    }

    var message: String {
        switch self {
        case .healthy: return ""
        case .slow(let message), .stalled(let message): return message
        }
    }
}

enum DownloadRetryDecision: Hashable {
    case retry(nextAttemptIndex: Int)
    case stop
}

enum DownloadAccelerationPolicy {
    static func rankedStrategies(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        systemProxyURLString: String? = nil,
        localProxyProbeResults: [Int: Bool] = [:]
    ) -> [DownloadAccelerationStrategy] {
        var strategies: [DownloadAccelerationStrategy] = []

        if let inherited = inheritedProxyURLString(from: environment) {
            strategies.append(DownloadAccelerationStrategy(kind: .inheritedProxy, proxyURLString: inherited))
        }
        if let systemProxyURLString, !systemProxyURLString.isEmpty, !strategies.contains(where: { $0.proxyURLString == systemProxyURLString }) {
            strategies.append(DownloadAccelerationStrategy(kind: .systemProxy, proxyURLString: systemProxyURLString))
        }
        for port in localProxyProbeResults.keys.sorted() where localProxyProbeResults[port] == true {
            let proxy = "http://127.0.0.1:\(port)"
            if !strategies.contains(where: { $0.proxyURLString == proxy }) {
                strategies.append(DownloadAccelerationStrategy(kind: .localProxy, proxyURLString: proxy))
            }
        }
        strategies.append(DownloadAccelerationStrategy(kind: .direct, proxyURLString: nil))
        return strategies
    }

    static func decision(for sample: DownloadSpeedSample, config: DownloadAccelerationConfig = .production) -> SlowDownloadDecision {
        if sample.secondsSinceLastGrowth >= config.stalledAfter {
            return .stalled("下载长时间没有增长")
        }
        guard sample.observedDuration >= config.minimumObservedDuration else {
            return .healthy
        }
        if let speed = sample.speedBytesPerSecond,
           speed < config.slowBytesPerSecond,
           sample.consecutiveSlowSamples >= config.requiredConsecutiveSlowSamples {
            return .slow("下载速度持续偏低")
        }
        if let expected = sample.expectedByteCount,
           expected <= config.smallDownloadLimitBytes,
           let remaining = sample.estimatedRemainingTime,
           remaining >= config.longRemainingTime {
            return .slow("预计剩余时间过长")
        }
        return .healthy
    }

    static func retryDecision(attemptIndex: Int, strategyCount: Int, maxAttempts: Int) -> DownloadRetryDecision {
        let next = attemptIndex + 1
        guard next < strategyCount, next < maxAttempts else { return .stop }
        return .retry(nextAttemptIndex: next)
    }

    private static func inheritedProxyURLString(from environment: [String: String]) -> String? {
        for key in ["HTTPS_PROXY", "https_proxy", "ALL_PROXY", "all_proxy", "HTTP_PROXY", "http_proxy"] {
            if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`

Expected: `DownloadAccelerationPolicyTest` passes and the suite continues to the next test.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/DownloadAcceleration.swift tests/DownloadAccelerationPolicyTest.swift scripts/test-native.sh
git commit -m "feat: add download acceleration policy"
```

## Task 2: CommandRunner Environment Overlay

**Files:**
- Modify: `native/MacSoftwareSteward/CommandRunner.swift`
- Modify: `tests/CommandRunnerControlTest.swift`

**Interfaces:**
- Consumes: `DownloadAccelerationStrategy.environmentOverlay` from Task 1.
- Produces: `CommandRunner.run(_:arguments:timeout:environmentOverlay:)`.
- Produces: `CommandRunner.runStreamingDetailed(_:arguments:timeout:cancellationToken:environmentOverlay:onOutput:)`.

- [ ] **Step 1: Write the failing test**

Add this block to `CommandRunnerControlTest.main()` after the existing cancellation check:

```swift
let overlayResult = await CommandRunner.run(
    "/usr/bin/env",
    arguments: [],
    timeout: 5,
    environmentOverlay: ["MSS_TEST_OVERLAY": "works"]
)
precondition(overlayResult.ok)
precondition(overlayResult.stdout.contains("MSS_TEST_OVERLAY=works"))

let streamingOverlay = await CommandRunner.runStreamingDetailed(
    "/usr/bin/env",
    arguments: [],
    timeout: 5,
    environmentOverlay: ["MSS_STREAMING_OVERLAY": "streaming"]
) { _, _ in }
precondition(streamingOverlay.code == 0)
precondition(streamingOverlay.recentOutput.contains("MSS_STREAMING_OVERLAY=streaming"))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test`

Expected: FAIL while building `CommandRunnerControlTest` because `environmentOverlay` is an extra argument.

- [ ] **Step 3: Write minimal implementation**

In `CommandRunner.run`, change the signature to:

```swift
static func run(
    _ executable: String,
    arguments: [String],
    timeout: TimeInterval = 60,
    environmentOverlay: [String: String] = [:]
) async -> CommandResult
```

Inside it, replace:

```swift
process.environment = processEnvironment()
```

with:

```swift
process.environment = processEnvironment(overlay: environmentOverlay)
```

In `CommandRunner.runStreamingDetailed`, change the signature to:

```swift
static func runStreamingDetailed(
    _ executable: String,
    arguments: [String],
    timeout: TimeInterval = 7200,
    cancellationToken: CommandCancellationToken? = nil,
    environmentOverlay: [String: String] = [:],
    onOutput: @escaping @Sendable (String, String) -> Void
) async -> StreamingCommandResult
```

Inside it, replace:

```swift
process.environment = processEnvironment()
```

with:

```swift
process.environment = processEnvironment(overlay: environmentOverlay)
```

Keep `runStreaming` source-compatible by passing the default overlay:

```swift
let result = await runStreamingDetailed(executable, arguments: arguments, onOutput: onOutput)
```

Change the private environment helper to:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`

Expected: `CommandRunnerControlTest` passes.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/CommandRunner.swift tests/CommandRunnerControlTest.swift
git commit -m "feat: allow command environment overlays"
```

## Task 3: Homebrew Scoped Cache Cleanup Helpers

**Files:**
- Modify: `native/MacSoftwareSteward/HomebrewDownloadMonitor.swift`
- Modify: `tests/HomebrewDownloadMonitorTest.swift`

**Interfaces:**
- Consumes: existing `HomebrewDownloadMonitor.snapshot(packageName:in:previous:now:expectedByteCountHint:fileManager:)`.
- Produces: `HomebrewDownloadMonitor.matchingIncompleteFile(packageName:in:fileManager:) throws -> URL?`.
- Produces: `HomebrewDownloadMonitor.removeIncompleteDownload(packageName:in:fileManager:) throws -> URL?`.

- [ ] **Step 1: Write the failing test**

Add this block near the end of `HomebrewDownloadMonitorTest.main()` before the phase assertions:

```swift
let warpFile = directory.appendingPathComponent("ghi--warp.dmg.incomplete")
try Data(repeating: 3, count: 90).write(to: warpFile)
let otherFile = directory.appendingPathComponent("jkl--visual-studio-code.zip.incomplete")
try Data(repeating: 4, count: 120).write(to: otherFile)

let matchedWarp = try HomebrewDownloadMonitor.matchingIncompleteFile(packageName: "warp", in: directory)
precondition(matchedWarp?.lastPathComponent == warpFile.lastPathComponent)

let removedWarp = try HomebrewDownloadMonitor.removeIncompleteDownload(packageName: "warp", in: directory)
precondition(removedWarp?.lastPathComponent == warpFile.lastPathComponent)
precondition(!FileManager.default.fileExists(atPath: warpFile.path), "Expected only warp incomplete file to be removed")
precondition(FileManager.default.fileExists(atPath: otherFile.path), "Unrelated incomplete file must remain")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test`

Expected: FAIL while building `HomebrewDownloadMonitorTest` because `matchingIncompleteFile` is not defined.

- [ ] **Step 3: Write minimal implementation**

In `HomebrewDownloadMonitor`, add these public static helpers after `snapshot(...)`:

```swift
static func matchingIncompleteFile(
    packageName: String,
    in directory: URL = downloadsDirectory(),
    fileManager: FileManager = .default
) throws -> URL? {
    let candidates = try fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
        options: [.skipsHiddenFiles]
    )
    .filter { $0.lastPathComponent.hasSuffix(".incomplete") }
    .filter { matches(fileName: $0.lastPathComponent, packageName: packageName) }

    return newestFile(in: candidates)
}

@discardableResult
static func removeIncompleteDownload(
    packageName: String,
    in directory: URL = downloadsDirectory(),
    fileManager: FileManager = .default
) throws -> URL? {
    guard let file = try matchingIncompleteFile(packageName: packageName, in: directory, fileManager: fileManager) else {
        return nil
    }
    try fileManager.removeItem(at: file)
    return file
}
```

Then refactor `snapshot(...)` to use `matchingIncompleteFile(...)`:

```swift
guard let selected = try matchingIncompleteFile(packageName: packageName, in: directory, fileManager: fileManager) else {
    return nil
}
```

Keep the existing `previous` preference by adding this helper inside `snapshot(...)` before selecting:

```swift
let candidates = try fileManager.contentsOfDirectory(
    at: directory,
    includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
    options: [.skipsHiddenFiles]
)
.filter { $0.lastPathComponent.hasSuffix(".incomplete") }
.filter { matches(fileName: $0.lastPathComponent, packageName: packageName) }

guard !candidates.isEmpty else { return nil }
let selected = candidates.first { $0 == previous?.fileURL } ?? newestFile(in: candidates)
```

Use `matchingIncompleteFile` for cleanup only; keep `snapshot` previous-file behavior intact.

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`

Expected: `HomebrewDownloadMonitorTest` passes.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/HomebrewDownloadMonitor.swift tests/HomebrewDownloadMonitorTest.swift
git commit -m "feat: add scoped homebrew download cleanup"
```

## Task 4: Acceleration Status Model and Presenter

**Files:**
- Modify: `native/MacSoftwareSteward/Models.swift`
- Modify: `native/MacSoftwareSteward/UpgradeProgressPresenter.swift`
- Modify: `tests/UpgradeProgressPresenterTest.swift`
- Modify: `native/MacSoftwareSteward/Views/UpdatesView.swift`

**Interfaces:**
- Produces: `PackageUpgradeProgress.accelerationStatusText`, `accelerationStrategyText`, `accelerationAttemptText`.
- Produces: `UpgradeProgressPresenter.accelerationHint(for:) -> String?`.

- [ ] **Step 1: Write the failing test**

Add this block to `UpgradeProgressPresenterTest.main()` before the final queued hint assertion:

```swift
let accelerating = PackageUpgradeProgress(
    packageID: "brew:cask:warp",
    packageName: "warp",
    status: .running,
    detail: "正在下载",
    phaseText: "下载中",
    updatedAt: now,
    accelerationStatusText: "下载速度持续偏低，正在自动加速",
    accelerationStrategyText: "系统代理",
    accelerationAttemptText: "第 2/3 次"
)
let accelerationHint = UpgradeProgressPresenter.accelerationHint(for: accelerating)
precondition(accelerationHint == "下载速度持续偏低，正在自动加速：系统代理（第 2/3 次）", "Unexpected acceleration hint: \(String(describing: accelerationHint))")
precondition(UpgradeProgressPresenter.staleHint(for: accelerating, now: now.addingTimeInterval(300)) == nil)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test`

Expected: FAIL while building `UpgradeProgressPresenterTest` because the new `PackageUpgradeProgress` fields and presenter method do not exist.

- [ ] **Step 3: Write minimal implementation**

In `Models.swift`, add these fields to `PackageUpgradeProgress` after `downloadTimeRemainingText`:

```swift
/// 自动下载加速状态描述。
var accelerationStatusText: String? = nil
/// 当前使用的下载策略描述。
var accelerationStrategyText: String? = nil
/// 当前重试次数描述。
var accelerationAttemptText: String? = nil
```

In `UpgradeProgressPresenter.swift`, add:

```swift
static func accelerationHint(for progress: PackageUpgradeProgress) -> String? {
    guard let status = progress.accelerationStatusText?.trimmingCharacters(in: .whitespacesAndNewlines),
          !status.isEmpty else { return nil }
    let strategy = progress.accelerationStrategyText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let attempt = progress.accelerationAttemptText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !strategy.isEmpty, !attempt.isEmpty {
        return "\(status)：\(strategy)（\(attempt)）"
    }
    if !strategy.isEmpty {
        return "\(status)：\(strategy)"
    }
    if !attempt.isEmpty {
        return "\(status)（\(attempt)）"
    }
    return status
}
```

At the start of `staleHint(for:now:)`, after the running-status guard, add:

```swift
if accelerationHint(for: progress) != nil {
    return nil
}
```

In `UpdatesView.swift`, inside `PackageProgressDetail.runningProgress`, insert this block before the stale hint:

```swift
if let accelerationHint = UpgradeProgressPresenter.accelerationHint(for: progress) {
    Label(accelerationHint, systemImage: "bolt.horizontal.circle.fill")
        .font(.caption)
        .foregroundStyle(.blue)
        .fixedSize(horizontal: false, vertical: true)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`

Expected: `UpgradeProgressPresenterTest` passes.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/Models.swift native/MacSoftwareSteward/UpgradeProgressPresenter.swift native/MacSoftwareSteward/Views/UpdatesView.swift tests/UpgradeProgressPresenterTest.swift
git commit -m "feat: show download acceleration status"
```

## Task 5: Strategy Discovery for Runtime Use

**Files:**
- Modify: `native/MacSoftwareSteward/DownloadAcceleration.swift`
- Modify: `tests/DownloadAccelerationPolicyTest.swift`

**Interfaces:**
- Consumes: Task 1 policy models.
- Produces: `DownloadAccelerationPolicy.systemProxyURLString(from:) -> String?`.
- Produces: `DownloadAccelerationPolicy.localProxyProbeResults(ports:timeout:) async -> [Int: Bool]`.
- Produces: `DownloadAccelerationPolicy.defaultStrategies() async -> [DownloadAccelerationStrategy]`.

- [ ] **Step 1: Write the failing test**

Add this block to `DownloadAccelerationPolicyTest.main()`:

```swift
let scutilOutput = """
<dictionary> {
  HTTPEnable : 1
  HTTPPort : 7890
  HTTPProxy : 127.0.0.1
  HTTPSEnable : 1
  HTTPSPort : 7890
  HTTPSProxy : 127.0.0.1
}
"""
let parsedSystemProxy = DownloadAccelerationPolicy.systemProxyURLString(from: scutilOutput)
precondition(parsedSystemProxy == "http://127.0.0.1:7890", "Unexpected system proxy: \(String(describing: parsedSystemProxy))")

let disabledScutilOutput = """
<dictionary> {
  HTTPEnable : 0
  HTTPPort : 7890
  HTTPProxy : 127.0.0.1
}
"""
precondition(DownloadAccelerationPolicy.systemProxyURLString(from: disabledScutilOutput) == nil)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test`

Expected: FAIL because `systemProxyURLString(from:)` is not defined.

- [ ] **Step 3: Write minimal implementation**

Add to `DownloadAccelerationPolicy`:

```swift
static func systemProxyURLString(from scutilOutput: String) -> String? {
    let lines = scutilOutput.components(separatedBy: .newlines)
    func value(for key: String) -> String? {
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count == 2, parts[0] == key, !parts[1].isEmpty {
                return parts[1]
            }
        }
        return nil
    }

    let httpsEnabled = value(for: "HTTPSEnable") == "1"
    let httpEnabled = value(for: "HTTPEnable") == "1"
    if httpsEnabled,
       let host = value(for: "HTTPSProxy"),
       let port = value(for: "HTTPSPort") {
        return "http://\(host):\(port)"
    }
    if httpEnabled,
       let host = value(for: "HTTPProxy"),
       let port = value(for: "HTTPPort") {
        return "http://\(host):\(port)"
    }
    return nil
}

static func localProxyProbeResults(
    ports: [Int] = [7890, 7897, 1080, 8080, 6152],
    timeout: TimeInterval = 0.2
) async -> [Int: Bool] {
    var results: [Int: Bool] = [:]
    for port in ports {
        results[port] = await canOpenLocalTCPConnection(port: port, timeout: timeout)
    }
    return results
}

static func defaultStrategies() async -> [DownloadAccelerationStrategy] {
    let systemProxy = await currentSystemProxyURLString()
    let localResults = await localProxyProbeResults()
    return rankedStrategies(
        environment: ProcessInfo.processInfo.environment,
        systemProxyURLString: systemProxy,
        localProxyProbeResults: localResults
    )
}

private static func currentSystemProxyURLString() async -> String? {
    let result = await CommandRunner.run("/usr/sbin/scutil", arguments: ["--proxy"], timeout: 2)
    guard result.ok else { return nil }
    return systemProxyURLString(from: result.stdout)
}

private static func canOpenLocalTCPConnection(port: Int, timeout: TimeInterval) async -> Bool {
    await withCheckedContinuation { continuation in
        let host = "127.0.0.1"
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            continuation.resume(returning: false)
            return
        }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        inet_pton(AF_INET, host, &address.sin_addr)

        DispatchQueue.global().async {
            var addr = address
            let connected = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                }
            }
            close(socketFD)
            continuation.resume(returning: connected)
        }
    }
}
```

Add `import Darwin` at the top of `DownloadAcceleration.swift`.

Because `currentSystemProxyURLString()` uses `CommandRunner`, update `DownloadAccelerationPolicyTest` in `scripts/test-native.sh` to include `"$SRC/CommandRunner.swift"` before `"$SRC/DownloadAcceleration.swift"`.

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`

Expected: `DownloadAccelerationPolicyTest` passes.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/DownloadAcceleration.swift tests/DownloadAccelerationPolicyTest.swift scripts/test-native.sh
git commit -m "feat: discover download acceleration strategies"
```

## Task 6: Command Attempt Loop and Homebrew Slow Retry

**Files:**
- Modify: `native/MacSoftwareSteward/StewardModel.swift`
- Modify: `tests/StewardModelScanGuardTest.swift`
- Modify: `scripts/test-native.sh`

**Interfaces:**
- Consumes: `DownloadAccelerationPolicy.defaultStrategies()`, `DownloadAccelerationPolicy.decision`, `CommandRunner.runStreamingDetailed(...environmentOverlay:)`.
- Produces: `StewardModel` command attempts that retry a package step when Homebrew monitor requests acceleration.
- Produces internal helpers: `applyAccelerationStatus`, `clearAccelerationStatus`, `requestDownloadAccelerationRetry`.

- [ ] **Step 1: Write the failing test**

Add a pure helper test to `tests/StewardModelScanGuardTest.swift` if that file already exercises package progress, or create `tests/DownloadAccelerationCommandPlannerTest.swift` with this content:

```swift
import Foundation

@main
struct DownloadAccelerationCommandPlannerTest {
    static func main() {
        let strategies = [
            DownloadAccelerationStrategy(kind: .inheritedProxy, proxyURLString: "http://127.0.0.1:7890"),
            DownloadAccelerationStrategy(kind: .systemProxy, proxyURLString: "http://127.0.0.1:8080"),
            DownloadAccelerationStrategy(kind: .direct, proxyURLString: nil)
        ]
        let first = CommandAccelerationAttempt(strategies: strategies, attemptIndex: 0, maxAttempts: 3)
        precondition(first.currentStrategy.title == "环境代理")
        precondition(first.attemptText == "第 1/3 次")
        precondition(first.next()?.currentStrategy.title == "系统代理")
        precondition(first.next()?.next()?.currentStrategy.title == "直连")
        precondition(first.next()?.next()?.next() == nil)
    }
}
```

Add this target to `scripts/test-native.sh` after `DownloadAccelerationPolicyTest`:

```bash
run_test DownloadAccelerationCommandPlannerTest \
  "$SRC/CommandRunner.swift" \
  "$SRC/DownloadAcceleration.swift" \
  "$TESTS/DownloadAccelerationCommandPlannerTest.swift"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test`

Expected: FAIL because `CommandAccelerationAttempt` is not defined.

- [ ] **Step 3: Write minimal helper implementation**

Add this struct to `DownloadAcceleration.swift`:

```swift
struct CommandAccelerationAttempt: Hashable {
    var strategies: [DownloadAccelerationStrategy]
    var attemptIndex: Int
    var maxAttempts: Int

    var currentStrategy: DownloadAccelerationStrategy {
        strategies[min(attemptIndex, max(strategies.count - 1, 0))]
    }

    var attemptText: String {
        "第 \(attemptIndex + 1)/\(min(maxAttempts, strategies.count)) 次"
    }

    func next() -> CommandAccelerationAttempt? {
        switch DownloadAccelerationPolicy.retryDecision(
            attemptIndex: attemptIndex,
            strategyCount: strategies.count,
            maxAttempts: maxAttempts
        ) {
        case .retry(let nextAttemptIndex):
            return CommandAccelerationAttempt(strategies: strategies, attemptIndex: nextAttemptIndex, maxAttempts: maxAttempts)
        case .stop:
            return nil
        }
    }
}
```

- [ ] **Step 4: Run helper test to verify it passes**

Run: `npm test`

Expected: `DownloadAccelerationCommandPlannerTest` passes.

- [ ] **Step 5: Wire `StewardModel` command execution**

Add these private properties near existing download monitor task dictionaries:

```swift
private var downloadAccelerationStrategies: [String: [DownloadAccelerationStrategy]] = [:]
private var downloadAccelerationAttempts: [String: CommandAccelerationAttempt] = [:]
private var downloadAccelerationRetryRequests: [String: SlowDownloadDecision] = [:]
private var downloadAccelerationTokens: [String: CommandCancellationToken] = [:]
private var downloadAccelerationCleanups: [String: Int] = [:]
private var downloadSlowSampleState: [String: (startedAt: Date, lastGrowthAt: Date, lastByteCount: Int64, consecutiveSlowSamples: Int)] = [:]
```

Add helpers:

```swift
private func accelerationKey(for step: UpgradeStep) -> String {
    step.packageID ?? step.command.display
}

private func strategiesForStep(_ step: UpgradeStep) async -> [DownloadAccelerationStrategy] {
    let key = accelerationKey(for: step)
    if let existing = downloadAccelerationStrategies[key] {
        return existing
    }
    let strategies = await DownloadAccelerationPolicy.defaultStrategies()
    await MainActor.run {
        self.downloadAccelerationStrategies[key] = strategies
    }
    return strategies
}

private func applyAccelerationStatus(_ attempt: CommandAccelerationAttempt, to step: UpgradeStep, status: String) {
    guard let packageID = step.packageID, var progress = packageProgress[packageID] else { return }
    progress.accelerationStatusText = status
    progress.accelerationStrategyText = attempt.currentStrategy.title
    progress.accelerationAttemptText = attempt.attemptText
    packageProgress[packageID] = progress
}

private func clearAccelerationStatus(for step: UpgradeStep) {
    guard let packageID = step.packageID, var progress = packageProgress[packageID] else { return }
    progress.accelerationStatusText = nil
    progress.accelerationStrategyText = nil
    progress.accelerationAttemptText = nil
    packageProgress[packageID] = progress
}

private func requestDownloadAccelerationRetry(packageID: String, decision: SlowDownloadDecision) {
    guard downloadAccelerationRetryRequests[packageID] == nil else { return }
    downloadAccelerationRetryRequests[packageID] = decision
    downloadAccelerationTokens[packageID]?.cancel()
}
```

Replace `runCommand(jobID:step:command:token:)` implementation with an attempt loop:

```swift
private func runCommand(jobID id: UUID, step: UpgradeStep, command: UpgradeCommand, token: CommandCancellationToken) async -> StreamingCommandResult {
    let strategies = await strategiesForStep(step)
    var attempt = CommandAccelerationAttempt(
        strategies: strategies,
        attemptIndex: 0,
        maxAttempts: DownloadAccelerationConfig.production.maxAttempts
    )
    let key = accelerationKey(for: step)

    while true {
        if token.isCancelled {
            return StreamingCommandResult(code: -1, recentOutput: "", terminationReason: .cancelled)
        }

        let attemptToken = CommandCancellationToken()
        downloadAccelerationTokens[key] = attemptToken
        applyAccelerationStatus(attempt, to: step, status: attempt.attemptIndex == 0 ? "正在自动选择最快下载方式" : "下载偏慢，正在自动切换加速方式重试")
        appendLog(id: id, stream: "system", text: "下载加速：本次命令使用\(attempt.currentStrategy.title)（\(attempt.attemptText)）。")

        Task {
            while !attemptToken.isCancelled {
                if token.isCancelled {
                    attemptToken.cancel()
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        let result = await CommandRunner.runStreamingDetailed(
            command.executable,
            arguments: command.arguments,
            timeout: 7200,
            cancellationToken: attemptToken,
            environmentOverlay: attempt.currentStrategy.environmentOverlay
        ) { stream, text in
            Task { @MainActor in
                self.appendLog(id: id, stream: stream, text: text)
                self.updatePackageDetail(for: step, stream: stream, text: text)
            }
        }

        downloadAccelerationTokens[key] = nil
        if result.terminationReason == .cancelled,
           let decision = downloadAccelerationRetryRequests.removeValue(forKey: key),
           let next = attempt.next() {
            appendLog(id: id, stream: "system", text: "\(decision.message)，正在切换到\(next.currentStrategy.title)重试。")
            attempt = next
            continue
        }

        clearAccelerationStatus(for: step)
        return result
    }
}
```

In `runPackageStepsConcurrently`, replace the inline `CommandRunner.runStreamingDetailed` call with:

```swift
let result = await model.runCommand(jobID: id, step: step, command: command, token: token)
```

- [ ] **Step 6: Feed Homebrew slow decisions into retry requests**

In `applyHomebrewDownloadSnapshot`, after applying download fields and before saving `packageProgress`, add:

```swift
let key = packageID
let now = Date()
var state = downloadSlowSampleState[key] ?? (startedAt: now, lastGrowthAt: now, lastByteCount: snapshot.byteCount, consecutiveSlowSamples: 0)
if snapshot.byteCount > state.lastByteCount {
    state.lastGrowthAt = now
    state.lastByteCount = snapshot.byteCount
}
let isSlowSpeed = (snapshot.speedBytesPerSecond ?? Double.greatestFiniteMagnitude) < DownloadAccelerationConfig.production.slowBytesPerSecond
state.consecutiveSlowSamples = isSlowSpeed ? state.consecutiveSlowSamples + 1 : 0
downloadSlowSampleState[key] = state

let sample = DownloadSpeedSample(
    startedAt: state.startedAt,
    sampledAt: now,
    byteCount: snapshot.byteCount,
    expectedByteCount: snapshot.expectedByteCount,
    speedBytesPerSecond: snapshot.speedBytesPerSecond,
    secondsSinceLastGrowth: now.timeIntervalSince(state.lastGrowthAt),
    consecutiveSlowSamples: state.consecutiveSlowSamples
)
let decision = DownloadAccelerationPolicy.decision(for: sample)
if decision.isRetryable {
    requestDownloadAccelerationRetry(packageID: packageID, decision: decision)
}
```

In `stopHomebrewDownloadMonitor(packageID:)`, clear the new state dictionaries for that package:

```swift
downloadAccelerationTokens[packageID]?.cancel()
downloadAccelerationTokens[packageID] = nil
downloadAccelerationRetryRequests[packageID] = nil
downloadAccelerationAttempts[packageID] = nil
downloadAccelerationStrategies[packageID] = nil
downloadAccelerationCleanups[packageID] = nil
downloadSlowSampleState[packageID] = nil
```

- [ ] **Step 7: Run tests**

Run: `npm test`

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add native/MacSoftwareSteward/DownloadAcceleration.swift native/MacSoftwareSteward/StewardModel.swift tests/DownloadAccelerationCommandPlannerTest.swift scripts/test-native.sh
git commit -m "feat: retry slow command downloads"
```

## Task 7: Homebrew Cleanup on Stalled Cask Retry

**Files:**
- Modify: `native/MacSoftwareSteward/StewardModel.swift`
- Modify: `tests/DownloadAccelerationPolicyTest.swift`

**Interfaces:**
- Consumes: `HomebrewDownloadMonitor.removeIncompleteDownload`.
- Produces: package-scoped cleanup during cask retries only when the slow decision is `.stalled`.

- [ ] **Step 1: Write the failing test**

Add this block to `DownloadAccelerationPolicyTest.main()`:

```swift
precondition(DownloadAccelerationPolicy.shouldCleanPartialDownload(for: .stalled("下载长时间没有增长"), cleanupCount: 0, maxCleanups: 2))
precondition(DownloadAccelerationPolicy.shouldCleanPartialDownload(for: .stalled("下载长时间没有增长"), cleanupCount: 1, maxCleanups: 2))
precondition(!DownloadAccelerationPolicy.shouldCleanPartialDownload(for: .stalled("下载长时间没有增长"), cleanupCount: 2, maxCleanups: 2))
precondition(!DownloadAccelerationPolicy.shouldCleanPartialDownload(for: .slow("下载速度持续偏低"), cleanupCount: 0, maxCleanups: 2))
precondition(!DownloadAccelerationPolicy.shouldCleanPartialDownload(for: .healthy, cleanupCount: 0, maxCleanups: 2))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test`

Expected: FAIL because `shouldCleanPartialDownload` is not defined.

- [ ] **Step 3: Write minimal implementation**

Add to `DownloadAccelerationPolicy`:

```swift
static func shouldCleanPartialDownload(
    for decision: SlowDownloadDecision,
    cleanupCount: Int,
    maxCleanups: Int
) -> Bool {
    guard cleanupCount < maxCleanups else { return false }
    if case .stalled = decision {
        return true
    }
    return false
}
```

- [ ] **Step 4: Wire cleanup into retry loop**

In `StewardModel.runCommand`, inside the retry branch before assigning `attempt = next`, add:

```swift
if let packageName = step.packageName,
   isHomebrewCaskUpgrade(step),
   DownloadAccelerationPolicy.shouldCleanPartialDownload(
       for: decision,
       cleanupCount: downloadAccelerationCleanups[key] ?? 0,
       maxCleanups: DownloadAccelerationConfig.production.maxCacheCleanups
   ) {
    do {
        if let removed = try HomebrewDownloadMonitor.removeIncompleteDownload(packageName: packageName) {
            downloadAccelerationCleanups[key, default: 0] += 1
            appendLog(id: id, stream: "system", text: "检测到 Homebrew 缓存文件无增长，已清理当前 cask 的未完成下载：\(removed.lastPathComponent)")
        }
    } catch {
        appendLog(id: id, stream: "system", text: "清理 Homebrew 未完成下载失败：\(error.localizedDescription)")
    }
}
```

- [ ] **Step 5: Run tests**

Run: `npm test`

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add native/MacSoftwareSteward/DownloadAcceleration.swift native/MacSoftwareSteward/StewardModel.swift tests/DownloadAccelerationPolicyTest.swift
git commit -m "feat: clean stalled cask downloads"
```

## Task 8: AcceleratedDownloader Core

**Files:**
- Create: `native/MacSoftwareSteward/AcceleratedDownloader.swift`
- Create: `tests/AcceleratedDownloaderTest.swift`
- Modify: `scripts/test-native.sh`

**Interfaces:**
- Consumes: `DownloadAccelerationStrategy`, `DownloadAccelerationConfig`, `DownloadAccelerationPolicy`.
- Produces: `AcceleratedDownloadRequest`.
- Produces: `AcceleratedDownloadProgress`.
- Produces: `AcceleratedDownloader.download(_:strategies:config:runner:onProgress:onStatus:) async throws -> URL`.

- [ ] **Step 1: Write the failing test**

Add `tests/AcceleratedDownloaderTest.swift`:

```swift
import Foundation

@main
struct AcceleratedDownloaderTest {
    static func main() async throws {
        let strategies = [
            DownloadAccelerationStrategy(kind: .inheritedProxy, proxyURLString: "http://127.0.0.1:7890"),
            DownloadAccelerationStrategy(kind: .direct, proxyURLString: nil)
        ]
        let request = AcceleratedDownloadRequest(
            url: URL(string: "https://example.com/app.zip")!,
            destinationFileName: "app.zip",
            expectedByteCount: 10,
            operationName: "测试下载"
        )
        var attempts: [String] = []
        var statuses: [String] = []
        let finalURL = try await AcceleratedDownloader.download(
            request,
            strategies: strategies,
            config: DownloadAccelerationConfig(
                minimumObservedDuration: 1,
                stalledAfter: 1,
                slowBytesPerSecond: 1,
                requiredConsecutiveSlowSamples: 1,
                longRemainingTime: 1,
                smallDownloadLimitBytes: 100,
                maxAttempts: 2,
                maxCacheCleanups: 0
            ),
            runner: { attempt, progress in
                attempts.append(attempt.strategy.title)
                progress(AcceleratedDownloadProgress(
                    byteCount: 1,
                    expectedByteCount: 10,
                    speedBytesPerSecond: 1,
                    statusText: "采样"
                ))
                if attempt.index == 0 {
                    throw AcceleratedDownloadError.retryable("模拟慢下载")
                }
                return URL(fileURLWithPath: "/tmp/app.zip")
            },
            onProgress: { progress in
                precondition(progress.byteCount == 1)
            },
            onStatus: { status in
                statuses.append(status)
            }
        )

        precondition(finalURL.path == "/tmp/app.zip")
        precondition(attempts == ["环境代理", "直连"], "Unexpected attempts: \(attempts)")
        precondition(statuses.contains { $0.contains("模拟慢下载") })
    }
}
```

Add target:

```bash
run_test AcceleratedDownloaderTest \
  "$SRC/CommandRunner.swift" \
  "$SRC/DownloadAcceleration.swift" \
  "$SRC/AcceleratedDownloader.swift" \
  "$TESTS/AcceleratedDownloaderTest.swift"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test`

Expected: FAIL because `AcceleratedDownloader` is not defined.

- [ ] **Step 3: Write minimal implementation**

Create `native/MacSoftwareSteward/AcceleratedDownloader.swift`:

```swift
import Foundation

struct AcceleratedDownloadRequest: Hashable {
    var url: URL
    var destinationFileName: String
    var expectedByteCount: Int64?
    var operationName: String
}

struct AcceleratedDownloadProgress: Hashable {
    var byteCount: Int64
    var expectedByteCount: Int64?
    var speedBytesPerSecond: Double?
    var statusText: String
}

struct AcceleratedDownloadAttempt: Hashable {
    var index: Int
    var strategy: DownloadAccelerationStrategy
    var request: AcceleratedDownloadRequest
}

enum AcceleratedDownloadError: LocalizedError, Equatable {
    case retryable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .retryable(let message), .failed(let message):
            return message
        }
    }
}

enum AcceleratedDownloader {
    typealias Runner = (
        AcceleratedDownloadAttempt,
        @escaping @Sendable (AcceleratedDownloadProgress) -> Void
    ) async throws -> URL

    static func download(
        _ request: AcceleratedDownloadRequest,
        strategies: [DownloadAccelerationStrategy],
        config: DownloadAccelerationConfig = .production,
        runner: Runner? = nil,
        onProgress: @escaping @Sendable (AcceleratedDownloadProgress) -> Void = { _ in },
        onStatus: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> URL {
        let effectiveStrategies = strategies.isEmpty
            ? [DownloadAccelerationStrategy(kind: .direct, proxyURLString: nil)]
            : strategies
        let run = runner ?? urlSessionRunner
        var attemptIndex = 0
        var lastError: Error?

        while attemptIndex < min(config.maxAttempts, effectiveStrategies.count) {
            let strategy = effectiveStrategies[attemptIndex]
            let attempt = AcceleratedDownloadAttempt(index: attemptIndex, strategy: strategy, request: request)
            onStatus("正在使用\(strategy.title)下载（第 \(attemptIndex + 1)/\(min(config.maxAttempts, effectiveStrategies.count)) 次）")
            do {
                return try await run(attempt, onProgress)
            } catch AcceleratedDownloadError.retryable(let message) {
                lastError = AcceleratedDownloadError.retryable(message)
                let retry = DownloadAccelerationPolicy.retryDecision(
                    attemptIndex: attemptIndex,
                    strategyCount: effectiveStrategies.count,
                    maxAttempts: config.maxAttempts
                )
                switch retry {
                case .retry(let next):
                    onStatus("\(message)，正在自动切换加速方式重试")
                    attemptIndex = next
                    continue
                case .stop:
                    throw AcceleratedDownloadError.failed(message)
                }
            } catch {
                lastError = error
                throw error
            }
        }

        throw lastError ?? AcceleratedDownloadError.failed("下载失败。")
    }

    private static func urlSessionRunner(
        attempt: AcceleratedDownloadAttempt,
        onProgress: @escaping @Sendable (AcceleratedDownloadProgress) -> Void
    ) async throws -> URL {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        if !attempt.strategy.connectionProxyDictionary.isEmpty {
            configuration.connectionProxyDictionary = attempt.strategy.connectionProxyDictionary
        }

        let delegate = AcceleratedURLSessionDelegate(
            expectedByteCount: attempt.request.expectedByteCount,
            onProgress: onProgress
        )
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: attempt.request.url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.setValue("MacSoftwareSteward", forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)
        let downloaded = try await delegate.waitForDownload(task)
        if let http = task.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AcceleratedDownloadError.retryable("下载服务返回 HTTP \(http.statusCode)")
        }
        return downloaded
    }
}

private final class AcceleratedURLSessionDelegate: NSObject, URLSessionDownloadDelegate {
    private let expectedByteCount: Int64?
    private let onProgress: @Sendable (AcceleratedDownloadProgress) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var lastBytes: Int64 = 0
    private var lastDate = Date()

    init(expectedByteCount: Int64?, onProgress: @escaping @Sendable (AcceleratedDownloadProgress) -> Void) {
        self.expectedByteCount = expectedByteCount
        self.onProgress = onProgress
    }

    func waitForDownload(_ task: URLSessionDownloadTask) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        continuation?.resume(returning: location)
        continuation = nil
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let now = Date()
        let interval = now.timeIntervalSince(lastDate)
        let speed = interval > 0 ? Double(totalBytesWritten - lastBytes) / interval : nil
        lastDate = now
        lastBytes = totalBytesWritten
        onProgress(AcceleratedDownloadProgress(
            byteCount: totalBytesWritten,
            expectedByteCount: totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedByteCount,
            speedBytesPerSecond: speed,
            statusText: "正在下载"
        ))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`

Expected: `AcceleratedDownloaderTest` passes.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/AcceleratedDownloader.swift tests/AcceleratedDownloaderTest.swift scripts/test-native.sh
git commit -m "feat: add accelerated downloader"
```

## Task 9: AppUpdateModel Integration

**Files:**
- Modify: `native/MacSoftwareSteward/AppUpdater.swift`
- Modify: `scripts/test-native.sh`

**Interfaces:**
- Consumes: `AcceleratedDownloader.download`.
- Preserves: `AppUpdateSecurity.verifySHA256`, unzip, install scheduling, and existing update dialog fields.

- [ ] **Step 1: Write a focused failing test for status formatting**

Add a pure status-formatting helper in `AppUpdateModel` and test it with `tests/AppUpdaterDownloadStatusTest.swift`:

```swift
import Foundation

@main
struct AppUpdaterDownloadStatusTest {
    static func main() {
        let progress = AcceleratedDownloadProgress(
            byteCount: 50,
            expectedByteCount: 100,
            speedBytesPerSecond: 10,
            statusText: "正在下载"
        )
        let text = AppUpdateModel.downloadStatusText(
            progress: progress,
            fileName: "MacSoftwareSteward.zip"
        )
        precondition(text.contains("MacSoftwareSteward.zip"))
        precondition(text.contains("50%"))
    }
}
```

Add target:

```bash
run_test AppUpdaterDownloadStatusTest \
  "$SRC/CommandRunner.swift" \
  "$SRC/DownloadAcceleration.swift" \
  "$SRC/AcceleratedDownloader.swift" \
  "$SRC/AppUpdateSecurity.swift" \
  "$SRC/SelfUpdateInstallScript.swift" \
  "$SRC/AppUpdater.swift" \
  "$TESTS/AppUpdaterDownloadStatusTest.swift"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test`

Expected: FAIL because `AppUpdateModel.downloadStatusText(progress:fileName:)` is not defined.

- [ ] **Step 3: Add status helper**

In `AppUpdateModel`, add:

```swift
static func downloadStatusText(progress: AcceleratedDownloadProgress, fileName: String) -> String {
    if let expected = progress.expectedByteCount, expected > 0 {
        let percent = Int((Double(progress.byteCount) / Double(expected)) * 100)
        let downloaded = ByteCountFormatter.string(fromByteCount: progress.byteCount, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: expected, countStyle: .file)
        return "正在下载 \(fileName)... \(percent)%  \(downloaded) / \(total)"
    }
    let downloaded = ByteCountFormatter.string(fromByteCount: progress.byteCount, countStyle: .file)
    return "正在下载 \(fileName)... \(downloaded)"
}
```

- [ ] **Step 4: Move download implementation**

In `AppUpdateModel.download(asset:)`, keep work directory and destination handling. Replace the custom `DownloadProgressDelegate` block and URLSession setup with:

```swift
let strategies = await DownloadAccelerationPolicy.defaultStrategies()
let downloadedFile = try await AcceleratedDownloader.download(
    AcceleratedDownloadRequest(
        url: url,
        destinationFileName: asset.name,
        expectedByteCount: asset.size > 0 ? Int64(asset.size) : nil,
        operationName: "应用自更新"
    ),
    strategies: strategies,
    onProgress: { [weak self] progress in
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let expected = progress.expectedByteCount, expected > 0 {
                self.downloadFraction = Double(progress.byteCount) / Double(expected)
                self.totalDownloadSizeText = ByteCountFormatter.string(fromByteCount: expected, countStyle: .file)
            } else {
                self.downloadFraction = nil
            }
            self.progress = Self.downloadStatusText(progress: progress, fileName: asset.name)
            self.downloadedSizeText = ByteCountFormatter.string(fromByteCount: progress.byteCount, countStyle: .file)
            if let speed = progress.speedBytesPerSecond {
                self.downloadSpeedText = ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s"
            }
        }
    },
    onStatus: { [weak self] status in
        Task { @MainActor [weak self] in
            self?.progress = status
        }
    }
)
```

Then keep the existing destination move:

```swift
if FileManager.default.fileExists(atPath: destination.path) {
    try FileManager.default.removeItem(at: destination)
}
try FileManager.default.moveItem(at: downloadedFile, to: destination)
return destination
```

Remove `DownloadProgressDelegate` only after verifying no other code uses it.

- [ ] **Step 5: Run tests**

Run: `npm test`

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add native/MacSoftwareSteward/AppUpdater.swift tests/AppUpdaterDownloadStatusTest.swift scripts/test-native.sh
git commit -m "feat: accelerate self update downloads"
```

## Task 10: Direct Replacement Integration

**Files:**
- Modify: `native/MacSoftwareSteward/StewardModel.swift`
- Modify: `native/MacSoftwareSteward/Views/ApplicationsView.swift`
- Modify: `tests/ManualAppReplacementInstallerTest.swift`

**Interfaces:**
- Consumes: `AcceleratedDownloader.download`.
- Preserves: `ManualAppReplacementInstaller.validateReplacement` and replacement rollback behavior.

- [ ] **Step 1: Write a small failing helper test**

Add to `ManualAppReplacementInstallerTest.main()`:

```swift
let downloadURL = URL(string: "https://example.com/downloads/Cool%20App.zip?token=abc")!
precondition(ManualAppReplacementInstaller.downloadFileName(from: downloadURL, fallback: "Fallback.zip") == "Cool App.zip")
let noNameURL = URL(string: "https://example.com/downloads/")!
precondition(ManualAppReplacementInstaller.downloadFileName(from: noNameURL, fallback: "Fallback.zip") == "Fallback.zip")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test`

Expected: FAIL because `downloadFileName(from:fallback:)` is not defined.

- [ ] **Step 3: Add helper**

Add to `ManualAppReplacementInstaller`:

```swift
static func downloadFileName(from url: URL, fallback: String) -> String {
    let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
}
```

- [ ] **Step 4: Add direct replacement status fields**

Add these published fields near `errorMessage` in `StewardModel`:

```swift
@Published var directReplacementAppID: String? = nil
@Published var directReplacementStatusText = ""
```

In `directlyReplace(_:)`, immediately after the confirmation guard, add:

```swift
directReplacementAppID = app.id
directReplacementStatusText = "正在准备直接替换 \(app.name)"
defer {
    directReplacementAppID = nil
    directReplacementStatusText = ""
}
```

- [ ] **Step 5: Replace direct URLSession download**

Replace the whole `downloadManualReplacement(from:into:)` method in `StewardModel` with:

```swift
private func downloadManualReplacement(from url: URL, into workDirectory: URL) async throws -> URL {
    let fileName = ManualAppReplacementInstaller.downloadFileName(
        from: url,
        fallback: "update-\(UUID().uuidString).zip"
    )
    let strategies = await DownloadAccelerationPolicy.defaultStrategies()
    let temporaryURL = try await AcceleratedDownloader.download(
        AcceleratedDownloadRequest(
            url: url,
            destinationFileName: fileName,
            expectedByteCount: nil,
            operationName: "直接替换下载"
        ),
        strategies: strategies,
        onStatus: { [weak self] status in
            Task { @MainActor [weak self] in
                self?.directReplacementStatusText = status
            }
        }
    )

    let destination = workDirectory.appendingPathComponent(fileName)
    if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.moveItem(at: temporaryURL, to: destination)
    return destination
}
```

Leave `safeDownloadFileName(from:fallbackURL:)` in place during this task. It becomes unused, but keeping it avoids an unrelated cleanup while the direct replacement path changes.

- [ ] **Step 6: Show compact direct replacement status**

In `ApplicationsView.swift`, inside `ManualUpdateActionPanel.body`, add this block before `Spacer(minLength: 12)`:

```swift
if model.directReplacementAppID == app.id, !model.directReplacementStatusText.isEmpty {
    Label(model.directReplacementStatusText, systemImage: "bolt.horizontal.circle.fill")
        .font(.caption)
        .foregroundStyle(.blue)
        .lineLimit(2)
}
```

- [ ] **Step 7: Run tests**

Run: `npm test`

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add native/MacSoftwareSteward/StewardModel.swift native/MacSoftwareSteward/Views/ApplicationsView.swift native/MacSoftwareSteward/ManualAppReplacementInstaller.swift tests/ManualAppReplacementInstallerTest.swift
git commit -m "feat: accelerate direct replacement downloads"
```

## Task 11: URLSession Retryable Network Errors

**Files:**
- Modify: `native/MacSoftwareSteward/AcceleratedDownloader.swift`
- Modify: `tests/AcceleratedDownloaderTest.swift`

**Interfaces:**
- Consumes: `AcceleratedDownloader`.
- Produces: retryable classification for timeout and transient connection failures.

- [ ] **Step 1: Write failing tests**

Add this block to `AcceleratedDownloaderTest.main()`:

```swift
let timeout = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
precondition(AcceleratedDownloader.isRetryableNetworkError(timeout))

let lost = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
precondition(AcceleratedDownloader.isRetryableNetworkError(lost))

let badURL = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL)
precondition(!AcceleratedDownloader.isRetryableNetworkError(badURL))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test`

Expected: FAIL because `isRetryableNetworkError` is not defined.

- [ ] **Step 3: Implement retryable classification**

Add to `AcceleratedDownloader`:

```swift
static func isRetryableNetworkError(_ error: Error) -> Bool {
    let nsError = error as NSError
    guard nsError.domain == NSURLErrorDomain else { return false }
    return [
        NSURLErrorTimedOut,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorCannotConnectToHost,
        NSURLErrorCannotFindHost,
        NSURLErrorDNSLookupFailed,
        NSURLErrorNotConnectedToInternet
    ].contains(nsError.code)
}
```

In `download(...)`, change the generic catch to:

```swift
} catch {
    lastError = error
    if isRetryableNetworkError(error),
       case .retry(let next) = DownloadAccelerationPolicy.retryDecision(
           attemptIndex: attemptIndex,
           strategyCount: effectiveStrategies.count,
           maxAttempts: config.maxAttempts
       ) {
        onStatus("网络连接不稳定，正在自动切换加速方式重试")
        attemptIndex = next
        continue
    }
    throw error
}
```

- [ ] **Step 4: Run tests**

Run: `npm test`

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add native/MacSoftwareSteward/AcceleratedDownloader.swift tests/AcceleratedDownloaderTest.swift
git commit -m "feat: retry transient download failures"
```

## Task 12: Build Integration and Final Verification

**Files:**
- Inspect: `scripts/build-native.sh` to confirm new source files are picked up by the existing `native/MacSoftwareSteward/*.swift` glob.
- Inspect: `scripts/test-native.sh` to confirm every new and affected test target includes `DownloadAcceleration.swift` or `AcceleratedDownloader.swift`.

**Interfaces:**
- Consumes: all previous tasks.
- Produces: passing test and build evidence.

- [ ] **Step 1: Run full tests**

Run: `npm test`

Expected: `All native tests passed.`

- [ ] **Step 2: Run full build**

Run: `npm run build`

Expected: build completes and signs `build/MacSoftwareSteward.app`.

- [ ] **Step 3: Restore generated icons if needed**

Run: `git status --short native/Resources/AppIcon.iconset`

Expected: no changes. If icon PNGs changed, run:

```bash
git restore native/Resources/AppIcon.iconset/*.png
```

- [ ] **Step 4: Inspect final diff**

Run: `git diff --stat`

Expected: only source, tests, and script files from this plan are changed.

- [ ] **Step 5: Commit final verification fixes if any**

If Step 2 or Step 3 required a small build-script/test-script fix, commit it:

```bash
git add scripts/test-native.sh scripts/build-native.sh
git commit -m "chore: wire download acceleration build inputs"
```

If no fixes were needed, do not create an empty commit.

## Self-Review

- Spec coverage: Tasks cover shared strategy discovery, per-process environment overlays, Homebrew slow/stall detection, package-scoped cask cleanup, URLSession retry, app self-update, direct replacement, UI status, bounded retries, tests, and build verification.
- Scope check: The plan is broad but cohesive; all work flows through the shared `DownloadAcceleration` policy and can be implemented in task order with each task testable on its own.
- Type consistency: `DownloadAccelerationStrategy`, `DownloadAccelerationConfig`, `SlowDownloadDecision`, `CommandAccelerationAttempt`, `AcceleratedDownloader`, and `AcceleratedDownloadProgress` are introduced before subsequent tasks consume them.
