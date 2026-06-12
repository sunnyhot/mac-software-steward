#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/tests"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
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

run_test AppUpdateSecurityTest \
  "$SRC/AppUpdateSecurity.swift" \
  "$TESTS/AppUpdateSecurityTest.swift"

run_test AppWindowDoubleClickZoomPolicyTest \
  "$SRC/AppWindowDoubleClickZoomPolicy.swift" \
  "$TESTS/AppWindowDoubleClickZoomPolicyTest.swift"

run_test AppTabVisibilityTest \
  "$SRC/Models.swift" \
  "$TESTS/AppTabVisibilityTest.swift"

run_test AutomationProfileStoreTest \
  "$SRC/AutomationProfileStore.swift" \
  "$TESTS/AutomationProfileStoreTest.swift"

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

run_test InboxStoreTest \
  "$SRC/InboxStore.swift" \
  "$TESTS/InboxStoreTest.swift"

run_test PackageProgressParserTest \
  "$SRC/PackageProgressParser.swift" \
  "$TESTS/PackageProgressParserTest.swift"

run_test ScannerBrewListFallbackTest \
  "$SRC/CommandRunner.swift" \
  "$SRC/Models.swift" \
  "$SRC/Scanner.swift" \
  "$TESTS/ScannerBrewListFallbackTest.swift"

run_test ScannerNormalizeTokenTest \
  "$SRC/CommandRunner.swift" \
  "$SRC/Models.swift" \
  "$SRC/Scanner.swift" \
  "$TESTS/ScannerNormalizeTokenTest.swift"

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
  "$SRC/SourceDiagnostics.swift" \
  "$SRC/UpgradeVerifier.swift" \
  "$SRC/StewardModel.swift" \
  "$TESTS/StewardModelScanGuardTest.swift"

run_test SelfUpdateInstallScriptTest \
  "$SRC/SelfUpdateInstallScript.swift" \
  "$TESTS/SelfUpdateInstallScriptTest.swift"

run_test UpgradeFailureAnalyzerTest \
  "$SRC/Models.swift" \
  "$SRC/BrewCaskCleanupDetector.swift" \
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
