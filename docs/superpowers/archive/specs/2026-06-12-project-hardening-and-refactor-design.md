# Project Hardening and Focused Refactor Design

## Context

Mac 软件管家 is a native macOS utility that scans installed software, plans upgrades, runs Homebrew and `mas` commands, schedules daily LaunchAgent inspections, and self-updates from GitHub Releases. The project has grown beyond a simple script: it has persistent policies, task logs, package progress, release packaging, and 18 Swift test entry points.

The current risk scan identified three confirmed implementation risks:

1. The self-update flow reads `sha256` from `latest.json` but does not verify the downloaded zip before installing it.
2. The self-update install script deletes the existing `.app` before copying the replacement, with no backup or rollback path.
3. Scanning can be triggered concurrently, and `Scanner` uses a mutable static token cache that can be written from concurrent scan tasks.

The scan also found engineering gaps: `npm test` is documented but missing, existing tests are not wired into npm or CI, release CI builds without test coverage, toolchain mismatch errors are hard to understand, README and PROJECT_MAP have drifted from the repo, and several files have become large enough to slow future changes.

## Goals

- Make self-update safer by verifying downloaded release artifacts and adding rollback-capable installation.
- Prevent duplicate scans and remove mutable shared scanner state.
- Wire existing Swift tests into local npm workflow and GitHub Actions.
- Improve build diagnostics for Swift/SDK toolchain mismatches.
- Bring README and PROJECT_MAP back in sync with the current repository.
- Apply focused refactoring only where it directly supports the safety and testability changes.

## Non-Goals

- No full UI redesign.
- No wholesale rewrite of `StewardModel`, `AppUpdater`, or SwiftUI view files.
- No Developer ID certificate setup or notarization automation in this pass because credentials and Apple account configuration are external to the repo.
- No conversion to Xcode project or Swift Package unless needed by the test runner; the current direct `swiftc` build model remains.

## Proposed Architecture

### Self-Update Artifact Trust

The release manifest should keep the expected `sha256` attached to the selected asset until after download. `downloadInstallAndRestart()` should fail before extraction if the downloaded zip hash does not match the manifest hash.

Implementation shape:

- Add a small value type for selected release assets, including name, download URL, size, and expected SHA-256.
- Add a hash helper that streams or reads the downloaded file and returns lowercase hex SHA-256.
- Validate hash immediately after download and before `extractApp(from:)`.
- Show a user-friendly error message when hash verification fails.

This keeps the trust boundary simple: network download is not trusted until hash verification passes.

### Rollback-Capable Install Script

The install script should avoid deleting the existing app before the replacement is known to be usable. The new flow:

1. Wait for the old app process to exit, then terminate as today if it does not exit.
2. Copy the new app to a temporary sibling path under the destination directory.
3. Verify the copied app has the expected executable and is a valid bundle directory.
4. Move the existing destination app to a backup sibling path.
5. Move the temporary app into the final destination.
6. Try to open the new app.
7. On failure after the backup step, restore the backup to the destination.
8. Clean temporary files when safe, but keep enough log detail to diagnose failure.

The script should stay shell-based because it must run after the GUI app exits, but its generated content should be covered by tests that assert ordering and rollback behavior.

### Scan Reentrancy and Scanner State

`StewardModel.scanSoftware()` should be internally guarded:

- If `isScanning` is already true, return without starting another scan.
- Use `defer` to reset `isScanning` and `scanPhase`.
- UI entry points should also disable scan actions while scanning, but the model guard is the source of truth.

`Scanner.normalizeToken` should remove the mutable static cache. The normalization is cheap and deterministic, so recalculating is safer than locking a global dictionary.

### Test Runner and CI

The repository should have one local command that runs all existing Swift tests:

- Add `scripts/test-native.sh`.
- Add `npm test` to `package.json`.
- Add `build:native` and `open:native` aliases to match README, while keeping existing `build` and `open`.
- The test script should compile each test as a standalone executable with exactly the production files it needs.
- GitHub release workflow should run `npm test` before building the release artifact.

The test script can remain explicit rather than clever. Explicit source lists make failures easier to diagnose in a repo without Swift Package metadata.

### Build Diagnostics

`scripts/build-native.sh` should print toolchain context before compiling:

- `xcodebuild -version`
- `xcrun swiftc --version`
- `xcrun --show-sdk-path`

If compilation fails due to a Swift/SDK mismatch, the script should show an actionable hint about selecting a matching Xcode/CommandLineTools path. The first pass can provide clearer preflight output and error trapping around the compile step; deep parsing of `.swiftinterface` files is not required.

### Focused Refactor

Refactoring should support the safety work without expanding scope:

- In `AppUpdater`, extract manifest/asset/hash responsibilities into focused helpers or small types in the same file or a new `ReleaseManifest.swift` if that keeps the public surface clean.
- Keep install script content in `SelfUpdateInstallScript.swift`, but make it more testable through constants or clear marker strings if useful.
- In `StewardModel`, avoid moving the whole job runner in this pass unless the scan guard and package execution changes force it. If a split is needed, use a focused extension file such as `StewardModel+Scanning.swift` or `StewardModel+Jobs.swift`.
- Do not restructure SwiftUI view composition in this pass except for scan-action disabled state changes.

## Data Flow

Self-update flow after this change:

1. `checkForUpdates()` fetches `latest.json`.
2. Manifest decoding creates an asset that includes expected SHA-256.
3. `downloadInstallAndRestart()` downloads the zip to the work directory.
4. The updater computes SHA-256 and compares with manifest value.
5. On mismatch, the flow stops with a user-facing error.
6. On match, the updater extracts the app and schedules install.
7. The install script copies to temp, backs up existing app, swaps, opens, and rolls back if needed.

Scan flow after this change:

1. UI or menu calls `scanSoftware()`.
2. Model returns immediately if a scan is already running.
3. One scan runs `SoftwareScanner.scanAll`.
4. The result writes back once, then `isScanning` and `scanPhase` are reset through `defer`.

Test/CI flow after this change:

1. Developer runs `npm test`.
2. `scripts/test-native.sh` compiles and runs each Swift test.
3. Release CI runs the same command before packaging.

## Error Handling

- Hash mismatch should produce a clear localized error such as "下载文件校验失败，请稍后重试。"
- Installation script failures should be logged to `self-update.log`, including whether a backup was created and restored.
- If rollback fails, logs should explicitly mention the backup path so the user can recover manually.
- Scan reentry should be silent because repeated scan clicks are harmless user behavior, not an error.
- Test runner failure should stop at the failing test and print the compile/run command context.

## Testing Strategy

Use test-first implementation for behavior changes.

Tests to add or update:

- `AppUpdate` hash verification: a mismatched expected SHA-256 fails before extraction or install scheduling.
- `SelfUpdateInstallScriptTest`: script contains temp destination, backup destination, rollback trap/restore logic, and replacement happens after copy/validation.
- `Scanner` normalization: normalization remains deterministic after removing cache.
- `StewardModel` scan guard: repeated scan calls while scanning do not launch a second scanner invocation. If direct injection is too invasive, introduce a small scanning client seam first and test that seam.
- `scripts/test-native.sh`: can be verified by running `npm test`.

Existing tests should continue to pass under `npm test`.

## Documentation Updates

- README should list actual npm scripts: `npm run build`, `npm run build:native`, `npm run open`, `npm run open:native`, `npm test`.
- README should clarify that the native app does not require the old Web panel path unless that panel still exists.
- PROJECT_MAP should update version references, file line counts where materially wrong, and remove the stale "no tests" statement.
- The risk report in `code-risk-scanner/` remains a local analysis artifact and is not part of this design's required code changes.

## Rollout Order

1. Add test runner and wire `npm test` so future work has a single verification command.
2. Add failing tests for self-update hash verification, then implement hash checking.
3. Add failing tests for rollback-capable install script, then update script.
4. Add failing tests for scan reentry/token normalization, then update scanner/model/UI disabled states.
5. Add CI test step and build diagnostics.
6. Update README and PROJECT_MAP.
7. Run `npm test` and `npm run build`.

## Acceptance Criteria

- `npm test` exists and runs the Swift tests.
- GitHub release workflow runs tests before packaging.
- Downloaded self-update zip is rejected when SHA-256 differs from manifest.
- Install script no longer removes the existing destination app before a replacement copy is prepared.
- Install script includes backup and rollback behavior.
- Concurrent scan triggers do not start overlapping scans.
- `Scanner` has no mutable static token cache.
- README and PROJECT_MAP no longer contradict package scripts or test presence.
- Any remaining build failure is accompanied by actionable toolchain diagnostics.
