#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MacSoftwareSteward"
APP_DIR="$ROOT_DIR/build/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SDK_PATH="$(xcrun --show-sdk-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/native/Info.plist" "$CONTENTS_DIR/Info.plist"

xcrun swiftc \
  -O \
  -target arm64-apple-macosx14.0 \
  -sdk "$SDK_PATH" \
  -framework SwiftUI \
  -framework AppKit \
  "$ROOT_DIR"/native/MacSoftwareSteward/*.swift \
  -o "$MACOS_DIR/$APP_NAME"

xcrun swiftc \
  -O \
  -target arm64-apple-macosx14.0 \
  -sdk "$SDK_PATH" \
  "$ROOT_DIR"/native/MacSoftwareSteward/CommandRunner.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/Models.swift \
  "$ROOT_DIR"/native/MacSoftwareSteward/Scanner.swift \
  "$ROOT_DIR"/native/MacSoftwareStewardAgent/*.swift \
  -o "$MACOS_DIR/${APP_NAME}Agent"

chmod +x "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/${APP_NAME}Agent"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$APP_DIR" >/dev/null
fi

echo "$APP_DIR"
