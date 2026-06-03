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
    echo "### 一键升级安全增强"
    echo "- 新增升级计划确认页，展示命令、来源、版本变化、风险标签和跳过原因"
    echo "- 新增单包升级策略：自动升级、确认后升级、仅提醒、跳过"
    echo "- 每日巡检只执行自动升级项，避免静默升级高风险软件"
    echo "- 支持升级任务取消、长时间命令超时、失败恢复提示和日志复制"
    echo "- 升级后自动重扫验证结果，并持久化升级历史"
    echo "- 更新页支持来源、风险、失败和跳过筛选"
    echo ""
    echo "### 扫描稳定性"
    echo "- Homebrew cask 版本列表失败时自动回退到名称列表，减少扫描误报"
    echo ""
    echo "安装包资产：\`MacSoftwareSteward.zip\`"
  } > "$NOTES_FILE"
fi

SHA256="$(awk '{print $1}' "$ZIP_PATH.sha256")"
cat > "$RELEASE_DIR/latest.json" <<MANIFEST_EOF
{
  "version": "$VERSION",
  "tag": "v$VERSION",
  "asset": "MacSoftwareSteward.zip",
  "sha256": "$SHA256",
  "notes": "Mac 软件管家 v$VERSION",
  "download_url": "https://github.com/sunnyhot/mac-software-steward/releases/download/v$VERSION/MacSoftwareSteward.zip",
  "html_url": "https://github.com/sunnyhot/mac-software-steward/releases/tag/v$VERSION"
}
MANIFEST_EOF

echo "$ZIP_PATH"
