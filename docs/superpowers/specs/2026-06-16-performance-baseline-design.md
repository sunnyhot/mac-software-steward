# Performance Baseline Design

## Context

Mac 软件管家 is a native SwiftUI macOS app that scans local `.app` bundles, Homebrew formulae and casks, and Mac App Store apps through `mas`. The repository already has project-native build and test scripts, with `npm test` compiling focused Swift test binaries and `npm run build` compiling the app directly through `xcrun swiftc`.

The user wants performance optimization across three areas: scan speed, UI responsiveness, and build/test speed. The selected first step is not to optimize immediately, but to produce an evidence-based performance baseline and hotspot report. This keeps the next optimization pass grounded in measured data instead of assumptions.

Current project signals:

1. `SoftwareScanner.scanAll` already runs Applications, Homebrew, and `mas` scans concurrently.
2. `system_profiler SPApplicationsDataType -json` is documented as a possible slow path, with `find` as a fallback.
3. Regular app Sparkle feed enrichment currently happens after classification and checks matching apps sequentially.
4. `StewardModel` is `@MainActor` and owns scan result application, derived data recomputation, progress state, and UI-facing collections.
5. `scripts/test-native.sh` compiles each Swift test executable explicitly, which makes test/build timing observable but may also reveal repeated compilation cost.

## Goals

- Produce a performance baseline report that covers scan speed, UI responsiveness risk, and build/test speed.
- Separate measured facts from static code analysis and informed hypotheses.
- Identify the highest-value optimization queue for the next implementation pass.
- Avoid requiring additional tools beyond what the repo already uses.
- Keep the baseline work small enough to complete before making behavior changes.

## Non-Goals

- No production performance optimization in the baseline pass.
- No UI redesign.
- No migration to Xcode project or Swift Package Manager.
- No dependency on Instruments, external profilers, or paid tools for the baseline report.
- No changes to release packaging or app distribution.

## Proposed Approach

Use an endpoint baseline plus hotspot localization.

The baseline report will be written to:

```text
docs/performance/2026-06-16-baseline.md
```

The report will have three sections:

1. Build and test timing from project-native commands.
2. Scan-path timing and hotspot analysis.
3. UI responsiveness risk analysis.

Where direct measurement is available, the report will label it as measured. Where the code suggests a likely bottleneck but the current repo has no timing hook yet, the report will label it as static analysis and recommend instrumentation for the next pass.

## Build And Test Baseline

The baseline should run:

```bash
time npm test
time npm run build
```

The report should capture:

- command success or failure,
- wall-clock elapsed time,
- key toolchain lines printed by the build script,
- the slowest visible phase from command output,
- whether failures are environmental, toolchain-related, or code-related.

`scripts/test-native.sh` already prints each test binary as it builds and runs. If command output is enough to identify a slow test target, the report should list it. If output is not enough, the report should recommend adding per-test timing to the script in the next pass.

## Scan Baseline

The desired scan breakdown is:

- total `scanAll` elapsed time,
- Applications scan through `system_profiler` or `find`,
- Homebrew command group,
- `mas` command group,
- application source classification,
- regular app update capability discovery,
- Sparkle appcast checks.

The first report can use static analysis for this breakdown if production code does not yet expose timings. The next implementation pass can add minimal instrumentation around these exact boundaries.

Important scanner observations to verify:

1. `system_profiler` has a 120 second timeout and may dominate cold scans on machines with many apps.
2. Homebrew work is already grouped with a task group, so optimization may come from timeout tuning, command count reduction, or better reporting rather than simple parallelization.
3. `mas list` and `mas outdated` already run concurrently.
4. Sparkle appcast checks are sequential today and can make scan time scale linearly with the number of manual apps that declare feeds.
5. Local `Info.plist` parsing for regular apps happens for every scanned app and may be worth measuring separately before adding caches.

## UI Responsiveness Baseline

The report should review the main UI-facing path from scan completion to SwiftUI update:

```text
StewardModel.scanSoftware()
  -> scanner.scanAll(...)
  -> scan = result
  -> prunePackageProgress(keeping:)
  -> recomputeDerivedData()
  -> inbox item publication
  -> notification decision
```

The report should call out work that runs on `@MainActor`, especially:

- applying large scan results,
- recomputing derived package collections,
- filtering/sorting for views,
- publishing inbox items after scans,
- frequent progress updates during long commands.

This pass should not change UI code. It should identify which work should remain on the main actor and which work could later move into pure helpers or background preparation before a single main-actor assignment.

## Data Flow

Baseline execution flow:

1. Record repository commit and toolchain context.
2. Run `npm test` and capture elapsed time and pass/fail status.
3. Run `npm run build` and capture elapsed time and pass/fail status.
4. Review scanner code paths and existing tests for phase boundaries.
5. Review `StewardModel` and SwiftUI-facing derived data paths for main-actor risk.
6. Write `docs/performance/2026-06-16-baseline.md`.
7. Summarize the optimization queue by likely impact and implementation risk.

## Error Handling

- If `npm test` fails, the report records the failing test or compile target and treats the result as a baseline blocker.
- If `npm run build` fails due to toolchain mismatch, the report records the build script diagnostics and does not classify the failure as app performance.
- If timing commands are interrupted, the report records the interruption and does not invent elapsed values.
- If scan timings cannot be measured without code changes, the report explicitly marks scan phase timings as not yet measured and recommends a small instrumentation task.

## Optimization Queue Format

The report should end with a prioritized queue. Each candidate should include:

- area: scan, UI, build/test,
- evidence type: measured or static analysis,
- expected benefit: high, medium, or low,
- implementation risk: high, medium, or low,
- suggested verification command.

Likely candidates to validate include:

1. Add bounded concurrent Sparkle appcast checks with per-request timeout.
2. Add scan phase timing instrumentation.
3. Cache or batch regular app `Info.plist` update capability discovery if measured as costly.
4. Move expensive derived-data preparation out of `@MainActor` where the data is pure.
5. Add per-test timing to `scripts/test-native.sh`.
6. Consider test/build compilation reuse only after the script timing shows repeated compilation is a meaningful cost.

## Testing And Verification

The baseline report itself is documentation, so verification is evidence quality:

- `time npm test` was run, or the exact blocker is recorded.
- `time npm run build` was run, or the exact blocker is recorded.
- The report includes the current git commit.
- Scanner, UI, and build/test sections each include at least one concrete hotspot or a reason no hotspot can be identified yet.
- Recommendations distinguish measured bottlenecks from static-analysis risks.

## Acceptance Criteria

- A baseline report exists at `docs/performance/2026-06-16-baseline.md`.
- The report answers where performance risk appears in scan speed, UI responsiveness, and build/test speed.
- The report provides evidence for each claim or labels it as static analysis.
- The report proposes a next optimization order with expected benefit, implementation risk, and verification command.
- The baseline work does not require extra user-installed tools.
