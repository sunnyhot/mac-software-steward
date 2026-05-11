#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(node -p "require('$ROOT_DIR/package.json').version")"
APP_DIR="$ROOT_DIR/build/MacSoftwareSteward.app"
RELEASE_DIR="$ROOT_DIR/release"
ZIP_PATH="$RELEASE_DIR/MacSoftwareSteward.zip"
VERSIONED_ZIP_PATH="$RELEASE_DIR/MacSoftwareSteward-v$VERSION.zip"

mkdir -p "$RELEASE_DIR"
bash "$ROOT_DIR/scripts/build-native.sh" >/dev/null

rm -f "$ZIP_PATH" "$VERSIONED_ZIP_PATH" "$ZIP_PATH.sha256" "$VERSIONED_ZIP_PATH.sha256"
/usr/bin/ditto -c -k --norsrc --noextattr --keepParent "$APP_DIR" "$ZIP_PATH"
cp "$ZIP_PATH" "$VERSIONED_ZIP_PATH"

(
  cd "$RELEASE_DIR"
  shasum -a 256 "MacSoftwareSteward.zip" > "MacSoftwareSteward.zip.sha256"
  shasum -a 256 "MacSoftwareSteward-v$VERSION.zip" > "MacSoftwareSteward-v$VERSION.zip.sha256"
)

NOTES_FILE="$RELEASE_DIR/RELEASE_NOTES.md"
{
  echo "## Mac 软件管家 v$VERSION"
  echo ""
  echo "- 移除 Web 前端，成为纯原生 macOS SwiftUI 应用，不再依赖 Node.js。"
  echo "- 新增应用自动更新：可设置定期检查并自动下载安装，无需手动操作。"
  echo "- 设置页新增\"自动下载并安装更新\"开关。"
  echo ""
  echo "安装包资产：\`MacSoftwareSteward.zip\`"
} > "$NOTES_FILE"

echo "$ZIP_PATH"
