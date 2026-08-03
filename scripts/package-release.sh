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
    echo "### 性能优化"
    echo "- 节流升级进度更新频率到约 10Hz，下载/升级时不再逐行输出触发全量 UI 重算，滚动更流畅"
    echo "- 可升级列表的筛选+排序在每次界面刷新时只计算一次"
    echo "- 移除下载进度详情中的流动动画和列表行的 hover 缩放动画，减少并发下载时的渲染负担"
    echo "- 收件箱条目扫描后批量写入，不再逐条全量编码写盘"
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
