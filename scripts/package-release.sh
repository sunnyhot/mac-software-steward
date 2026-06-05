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
    echo "### 应用自更新体验"
    echo "- 修复 Homebrew 下载缓存被锁时误报为文件不完整的问题，改为提示等待原任务结束后重试"
    echo "- 启动时自动避免 Mac 软件管家多实例并存，降低重复触发 brew upgrade 导致锁冲突的概率"
    echo "- 更新弹框改为更紧凑的确认面板，降低遮挡感；更新说明保留滚动查看"
    echo "- Homebrew Cask 下载时通过 cask URL 探测文件总大小，显示百分比、已下载/总大小、速度和剩余时间"
    echo "- 修复 Homebrew Cask 续传下载时被 Upgrading 日志提前显示成安装中的问题，下载缓存仍存在时会继续显示下载大小和速度"
    echo "- Homebrew Cask 下载日志没有持续进度时，自动从 Homebrew 缓存 .incomplete 文件推断已下载大小和速度"
    echo "- 修复从深色切换到跟随系统后，窗口侧栏与设置卡片出现深浅混搭的问题"
    echo "- 升级列表显示当前阶段：准备下载、下载中、安装中、替换应用、清理中等"
    echo "- Homebrew/curl 下载时展示百分比、已下载/总大小和下载速度"
    echo "- Homebrew Caskroom 旧版本 App 残留导致覆盖冲突时，自动执行 brew uninstall --cask --force 清理"
    echo "- Homebrew Cask 下载失败但本机 App 已不存在时，自动执行 brew uninstall --cask --force 清理残留"
    echo "- 遇到 Homebrew Cask 记录仍在但 App 已被删除时，自动执行 brew uninstall --cask --force 清理残留"
    echo "- 修复一键升级并行数量只作用于 job、包升级仍串行执行的问题"
    echo "- 一键升级现在会在 brew update 后按设置的并行数量同时执行多个包升级"
    echo "- 修复应用更新下载进度可能一直停在 0% 的问题"
    echo "- 修复自更新下载完成后临时文件可能无法保存导致安装失败的问题"
    echo "- 升级弹框展示包名、大小、发布时间和完整更新说明"
    echo "- 下载中展示百分比和已下载/总大小，安装中按钮进入明确禁用态"
    echo "- latest.json 写入 release notes、包大小和发布时间，客户端无需额外请求即可展示"
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
