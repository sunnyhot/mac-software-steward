# Scan Optimization Design

## Context

Mac 软件管家 now has scan performance instrumentation and an Advanced Mode Performance tab. The baseline report at `docs/performance/2026-06-16-baseline.md` identified the next likely scan bottlenecks after instrumentation:

1. Sparkle appcast checks are still sequential in `SoftwareScanner.enrichRegularAppUpdates`.
2. `SparkleAppcastChecker.check` uses `URLSession.shared.data(from:)` without an explicit per-feed timeout.
3. Local regular app update discovery reads and parses each app's `Info.plist` on every scan.

The user chose the full scan optimization scope for this pass: bounded concurrent Sparkle appcast checks, request timeout handling, and local update-capability discovery caching.

Current project constraints:

1. The app is native SwiftUI/AppKit with no Xcode project; build and tests run through `scripts/build-native.sh` and `scripts/test-native.sh`.
2. Scan behavior is concentrated in `SoftwareScanner.scanAll`, `SoftwareScanner.attachUpdateCapabilities`, `SoftwareScanner.enrichRegularAppUpdates`, `RegularAppUpdateDiscovery`, and `SparkleAppcastChecker`.
3. Existing scanner tests use single-file Swift executables and injected `sparkleChecker` closures.
4. Persistent local JSON store patterns exist for inspection reports, upgrade history, and scan performance.
5. User-facing text is Chinese; code identifiers remain English.

## Goals

- Check multiple Sparkle appcast feeds concurrently while keeping a bounded concurrency limit.
- Preserve the original app ordering in scan results after concurrent Sparkle enrichment.
- Add an explicit per-feed request timeout so one slow feed cannot dominate scan duration.
- Cache local regular app update capability discovery when `Info.plist` metadata has not changed.
- Keep scan failure behavior non-fatal: one appcast timeout or cache read failure must not fail the whole scan.
- Keep all changes observable through existing `sparkleAppcast` and `regularAppDiscovery` performance phases.

## Non-Goals

- No Homebrew, `mas`, or `system_profiler` optimization in this pass.
- No UI changes to the Performance tab.
- No remote telemetry.
- No feed-result persistence in this pass.
- No stale remote version caching that could hide newly available updates.
- No new dependencies or build-system migration.

## Proposed Architecture

### Bounded Concurrent Sparkle Enrichment

Replace the sequential appcast loop in `SoftwareScanner.enrichRegularAppUpdates` with a small bounded-concurrency scheduler.

New behavior:

- `RegularAppNetworkPolicy.localOnly` returns the input apps unchanged and starts no Sparkle work.
- Non-Sparkle apps and Sparkle apps without a feed URL are returned unchanged.
- Eligible Sparkle apps are checked concurrently with a default limit of `4`.
- The function returns apps in the same order as the input array.
- Each feed result only mutates its corresponding app.
- One feed failure or timeout only writes that app's diagnostic and does not cancel the rest.

Add a parameter with a default so tests can exercise limits without changing callers:

```swift
static func enrichRegularAppUpdates(
    _ apps: [AppItem],
    networkPolicy: RegularAppNetworkPolicy,
    sparkleConcurrencyLimit: Int = 4,
    sparkleChecker: SparkleChecker = SparkleAppcastChecker.check
) async -> [AppItem]
```

The effective limit is clamped to at least `1`. This keeps accidental `0` values from disabling checks in non-local policies.

### Sparkle Request Timeout

Change `SparkleAppcastChecker.check` to build a `URLRequest` with an explicit timeout, defaulting to `8` seconds:

```swift
static func check(
    feedURLString: String,
    installedVersion: String,
    timeout: TimeInterval = 8
) async -> SparkleAppcastCheckResult
```

The implementation should use:

```swift
let request = URLRequest(url: url, timeoutInterval: timeout)
let (data, response) = try await URLSession.shared.data(for: request)
```

Diagnostic behavior:

- Invalid feed URL: `Sparkle feed URL 无效。`
- HTTP non-2xx: existing HTTP status diagnostic.
- Timeout: `Sparkle feed 检查超时。`
- Other errors: existing generic failure diagnostic with `localizedDescription`.

The timeout must be testable without live network dependency. Add a small helper that maps errors to diagnostics, or inject the request-running closure in tests if needed. The preferred implementation is a pure helper because it keeps `SparkleAppcastChecker.check` simple.

### Local Update Capability Cache

Add `RegularAppUpdateDiscoveryCache`, a local JSON store that caches the result of reading and parsing `Contents/Info.plist`.

Default file path:

```text
~/Library/Application Support/MacSoftwareSteward/regular-app-discovery-cache.json
```

Cache key and validation:

- Key: app path.
- Metadata: `Info.plist` modification date and file size.
- Value: `AppUpdateCapability`.
- Cache version: integer stored with the file, starting at `1`.
- A cache entry is valid only when app path, cache version, `Info.plist` mtime, and `Info.plist` size match current filesystem metadata.
- Missing app or missing `Info.plist` returns `.none` and removes any stale cache entry for that app.

Store behavior:

- Default limit: `1000` records.
- Records are sorted newest-first by `lastSeenAt`.
- Writes use atomic JSON writes.
- Load failure returns an empty cache and logs with `NSLog`.
- Save failure logs with `NSLog` and does not fail scanning.

Scanner integration:

- Add a cache-aware discovery method that keeps the current non-cached API intact for tests and direct use.
- Update `SoftwareScanner.attachUpdateCapabilities` to accept an optional cache.
- `SoftwareScanner.scanAll` should create or use a default cache for main-app scans.

Suggested shape:

```swift
final class RegularAppUpdateDiscoveryCache: ObservableObject {
    func capability(for appPath: String, loader: (String) -> AppUpdateCapability = RegularAppUpdateDiscovery.discover) -> AppUpdateCapability
    func clear()
    func reload()
}

static func attachUpdateCapabilities(
    to apps: [AppItem],
    cache: RegularAppUpdateDiscoveryCache? = nil
) -> [AppItem]
```

The cache should only skip filesystem parsing when metadata matches. It should not cache remote Sparkle appcast results.

## Data Flow

```text
SoftwareScanner.scanAll(...)
  -> scanApplications()
  -> classify(...)
  -> attachUpdateCapabilities(..., cache: regularAppCache)
       -> cache validates Info.plist metadata
       -> cache hit returns AppUpdateCapability
       -> cache miss calls RegularAppUpdateDiscovery.discover(appPath:)
       -> cache saves updated record
  -> enrichRegularAppUpdates(..., sparkleConcurrencyLimit: 4)
       -> eligible Sparkle apps checked concurrently
       -> SparkleAppcastChecker.check(..., timeout: 8)
       -> results applied by original index
  -> ScanPerformanceSnapshot still records regularAppDiscovery and sparkleAppcast phases
```

## Error Handling

- Invalid or corrupt cache JSON logs and starts with an empty cache.
- Cache save failure logs and scan continues with fresh discovery results.
- Missing `Info.plist` removes stale cache data and returns `.none`.
- Sparkle timeout writes a timeout diagnostic to that app and does not throw.
- Sparkle HTTP and parse failures keep current non-fatal behavior.
- If a concurrent Sparkle task fails internally, it returns the same app with diagnostic text rather than canceling sibling tasks.

## Testing Strategy

Use focused Swift single-file tests compatible with `scripts/test-native.sh`.

### Sparkle Concurrency Tests

Update `ScannerSparkleAppcastPolicyTest` or add `ScannerSparkleConcurrencyTest` to cover:

- `localOnly` still does not invoke `sparkleChecker`.
- With three eligible Sparkle apps and limit `2`, at most two checks are active at once.
- Returned apps preserve original input order even if checks complete out of order.
- Non-Sparkle apps and Sparkle apps without feed URLs pass through unchanged.

The test can use an actor to count active checks and control completions.

### Sparkle Timeout Tests

Update `SparkleAppcastCheckerTest` to cover:

- Request timeout uses the configured value through a testable request-builder helper, or timeout errors map to `Sparkle feed 检查超时。`.
- Existing parse and version comparison tests still pass.

Avoid live network tests.

### Discovery Cache Tests

Add `RegularAppUpdateDiscoveryCacheTest` covering:

- First lookup calls loader and saves a record.
- Second lookup with unchanged `Info.plist` metadata returns cached capability without calling loader.
- Changing `Info.plist` invalidates the entry and calls loader again.
- Missing app or missing `Info.plist` returns `.none` and removes stale entries.
- Corrupt JSON loads as an empty cache.
- Records are trimmed to the configured limit.

### Scanner Integration Tests

Update `ScannerAppUpdateCapabilityTest` to verify:

- `attachUpdateCapabilities(to:cache:)` produces the same capability result as the uncached path.
- A cache hit preserves the existing `checkable` state transition for manual apps.

## Rollout Order

1. Add Sparkle concurrency tests.
2. Implement bounded concurrent Sparkle enrichment.
3. Add Sparkle timeout diagnostic/request helper tests.
4. Implement explicit timeout in `SparkleAppcastChecker`.
5. Add discovery cache model/store tests.
6. Implement `RegularAppUpdateDiscoveryCache`.
7. Wire cache into scanner update capability discovery.
8. Run `npm test` and `npm run build`.

## Acceptance Criteria

- Sparkle appcast enrichment no longer checks eligible feeds strictly sequentially.
- Sparkle appcast concurrency is bounded and deterministic in tests.
- Sparkle enrichment preserves input app order.
- One slow feed is bounded by an explicit timeout and records a timeout diagnostic.
- Local update capability discovery skips `Info.plist` parsing when metadata is unchanged.
- Cache corruption or write failure does not block scans.
- Existing scan performance phases continue to be recorded.
- `npm test` passes.
- `npm run build` passes.
