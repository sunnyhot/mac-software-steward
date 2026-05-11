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
  echo "- 设置页新增「在 Dock 中显示」开关，可隐藏 Dock 图标，仅通过菜单栏操作。"
  echo "- 修复 auto_updates 类 Cask（如 Docker、Raycast、Arc）反复出现在可升级列表的问题，现在标记为「自更新」状态。"
  echo ""
  echo "安装包资产：\`MacSoftwareSteward.zip\`"
} > "$NOTES_FILE"

echo "$ZIP_PATH"
