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
  # 与 CI(release.yml) 一致：从 CHANGELOG.md 抽本版本段落（## v$VERSION 到下一个 ## 之间）。
  awk -v tag="v$VERSION" '
    $0 ~ "^## "tag"([ (]|$)" {capture=1; next}
    capture && /^## / {exit}
    capture {print}
  ' "$ROOT_DIR/CHANGELOG.md" > "$NOTES_FILE"
fi
# 兜底：CHANGELOG 没匹配到（如格式变动/版本写错）时给最小占位，不发空说明。
if [ ! -s "$NOTES_FILE" ]; then
  { echo "## Mac 软件管家 v$VERSION"; echo ""; echo "详见 CHANGELOG.md。"; } > "$NOTES_FILE"
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
