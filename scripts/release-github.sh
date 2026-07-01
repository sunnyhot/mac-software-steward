#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(node -p "require('$ROOT_DIR/package.json').version")"
OWNER="${GITHUB_OWNER:-$(gh api user --jq .login)}"
REPO="${GITHUB_REPO:-mac-software-steward}"
VISIBILITY="${GITHUB_VISIBILITY:-public}"
TAG="v$VERSION"

cd "$ROOT_DIR"

if [ ! -d .git ]; then
  git init -b main
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  if gh repo view "$OWNER/$REPO" >/dev/null 2>&1; then
    git remote add origin "https://github.com/$OWNER/$REPO.git"
  else
    case "$VISIBILITY" in
      public) gh repo create "$OWNER/$REPO" --public --source=. --remote=origin ;;
      private) gh repo create "$OWNER/$REPO" --private --source=. --remote=origin ;;
      internal) gh repo create "$OWNER/$REPO" --internal --source=. --remote=origin ;;
      *) echo "Unsupported GITHUB_VISIBILITY=$VISIBILITY" >&2; exit 2 ;;
    esac
  fi
fi

bash "$ROOT_DIR/scripts/package-release.sh" >/dev/null
git restore --worktree --staged native/Resources/AppIcon.iconset >/dev/null 2>&1 || true

git add \
  .gitignore \
  README.md \
  package.json \
  native \
  scripts \
  tests

if ! git diff --cached --quiet; then
  git commit -m "release: v$VERSION"
fi

git push -u origin HEAD:main

if gh release view "$TAG" --repo "$OWNER/$REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" \
    "$ROOT_DIR/release/MacSoftwareSteward.zip" \
    "$ROOT_DIR/release/MacSoftwareSteward.zip.sha256" \
    "$ROOT_DIR/release/MacSoftwareSteward-v$VERSION.zip" \
    "$ROOT_DIR/release/MacSoftwareSteward-v$VERSION.zip.sha256" \
    "$ROOT_DIR/release/latest.json" \
    --repo "$OWNER/$REPO" \
    --clobber
else
  gh release create "$TAG" \
    "$ROOT_DIR/release/MacSoftwareSteward.zip" \
    "$ROOT_DIR/release/MacSoftwareSteward.zip.sha256" \
    "$ROOT_DIR/release/MacSoftwareSteward-v$VERSION.zip" \
    "$ROOT_DIR/release/MacSoftwareSteward-v$VERSION.zip.sha256" \
    "$ROOT_DIR/release/latest.json" \
    --repo "$OWNER/$REPO" \
    --title "Mac 软件管家 $TAG" \
    --notes-file "$ROOT_DIR/release/RELEASE_NOTES.md" \
    --latest
fi

echo "https://github.com/$OWNER/$REPO/releases/tag/$TAG"
