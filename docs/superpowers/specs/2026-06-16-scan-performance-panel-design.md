# Scan Performance Panel Design

## Context

Mac 软件管家 now has a performance baseline report at `docs/performance/2026-06-16-baseline.md`. The report found that scan phase timings are blocked because the scanner only records total `ScanSummary.scanMs`, while source analysis points to likely hotspots in Applications scanning, regular app metadata discovery, and sequential Sparkle appcast checks.

The user chose the full performance panel approach: scan performance should be visible in Advanced Mode UI, and the app should persist the latest 50 scan performance records across app restarts.

Current project constraints:

1. The app is native SwiftUI/AppKit with no Xcode project; build and tests run through `scripts/build-native.sh` and `scripts/test-native.sh`.
2. Advanced Mode tabs are controlled by `AppTab.visibleTabs(advancedModeEnabled:)`.
3. `SoftwareScanner.scanAll` already has natural scan phase boundaries and records total scan time.
4. Persistent local JSON stores already exist for inspection reports and upgrade history.
5. UI text is Chinese, while code identifiers remain English.

## Goals

- Add a Performance tab that appears only in Advanced Mode.
- Record scan phase durations for each completed scan.
- Persist the latest 50 scan performance records in a local JSON file.
- Show the latest scan, the slowest phase, phase duration breakdown, recent scan trend list, and simple diagnostic hints.
- Keep the first implementation focused on observability, not optimization.

## Non-Goals

- No scanning speed optimization in this pass.
- No charting library or custom graph framework.
- No Instruments integration, sampling profiler, CPU metrics, memory metrics, or frame-time profiler.
- No cloud sync or remote telemetry.
- No changes to release packaging, code signing, or distribution.
- No screenshots-based UI tests.

## Proposed Architecture

### Scan Timing Model

Add small value types near the existing scan models:

- `ScanPerformancePhase`: a stable phase key with Chinese display title.
- `ScanPerformanceStage`: one phase duration, in milliseconds.
- `ScanPerformanceSnapshot`: one completed scan's timings and high-level metadata.

The initial phases are:

1. `applications`: 本机应用
2. `brew`: Homebrew
3. `mas`: App Store
4. `classification`: 关联来源
5. `regularAppDiscovery`: 普通 App 检查
6. `sparkleAppcast`: Sparkle 更新源
7. `total`: 总耗时

The implementation should split the current regular app work into two explicit timing boundaries:

- local update capability discovery, which reads app metadata such as `Info.plist`;
- Sparkle appcast network checks, which fetch declared update feeds.

This avoids double-counting the enclosing regular-app phase and gives the Performance page enough detail to distinguish local filesystem work from network update checks.

### Scan Result Integration

Extend `ScanResult` with:

```swift
var performance: ScanPerformanceSnapshot
```

`SoftwareScanner.scanAll` should create the snapshot while it already coordinates the scan:

1. Start an overall timer.
2. Time the async Applications, Homebrew, and `mas` tasks independently.
3. Time classification after those tasks return.
4. Time local regular app update capability discovery separately from Applications enumeration.
5. Time Sparkle appcast enrichment separately from local discovery.
6. Build `ScanPerformanceSnapshot` with stage timings, scan source metadata, package/app counts, and `includeGreedy`.

The existing `ScanSummary.scanMs` remains as the user-facing total summary field for compatibility. It should be derived from the same total timer as `performance.totalMs`.

### Persistent Store

Add `ScanPerformanceStore`, following the local JSON pattern used by `InspectionReportStore` and `UpgradeHistoryStore`.

Store behavior:

- File path: `~/Library/Application Support/MacSoftwareSteward/scan-performance.json`
- Default limit: 50 records
- New records are inserted newest-first.
- Duplicate IDs are replaced.
- Records are sorted newest-first before saving.
- `reload()`, `append(_:)`, `clear()`, and `replaceRecords(_:)` are available for tests and import/export compatibility.
- Save failures use `NSLog`, matching the existing local store pattern.

The app should instantiate the store in `StewardModel` so scan completion can append to it, and `PerformanceView` can observe it through the model.

### Advanced Mode Navigation

Add a new `AppTab.performance = "性能"`.

Tab behavior:

- Advanced Mode visible tabs include `.performance`.
- Default mode visible tabs do not include `.performance`.
- If Advanced Mode is turned off while Performance is selected, the existing visibility guard should move the user back to Inbox.
- The tab symbol should use an SF Symbol such as `speedometer` or `chart.line.uptrend.xyaxis`.
- `usesSearch` should be false for Performance.

### Performance View

Add `native/MacSoftwareSteward/Views/PerformanceView.swift`.

The view should be dense and utility-focused, consistent with the existing operational UI:

- Empty state when no performance records exist.
- Latest scan summary:
  - total duration,
  - slowest phase,
  - scan time,
  - applications/brew/mas counts.
- Phase breakdown:
  - phase title,
  - duration in ms or seconds,
  - percentage of total,
  - compact horizontal bar using SwiftUI shapes.
- Recent scans:
  - newest-first list,
  - total duration,
  - slowest phase,
  - count summary,
  - timestamp.
- Diagnostics:
  - if Applications dominates, mention `system_profiler` can be slow;
  - if regular app/Sparkle dominates, mention ordinary app update checks may be the bottleneck;
  - if Homebrew dominates, mention source command latency;
  - if no single phase dominates, show a neutral "scan is balanced" note.

The first version does not need an interactive chart. A compact trend list and phase bars satisfy the full panel requirement without adding a new visualization dependency.

## Data Flow

```text
Header scan button / menu scan action
  -> StewardModel.scanSoftware(...)
  -> scanner.scanAll(...)
  -> SoftwareScanner measures phase timings
  -> ScanResult(performance: snapshot)
  -> StewardModel assigns scan
  -> StewardModel.scanPerformanceStore.append(snapshot)
  -> PerformanceView observes scanPerformanceStore.records
```

Manual scans, menu scans, and automatic rescans triggered by upgrade flows should all produce a performance record because they call `StewardModel.scanSoftware`.

Daily inspection agent scans do not need to write to the GUI app performance store in this pass because the agent runs as a separate command-line target and would require shared store wiring. That can be a follow-up after the main app panel proves useful.

## Error Handling

- Store read failure returns an empty list rather than blocking app launch.
- Store write failure logs with `NSLog` and does not fail the scan.
- Missing or zero durations should render as `0 ms` and avoid division by zero.
- If a scan fails partially but still returns a `ScanResult`, the performance snapshot should still be appended, with source errors visible through existing scan structures.
- If no records exist, PerformanceView shows an empty state instead of placeholder numbers.

## Testing Strategy

Use focused Swift single-file tests compatible with `scripts/test-native.sh`.

### Model Tests

Add tests for:

- `ScanPerformanceSnapshot.slowestStage` picks the highest non-total phase.
- `ScanPerformanceStage.fraction(of:)` returns 0 when total is 0.
- Phase titles are stable and Chinese.
- Total duration formatting handles milliseconds and seconds.

### Store Tests

Add `ScanPerformanceStoreTest` covering:

- append inserts newest-first,
- appending a duplicate ID replaces the existing record,
- records are trimmed to the configured limit,
- `reload()` loads JSON from disk,
- `clear()` removes records and saves an empty list.

### Integration Tests

Update or add tests for:

- `AppTab.visibleTabs(advancedModeEnabled:)` includes Performance only in Advanced Mode.
- `StewardModel.scanSoftware` appends one performance record after a successful scan. This can use a test scanner returning a fixed `ScanResult`.
- Existing scan guard behavior still ignores overlapping scans.

### Presenter/View Tests

Avoid brittle screenshot tests. If the view needs derived display rows, add a small presenter such as `ScanPerformancePresenter` and test:

- summary values,
- phase row ordering,
- diagnostic hint selection,
- empty-state detection.

## Documentation Updates

- Update `PROJECT_MAP.md` after implementation to include the new performance store/view.
- Update the performance baseline report or add a follow-up note only if implementation changes the previously blocked scan timing status.
- No README update is required unless the Performance tab becomes part of user-facing feature coverage.

## Rollout Order

1. Add scan performance model and tests.
2. Add scan performance store and tests.
3. Instrument `SoftwareScanner.scanAll`.
4. Wire `StewardModel` to append snapshots.
5. Add Advanced Mode Performance tab.
6. Add presenter and Performance view.
7. Update `scripts/test-native.sh` for new tests.
8. Update project docs.
9. Run `npm test` and `npm run build`.

## Acceptance Criteria

- Advanced Mode shows a "性能" tab; default mode does not.
- Every completed main-app scan appends one scan performance record.
- The latest 50 scan performance records persist across app restarts.
- The Performance page shows latest scan summary, phase breakdown, recent trend list, and diagnostic hints.
- Phase calculations avoid crashes for zero-duration or missing data.
- Existing scan behavior and scan guard behavior continue to work.
- `npm test` passes.
- `npm run build` passes.
