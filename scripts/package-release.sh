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
    echo "### 界面精简"
    echo "- 合并「自动化策略」页进「设置」页，所有配置集中一处"
    echo "- 移除「维护总览」和「任务日志」页，侧边栏精简为可升级、本机软件、设置三个标签"
    echo "- 可升级页每行精简：移除逐包策略下拉框、来源文字胶囊和固定/自更新徽章"
    echo "- 设置页精简：隐藏失败恢复、普通 App 联网检查，通知选项从 4 个简化为 2 个"
    echo ""
    echo "### 新功能"
    echo "- 可升级页新增「一键升级」按钮，一键批量升级所有可执行项"
    echo "- 批量升级作为单个任务执行，需要管理员密码的 Cask 只弹一次系统密码框"
    echo ""
    echo "### 问题修复"
    echo "- 修复扫描恢复正常后「Homebrew 扫描错误」等收件箱条目永久残留的问题"
    echo "- 修复浅色系统下「跟随系统 → 深色 → 跟随系统」后窗口出现深浅混搭的问题"
    echo "- 移除普通 App 联网检查中的「积极检查公开页面」选项（该选项无实际效果）"
    echo ""
    echo "安装包资产：\`MacSoftwareSteward.zip\`"
  } > "$NOTES_FILE"
fi

SHA256="$(awk '{print $1}' "$ZIP_PATH.sha256")"
SIZE="$(stat -f%z "$ZIP_PATH")"
PUBLISHED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
VERSION="$VERSION" \
SHA256="$SHA256" \
SIZE="$SIZE" \
PUBLISHED_AT="$PUBLISHED_AT" \
NOTES_FILE="$NOTES_FILE" \
OUT_FILE="$RELEASE_DIR/latest.json" \
node <<'NODE'
const fs = require('fs');

const version = process.env.VERSION;
const manifest = {
  version,
  tag: `v${version}`,
  asset: 'MacSoftwareSteward.zip',
  sha256: process.env.SHA256,
  size: Number(process.env.SIZE || 0),
  published_at: process.env.PUBLISHED_AT,
  notes: fs.readFileSync(process.env.NOTES_FILE, 'utf8').trim(),
  download_url: `https://github.com/sunnyhot/mac-software-steward/releases/download/v${version}/MacSoftwareSteward.zip`,
  html_url: `https://github.com/sunnyhot/mac-software-steward/releases/tag/v${version}`
};

fs.writeFileSync(process.env.OUT_FILE, `${JSON.stringify(manifest, null, 2)}\n`);
NODE

echo "$ZIP_PATH"
