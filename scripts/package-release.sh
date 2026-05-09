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

- 新增应用自更新：启动时自动检查、手动检查、从 GitHub Release 下载并安装。
- 新增每日巡检：通过 LaunchAgent 定时扫描并自动升级可管理软件。
- 新增菜单栏状态入口：显示可升级数量，并可直接一键升级。
- 优化升级体验：列表条目显示排队、升级中、完成、失败等实时状态。
- 新增 macOS 应用图标，并打入 .app 与 release zip。
- 修复从 App Translocation 临时路径启动时无法自更新的问题；遇到不可写目录时自动安装到 ~/Applications。
- 支持缺失 mas CLI 时通过 Homebrew 自动安装。

安装包资产：\`MacSoftwareSteward.zip\`
NOTES

echo "$ZIP_PATH"
