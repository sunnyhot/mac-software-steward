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
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/AppAppearanceResolver.swift" \
  "$TESTS/AppAppearanceResolverTest.swift"

run_test AppSurfacePaletteTest \
  "$SRC/AppSurfacePalette.swift" \
  "$TESTS/AppSurfacePaletteTest.swift"

run_test AppSingleInstancePolicyTest \
  "$SRC/AppSingleInstancePolicy.swift" \
  "$TESTS/AppSingleInstancePolicyTest.swift"

run_test AppUpdateDialogLayoutTest \
  "$SRC/AppUpdateDialogLayout.swift" \
  "$TESTS/AppUpdateDialogLayoutTest.swift"

run_test AppUpdateSecurityTest \
  "$SRC/AppUpdateSecurity.swift" \
  "$TESTS/AppUpdateSecurityTest.swift"

run_test AppUpdateDownloadPresenterTest \
  "$SRC/CommandRunner.swift" \
  "$SRC/DownloadAcceleration.swift" \
  "$SRC/AcceleratedDownloader.swift" \
  "$SRC/AppUpdateDownloadPresenter.swift" \
  "$TESTS/AppUpdateDownloadPresenterTest.swift"

run_test AppUpdateModelAccelerationTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/CommandRunner.swift" \
  "$SRC/SelfUpdateInstallScript.swift" \
  "$SRC/AppUpdateSecurity.swift" \
  "$SRC/DownloadAcceleration.swift" \
  "$SRC/AcceleratedDownloader.swift" \
  "$SRC/AppUpdateDownloadPresenter.swift" \
  "$SRC/AppUpdater.swift" \
  "$TESTS/AppUpdateModelAccelerationTest.swift"

run_test AppWindowDoubleClickZoomPolicyTest \
  "$SRC/AppWindowDoubleClickZoomPolicy.swift" \
  "$TESTS/AppWindowDoubleClickZoomPolicyTest.swift"

run_test AppWindowChromePolicyTest \
  "$SRC/AppWindowChromePolicy.swift" \
  "$TESTS/AppWindowChromePolicyTest.swift"

run_test AppManualUpdatePresenterTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/AppManualUpdatePresenter.swift" \
  "$TESTS/AppManualUpdatePresenterTest.swift"

run_test ManualAppReplacementInstallerTest \
  "$SRC/ManualAppReplacementInstaller.swift" \
  "$TESTS/ManualAppReplacementInstallerTest.swift"

run_test AppTabVisibilityTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/AppTabNavigationPresenter.swift" \
  "$TESTS/AppTabVisibilityTest.swift"

run_test TabScrollStructureTest \
  "$TESTS/TabScrollStructureTest.swift"

run_test MaintenanceStatusPresenterTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/MaintenanceStatusPresenter.swift" \
  "$TESTS/MaintenanceStatusPresenterTest.swift"

run_test MaintenanceWorkflowStateTest \
  "$SRC/MaintenanceWorkflowState.swift" \
  "$TESTS/MaintenanceWorkflowStateTest.swift"

run_test MaintenanceRunLeaseTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/InboxStore.swift" \
  "$SRC/AutomationProfileStore.swift" \
  "$SRC/UpgradePolicyStore.swift" \
  "$SRC/RiskAssessor.swift" \
  "$SRC/MaintenanceWorkflowState.swift" \
  "$SRC/MaintenancePlanner.swift" \
  "$SRC/MaintenanceProtocols.swift" \
  "$SRC/MaintenanceRunLease.swift" \
  "$TESTS/MaintenanceRunLeaseTest.swift"

run_test SettingsPagePresenterTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/SettingsPagePresenter.swift" \
  "$TESTS/SettingsPagePresenterTest.swift"

run_test ApplicationVisibilityPresenterTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/ApplicationVisibilityPresenter.swift" \
  "$TESTS/ApplicationVisibilityPresenterTest.swift"

run_test LocalSoftwarePresenterTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/ApplicationVisibilityPresenter.swift" \
  "$SRC/LocalSoftwarePresenter.swift" \
  "$TESTS/LocalSoftwarePresenterTest.swift"

run_test ScanPerformanceModelTest \
  "$SRC/ScanPerformance.swift" \
  "$TESTS/ScanPerformanceModelTest.swift"

run_test ScanPerformanceStoreTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/ScanPerformanceStore.swift" \
  "$TESTS/ScanPerformanceStoreTest.swift"

run_test ScanPerformancePresenterTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/ScanPerformancePresenter.swift" \
  "$TESTS/ScanPerformancePresenterTest.swift"

run_test AutomationProfileStoreTest \
  "$SRC/AutomationProfileStore.swift" \
  "$TESTS/AutomationProfileStoreTest.swift"

run_test AutomationMaintenanceAccessTest \
  "$SRC/AutomationProfileStore.swift" \
  "$SRC/AutomationMaintenanceAccess.swift" \
  "$TESTS/AutomationMaintenanceAccessTest.swift"

run_test AutomationDataBundleTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/AutomationProfileStore.swift" \
  "$SRC/UpgradePolicyStore.swift" \
  "$SRC/UpgradeHistoryStore.swift" \
  "$SRC/InspectionReportStore.swift" \
  "$SRC/AutomationDataBundle.swift" \
  "$TESTS/AutomationDataBundleTest.swift"

run_test RulesConsolePresenterTest \
  "$SRC/AutomationProfileStore.swift" \
  "$SRC/RulesConsolePresenter.swift" \
  "$TESTS/RulesConsolePresenterTest.swift"

run_test HistoryPresenterTest \
  "$SRC/InspectionReportStore.swift" \
  "$SRC/UpgradeHistoryStore.swift" \
  "$SRC/HistoryPresenter.swift" \
  "$TESTS/HistoryPresenterTest.swift"

run_test AutomationNotificationDeciderTest \
  "$SRC/AutomationProfileStore.swift" \
  "$SRC/InboxStore.swift" \
  "$SRC/AutomationNotificationDecider.swift" \
  "$TESTS/AutomationNotificationDeciderTest.swift"

run_test AutomationIssueInboxFactoryTest \
  "$SRC/AutomationProfileStore.swift" \
  "$SRC/InboxStore.swift" \
  "$SRC/AutomationIssueInboxFactory.swift" \
  "$TESTS/AutomationIssueInboxFactoryTest.swift"

run_test BrewCaskCleanupDetectorTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/BrewCaskCleanupDetector.swift" \
  "$TESTS/BrewCaskCleanupDetectorTest.swift"

run_test CommandRunnerControlTest \
  "$SRC/CommandRunner.swift" \
  "$TESTS/CommandRunnerControlTest.swift"

run_test DownloadAccelerationPolicyTest \
  "$SRC/CommandRunner.swift" \
  "$SRC/DownloadAcceleration.swift" \
  "$TESTS/DownloadAccelerationPolicyTest.swift"

run_test DownloadAccelerationCommandPlannerTest \
  "$SRC/CommandRunner.swift" \
  "$SRC/DownloadAcceleration.swift" \
  "$TESTS/DownloadAccelerationCommandPlannerTest.swift"

run_test AcceleratedDownloaderTest \
  "$SRC/CommandRunner.swift" \
  "$SRC/DownloadAcceleration.swift" \
  "$SRC/AcceleratedDownloader.swift" \
  "$TESTS/AcceleratedDownloaderTest.swift"

run_test DailyPolicyFilteringTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/UpgradePolicyStore.swift" \
  "$SRC/RiskAssessor.swift" \
  "$SRC/UpgradePlanner.swift" \
  "$SRC/DailyUpgradePolicy.swift" \
  "$TESTS/DailyPolicyFilteringTest.swift"

run_test MaintenancePlannerTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/UpgradePolicyStore.swift" \
  "$SRC/AutomationProfileStore.swift" \
  "$SRC/RiskAssessor.swift" \
  "$SRC/MaintenancePlanner.swift" \
  "$TESTS/MaintenancePlannerTest.swift"

run_test HomebrewCaskDownloadSizeResolverTest \
  "$SRC/CommandRunner.swift" \
  "$SRC/HomebrewCaskDownloadSizeResolver.swift" \
  "$TESTS/HomebrewCaskDownloadSizeResolverTest.swift"

run_test HomebrewDownloadMonitorTest \
  "$SRC/HomebrewDownloadMonitor.swift" \
  "$TESTS/HomebrewDownloadMonitorTest.swift"

run_test HomebrewCaskUpdateAdvisorTest \
  "$SRC/CommandRunner.swift" \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/AutomationProfileStore.swift" \
  "$SRC/SparkleAppcastChecker.swift" \
  "$SRC/HomebrewCaskUpdateAdvisor.swift" \
  "$SRC/RegularAppUpdateDiscovery.swift" \
  "$SRC/RegularAppUpdateDiscoveryCache.swift" \
  "$SRC/Scanner.swift" \
  "$TESTS/HomebrewCaskUpdateAdvisorTest.swift"

run_test InboxStoreTest \
  "$SRC/InboxStore.swift" \
  "$TESTS/InboxStoreTest.swift"

run_test InboxHistoryRecorderTest \
  "$SRC/InboxStore.swift" \
  "$SRC/UpgradeHistoryStore.swift" \
  "$SRC/InboxHistoryRecorder.swift" \
  "$TESTS/InboxHistoryRecorderTest.swift"

run_test InboxFilterPresenterTest \
  "$SRC/InboxStore.swift" \
  "$SRC/InboxFilterPresenter.swift" \
  "$TESTS/InboxFilterPresenterTest.swift"

run_test AppUpdateInboxFactoryTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/InboxStore.swift" \
  "$SRC/AppUpdateInboxFactory.swift" \
  "$TESTS/AppUpdateInboxFactoryTest.swift"

run_test AppDiagnosticsPresenterTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/InboxStore.swift" \
  "$SRC/AppDiagnosticsPresenter.swift" \
  "$TESTS/AppDiagnosticsPresenterTest.swift"

run_test SourceIssueInboxFactoryTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/InboxStore.swift" \
  "$SRC/SourceIssueInboxFactory.swift" \
  "$TESTS/SourceIssueInboxFactoryTest.swift"

run_test DailyInspectionInboxPublisherTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/UpgradePolicyStore.swift" \
  "$SRC/RiskAssessor.swift" \
  "$SRC/UpgradePlanner.swift" \
  "$SRC/InboxStore.swift" \
  "$SRC/RiskInboxFactory.swift" \
  "$SRC/AppUpdateInboxFactory.swift" \
  "$SRC/SourceIssueInboxFactory.swift" \
  "$SRC/DailyInspectionInboxPublisher.swift" \
  "$TESTS/DailyInspectionInboxPublisherTest.swift"

run_test InspectionReportStoreTest \
  "$SRC/InspectionReportStore.swift" \
  "$TESTS/InspectionReportStoreTest.swift"

run_test InspectionReportBuilderTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/InspectionReportStore.swift" \
  "$SRC/InspectionReportBuilder.swift" \
  "$SRC/UpgradePolicyStore.swift" \
  "$SRC/RiskAssessor.swift" \
  "$SRC/UpgradePlanner.swift" \
  "$TESTS/InspectionReportBuilderTest.swift"

run_test RegularAppUpdateDiscoveryTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/RegularAppUpdateDiscovery.swift" \
  "$TESTS/RegularAppUpdateDiscoveryTest.swift"

run_test RegularAppUpdateDiscoveryCacheTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/RegularAppUpdateDiscovery.swift" \
  "$SRC/RegularAppUpdateDiscoveryCache.swift" \
  "$TESTS/RegularAppUpdateDiscoveryCacheTest.swift"

run_test RegularAppUpdateActionResolverTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/RegularAppUpdateActionResolver.swift" \
  "$TESTS/RegularAppUpdateActionResolverTest.swift"

run_test RecoveryActionPlannerTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/RecoveryActionPlanner.swift" \
  "$TESTS/RecoveryActionPlannerTest.swift"

run_test RecoveryInboxFactoryTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/InboxStore.swift" \
  "$SRC/RecoveryActionPlanner.swift" \
  "$SRC/RecoveryInboxFactory.swift" \
  "$TESTS/RecoveryInboxFactoryTest.swift"

run_test AutoRepairDeciderTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/AutomationProfileStore.swift" \
  "$SRC/RecoveryActionPlanner.swift" \
  "$SRC/AutoRepairDecider.swift" \
  "$TESTS/AutoRepairDeciderTest.swift"

run_test SparkleAppcastCheckerTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/SparkleAppcastChecker.swift" \
  "$TESTS/SparkleAppcastCheckerTest.swift"

run_test RiskAssessorTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/RiskAssessor.swift" \
  "$TESTS/RiskAssessorTest.swift"

run_test RiskInboxFactoryTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/InboxStore.swift" \
  "$SRC/RiskAssessor.swift" \
  "$SRC/UpgradePolicyStore.swift" \
  "$SRC/UpgradePlanner.swift" \
  "$SRC/RiskInboxFactory.swift" \
  "$TESTS/RiskInboxFactoryTest.swift"

run_test PackageProgressParserTest \
  "$SRC/PackageProgressParser.swift" \
  "$TESTS/PackageProgressParserTest.swift"

run_test ScannerBrewListFallbackTest \
  "$SRC/CommandRunner.swift" \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/AutomationProfileStore.swift" \
  "$SRC/RegularAppUpdateDiscovery.swift" \
  "$SRC/RegularAppUpdateDiscoveryCache.swift" \
  "$SRC/SparkleAppcastChecker.swift" \
  "$SRC/HomebrewCaskUpdateAdvisor.swift" \
  "$SRC/Scanner.swift" \
  "$TESTS/ScannerBrewListFallbackTest.swift"

run_test ScannerAppUpdateCapabilityTest \
  "$SRC/CommandRunner.swift" \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/AutomationProfileStore.swift" \
  "$SRC/RegularAppUpdateDiscovery.swift" \
  "$SRC/RegularAppUpdateDiscoveryCache.swift" \
  "$SRC/SparkleAppcastChecker.swift" \
  "$SRC/HomebrewCaskUpdateAdvisor.swift" \
  "$SRC/Scanner.swift" \
  "$TESTS/ScannerAppUpdateCapabilityTest.swift"

run_test ScannerSparkleAppcastPolicyTest \
  "$SRC/CommandRunner.swift" \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/AutomationProfileStore.swift" \
  "$SRC/RegularAppUpdateDiscovery.swift" \
  "$SRC/RegularAppUpdateDiscoveryCache.swift" \
  "$SRC/SparkleAppcastChecker.swift" \
  "$SRC/HomebrewCaskUpdateAdvisor.swift" \
  "$SRC/Scanner.swift" \
  "$TESTS/ScannerSparkleAppcastPolicyTest.swift"

run_test ScannerNormalizeTokenTest \
  "$SRC/CommandRunner.swift" \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/AutomationProfileStore.swift" \
  "$SRC/RegularAppUpdateDiscovery.swift" \
  "$SRC/RegularAppUpdateDiscoveryCache.swift" \
  "$SRC/SparkleAppcastChecker.swift" \
  "$SRC/HomebrewCaskUpdateAdvisor.swift" \
  "$SRC/Scanner.swift" \
  "$TESTS/ScannerNormalizeTokenTest.swift"

run_test StewardModelScanGuardTest \
  "$SRC/CommandRunner.swift" \
  "$SRC/ScanPerformance.swift" \
  "$SRC/ScanPerformanceStore.swift" \
  "$SRC/Models.swift" \
  "$SRC/AutomationProfileStore.swift" \
  "$SRC/RegularAppUpdateDiscovery.swift" \
  "$SRC/RegularAppUpdateDiscoveryCache.swift" \
  "$SRC/RegularAppUpdateActionResolver.swift" \
  "$SRC/AutomationNotificationDecider.swift" \
  "$SRC/AutomationNotificationDispatcher.swift" \
  "$SRC/RecoveryActionPlanner.swift" \
  "$SRC/RecoveryInboxFactory.swift" \
  "$SRC/AutoRepairDecider.swift" \
  "$SRC/SparkleAppcastChecker.swift" \
  "$SRC/HomebrewCaskUpdateAdvisor.swift" \
  "$SRC/Scanner.swift" \
  "$SRC/SoftwareScanning.swift" \
  "$SRC/InboxStore.swift" \
  "$SRC/AppUpdateInboxFactory.swift" \
  "$SRC/SourceIssueInboxFactory.swift" \
  "$SRC/UpgradePolicyStore.swift" \
  "$SRC/RiskAssessor.swift" \
  "$SRC/UpgradePlanner.swift" \
  "$SRC/RiskInboxFactory.swift" \
  "$SRC/DailyUpgradePolicy.swift" \
  "$SRC/InspectionReportStore.swift" \
  "$SRC/DailyInspectionScheduler.swift" \
  "$SRC/UpgradeHistoryStore.swift" \
  "$SRC/BrewCaskCleanupDetector.swift" \
  "$SRC/UpgradeFailureAnalyzer.swift" \
  "$SRC/HomebrewDownloadMonitor.swift" \
  "$SRC/HomebrewCaskDownloadSizeResolver.swift" \
  "$SRC/DownloadAcceleration.swift" \
  "$SRC/AcceleratedDownloader.swift" \
  "$SRC/PackageProgressParser.swift" \
  "$SRC/ManualAppReplacementInstaller.swift" \
  "$SRC/SourceDiagnostics.swift" \
  "$SRC/UpgradeVerifier.swift" \
  "$SRC/StewardModel.swift" \
  "$TESTS/StewardModelScanGuardTest.swift"

run_test SelfUpdateInstallScriptTest \
  "$SRC/SelfUpdateInstallScript.swift" \
  "$TESTS/SelfUpdateInstallScriptTest.swift"

run_test UpgradeFailureAnalyzerTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/BrewCaskCleanupDetector.swift" \
  "$SRC/UpgradeFailureAnalyzer.swift" \
  "$TESTS/UpgradeFailureAnalyzerTest.swift"

run_test UpgradeHistoryStoreTest \
  "$SRC/UpgradeHistoryStore.swift" \
  "$TESTS/UpgradeHistoryStoreTest.swift"

run_test UpgradePlannerTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/UpgradePolicyStore.swift" \
  "$SRC/RiskAssessor.swift" \
  "$SRC/UpgradePlanner.swift" \
  "$TESTS/UpgradePlannerTest.swift"

run_test UpgradePolicyStoreTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/UpgradePolicyStore.swift" \
  "$TESTS/UpgradePolicyStoreTest.swift"

run_test UpgradeProgressPresenterTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/UpgradeProgressPresenter.swift" \
  "$TESTS/UpgradeProgressPresenterTest.swift"

run_test UpgradeVerifierTest \
  "$SRC/ScanPerformance.swift" \
  "$SRC/Models.swift" \
  "$SRC/UpgradeVerifier.swift" \
  "$TESTS/UpgradeVerifierTest.swift"

echo "All native tests passed."
