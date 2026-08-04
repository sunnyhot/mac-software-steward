#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MacSoftwareSteward"
APP_DIR="$ROOT_DIR/build/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

first_tool_line() {
  local output
  output="$("$@" 2>&1 || true)"
  printf '%s\n' "$output" | sed -n '1p'
}

print_toolchain() {
  echo "==> Toolchain"
  echo "    Developer dir: $(xcode-select -p 2>/dev/null || echo unknown)"
  echo "    macOS SDK: $SDK_PATH"
  echo "    SDK version: $(xcrun --sdk macosx --show-sdk-version 2>/dev/null || echo unknown)"
  echo "    Swift: $(first_tool_line xcrun swift --version)"
  echo "    Swift compiler: $(first_tool_line xcrun swiftc --version)"
}

explain_toolchain_failure() {
  local output="$1"
  if printf '%s' "$output" | grep -q "this SDK is not supported by the compiler"; then
    echo ""
    echo "error: Swift compiler and macOS SDK versions are incompatible."
    echo "hint: Select matching Xcode/Command Line Tools with xcode-select."
    echo "hint: Current SDK: $SDK_PATH"
    echo "hint: Current swiftc: $(first_tool_line xcrun swiftc --version)"
  fi
}

run_or_explain() {
  local label="$1"
  shift

  echo "==> $label"
  local output
  if ! output="$("$@" 2>&1)"; then
    printf '%s\n' "$output" >&2
    explain_toolchain_failure "$output" >&2
    return 1
  fi

  if [ -n "$output" ]; then
    printf '%s\n' "$output"
  fi
}

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
print_toolchain
run_or_explain "Generating app icon" xcrun swift "$ROOT_DIR/scripts/generate-app-icon.swift"
cp "$ROOT_DIR/native/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/native/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

run_or_explain "Building $APP_NAME" xcrun swiftc \
  -O \
  -target arm64-apple-macosx14.0 \
  -sdk "$SDK_PATH" \
  -framework UserNotifications \
  -framework SwiftUI \
  -framework AppKit \
  "$ROOT_DIR"/native/MacSoftwareSteward/*.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/Views/*.swift \
  -o "$MACOS_DIR/$APP_NAME"

run_or_explain "Building ${APP_NAME}Agent" xcrun swiftc \
  -O \
  -target arm64-apple-macosx14.0 \
  -sdk "$SDK_PATH" \
  -framework UserNotifications \
  "$ROOT_DIR"/native/MacSoftwareSteward/CommandRunner.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/ScanPerformance.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/Models.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/AutomationProfileStore.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/AutomationNotificationDecider.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/AutomationNotificationDispatcher.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/UpgradePolicyStore.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/RiskAssessor.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/UpgradePlanner.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/DailyUpgradePolicy.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/MaintenancePlanner.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/InboxStore.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/RiskInboxFactory.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/AppUpdateInboxFactory.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/SourceIssueInboxFactory.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/DailyInspectionInboxPublisher.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/InspectionReportStore.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/InspectionReportBuilder.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/RegularAppUpdateDiscovery.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/RegularAppUpdateDiscoveryCache.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/SparkleAppcastChecker.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/HomebrewCaskUpdateAdvisor.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/BrewCaskCleanupDetector.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/Scanner.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/SoftwareScanning.swift \
  "$ROOT_DIR"/native/MacSoftwareStewardAgent/*.swift \
  -o "$MACOS_DIR/${APP_NAME}Agent"

chmod +x "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/${APP_NAME}Agent"

# Ad-hoc sign (sign frameworks first, then the whole bundle)
echo "==> Signing app bundle..."
if [ -d "${APP_DIR}/Contents/Frameworks/Sparkle.framework" ]; then
    codesign --force --sign - "${APP_DIR}/Contents/Frameworks/Sparkle.framework"
    echo "    Signed Sparkle.framework"
fi
codesign --deep --force --sign - "${APP_DIR}"
echo "    Ad-hoc signed ${APP_NAME}.app"

# Verify signature
echo "==> Verifying signature..."
codesign --verify --deep --strict "${APP_DIR}"
echo "    Signature OK"

# Clear quarantine attributes
xattr -cr "${APP_DIR}"
echo "    Cleared quarantine attributes"

echo "$APP_DIR"
