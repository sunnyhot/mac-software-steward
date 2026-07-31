# Project Hardening and Focused Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden self-update, prevent duplicate scans, wire tests into local and CI workflows, improve build diagnostics, and refresh documentation while keeping refactors focused.

**Architecture:** Add small focused helpers instead of expanding large types: `AppUpdateSecurity` for hash verification and `SoftwareScanning` for scan injection. Keep the direct `swiftc` build model, but add an explicit native test runner and CI test step. Refactor only the code touched by the safety work.

**Tech Stack:** Swift 6.x, SwiftUI/AppKit, Foundation, CryptoKit, Bash, npm scripts, GitHub Actions.

---

## File Structure

- Create `native/MacSoftwareSteward/AppUpdateSecurity.swift`: SHA-256 computation, expected-hash normalization, and localized verification errors.
- Create `native/MacSoftwareSteward/SoftwareScanning.swift`: protocol seam for `StewardModel.scanSoftware()` and live adapter to `SoftwareScanner`.
- Create `tests/AppUpdateSecurityTest.swift`: tests hash success and hash mismatch behavior.
- Create `tests/ScannerNormalizeTokenTest.swift`: tests deterministic normalization after removing mutable static cache.
- Create `tests/StewardModelScanGuardTest.swift`: tests duplicate scan calls do not launch a second scanner.
- Create `scripts/test-native.sh`: explicit compile/run map for all Swift tests.
- Modify `native/MacSoftwareSteward/AppUpdater.swift`: preserve manifest `sha256` on selected assets and verify downloaded zip before extraction.
- Modify `native/MacSoftwareSteward/SelfUpdateInstallScript.swift`: implement temp-copy, backup, swap, and rollback.
- Modify `native/MacSoftwareSteward/Scanner.swift`: remove mutable static `tokenCache`.
- Modify `native/MacSoftwareSteward/StewardModel.swift`: inject scanner and guard `scanSoftware()` reentry with `defer` cleanup.
- Modify `native/MacSoftwareSteward/App.swift`: disable command-menu scan while scanning.
- Modify `native/MacSoftwareSteward/Views/UpdatesView.swift`: disable failure-card rescan while scanning.
- Modify `scripts/build-native.sh`: print toolchain diagnostics and show an actionable compile-failure hint.
- Modify `.github/workflows/release.yml`: run `npm test` before build.
- Modify `package.json`: add `test`, `build:native`, and `open:native` scripts.
- Modify `README.md`: align commands and remove stale Web-panel emphasis.
- Modify `PROJECT_MAP.md`: align version, file map, tests, and known caveats.

## Task 1: Native Test Runner and npm Scripts

**Files:**
- Create: `scripts/test-native.sh`
- Modify: `package.json`

- [ ] **Step 1: Write the native test runner**

Create `scripts/test-native.sh` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/tests"
SDK_PATH="$(xcrun --show-sdk-path)"
SWIFTC=(xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK_PATH")
SRC="$ROOT_DIR/native/MacSoftwareSteward"
TESTS="$ROOT_DIR/tests"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

run_test() {
  local name="$1"
  shift
  local output="$BUILD_DIR/$name"
  echo "==> Building $name"
  "${SWIFTC[@]}" "$@" -o "$output"
  echo "==> Running $name"
  "$output"
}

run_test AppAppearanceResolverTest \
  "$SRC/Models.swift" \
  "$SRC/AppAppearanceResolver.swift" \
  "$TESTS/AppAppearanceResolverTest.swift"

run_test AppSingleInstancePolicyTest \
  "$SRC/AppSingleInstancePolicy.swift" \
  "$TESTS/AppSingleInstancePolicyTest.swift"

run_test AppUpdateDialogLayoutTest \
  "$SRC/AppUpdateDialogLayout.swift" \
  "$TESTS/AppUpdateDialogLayoutTest.swift"

run_test AppWindowDoubleClickZoomPolicyTest \
  "$SRC/AppWindowDoubleClickZoomPolicy.swift" \
  "$TESTS/AppWindowDoubleClickZoomPolicyTest.swift"

run_test BrewCaskCleanupDetectorTest \
  "$SRC/Models.swift" \
  "$SRC/BrewCaskCleanupDetector.swift" \
  "$TESTS/BrewCaskCleanupDetectorTest.swift"

run_test CommandRunnerControlTest \
  "$SRC/CommandRunner.swift" \
  "$TESTS/CommandRunnerControlTest.swift"

run_test DailyPolicyFilteringTest \
  "$SRC/Models.swift" \
  "$SRC/UpgradePolicyStore.swift" \
  "$SRC/UpgradePlanner.swift" \
  "$SRC/DailyUpgradePolicy.swift" \
  "$TESTS/DailyPolicyFilteringTest.swift"

run_test HomebrewCaskDownloadSizeResolverTest \
  "$SRC/CommandRunner.swift" \
  "$SRC/HomebrewCaskDownloadSizeResolver.swift" \
  "$TESTS/HomebrewCaskDownloadSizeResolverTest.swift"

run_test HomebrewDownloadMonitorTest \
  "$SRC/HomebrewDownloadMonitor.swift" \
  "$TESTS/HomebrewDownloadMonitorTest.swift"

run_test PackageProgressParserTest \
  "$SRC/PackageProgressParser.swift" \
  "$TESTS/PackageProgressParserTest.swift"

run_test ScannerBrewListFallbackTest \
  "$SRC/CommandRunner.swift" \
  "$SRC/Models.swift" \
  "$SRC/Scanner.swift" \
  "$TESTS/ScannerBrewListFallbackTest.swift"

run_test SelfUpdateInstallScriptTest \
  "$SRC/SelfUpdateInstallScript.swift" \
  "$TESTS/SelfUpdateInstallScriptTest.swift"

run_test UpgradeFailureAnalyzerTest \
  "$SRC/Models.swift" \
  "$SRC/UpgradeFailureAnalyzer.swift" \
  "$TESTS/UpgradeFailureAnalyzerTest.swift"

run_test UpgradeHistoryStoreTest \
  "$SRC/UpgradeHistoryStore.swift" \
  "$TESTS/UpgradeHistoryStoreTest.swift"

run_test UpgradePlannerTest \
  "$SRC/Models.swift" \
  "$SRC/UpgradePolicyStore.swift" \
  "$SRC/UpgradePlanner.swift" \
  "$TESTS/UpgradePlannerTest.swift"

run_test UpgradePolicyStoreTest \
  "$SRC/Models.swift" \
  "$SRC/UpgradePolicyStore.swift" \
  "$TESTS/UpgradePolicyStoreTest.swift"

run_test UpgradeProgressPresenterTest \
  "$SRC/Models.swift" \
  "$SRC/UpgradeProgressPresenter.swift" \
  "$TESTS/UpgradeProgressPresenterTest.swift"

run_test UpgradeVerifierTest \
  "$SRC/Models.swift" \
  "$SRC/UpgradeVerifier.swift" \
  "$TESTS/UpgradeVerifierTest.swift"

echo "All native tests passed."
```

- [ ] **Step 2: Make the runner executable**

Run:

```bash
chmod +x scripts/test-native.sh
```

Expected: command exits 0.

- [ ] **Step 3: Add npm aliases**

Modify `package.json` scripts to:

```json
"scripts": {
  "build": "bash scripts/build-native.sh",
  "build:native": "bash scripts/build-native.sh",
  "test": "bash scripts/test-native.sh",
  "package": "bash scripts/package-release.sh",
  "release": "bash scripts/release-github.sh",
  "open": "bash scripts/build-native.sh && open build/MacSoftwareSteward.app",
  "open:native": "bash scripts/build-native.sh && open build/MacSoftwareSteward.app"
}
```

- [ ] **Step 4: Run test runner**

Run:

```bash
npm test
```

Expected: either all tests pass, or the current local Swift/SDK mismatch appears before any project-specific failures. If mismatch appears, keep the runner and continue to Task 7 diagnostics.

- [ ] **Step 5: Commit**

```bash
git add package.json scripts/test-native.sh
git commit -m "test: add native swift test runner"
```

## Task 2: App Update SHA-256 Verification

**Files:**
- Create: `native/MacSoftwareSteward/AppUpdateSecurity.swift`
- Create: `tests/AppUpdateSecurityTest.swift`
- Modify: `native/MacSoftwareSteward/AppUpdater.swift`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Write the failing hash verification test**

Create `tests/AppUpdateSecurityTest.swift`:

```swift
import Foundation

@main
struct AppUpdateSecurityTest {
    static func main() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("app-update-security-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try Data("hello".utf8).write(to: fileURL)

        let expected = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        let actual = try AppUpdateSecurity.sha256Hex(of: fileURL)
        precondition(actual == expected, "Expected SHA-256 \(expected), got \(actual)")

        try AppUpdateSecurity.verifySHA256(fileURL: fileURL, expectedSHA256: "  \(expected.uppercased())  ")

        do {
            try AppUpdateSecurity.verifySHA256(fileURL: fileURL, expectedSHA256: String(repeating: "0", count: 64))
            preconditionFailure("Expected mismatched SHA-256 to throw")
        } catch AppUpdateSecurityError.sha256Mismatch(let expected, let actual) {
            precondition(expected == String(repeating: "0", count: 64))
            precondition(actual == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        }
    }
}
```

- [ ] **Step 2: Add the new test to the runner before implementation**

Append this block after `AppUpdateDialogLayoutTest` in `scripts/test-native.sh`:

```bash
run_test AppUpdateSecurityTest \
  "$SRC/AppUpdateSecurity.swift" \
  "$TESTS/AppUpdateSecurityTest.swift"
```

- [ ] **Step 3: Run the test and verify RED**

Run:

```bash
bash scripts/test-native.sh
```

Expected: FAIL because `native/MacSoftwareSteward/AppUpdateSecurity.swift` does not exist or `AppUpdateSecurity` is not in scope.

- [ ] **Step 4: Implement `AppUpdateSecurity`**

Create `native/MacSoftwareSteward/AppUpdateSecurity.swift`:

```swift
import CryptoKit
import Foundation

enum AppUpdateSecurityError: LocalizedError, Equatable {
    case missingExpectedSHA256
    case sha256Mismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .missingExpectedSHA256:
            return "更新清单缺少安装包校验值。"
        case .sha256Mismatch:
            return "下载文件校验失败，请稍后重试。"
        }
    }
}

enum AppUpdateSecurity {
    static func sha256Hex(of fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func verifySHA256(fileURL: URL, expectedSHA256: String) throws {
        let expected = expectedSHA256
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !expected.isEmpty else {
            throw AppUpdateSecurityError.missingExpectedSHA256
        }

        let actual = try sha256Hex(of: fileURL)
        guard actual == expected else {
            throw AppUpdateSecurityError.sha256Mismatch(expected: expected, actual: actual)
        }
    }
}
```

- [ ] **Step 5: Run the focused test and verify GREEN**

Run:

```bash
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$(xcrun --show-sdk-path)" \
  native/MacSoftwareSteward/AppUpdateSecurity.swift \
  tests/AppUpdateSecurityTest.swift \
  -o build/AppUpdateSecurityTest && build/AppUpdateSecurityTest
```

Expected: PASS with exit code 0.

- [ ] **Step 6: Preserve expected hash on release assets**

In `native/MacSoftwareSteward/AppUpdater.swift`, update the manifest conversion:

```swift
GitHubRelease.Asset(
    name: manifest.asset,
    browserDownloadURL: manifest.downloadURL,
    size: manifest.size ?? 0,
    expectedSHA256: manifest.sha256
)
```

Update `GitHubRelease.Asset`:

```swift
struct Asset: Decodable {
    var name: String
    var browserDownloadURL: String
    var size: Int
    var expectedSHA256: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
        case expectedSHA256 = "sha256"
    }
}
```

- [ ] **Step 7: Verify the downloaded zip before extraction**

In `downloadInstallAndRestart()`, replace:

```swift
let downloaded = try await download(asset: asset)
downloadFraction = nil
progress = "正在解压安装包..."
```

with:

```swift
let downloaded = try await download(asset: asset)
downloadFraction = nil
progress = "正在校验安装包..."
try AppUpdateSecurity.verifySHA256(fileURL: downloaded, expectedSHA256: asset.expectedSHA256)
progress = "正在解压安装包..."
```

- [ ] **Step 8: Run tests**

Run:

```bash
npm test
```

Expected: PASS, unless blocked by the local Swift/SDK mismatch. If blocked, record the mismatch and run the focused command from Step 5 if possible.

- [ ] **Step 9: Commit**

```bash
git add native/MacSoftwareSteward/AppUpdateSecurity.swift native/MacSoftwareSteward/AppUpdater.swift tests/AppUpdateSecurityTest.swift scripts/test-native.sh
git commit -m "fix: verify self-update package checksum"
```

## Task 3: Rollback-Capable Self-Update Install Script

**Files:**
- Modify: `native/MacSoftwareSteward/SelfUpdateInstallScript.swift`
- Modify: `tests/SelfUpdateInstallScriptTest.swift`

- [ ] **Step 1: Rewrite the test for backup and rollback behavior**

Replace `tests/SelfUpdateInstallScriptTest.swift` with:

```swift
import Foundation

@main
struct SelfUpdateInstallScriptTest {
    static func main() {
        let script = SelfUpdateInstallScript.content

        guard let waitRange = script.range(of: "for i in {1..80}") else {
            preconditionFailure("Expected script to wait for the app to quit")
        }
        guard let termRange = script.range(of: #"/bin/kill -TERM "$APP_PID""#) else {
            preconditionFailure("Expected script to terminate the old app if it is still running")
        }
        guard let killRange = script.range(of: #"/bin/kill -KILL "$APP_PID""#) else {
            preconditionFailure("Expected script to force kill the old app if TERM does not work")
        }
        guard let tempRange = script.range(of: #"TEMP_APP="$DEST_APP.updating.$$""#) else {
            preconditionFailure("Expected script to prepare a temporary destination")
        }
        guard let backupRange = script.range(of: #"BACKUP_APP="$DEST_APP.previous.$$""#) else {
            preconditionFailure("Expected script to prepare a backup destination")
        }
        guard let trapRange = script.range(of: #"trap 'restore_backup' ERR"#) else {
            preconditionFailure("Expected script to restore backup on failure")
        }
        guard let copyRange = script.range(of: #"/usr/bin/ditto "$NEW_APP" "$TEMP_APP""#) else {
            preconditionFailure("Expected script to copy the new app into a temporary destination")
        }
        guard let backupMoveRange = script.range(of: #"/bin/mv "$DEST_APP" "$BACKUP_APP""#) else {
            preconditionFailure("Expected script to move the old app to backup before replacement")
        }
        guard let replaceRange = script.range(of: #"/bin/mv "$TEMP_APP" "$DEST_APP""#) else {
            preconditionFailure("Expected script to promote temporary app into final destination")
        }
        guard script.range(of: #"/bin/rm -rf "$DEST_APP""#) == nil else {
            preconditionFailure("Script must not delete the destination app before backup")
        }

        precondition(waitRange.lowerBound < termRange.lowerBound, "TERM should happen after graceful wait")
        precondition(termRange.lowerBound < killRange.lowerBound, "KILL should happen after TERM")
        precondition(tempRange.lowerBound < copyRange.lowerBound, "Temp path should be defined before copy")
        precondition(backupRange.lowerBound < backupMoveRange.lowerBound, "Backup path should be defined before backup")
        precondition(trapRange.lowerBound < backupMoveRange.lowerBound, "Rollback trap should be active before moving the old app")
        precondition(copyRange.lowerBound < backupMoveRange.lowerBound, "New app should be copied before old app is moved")
        precondition(backupMoveRange.lowerBound < replaceRange.lowerBound, "Backup should happen before final replacement")
    }
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$(xcrun --show-sdk-path)" \
  native/MacSoftwareSteward/SelfUpdateInstallScript.swift \
  tests/SelfUpdateInstallScriptTest.swift \
  -o build/SelfUpdateInstallScriptTest && build/SelfUpdateInstallScriptTest
```

Expected: FAIL because the current script deletes `"$DEST_APP"` and lacks temp/backup/rollback markers.

- [ ] **Step 3: Replace the install script content**

Update `SelfUpdateInstallScript.content` to:

```swift
static let content = """
#!/bin/zsh
set -euo pipefail
APP_PID="$1"
DEST_APP="$2"
NEW_APP="$3"
WORK_DIR="$4"
LOG_PATH="$5"
TEMP_APP="$DEST_APP.updating.$$"
BACKUP_APP="$DEST_APP.previous.$$"
RESTORE_NEEDED=0
restore_backup() {
  local code="$?"
  if [ "$RESTORE_NEEDED" = "1" ] && [ -d "$BACKUP_APP" ]; then
    echo "[system] install failed, restoring backup from $BACKUP_APP"
    /bin/rm -rf "$DEST_APP"
    /bin/mv "$BACKUP_APP" "$DEST_APP"
  fi
  /bin/rm -rf "$TEMP_APP"
  exit "$code"
}
trap 'restore_backup' ERR
{
  echo "[system] $(date -u +%FT%TZ) installing update"
  for i in {1..80}; do
    /bin/kill -0 "$APP_PID" 2>/dev/null || break
    /bin/sleep 0.25
  done
  if /bin/kill -0 "$APP_PID" 2>/dev/null; then
    echo "[system] old app still running, terminating $APP_PID"
    /bin/kill -TERM "$APP_PID" 2>/dev/null || true
    for i in {1..20}; do
      /bin/kill -0 "$APP_PID" 2>/dev/null || break
      /bin/sleep 0.25
    done
  fi
  if /bin/kill -0 "$APP_PID" 2>/dev/null; then
    echo "[system] old app still running after TERM, force killing $APP_PID"
    /bin/kill -KILL "$APP_PID" 2>/dev/null || true
    /bin/sleep 0.25
  fi
  /bin/mkdir -p "$(/usr/bin/dirname "$DEST_APP")"
  /bin/rm -rf "$TEMP_APP" "$BACKUP_APP"
  /usr/bin/ditto "$NEW_APP" "$TEMP_APP"
  /usr/bin/test -d "$TEMP_APP/Contents/MacOS"
  EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$TEMP_APP/Contents/Info.plist")"
  /usr/bin/test -x "$TEMP_APP/Contents/MacOS/$EXECUTABLE_NAME"
  if [ -e "$DEST_APP" ]; then
    /bin/mv "$DEST_APP" "$BACKUP_APP"
    RESTORE_NEEDED=1
  fi
  /bin/mv "$TEMP_APP" "$DEST_APP"
  /usr/bin/xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true
  /usr/bin/open -n "$DEST_APP"
  RESTORE_NEEDED=0
  /bin/rm -rf "$BACKUP_APP" "$WORK_DIR"
  echo "[system] update installed to $DEST_APP"
} >> "$LOG_PATH" 2>&1
"""
```

- [ ] **Step 4: Run focused test and verify GREEN**

Run:

```bash
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$(xcrun --show-sdk-path)" \
  native/MacSoftwareSteward/SelfUpdateInstallScript.swift \
  tests/SelfUpdateInstallScriptTest.swift \
  -o build/SelfUpdateInstallScriptTest && build/SelfUpdateInstallScriptTest
```

Expected: PASS.

- [ ] **Step 5: Run all tests**

Run:

```bash
npm test
```

Expected: PASS, unless blocked by the local Swift/SDK mismatch.

- [ ] **Step 6: Commit**

```bash
git add native/MacSoftwareSteward/SelfUpdateInstallScript.swift tests/SelfUpdateInstallScriptTest.swift
git commit -m "fix: add rollback to self-update install"
```

## Task 4: Scanner Normalization Without Mutable Static Cache

**Files:**
- Create: `tests/ScannerNormalizeTokenTest.swift`
- Modify: `native/MacSoftwareSteward/Scanner.swift`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Write deterministic normalization test**

Create `tests/ScannerNormalizeTokenTest.swift`:

```swift
import Foundation

@main
struct ScannerNormalizeTokenTest {
    static func main() {
        precondition(SoftwareScanner.normalizeToken("Visual Studio Code.app") == "visual-studio-code")
        precondition(SoftwareScanner.normalizeToken("Microsoft_Outlook 16.109") == "microsoft-outlook-16-109")
        precondition(SoftwareScanner.normalizeToken("  IINA++  ") == "iina")

        let repeated = (0..<1_000).map { _ in SoftwareScanner.normalizeToken("Arc.app") }
        precondition(Set(repeated) == ["arc"], "Normalization should be deterministic without shared mutable cache")
    }
}
```

- [ ] **Step 2: Add test to runner**

Add to `scripts/test-native.sh` after `ScannerBrewListFallbackTest`:

```bash
run_test ScannerNormalizeTokenTest \
  "$SRC/CommandRunner.swift" \
  "$SRC/Models.swift" \
  "$SRC/Scanner.swift" \
  "$TESTS/ScannerNormalizeTokenTest.swift"
```

- [ ] **Step 3: Run the test before implementation**

Run:

```bash
bash scripts/test-native.sh
```

Expected: PASS before implementation because behavior already normalizes correctly. This is a characterization test for safe refactoring, not a RED behavior test.

- [ ] **Step 4: Remove mutable static cache**

Replace `normalizeToken` in `native/MacSoftwareSteward/Scanner.swift` with:

```swift
static func normalizeToken(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: ".app", with: "")
        .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}
```

Delete:

```swift
private static var tokenCache: [String: String] = [:]
```

- [ ] **Step 5: Run tests**

Run:

```bash
npm test
```

Expected: PASS, unless blocked by the local Swift/SDK mismatch.

- [ ] **Step 6: Commit**

```bash
git add native/MacSoftwareSteward/Scanner.swift tests/ScannerNormalizeTokenTest.swift scripts/test-native.sh
git commit -m "fix: remove scanner token cache"
```

## Task 5: Scan Reentry Guard and Scanner Injection

**Files:**
- Create: `native/MacSoftwareSteward/SoftwareScanning.swift`
- Create: `tests/StewardModelScanGuardTest.swift`
- Modify: `native/MacSoftwareSteward/StewardModel.swift`
- Modify: `native/MacSoftwareSteward/App.swift`
- Modify: `native/MacSoftwareSteward/Views/UpdatesView.swift`
- Modify: `scripts/test-native.sh`

- [ ] **Step 1: Create failing scan guard test**

Create `tests/StewardModelScanGuardTest.swift`:

```swift
import Foundation

@MainActor
final class DelayedScanner: SoftwareScanning {
    private(set) var callCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func scanAll(includeGreedy: Bool, onPhaseChange: ((ScanPhase) -> Void)?) async -> ScanResult {
        callCount += 1
        onPhaseChange?(.brewInfo)
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return ScanResult(
            scannedAt: Date(timeIntervalSince1970: 0),
            includeGreedy: includeGreedy,
            summary: ScanSummary(applications: 0, brewFormulae: 0, brewCasks: 0, masApps: 0, outdated: 0, actionable: 0, scanMs: 1),
            applications: ApplicationsScan(source: "test", ok: true, error: "", items: []),
            brew: BrewScan(available: false, path: "", prefix: "", version: "", error: "", includeGreedy: includeGreedy, formulae: [], casks: []),
            mas: MasScan(available: false, path: "", error: "", apps: [])
        )
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

@main
struct StewardModelScanGuardTest {
    static func main() async {
        await MainActor.run {
            UserDefaults.standard.removeObject(forKey: "maxConcurrentUpgrades")
        }

        let scanner = DelayedScanner()
        let model = await MainActor.run {
            StewardModel(scanner: scanner)
        }

        let first = Task { await model.scanSoftware() }

        while await MainActor.run(body: { scanner.callCount }) == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }

        await model.scanSoftware()

        let callsWhileRunning = await MainActor.run { scanner.callCount }
        precondition(callsWhileRunning == 1, "Expected duplicate scan call to be ignored, got \(callsWhileRunning)")

        await MainActor.run {
            scanner.finish()
        }
        await first.value

        let finalIsScanning = await MainActor.run { model.isScanning }
        precondition(finalIsScanning == false, "Expected scan flag to reset after completion")
    }
}
```

- [ ] **Step 2: Add the test to runner before implementation**

Add to `scripts/test-native.sh` after `ScannerNormalizeTokenTest`:

```bash
run_test StewardModelScanGuardTest \
  "$SRC/CommandRunner.swift" \
  "$SRC/Models.swift" \
  "$SRC/Scanner.swift" \
  "$SRC/SoftwareScanning.swift" \
  "$SRC/UpgradePolicyStore.swift" \
  "$SRC/UpgradePlanner.swift" \
  "$SRC/DailyUpgradePolicy.swift" \
  "$SRC/DailyInspectionScheduler.swift" \
  "$SRC/UpgradeHistoryStore.swift" \
  "$SRC/BrewCaskCleanupDetector.swift" \
  "$SRC/UpgradeFailureAnalyzer.swift" \
  "$SRC/HomebrewDownloadMonitor.swift" \
  "$SRC/HomebrewCaskDownloadSizeResolver.swift" \
  "$SRC/PackageProgressParser.swift" \
  "$SRC/UpgradeVerifier.swift" \
  "$SRC/StewardModel.swift" \
  "$TESTS/StewardModelScanGuardTest.swift"
```

- [ ] **Step 3: Run the test and verify RED**

Run:

```bash
bash scripts/test-native.sh
```

Expected: FAIL because `SoftwareScanning.swift` does not exist and `StewardModel(scanner:)` is not available.

- [ ] **Step 4: Add scanner seam**

Create `native/MacSoftwareSteward/SoftwareScanning.swift`:

```swift
import Foundation

protocol SoftwareScanning {
    func scanAll(includeGreedy: Bool, onPhaseChange: ((ScanPhase) -> Void)?) async -> ScanResult
}

struct LiveSoftwareScanning: SoftwareScanning {
    func scanAll(includeGreedy: Bool, onPhaseChange: ((ScanPhase) -> Void)?) async -> ScanResult {
        await SoftwareScanner.scanAll(includeGreedy: includeGreedy, onPhaseChange: onPhaseChange)
    }
}
```

- [ ] **Step 5: Inject scanner into StewardModel**

In `StewardModel`, add a private property near stores:

```swift
private let scanner: SoftwareScanning
```

Replace the current initializer:

```swift
init() {
    refreshDailyInspectionStatus()
}
```

with:

```swift
init(scanner: SoftwareScanning = LiveSoftwareScanning()) {
    self.scanner = scanner
    refreshDailyInspectionStatus()
}
```

- [ ] **Step 6: Guard scan reentry**

Replace `scanSoftware()` with:

```swift
func scanSoftware() async {
    guard !isScanning else { return }
    isScanning = true
    errorMessage = ""
    scanPhase = .systemProfiler
    defer {
        scanPhase = nil
        isScanning = false
    }

    let result = await scanner.scanAll(includeGreedy: includeGreedy) { [weak self] phase in
        Task { @MainActor in
            self?.scanPhase = phase
        }
    }
    scan = result
    prunePackageProgress(keeping: result)
    recomputeDerivedData()
}
```

- [ ] **Step 7: Disable remaining scan UI entry points while scanning**

In `native/MacSoftwareSteward/App.swift`, update command-menu scan button:

```swift
Button("扫描软件") {
    Task { await model.scanSoftware() }
}
.keyboardShortcut("r", modifiers: [.command])
.disabled(model.isScanning)
```

In `native/MacSoftwareSteward/Views/UpdatesView.swift`, update the `.rescan` action disabled state:

```swift
.disabled(model.isScanning || model.isConfirmingUpgradePlan)
```

- [ ] **Step 8: Run tests**

Run:

```bash
npm test
```

Expected: PASS, unless blocked by the local Swift/SDK mismatch.

- [ ] **Step 9: Commit**

```bash
git add native/MacSoftwareSteward/SoftwareScanning.swift native/MacSoftwareSteward/StewardModel.swift native/MacSoftwareSteward/App.swift native/MacSoftwareSteward/Views/UpdatesView.swift tests/StewardModelScanGuardTest.swift scripts/test-native.sh
git commit -m "fix: guard duplicate software scans"
```

## Task 6: Build Script Toolchain Diagnostics

**Files:**
- Modify: `scripts/build-native.sh`

- [ ] **Step 1: Add diagnostic helpers**

Near the top of `scripts/build-native.sh`, after `SDK_PATH=...`, add:

```bash
print_toolchain() {
  echo "==> Toolchain"
  if command -v xcodebuild >/dev/null 2>&1; then
    xcodebuild -version | sed 's/^/    /'
  else
    echo "    xcodebuild not found"
  fi
  xcrun swiftc --version | sed 's/^/    /'
  echo "    SDK: $SDK_PATH"
}

compile_or_explain() {
  local label="$1"
  shift
  echo "==> Compiling $label"
  if ! "$@"; then
    echo ""
    echo "Build failed while compiling $label." >&2
    echo "If the error says the SDK is not supported by the compiler, select a matching Xcode or Command Line Tools path:" >&2
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    echo "Then confirm with:" >&2
    echo "  xcrun swiftc --version" >&2
    echo "  xcrun --show-sdk-path" >&2
    exit 1
  fi
}

print_toolchain
```

- [ ] **Step 2: Wrap the main app compile command**

Replace the first `xcrun swiftc ...` block with:

```bash
compile_or_explain "main app" xcrun swiftc \
  -O \
  -target arm64-apple-macosx14.0 \
  -sdk "$SDK_PATH" \
  -framework SwiftUI \
  -framework AppKit \
  "$ROOT_DIR"/native/MacSoftwareSteward/*.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/Views/*.swift \
  -o "$MACOS_DIR/$APP_NAME"
```

- [ ] **Step 3: Wrap the agent compile command**

Replace the second `xcrun swiftc ...` block with:

```bash
compile_or_explain "daily inspection agent" xcrun swiftc \
  -O \
  -target arm64-apple-macosx14.0 \
  -sdk "$SDK_PATH" \
  "$ROOT_DIR"/native/MacSoftwareSteward/CommandRunner.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/Models.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/UpgradePolicyStore.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/UpgradePlanner.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/DailyUpgradePolicy.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/Scanner.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/SoftwareScanning.swift \
  "$ROOT_DIR"/native/MacSoftwareStewardAgent/*.swift \
  -o "$MACOS_DIR/${APP_NAME}Agent"
```

- [ ] **Step 4: Run build**

Run:

```bash
npm run build
```

Expected: If the local toolchain is compatible, build succeeds. If the current Swift/SDK mismatch remains, output includes the toolchain section and the `xcode-select` hint.

- [ ] **Step 5: Commit**

```bash
git add scripts/build-native.sh
git commit -m "chore: explain swift toolchain build failures"
```

## Task 7: CI Runs Native Tests

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Add test step before build**

In `.github/workflows/release.yml`, insert after "Update version in Info.plist":

```yaml
      - name: Run native tests
        run: |
          chmod +x scripts/test-native.sh
          npm test
```

- [ ] **Step 2: Verify workflow syntax**

Run:

```bash
ruby -e "require 'yaml'; YAML.load_file('.github/workflows/release.yml'); puts 'workflow yaml ok'"
```

Expected: `workflow yaml ok`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: run native tests before release build"
```

## Task 8: README and PROJECT_MAP Refresh

**Files:**
- Modify: `README.md`
- Modify: `PROJECT_MAP.md`

- [ ] **Step 1: Update README commands**

In `README.md`, replace the native build/open snippets so they use existing aliases:

```markdown
构建 `.app`：

```bash
npm run build
# 或
npm run build:native
```

构建并打开：

```bash
npm run open
# 或
npm run open:native
```
```

- [ ] **Step 2: Remove stale Web panel instructions or mark them historical**

Replace the "Web 面板运行" section with:

```markdown
## Web 面板

当前主线是 SwiftUI 原生 macOS 应用，不需要启动本地 Web 服务。旧版 Web 面板不参与当前构建与发布流程。
```

- [ ] **Step 3: Update test and build section**

Replace the final command block with:

```markdown
```bash
npm test
npm run build
npm run package
```
```

Add this note below it:

```markdown
如果构建失败并提示 SDK 与 Swift compiler 不匹配，请先检查 `xcrun swiftc --version` 与 `xcrun --show-sdk-path`，并用 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` 切换到匹配的 Xcode。
```

- [ ] **Step 4: Update PROJECT_MAP version and test caveat**

In `PROJECT_MAP.md`:

- Change version line to `0.13.18` unless code version has changed during release work.
- Replace the stale "无单元测试" caveat with:

```markdown
7. **测试是独立 Swift 入口**: `tests/*.swift` 通过 `scripts/test-native.sh` 逐个编译运行，`npm test` 是统一入口。
```

- Add `AppUpdateSecurity.swift` and `SoftwareScanning.swift` to the main app file table.
- Update build commands to include `npm test`, `npm run build:native`, and `npm run open:native`.

- [ ] **Step 5: Verify docs mention existing scripts only**

Run:

```bash
node - <<'NODE'
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
const readme = fs.readFileSync('README.md', 'utf8');
for (const script of ['build', 'build:native', 'open', 'open:native', 'test', 'package']) {
  if (!pkg.scripts[script]) throw new Error(`missing package script ${script}`);
  if (!readme.includes(`npm run ${script}`) && script !== 'test') throw new Error(`README missing npm run ${script}`);
}
if (!readme.includes('npm test')) throw new Error('README missing npm test');
console.log('docs script references ok');
NODE
```

Expected: `docs script references ok`.

- [ ] **Step 6: Commit**

```bash
git add README.md PROJECT_MAP.md
git commit -m "docs: refresh native workflow map"
```

## Task 9: Full Verification

**Files:**
- No file changes unless a previous task needs a small fix.

- [ ] **Step 1: Check worktree**

Run:

```bash
git status --short
```

Expected: only intentional untracked `code-risk-scanner/` remains, unless the user wants it staged separately.

- [ ] **Step 2: Run tests**

Run:

```bash
npm test
```

Expected: PASS. If blocked by local Swift/SDK mismatch, output must show the mismatch context from the test runner or build diagnostics.

- [ ] **Step 3: Run build**

Run:

```bash
npm run build
```

Expected: PASS on a compatible toolchain. On the current mismatched toolchain, expected output includes `==> Toolchain` and the `xcode-select` hint.

- [ ] **Step 4: Inspect changed files**

Run:

```bash
git diff --stat HEAD
```

Expected: no unstaged implementation changes after task commits, except the untracked risk report directory.

- [ ] **Step 5: Final summary**

Report:

- The commits created.
- Whether `npm test` passed or was blocked by toolchain mismatch.
- Whether `npm run build` passed or was blocked by toolchain mismatch.
- The remaining untracked `code-risk-scanner/` report status.

