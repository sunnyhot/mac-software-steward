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
if [ -f "$ROOT_DIR/release/RELEASE_NOTES-v$VERSION.md" ]; then
  cp "$ROOT_DIR/release/RELEASE_NOTES-v$VERSION.md" "$NOTES_FILE"
else
  {
    echo "## Mac 软件管家 v$VERSION"
    echo ""
    echo "### UI 优化"
    echo "- 整体布局专业化重构：统一 .regularMaterial 背景、.rounded 字体、12pt/10pt 圆角规范"
    echo "- 组件化提取：HeaderButton、MetricCard、SettingsDivider、JobNoticeIcon 等"
    echo "- macOS 15+ 特效适配：symbolEffect 添加 #available 守卫，兼容 macOS 14"
    echo "- 动效打磨：hover 缩放、spring 动画参数优化"
    echo "- 全页面覆盖：UpdatesView/ApplicationsView/SourcesView/JobsView/SettingsView"
    echo ""
    echo "安装包资产：\`MacSoftwareSteward.zip\`"
  } > "$NOTES_FILE"
fi

echo "$ZIP_PATH"
