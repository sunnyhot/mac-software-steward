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
  echo "### 新功能"
  echo "- 软件名称支持点击复制"
  echo "- 添加升级进度条，提升进行中状态的可视性"
  echo "- 支持并行升级：单条升级与一键升级不冲突"
  echo ""
  echo "### 改进"
  echo "- 改进升级失败的错误提示和恢复建议（重试、清理空间、检查网络等）"
  echo "- sidebar hover effect below macOS 26 - add SidebarRow with onHover tracking"
  echo ""
  echo "### 修复"
  echo "- 修复菜单点击「打开Mac软件管家」重复打开多窗口，改为单例模式"
  echo ""
  echo "安装包资产：\`MacSoftwareSteward.zip\`"
} > "$NOTES_FILE"

echo "$ZIP_PATH"
