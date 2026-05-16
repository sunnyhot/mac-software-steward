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
  echo "- 新增 CleanEngine（清理引擎）：DevTools缓存、项目构建产物、HintEngine智能提示"
  echo "- 新增 UninstallEngine（卸载引擎）：应用发现、批量卸载、Homebrew集成、残留扫描、安全移除"
  echo "- 新增 OptimizeEngine（优化引擎）：安装器管理、进程管理、缓存清理、TouchID安全认证"
  echo "- 新增 StewardRuntime 统一运行时，三个引擎通过 Adapter 桥接到 SwiftUI 界面"
  echo ""
  echo "### 改进"
  echo "- 模块化架构重构：MoleApp 引擎层与 UI 层完全解耦"
  echo "- 构建脚本支持自动发现 MoleApp/Sources 下所有 Swift 文件"
  echo ""
  echo "安装包资产：\`MacSoftwareSteward.zip\`"
} > "$NOTES_FILE"

echo "$ZIP_PATH"
