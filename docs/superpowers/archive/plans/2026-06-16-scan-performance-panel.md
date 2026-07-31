# Scan Performance Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an Advanced Mode Performance tab that records, persists, and displays recent scan phase timings.

**Architecture:** Add focused scan performance value types, a local JSON store capped at 50 records, and scanner instrumentation around existing phase boundaries. Wire `StewardModel.scanSoftware` to append completed scan snapshots, add an Advanced Mode-only `性能` tab, and render the panel through a small presenter so display logic is testable without screenshot tests.

**Tech Stack:** Swift, SwiftUI, AppKit, Foundation JSON encoding/decoding, existing `swiftc` shell build/test scripts.

---

## Scope Check

This plan covers one coherent feature: scan performance observability in the main app. It does not optimize scan behavior, change daily agent behavior, introduce a charting dependency, or migrate the build system. Daily inspection agent scan performance persistence is explicitly out of scope for this pass.

## File Structure

- Create: `native/MacSoftwareSteward/ScanPerformance.swift`
  - Scan performance phase enum, stage values, snapshots, duration formatting, and derived helpers.
- Create: `native/MacSoftwareSteward/ScanPerformanceStore.swift`
  - Local JSON store for the latest 50 scan performance snapshots.
- Create: `native/MacSoftwareSteward/ScanPerformancePresenter.swift`
  - Testable display rows, summary values, phase ordering, and diagnostic hints.
- Create: `native/MacSoftwareSteward/Views/PerformanceView.swift`
  - Advanced Mode scan performance panel.
- Modify: `native/MacSoftwareSteward/Models.swift`
  - Add `.performance` tab and add `performance` to `ScanResult`.
- Modify: `native/MacSoftwareSteward/Scanner.swift`
  - Measure scan phases and split local app discovery from Sparkle appcast enrichment.
- Modify: `native/MacSoftwareSteward/StewardModel.swift`
  - Own `ScanPerformanceStore` and append scan snapshots after completed scans.
- Modify: `native/MacSoftwareSteward/ContentView.swift`
  - Route the new Performance tab to `PerformanceView`.
- Modify: `scripts/build-native.sh`
  - Include `ScanPerformance.swift` in the Agent compile source list because `Scanner.swift` will depend on it.
- Modify: `scripts/test-native.sh`
  - Add new focused tests and include new source files in existing scanner/model tests.
- Modify: `PROJECT_MAP.md`
  - Document the new performance model/store/presenter/view.
- Test: `tests/ScanPerformanceModelTest.swift`
- Test: `tests/ScanPerformanceStoreTest.swift`
- Test: `tests/ScanPerformancePresenterTest.swift`
- Test: update `tests/AppTabVisibilityTest.swift`
- Test: update `tests/StewardModelScanGuardTest.swift`

## Task 1: Scan Performance Model

**Files:**
- Create: `native/MacSoftwareSteward/ScanPerformance.swift`
- Test: `tests/ScanPerformanceModelTest.swift`
- Modify: `native/MacSoftwareSteward/Models.swift`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Write the model test**

Create `tests/ScanPerformanceModelTest.swift`:

```swift
import Foundation

@main
struct ScanPerformanceModelTest {
    static func main() {
        let stages = [
            ScanPerformanceStage(phase: .applications, durationMs: 250),
            ScanPerformanceStage(phase: .brew, durationMs: 700),
            ScanPerformanceStage(phase: .mas, durationMs: 100),
            ScanPerformanceStage(phase: .classification, durationMs: 30),
            ScanPerformanceStage(phase: .regularAppDiscovery, durationMs: 200),
            ScanPerformanceStage(phase: .sparkleAppcast, durationMs: 450),
            ScanPerformanceStage(phase: .total, durationMs: 1_800)
        ]
        let snapshot = ScanPerformanceSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!,
            scannedAt: Date(timeIntervalSince1970: 100),
            includeGreedy: true,
            stages: stages,
            applications: 12,
            brewFormulae: 4,
            brewCasks: 3,
            masApps: 2,
            outdated: 5,
            actionable: 4,
            applicationsSource: "system_profiler",
            brewAvailable: true,
            masAvailable: true
        )

        precondition(ScanPerformancePhase.applications.title == "本机应用")
        precondition(ScanPerformancePhase.sparkleAppcast.title == "Sparkle 更新源")
        precondition(ScanPerformancePhase.total.title == "总耗时")
        precondition(ScanPerformancePhase.ordered == [
            .applications,
            .brew,
            .mas,
            .classification,
            .regularAppDiscovery,
            .sparkleAppcast,
            .total
        ])

        precondition(snapshot.totalMs == 1_800)
        precondition(snapshot.measuredStages.map(\.phase) == [
            .applications,
            .brew,
            .mas,
            .classification,
            .regularAppDiscovery,
            .sparkleAppcast
        ])
        precondition(snapshot.slowestStage?.phase == .brew)
        precondition(snapshot.countSummary == "12 个 App / 7 个 Brew / 2 个 MAS")

        precondition(ScanPerformanceStage(phase: .brew, durationMs: 500).fraction(of: 2_000) == 0.25)
        precondition(ScanPerformanceStage(phase: .brew, durationMs: 500).fraction(of: 0) == 0)
        precondition(ScanPerformanceStage.formatDuration(999) == "999 ms")
        precondition(ScanPerformanceStage.formatDuration(1_250) == "1.25 s")

        let empty = ScanPerformanceSnapshot.empty(scannedAt: Date(timeIntervalSince1970: 200))
        precondition(empty.totalMs == 0)
        precondition(empty.slowestStage == nil)
    }
}
```

- [ ] **Step 2: Wire and run the failing model test**

Add this block near the other model-style tests in `scripts/test-native.sh`:

```bash
run_test ScanPerformanceModelTest \
  "$SRC/ScanPerformance.swift" \
  "$TESTS/ScanPerformanceModelTest.swift"
```

Run:

```bash
npm test
```

Expected: FAIL while compiling `ScanPerformanceModelTest` because `ScanPerformance.swift` and the scan performance types do not exist yet.

- [ ] **Step 3: Add scan performance value types**

Create `native/MacSoftwareSteward/ScanPerformance.swift`:

```swift
import Foundation

enum ScanPerformancePhase: String, Codable, CaseIterable, Hashable, Identifiable {
    case applications
    case brew
    case mas
    case classification
    case regularAppDiscovery
    case sparkleAppcast
    case total

    var id: String { rawValue }

    static let ordered: [ScanPerformancePhase] = [
        .applications,
        .brew,
        .mas,
        .classification,
        .regularAppDiscovery,
        .sparkleAppcast,
        .total
    ]

    var title: String {
        switch self {
        case .applications: return "本机应用"
        case .brew: return "Homebrew"
        case .mas: return "App Store"
        case .classification: return "关联来源"
        case .regularAppDiscovery: return "普通 App 检查"
        case .sparkleAppcast: return "Sparkle 更新源"
        case .total: return "总耗时"
        }
    }

    var symbol: String {
        switch self {
        case .applications: return "macwindow"
        case .brew: return "shippingbox"
        case .mas: return "app.badge"
        case .classification: return "link"
        case .regularAppDiscovery: return "doc.text.magnifyingglass"
        case .sparkleAppcast: return "sparkles"
        case .total: return "timer"
        }
    }
}

struct ScanPerformanceStage: Codable, Hashable, Identifiable {
    var phase: ScanPerformancePhase
    var durationMs: Int

    var id: ScanPerformancePhase { phase }
    var title: String { phase.title }
    var durationText: String { Self.formatDuration(durationMs) }

    func fraction(of totalMs: Int) -> Double {
        guard totalMs > 0, durationMs > 0 else { return 0 }
        return min(1, Double(durationMs) / Double(totalMs))
    }

    static func formatDuration(_ durationMs: Int) -> String {
        if durationMs < 1_000 {
            return "\(max(durationMs, 0)) ms"
        }
        let seconds = Double(durationMs) / 1_000
        return String(format: "%.2f s", seconds)
    }
}

struct ScanPerformanceSnapshot: Codable, Identifiable, Hashable {
    var id: UUID
    var scannedAt: Date
    var includeGreedy: Bool
    var stages: [ScanPerformanceStage]
    var applications: Int
    var brewFormulae: Int
    var brewCasks: Int
    var masApps: Int
    var outdated: Int
    var actionable: Int
    var applicationsSource: String
    var brewAvailable: Bool
    var masAvailable: Bool

    var totalMs: Int {
        stages.first(where: { $0.phase == .total })?.durationMs
            ?? stages.map(\.durationMs).reduce(0, +)
    }

    var measuredStages: [ScanPerformanceStage] {
        let byPhase = Dictionary(stages.map { ($0.phase, $0) }, uniquingKeysWith: { _, last in last })
        return ScanPerformancePhase.ordered
            .filter { $0 != .total }
            .compactMap { byPhase[$0] }
    }

    var slowestStage: ScanPerformanceStage? {
        measuredStages.max { lhs, rhs in
            lhs.durationMs < rhs.durationMs
        }
    }

    var countSummary: String {
        "\(applications) 个 App / \(brewFormulae + brewCasks) 个 Brew / \(masApps) 个 MAS"
    }

    static func empty(scannedAt: Date = Date()) -> ScanPerformanceSnapshot {
        ScanPerformanceSnapshot(
            id: UUID(),
            scannedAt: scannedAt,
            includeGreedy: false,
            stages: [ScanPerformanceStage(phase: .total, durationMs: 0)],
            applications: 0,
            brewFormulae: 0,
            brewCasks: 0,
            masApps: 0,
            outdated: 0,
            actionable: 0,
            applicationsSource: "",
            brewAvailable: false,
            masAvailable: false
        )
    }
}
```

- [ ] **Step 4: Add `performance` to `ScanResult`**

Modify `native/MacSoftwareSteward/Models.swift`:

```swift
struct ScanResult {
    var scannedAt: Date
    var includeGreedy: Bool
    var summary: ScanSummary
    var applications: ApplicationsScan
    var brew: BrewScan
    var mas: MasScan
    var performance: ScanPerformanceSnapshot = .empty()
}
```

The default value keeps existing tests that construct `ScanResult` compiling while scanner instrumentation is added later.

Update every existing `run_test` block in `scripts/test-native.sh` that includes `"$SRC/Models.swift"` so `ScanPerformance.swift` appears immediately before `Models.swift`. For example, change this pattern:

```bash
run_test AppTabVisibilityTest \
  "$SRC/Models.swift" \
  "$TESTS/AppTabVisibilityTest.swift"
```

to:

```bash
run_test AppTabVisibilityTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$TESTS/AppTabVisibilityTest.swift"
```

Apply the same insertion to every other test source list that compiles `Models.swift`. This is required because `ScanResult` now references `ScanPerformanceSnapshot`.

Verify the script update with:

```bash
rg -n '"\$SRC/Models\.swift"' scripts/test-native.sh
```

Expected: every returned `run_test` block has `"$SRC/ScanPerformance.swift"` on the line immediately before `"$SRC/Models.swift"`.

- [ ] **Step 5: Run the model test**

Run:

```bash
bash scripts/test-native.sh
```

Expected: PASS through `ScanPerformanceModelTest` and all existing tests that compile `Models.swift`.

- [ ] **Step 6: Commit the model work**

Run:

```bash
git add native/MacSoftwareSteward/ScanPerformance.swift native/MacSoftwareSteward/Models.swift tests/ScanPerformanceModelTest.swift scripts/test-native.sh
git commit -m "feat: add scan performance model"
```

## Task 2: Scan Performance Store

**Files:**
- Create: `native/MacSoftwareSteward/ScanPerformanceStore.swift`
- Test: `tests/ScanPerformanceStoreTest.swift`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Write the store test**

Create `tests/ScanPerformanceStoreTest.swift`:

```swift
import Foundation

@main
struct ScanPerformanceStoreTest {
    static func main() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-performance-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let thirdID = UUID(uuidString: "00000000-0000-0000-0000-000000000203")!

        let store = ScanPerformanceStore(fileURL: url, limit: 2)
        precondition(store.records.isEmpty)

        store.append(makeSnapshot(id: firstID, scannedAt: 1, totalMs: 100))
        store.append(makeSnapshot(id: secondID, scannedAt: 3, totalMs: 300))
        precondition(store.records.map(\.id) == [secondID, firstID])

        store.append(makeSnapshot(id: firstID, scannedAt: 5, totalMs: 500))
        precondition(store.records.map(\.id) == [firstID, secondID])
        precondition(store.records.first?.totalMs == 500)

        store.append(makeSnapshot(id: thirdID, scannedAt: 4, totalMs: 400))
        precondition(store.records.map(\.id) == [firstID, thirdID])

        let reloaded = ScanPerformanceStore(fileURL: url, limit: 5)
        precondition(reloaded.records.map(\.id) == [firstID, thirdID])

        let replacement = [
            makeSnapshot(id: secondID, scannedAt: 2, totalMs: 200),
            makeSnapshot(id: thirdID, scannedAt: 6, totalMs: 600),
            makeSnapshot(id: firstID, scannedAt: 1, totalMs: 100)
        ]
        reloaded.replaceRecords(replacement)
        precondition(reloaded.records.map(\.id) == [thirdID, secondID])

        reloaded.clear()
        precondition(reloaded.records.isEmpty)

        let clearedReload = ScanPerformanceStore(fileURL: url, limit: 5)
        precondition(clearedReload.records.isEmpty)
    }

    private static func makeSnapshot(id: UUID, scannedAt: TimeInterval, totalMs: Int) -> ScanPerformanceSnapshot {
        ScanPerformanceSnapshot(
            id: id,
            scannedAt: Date(timeIntervalSince1970: scannedAt),
            includeGreedy: false,
            stages: [
                ScanPerformanceStage(phase: .applications, durationMs: totalMs / 2),
                ScanPerformanceStage(phase: .brew, durationMs: totalMs / 4),
                ScanPerformanceStage(phase: .total, durationMs: totalMs)
            ],
            applications: 1,
            brewFormulae: 1,
            brewCasks: 0,
            masApps: 0,
            outdated: 0,
            actionable: 0,
            applicationsSource: "test",
            brewAvailable: true,
            masAvailable: false
        )
    }
}
```

- [ ] **Step 2: Wire and run the failing store test**

Add this block to `scripts/test-native.sh` after `ScanPerformanceModelTest`:

```bash
run_test ScanPerformanceStoreTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/ScanPerformanceStore.swift" \
  "$TESTS/ScanPerformanceStoreTest.swift"
```

Run:

```bash
bash scripts/test-native.sh
```

Expected: FAIL while compiling `ScanPerformanceStoreTest` because `ScanPerformanceStore.swift` does not exist yet.

- [ ] **Step 3: Add the store**

Create `native/MacSoftwareSteward/ScanPerformanceStore.swift`:

```swift
import Combine
import Foundation

final class ScanPerformanceStore: ObservableObject {
    static let defaultFileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacSoftwareSteward", isDirectory: true)
            .appendingPathComponent("scan-performance.json")
    }()

    @Published private(set) var records: [ScanPerformanceSnapshot]

    private let fileURL: URL
    private let limit: Int

    init(fileURL: URL = ScanPerformanceStore.defaultFileURL, limit: Int = 50) {
        self.fileURL = fileURL
        self.limit = limit
        records = Self.load(from: fileURL)
        trimToLimit()
    }

    func append(_ record: ScanPerformanceSnapshot) {
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        trimToLimit()
        save()
    }

    func reload() {
        records = Self.load(from: fileURL)
        trimToLimit()
    }

    func clear() {
        records.removeAll()
        save()
    }

    func replaceRecords(_ newRecords: [ScanPerformanceSnapshot]) {
        records = newRecords
        trimToLimit()
        save()
    }

    private func sortNewestFirst() {
        records.sort { lhs, rhs in
            lhs.scannedAt > rhs.scannedAt
        }
    }

    private func trimToLimit() {
        sortNewestFirst()
        if records.count > limit {
            records.removeLast(records.count - limit)
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Failed to save scan performance records: \(error.localizedDescription)")
        }
    }

    private static func load(from url: URL) -> [ScanPerformanceSnapshot] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = (try? decoder.decode([ScanPerformanceSnapshot].self, from: data)) ?? []
        return records.sorted { lhs, rhs in
            lhs.scannedAt > rhs.scannedAt
        }
    }
}
```

- [ ] **Step 4: Run the store test**

Run:

```bash
bash scripts/test-native.sh
```

Expected: PASS through `ScanPerformanceStoreTest`.

- [ ] **Step 5: Commit the store work**

Run:

```bash
git add native/MacSoftwareSteward/ScanPerformanceStore.swift tests/ScanPerformanceStoreTest.swift scripts/test-native.sh
git commit -m "feat: persist scan performance history"
```

## Task 3: Scanner Timing Instrumentation

**Files:**
- Modify: `native/MacSoftwareSteward/Scanner.swift`
- Modify: `scripts/build-native.sh`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Run the scanner tests before changing scanner behavior**

Run:

```bash
bash scripts/test-native.sh
```

Expected: PASS before instrumentation starts. If it fails here, fix the previous task before changing scanner code.

- [ ] **Step 2: Add timing helpers inside `SoftwareScanner`**

In `native/MacSoftwareSteward/Scanner.swift`, add these helpers near `BrewInstalledPackagesResult`:

```swift
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
```

- [ ] **Step 3: Replace `scanAll` with timed orchestration**

Replace `SoftwareScanner.scanAll` with:

```swift
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
```

- [ ] **Step 4: Stop attaching update capabilities inside Applications scan**

In `scanApplications`, change the successful return to:

```swift
            return ApplicationsScan(source: "system_profiler", ok: true, error: "", items: items)
```

In `scanApplicationsByFind`, change the final return to:

```swift
        return ApplicationsScan(source: "find", ok: result.ok, error: error, items: items)
```

This ensures local regular app discovery is timed separately by `scanAll`.

- [ ] **Step 5: Include the new model in Agent and scanner test compile lists**

In `scripts/build-native.sh`, add this line before `Models.swift` in the Agent compile source list:

```bash
  "$ROOT_DIR"/native/MacSoftwareSteward/ScanPerformance.swift \
```

In `scripts/test-native.sh`, add `"$SRC/ScanPerformance.swift"` to every scanner test block that compiles `Scanner.swift`, including:

```bash
run_test ScannerBrewListFallbackTest
run_test ScannerAppUpdateCapabilityTest
run_test ScannerSparkleAppcastPolicyTest
run_test ScannerNormalizeTokenTest
run_test StewardModelScanGuardTest
```

- [ ] **Step 6: Run scanner and build verification**

Run:

```bash
bash scripts/test-native.sh
npm run build
```

Expected: both PASS. `npm run build` verifies the Agent source list includes `ScanPerformance.swift`.

- [ ] **Step 7: Commit scanner instrumentation**

Run:

```bash
git add native/MacSoftwareSteward/Scanner.swift scripts/build-native.sh scripts/test-native.sh
git commit -m "feat: record scan phase timings"
```

## Task 4: StewardModel Store Integration

**Files:**
- Modify: `native/MacSoftwareSteward/StewardModel.swift`
- Modify: `tests/StewardModelScanGuardTest.swift`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Extend the StewardModel test with a performance store assertion**

In `tests/StewardModelScanGuardTest.swift`, add this after the notification scan assertions:

```swift
        let performanceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-performance-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: performanceURL) }
        let performanceStore = ScanPerformanceStore(fileURL: performanceURL, limit: 10)
        let performanceSnapshot = ScanPerformanceSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
            scannedAt: Date(timeIntervalSince1970: 11),
            includeGreedy: false,
            stages: [
                ScanPerformanceStage(phase: .applications, durationMs: 20),
                ScanPerformanceStage(phase: .brew, durationMs: 10),
                ScanPerformanceStage(phase: .total, durationMs: 40)
            ],
            applications: 1,
            brewFormulae: 0,
            brewCasks: 0,
            masApps: 0,
            outdated: 1,
            actionable: 0,
            applicationsSource: "test",
            brewAvailable: false,
            masAvailable: false
        )
        var performanceResult = appUpdateScanResult()
        performanceResult.performance = performanceSnapshot
        let performanceModel = StewardModel(
            scanner: StaticScanner(result: performanceResult),
            scanPerformanceStore: performanceStore
        )
        await performanceModel.scanSoftware()
        precondition(performanceStore.records.map(\.id) == [performanceSnapshot.id])
```

- [ ] **Step 2: Add new source files to the StewardModel test script block**

In `scripts/test-native.sh`, add these files to `run_test StewardModelScanGuardTest` before `StewardModel.swift`:

```bash
  "$SRC/ScanPerformance.swift" \
  "$SRC/ScanPerformanceStore.swift" \
```

Run:

```bash
bash scripts/test-native.sh
```

Expected: FAIL because `StewardModel` does not accept `scanPerformanceStore` and does not append performance snapshots yet.

- [ ] **Step 3: Wire the store into StewardModel**

In `native/MacSoftwareSteward/StewardModel.swift`, add the store property near the existing stores:

```swift
    let scanPerformanceStore: ScanPerformanceStore
```

Change the initializer to:

```swift
    init(
        scanner: SoftwareScanning = LiveSoftwareScanning(),
        notificationDispatcher: AutomationNotificationDelivering? = nil,
        scanPerformanceStore: ScanPerformanceStore = ScanPerformanceStore()
    ) {
        self.scanner = scanner
        self.notificationDispatcher = notificationDispatcher ?? UserNotificationDispatcher()
        self.scanPerformanceStore = scanPerformanceStore
        refreshDailyInspectionStatus()
    }
```

After `scan = result` in `scanSoftware`, append:

```swift
        scanPerformanceStore.append(result.performance)
```

- [ ] **Step 4: Run the StewardModel test**

Run:

```bash
bash scripts/test-native.sh
```

Expected: PASS through `StewardModelScanGuardTest`; scan guard behavior still passes.

- [ ] **Step 5: Commit model-store integration**

Run:

```bash
git add native/MacSoftwareSteward/StewardModel.swift tests/StewardModelScanGuardTest.swift scripts/test-native.sh
git commit -m "feat: save scan performance after scans"
```

## Task 5: Advanced Mode Performance Tab

**Files:**
- Modify: `native/MacSoftwareSteward/Models.swift`
- Modify: `native/MacSoftwareSteward/ContentView.swift`
- Create: `native/MacSoftwareSteward/Views/PerformanceView.swift`
- Modify: `tests/AppTabVisibilityTest.swift`

- [ ] **Step 1: Update the tab visibility test**

Modify `tests/AppTabVisibilityTest.swift` so the Advanced Mode expectation includes `.performance` before `.jobs`, and add performance symbol/search assertions:

```swift
        precondition(AppTab.visibleTabs(advancedModeEnabled: true) == [
            .inbox,
            .updates,
            .applications,
            .sources,
            .rules,
            .history,
            .performance,
            .jobs,
            .settings
        ])
        precondition(AppTab.performance.symbol == "speedometer")
        precondition(AppTab.performance.usesSearch == false)
```

Run:

```bash
bash scripts/test-native.sh
```

Expected: FAIL because `AppTab.performance` does not exist yet.

- [ ] **Step 2: Add the tab and buildable route**

In `native/MacSoftwareSteward/Models.swift`, update `AppTab`:

```swift
    case performance = "性能"
```

Change Advanced Mode visible tabs to:

```swift
            return [.inbox, .updates, .applications, .sources, .rules, .history, .performance, .jobs, .settings]
```

Add symbol handling:

```swift
        case .performance: return "speedometer"
```

Add `performance` to the non-search cases:

```swift
        case .inbox, .rules, .history, .performance, .settings, .jobs:
            return false
```

In `native/MacSoftwareSteward/ContentView.swift`, add the exhaustive switch case now, so the app build stays valid immediately after `AppTab.performance` exists:

```swift
                case .performance:
                    PerformanceView()
```

Create a temporary shell at `native/MacSoftwareSteward/Views/PerformanceView.swift`; Task 7 will replace it with the full panel:

```swift
import SwiftUI

struct PerformanceView: View {
    var body: some View {
        EmptyStateView(
            symbol: "speedometer",
            title: "暂无性能记录",
            text: "完成一次扫描后，这里会显示阶段耗时、最近趋势和瓶颈提示。"
        )
    }
}
```

- [ ] **Step 3: Run the tab test and build**

Run:

```bash
bash scripts/test-native.sh
npm run build
```

Expected: `AppTabVisibilityTest` PASS and `npm run build` PASS. The build matters here because adding an `AppTab` case without a `ContentView` switch case breaks the main app even if standalone tests pass.

- [ ] **Step 4: Commit navigation model**

Run:

```bash
git add native/MacSoftwareSteward/Models.swift native/MacSoftwareSteward/ContentView.swift native/MacSoftwareSteward/Views/PerformanceView.swift tests/AppTabVisibilityTest.swift
git commit -m "feat: add performance tab shell"
```

## Task 6: Performance Presenter

**Files:**
- Create: `native/MacSoftwareSteward/ScanPerformancePresenter.swift`
- Test: `tests/ScanPerformancePresenterTest.swift`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Write the presenter test**

Create `tests/ScanPerformancePresenterTest.swift`:

```swift
import Foundation

@main
struct ScanPerformancePresenterTest {
    static func main() {
        let snapshot = ScanPerformanceSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
            scannedAt: Date(timeIntervalSince1970: 100),
            includeGreedy: true,
            stages: [
                ScanPerformanceStage(phase: .applications, durationMs: 400),
                ScanPerformanceStage(phase: .brew, durationMs: 100),
                ScanPerformanceStage(phase: .mas, durationMs: 50),
                ScanPerformanceStage(phase: .classification, durationMs: 20),
                ScanPerformanceStage(phase: .regularAppDiscovery, durationMs: 80),
                ScanPerformanceStage(phase: .sparkleAppcast, durationMs: 1_200),
                ScanPerformanceStage(phase: .total, durationMs: 2_000)
            ],
            applications: 10,
            brewFormulae: 3,
            brewCasks: 2,
            masApps: 1,
            outdated: 4,
            actionable: 3,
            applicationsSource: "system_profiler",
            brewAvailable: true,
            masAvailable: false
        )

        let summary = ScanPerformancePresenter.summary(for: [snapshot])
        precondition(summary?.totalText == "2.00 s")
        precondition(summary?.slowestPhaseTitle == "Sparkle 更新源")
        precondition(summary?.countSummary == "10 个 App / 5 个 Brew / 1 个 MAS")

        let rows = ScanPerformancePresenter.phaseRows(for: snapshot)
        precondition(rows.map(\.title) == [
            "本机应用",
            "Homebrew",
            "App Store",
            "关联来源",
            "普通 App 检查",
            "Sparkle 更新源"
        ])
        precondition(rows.last?.isSlowest == true)
        precondition(rows.last?.percentText == "60%")

        let hint = ScanPerformancePresenter.diagnosticHint(for: snapshot)
        precondition(hint.title == "普通 App 更新检查较慢")
        precondition(hint.detail.contains("Sparkle"))

        precondition(ScanPerformancePresenter.summary(for: []) == nil)
        precondition(ScanPerformancePresenter.recentRows(for: [snapshot]).count == 1)
    }
}
```

- [ ] **Step 2: Wire and run the failing presenter test**

Add this block to `scripts/test-native.sh`:

```bash
run_test ScanPerformancePresenterTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/ScanPerformancePresenter.swift" \
  "$TESTS/ScanPerformancePresenterTest.swift"
```

Run:

```bash
bash scripts/test-native.sh
```

Expected: FAIL because `ScanPerformancePresenter.swift` does not exist.

- [ ] **Step 3: Add the presenter**

Create `native/MacSoftwareSteward/ScanPerformancePresenter.swift`:

```swift
import Foundation

struct ScanPerformanceSummaryRow: Hashable {
    var totalText: String
    var slowestPhaseTitle: String
    var scannedAt: Date
    var countSummary: String
}

struct ScanPerformancePhaseRow: Identifiable, Hashable {
    var id: ScanPerformancePhase { phase }
    var phase: ScanPerformancePhase
    var title: String
    var durationText: String
    var percentText: String
    var fraction: Double
    var isSlowest: Bool
}

struct ScanPerformanceRecentRow: Identifiable, Hashable {
    var id: UUID
    var scannedAt: Date
    var totalText: String
    var slowestPhaseTitle: String
    var countSummary: String
}

struct ScanPerformanceDiagnosticHint: Hashable {
    var title: String
    var detail: String
    var symbol: String
}

enum ScanPerformancePresenter {
    static func summary(for records: [ScanPerformanceSnapshot]) -> ScanPerformanceSummaryRow? {
        guard let latest = records.first else { return nil }
        return ScanPerformanceSummaryRow(
            totalText: ScanPerformanceStage.formatDuration(latest.totalMs),
            slowestPhaseTitle: latest.slowestStage?.title ?? "无",
            scannedAt: latest.scannedAt,
            countSummary: latest.countSummary
        )
    }

    static func phaseRows(for snapshot: ScanPerformanceSnapshot) -> [ScanPerformancePhaseRow] {
        let total = snapshot.totalMs
        let slowest = snapshot.slowestStage?.phase
        return snapshot.measuredStages.map { stage in
            let fraction = stage.fraction(of: total)
            return ScanPerformancePhaseRow(
                phase: stage.phase,
                title: stage.title,
                durationText: stage.durationText,
                percentText: "\(Int((fraction * 100).rounded()))%",
                fraction: fraction,
                isSlowest: stage.phase == slowest
            )
        }
    }

    static func recentRows(for records: [ScanPerformanceSnapshot]) -> [ScanPerformanceRecentRow] {
        records.map { record in
            ScanPerformanceRecentRow(
                id: record.id,
                scannedAt: record.scannedAt,
                totalText: ScanPerformanceStage.formatDuration(record.totalMs),
                slowestPhaseTitle: record.slowestStage?.title ?? "无",
                countSummary: record.countSummary
            )
        }
    }

    static func diagnosticHint(for snapshot: ScanPerformanceSnapshot) -> ScanPerformanceDiagnosticHint {
        guard let slowest = snapshot.slowestStage else {
            return ScanPerformanceDiagnosticHint(title: "暂无瓶颈", detail: "没有可分析的阶段耗时。", symbol: "checkmark.circle")
        }
        let fraction = slowest.fraction(of: snapshot.totalMs)
        if fraction < 0.4 {
            return ScanPerformanceDiagnosticHint(title: "扫描耗时较均衡", detail: "没有单一阶段占用超过 40%。", symbol: "equal.circle")
        }
        switch slowest.phase {
        case .applications:
            return ScanPerformanceDiagnosticHint(title: "本机应用扫描较慢", detail: "system_profiler 在应用数量较多或系统负载较高时可能变慢。", symbol: "macwindow")
        case .regularAppDiscovery, .sparkleAppcast:
            return ScanPerformanceDiagnosticHint(title: "普通 App 更新检查较慢", detail: "普通 App 元数据读取或 Sparkle 更新源请求可能是瓶颈。", symbol: "sparkles")
        case .brew:
            return ScanPerformanceDiagnosticHint(title: "Homebrew 来源较慢", detail: "Homebrew 命令响应时间较长，可能受本机包数量或网络状态影响。", symbol: "shippingbox")
        case .mas:
            return ScanPerformanceDiagnosticHint(title: "App Store 来源较慢", detail: "mas 命令响应时间较长，可能受 App Store 登录状态或网络影响。", symbol: "app.badge")
        case .classification:
            return ScanPerformanceDiagnosticHint(title: "来源关联较慢", detail: "应用和管理来源的匹配耗时偏高，可以后续检查匹配规则。", symbol: "link")
        case .total:
            return ScanPerformanceDiagnosticHint(title: "扫描耗时较均衡", detail: "没有单一阶段占用超过 40%。", symbol: "equal.circle")
        }
    }
}
```

- [ ] **Step 4: Run the presenter test**

Run:

```bash
bash scripts/test-native.sh
```

Expected: PASS through `ScanPerformancePresenterTest`.

- [ ] **Step 5: Commit presenter work**

Run:

```bash
git add native/MacSoftwareSteward/ScanPerformancePresenter.swift tests/ScanPerformancePresenterTest.swift scripts/test-native.sh
git commit -m "feat: present scan performance summaries"
```

## Task 7: Performance View

**Files:**
- Modify: `native/MacSoftwareSteward/Views/PerformanceView.swift`

- [ ] **Step 1: Confirm the tab shell still builds before filling the view**

Run:

```bash
npm run build
```

Expected: PASS. If this fails, fix the Task 5 shell before replacing the view content.

- [ ] **Step 2: Replace the shell with the full Performance view**

Replace `native/MacSoftwareSteward/Views/PerformanceView.swift` with:

```swift
import SwiftUI

struct PerformanceView: View {
    @EnvironmentObject private var model: StewardModel

    var body: some View {
        PerformanceContentView(store: model.scanPerformanceStore)
            .onAppear {
                model.scanPerformanceStore.reload()
            }
    }
}

private struct PerformanceContentView: View {
    @ObservedObject var store: ScanPerformanceStore

    private var records: [ScanPerformanceSnapshot] { store.records }
    private var latest: ScanPerformanceSnapshot? { records.first }
    private var summary: ScanPerformanceSummaryRow? { ScanPerformancePresenter.summary(for: records) }

    var body: some View {
        if records.isEmpty {
            EmptyStateView(
                symbol: "speedometer",
                title: "暂无性能记录",
                text: "完成一次扫描后，这里会显示阶段耗时、最近趋势和瓶颈提示。"
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let latest, let summary {
                        PerformanceSummaryPanel(snapshot: latest, summary: summary)
                        PerformancePhasePanel(snapshot: latest)
                        PerformanceDiagnosticPanel(snapshot: latest)
                    }
                    PerformanceRecentPanel(records: records)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

private struct PerformanceSummaryPanel: View {
    var snapshot: ScanPerformanceSnapshot
    var summary: ScanPerformanceSummaryRow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近扫描")
                .font(.system(.headline, design: .rounded))
            HStack(spacing: 10) {
                PerformanceMetric(title: "总耗时", value: summary.totalText, symbol: "timer")
                PerformanceMetric(title: "最慢阶段", value: summary.slowestPhaseTitle, symbol: "speedometer")
                PerformanceMetric(title: "扫描范围", value: summary.countSummary, symbol: "square.grid.2x2")
            }
            Text(summary.scannedAt.formatted(date: .abbreviated, time: .standard))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

private struct PerformanceMetric: View {
    var title: String
    var value: String
    var symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.callout, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private struct PerformancePhasePanel: View {
    var snapshot: ScanPerformanceSnapshot

    private var rows: [ScanPerformancePhaseRow] {
        ScanPerformancePresenter.phaseRows(for: snapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("阶段耗时")
                .font(.system(.headline, design: .rounded))
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Label(row.title, systemImage: row.phase.symbol)
                            .font(.subheadline)
                        Spacer()
                        Text("\(row.durationText) · \(row.percentText)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(row.isSlowest ? .orange : .secondary)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule()
                                .fill(row.isSlowest ? Color.orange.opacity(0.75) : Color.accentColor.opacity(0.65))
                                .frame(width: max(4, proxy.size.width * row.fraction))
                        }
                    }
                    .frame(height: 7)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

private struct PerformanceDiagnosticPanel: View {
    var snapshot: ScanPerformanceSnapshot

    private var hint: ScanPerformanceDiagnosticHint {
        ScanPerformancePresenter.diagnosticHint(for: snapshot)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: hint.symbol)
                .foregroundStyle(.orange)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(hint.title)
                    .font(.system(.headline, design: .rounded))
                Text(hint.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

private struct PerformanceRecentPanel: View {
    var records: [ScanPerformanceSnapshot]

    private var rows: [ScanPerformanceRecentRow] {
        ScanPerformancePresenter.recentRows(for: records)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近扫描")
                .font(.system(.headline, design: .rounded))
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.scannedAt.formatted(date: .abbreviated, time: .standard))
                            .font(.subheadline)
                        Text(row.countSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(row.totalText)
                            .font(.system(.subheadline, design: .monospaced))
                        Text(row.slowestPhaseTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }
}
```

- [ ] **Step 3: Build the app**

Run:

```bash
npm run build
```

Expected: PASS. The main app wildcard compile includes the new view.

- [ ] **Step 4: Commit the view**

Run:

```bash
git add native/MacSoftwareSteward/Views/PerformanceView.swift
git commit -m "feat: add scan performance view"
```

## Task 8: Docs And Full Verification

**Files:**
- Modify: `PROJECT_MAP.md`
- Verify: `scripts/test-native.sh`
- Verify: `scripts/build-native.sh`

- [ ] **Step 1: Update PROJECT_MAP**

In `PROJECT_MAP.md`, add scan performance files to the main app table:

```markdown
| `ScanPerformance.swift` / `ScanPerformanceStore.swift` / `ScanPerformancePresenter.swift` | 约 250 | 扫描阶段耗时模型、本机性能历史持久化和性能页展示数据 |
```

Add `Views/PerformanceView.swift` to the views description if the table already aggregates `Views/*.swift`.

- [ ] **Step 2: Run all tests**

Run:

```bash
npm test
```

Expected: PASS with `All native tests passed.`

- [ ] **Step 3: Run full build**

Run:

```bash
npm run build
```

Expected: PASS with `Signature OK`.

- [ ] **Step 4: Restore generated icon diffs if build rewrites them**

Run:

```bash
git status --short
```

If `native/Resources/AppIcon.iconset/*.png` appears, run:

```bash
git restore native/Resources/AppIcon.iconset
```

Expected after restore: only intentional source, test, script, and docs changes remain.

- [ ] **Step 5: Commit docs and final script state**

Run:

```bash
git add PROJECT_MAP.md scripts/test-native.sh scripts/build-native.sh
git commit -m "docs: document scan performance panel"
```

If the scripts were already committed in earlier tasks and only `PROJECT_MAP.md` changed, stage and commit only `PROJECT_MAP.md` with the same message.

- [ ] **Step 6: Final status check**

Run:

```bash
git status --short
git log --oneline -8
```

Expected: clean working tree and recent commits for model, store, scanner timing, store wiring, tab, presenter, view, and docs.
