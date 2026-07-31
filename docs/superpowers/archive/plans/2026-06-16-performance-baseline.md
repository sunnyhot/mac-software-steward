# Performance Baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce an evidence-based baseline report for scan speed, UI responsiveness risk, and build/test speed.

**Architecture:** The baseline pass collects raw command evidence under `build/performance/2026-06-16/`, analyzes scanner and UI source paths without production changes, then writes one human-readable report under `docs/performance/2026-06-16-baseline.md`. The work treats measured timings and static analysis separately so follow-up optimization can target the highest-value bottlenecks.

**Tech Stack:** Swift/macOS, SwiftUI/AppKit, shell scripts, npm scripts, git, Markdown documentation.

---

## Scope Check

The approved spec spans scan speed, UI responsiveness, and build/test speed, but the implementation output is one baseline report plus local raw evidence. This is a single coherent plan because all three areas feed one optimization queue and no production Swift code changes are required.

## File Structure

- Create: `docs/performance/2026-06-16-baseline.md`
  - Responsibility: final baseline report with measured command timings, static hotspot analysis, UI responsiveness risks, and prioritized optimization candidates.
- Generate locally, do not commit: `build/performance/2026-06-16/environment.txt`
  - Responsibility: raw environment and toolchain evidence.
- Generate locally, do not commit: `build/performance/2026-06-16/npm-test.log`
  - Responsibility: raw `npm test` timing and output.
- Generate locally, do not commit: `build/performance/2026-06-16/npm-test.exit`
  - Responsibility: exit code for `npm test`.
- Generate locally, do not commit: `build/performance/2026-06-16/npm-build.log`
  - Responsibility: raw `npm run build` timing and output.
- Generate locally, do not commit: `build/performance/2026-06-16/npm-build.exit`
  - Responsibility: exit code for `npm run build`.
- Reference only: `docs/superpowers/specs/2026-06-16-performance-baseline-design.md`
  - Responsibility: approved design source.
- Reference only: `native/MacSoftwareSteward/Scanner.swift`
  - Responsibility: scan orchestration, Applications scan, Homebrew scan, `mas` scan, classification, update capability discovery, Sparkle enrichment.
- Reference only: `native/MacSoftwareSteward/SparkleAppcastChecker.swift`
  - Responsibility: Sparkle feed network check and XML parsing.
- Reference only: `native/MacSoftwareSteward/StewardModel.swift`
  - Responsibility: main-actor scan application, derived data recomputation, inbox publication, UI-facing state.
- Reference only: `scripts/test-native.sh`
  - Responsibility: explicit Swift test binary build/run loop.
- Reference only: `scripts/build-native.sh`
  - Responsibility: app build, toolchain diagnostics, signing, and bundle verification.

## Task 1: Capture Environment Evidence

**Files:**
- Generate locally: `build/performance/2026-06-16/environment.txt`
- Reference: `package.json`
- Reference: `scripts/build-native.sh`

- [ ] **Step 1: Verify repository state before measuring**

Run:

```bash
git status --short
```

Expected: no production Swift files are modified. If uncommitted files exist, record them in the final report under "Measurement Notes" before running timings.

- [ ] **Step 2: Create the raw evidence directory**

Run:

```bash
mkdir -p build/performance/2026-06-16
```

Expected: command exits successfully and creates the scratch directory.

- [ ] **Step 3: Capture commit, OS, architecture, Node, npm, and Swift toolchain**

Run:

```bash
{
  printf 'commit='
  git rev-parse --short HEAD
  printf 'date='
  date '+%Y-%m-%d %H:%M:%S %Z'
  printf '\n[sw_vers]\n'
  sw_vers
  printf '\n[uname]\n'
  uname -a
  printf '\n[node]\n'
  node --version
  printf '\n[npm]\n'
  npm --version
  printf '\n[xcode-select]\n'
  xcode-select -p
  printf '\n[macosx-sdk-path]\n'
  xcrun --sdk macosx --show-sdk-path
  printf '\n[macosx-sdk-version]\n'
  xcrun --sdk macosx --show-sdk-version
  printf '\n[swift]\n'
  xcrun swift --version | sed -n '1p'
  printf '\n[swiftc]\n'
  xcrun swiftc --version | sed -n '1p'
} > build/performance/2026-06-16/environment.txt
```

Expected: `build/performance/2026-06-16/environment.txt` contains a commit hash, macOS version, machine architecture, Node/npm versions, Xcode path, SDK path/version, and Swift version lines.

- [ ] **Step 4: Inspect captured environment**

Run:

```bash
sed -n '1,160p' build/performance/2026-06-16/environment.txt
```

Expected: output is readable and has no missing command sections. If a command is unavailable, keep the command error in the raw file and mention it in the final report.

## Task 2: Measure Build And Test Commands

**Files:**
- Generate locally: `build/performance/2026-06-16/npm-test.log`
- Generate locally: `build/performance/2026-06-16/npm-test.exit`
- Generate locally: `build/performance/2026-06-16/npm-build.log`
- Generate locally: `build/performance/2026-06-16/npm-build.exit`
- Reference: `scripts/test-native.sh`
- Reference: `scripts/build-native.sh`

- [ ] **Step 1: Run timed test command**

Run:

```bash
bash -lc '/usr/bin/time -p npm test' > build/performance/2026-06-16/npm-test.log 2>&1
printf '%s\n' "$?" > build/performance/2026-06-16/npm-test.exit
```

Expected: `npm-test.log` ends with `real`, `user`, and `sys` timing lines from `/usr/bin/time -p`. `npm-test.exit` contains `0` when tests pass, or a non-zero code when test/build compilation fails.

- [ ] **Step 2: Summarize test result from raw output**

Run:

```bash
cat build/performance/2026-06-16/npm-test.exit
tail -n 30 build/performance/2026-06-16/npm-test.log
rg -n "==> Building|==> Running|real|user|sys|error:|failed|FAIL|PASS" build/performance/2026-06-16/npm-test.log
```

Expected: the exit code and timing lines are visible. The `rg` output shows the test script's per-target build/run labels; if it does not reveal per-target duration, record that limitation in the final report.

- [ ] **Step 3: Run timed build command**

Run:

```bash
bash -lc '/usr/bin/time -p npm run build' > build/performance/2026-06-16/npm-build.log 2>&1
printf '%s\n' "$?" > build/performance/2026-06-16/npm-build.exit
```

Expected: `npm-build.log` ends with `real`, `user`, and `sys` timing lines from `/usr/bin/time -p`. `npm-build.exit` contains `0` when the app builds and signs successfully, or a non-zero code when compilation, signing, or toolchain setup fails.

- [ ] **Step 4: Summarize build result from raw output**

Run:

```bash
cat build/performance/2026-06-16/npm-build.exit
tail -n 40 build/performance/2026-06-16/npm-build.log
rg -n "==> Toolchain|==> Generating app icon|==> Building|==> Signing|==> Verifying|real|user|sys|error:|failed|Signature OK" build/performance/2026-06-16/npm-build.log
```

Expected: the exit code, toolchain section, build phases, signing/verification status, and timing lines are visible. If the build fails before timing lines, record the exact failure as a blocker rather than estimating duration.

## Task 3: Analyze Scanner And UI Hotspots

**Files:**
- Reference: `native/MacSoftwareSteward/Scanner.swift`
- Reference: `native/MacSoftwareSteward/SparkleAppcastChecker.swift`
- Reference: `native/MacSoftwareSteward/RegularAppUpdateDiscovery.swift`
- Reference: `native/MacSoftwareSteward/StewardModel.swift`
- Reference: `scripts/test-native.sh`

- [ ] **Step 1: Capture scan orchestration anchors**

Run:

```bash
nl -ba native/MacSoftwareSteward/Scanner.swift | sed -n '23,93p'
nl -ba native/MacSoftwareSteward/Scanner.swift | sed -n '120,205p'
nl -ba native/MacSoftwareSteward/Scanner.swift | sed -n '475,535p'
```

Expected: output shows `scanAll`, the `system_profiler` Applications scan with 120 second timeout, Homebrew task group commands, concurrent `mas` commands, local update capability discovery, and the sequential Sparkle enrichment loop.

- [ ] **Step 2: Capture Sparkle network check anchors**

Run:

```bash
nl -ba native/MacSoftwareSteward/SparkleAppcastChecker.swift | sed -n '1,45p'
```

Expected: output shows `URLSession.shared.data(from:)` and confirms there is no explicit per-feed request timeout in the checker.

- [ ] **Step 3: Capture main-actor UI state anchors**

Run:

```bash
nl -ba native/MacSoftwareSteward/StewardModel.swift | sed -n '68,165p'
rg -n "func recomputeDerivedData|scan = result|SourceIssueInboxFactory|AppUpdateInboxFactory|@Published var availableUpdates|@Published var allUpgradeablePackages" native/MacSoftwareSteward/StewardModel.swift
```

Expected: output shows derived package recomputation and scan result application inside `StewardModel`, which is a `@MainActor` observable model.

- [ ] **Step 4: Capture build/test script structure anchors**

Run:

```bash
nl -ba scripts/test-native.sh | sed -n '1,80p'
nl -ba scripts/build-native.sh | sed -n '1,120p'
```

Expected: output shows explicit per-test `run_test` calls, direct `swiftc` usage, toolchain diagnostics, app and agent build phases, signing, and verification.

- [ ] **Step 5: Classify findings by evidence type**

Use these classifications in the report:

```text
Measured: command timing and exit status from Task 2 logs.
Static analysis: source-level risk visible from Task 3 anchors.
Blocked: data that cannot be measured without adding instrumentation or using external tools.
```

Expected: every performance claim in the report is tagged as measured, static analysis, or blocked.

## Task 4: Write The Baseline Report

**Files:**
- Create: `docs/performance/2026-06-16-baseline.md`
- Reference: `docs/superpowers/specs/2026-06-16-performance-baseline-design.md`
- Reference: raw evidence files under `build/performance/2026-06-16/`

- [ ] **Step 1: Create the report directory**

Run:

```bash
mkdir -p docs/performance
```

Expected: command exits successfully.

- [ ] **Step 2: Draft the report with the required structure**

Use `apply_patch` to create `docs/performance/2026-06-16-baseline.md`. The report must include these sections in this order:

```markdown
# Performance Baseline - 2026-06-16

## Summary

## Environment

## Build And Test Baseline

## Scan Baseline

## UI Responsiveness Risk

## Optimization Queue

## Measurement Notes

## Verification
```

Expected content rules:

- `Summary` states the highest-risk area, the strongest measured fact, and the first recommended follow-up.
- `Environment` records exact values from `environment.txt`.
- `Build And Test Baseline` includes one row for `npm test` and one row for `npm run build`, each with status, `real`, `user`, `sys`, and notes.
- `Scan Baseline` cites scanner anchors such as `native/MacSoftwareSteward/Scanner.swift:23`, `native/MacSoftwareSteward/Scanner.swift:70`, `native/MacSoftwareSteward/Scanner.swift:120`, `native/MacSoftwareSteward/Scanner.swift:192`, `native/MacSoftwareSteward/Scanner.swift:475`, `native/MacSoftwareSteward/Scanner.swift:493`, and `native/MacSoftwareSteward/SparkleAppcastChecker.swift:9`.
- `UI Responsiveness Risk` cites `native/MacSoftwareSteward/StewardModel.swift:74` and `native/MacSoftwareSteward/StewardModel.swift:133`.
- `Optimization Queue` uses a table with columns `Priority`, `Area`, `Evidence`, `Expected Benefit`, `Implementation Risk`, `Verification`.
- `Measurement Notes` records uncommitted files seen before measuring, missing tools, command failures, and limits such as missing per-test timing.
- `Verification` lists the commands run and whether they passed, failed, or were blocked.

- [ ] **Step 3: Ensure no raw logs are copied wholesale into the report**

Run:

```bash
wc -l docs/performance/2026-06-16-baseline.md
rg -n "==> Building .*Test|^real |^user |^sys |swift-driver|CompileSwift|Command failed" docs/performance/2026-06-16-baseline.md
```

Expected: report is concise. Timing values are summarized, and large raw command output is not pasted into the report. `rg` may find short timing summary lines but should not show long copied build logs.

## Task 5: Verify, Commit, And Handoff

**Files:**
- Verify: `docs/performance/2026-06-16-baseline.md`
- Do not commit: `build/performance/2026-06-16/*`

- [ ] **Step 1: Check report completeness**

Run:

```bash
rg -n "^## Summary|^## Environment|^## Build And Test Baseline|^## Scan Baseline|^## UI Responsiveness Risk|^## Optimization Queue|^## Measurement Notes|^## Verification" docs/performance/2026-06-16-baseline.md
rg -n "Measured|Static analysis|Blocked|npm test|npm run build|Scanner.swift|StewardModel.swift" docs/performance/2026-06-16-baseline.md
```

Expected: all required sections exist, and the report explicitly contains evidence labels plus references to measured commands and source hotspots.

- [ ] **Step 2: Confirm raw evidence is not staged**

Run:

```bash
git status --short
```

Expected: `docs/performance/2026-06-16-baseline.md` is untracked or modified. Raw files under `build/performance/2026-06-16/` are not staged and should not be committed.

- [ ] **Step 3: Stage only the final report**

Run:

```bash
git add docs/performance/2026-06-16-baseline.md
git status --short
```

Expected: only `docs/performance/2026-06-16-baseline.md` is staged for commit. If `build/performance/2026-06-16/*` appears, remove it from staging with `git restore --staged build/performance/2026-06-16`.

- [ ] **Step 4: Commit the baseline report**

Run:

```bash
git commit -m "docs: add performance baseline report"
```

Expected: commit succeeds and includes only `docs/performance/2026-06-16-baseline.md`.

- [ ] **Step 5: Final handoff summary**

Report these items to the user:

```text
Baseline report path: docs/performance/2026-06-16-baseline.md
Commit: output from `git log --oneline -1`
Command timing status: npm test result and npm run build result
Top follow-up: first item from the Optimization Queue
```

Expected: the user can open the report, see the evidence, and choose the first real optimization task.
