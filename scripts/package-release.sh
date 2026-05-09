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

cat > "$RELEASE_DIR/RELEASE_NOTES.md" <<NOTES
## Mac 软件管家 v$VERSION

- 修复“一键升级”看起来没有反应的问题：升级任务会显示全局执行状态，失败时展示最近 stdout/stderr，而不只是退出码。
- 修复 App Store 版本解析：支持 mas 输出无括号版本格式，拿不到新版号时显示“待 App Store 确认”。
- 新增开机自动启动开关，可在“应用更新”页启用或停用。
- 重新设计菜单栏图标，使用更轻量的线性状态图标，并仅在有更新时显示数量。
- 继续保留 Homebrew、App Store、应用程序列表间的升级状态联动。

安装包资产：\`MacSoftwareSteward.zip\`
NOTES

echo "$ZIP_PATH"
