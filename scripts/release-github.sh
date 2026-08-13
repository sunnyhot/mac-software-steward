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

# Local pre-flight build only. The resulting release/ artifacts are NOT
# published — CI (.github/workflows/release.yml) is the sole publisher.
bash "$ROOT_DIR/scripts/package-release.sh" >/dev/null
git restore --worktree --staged native/Resources/AppIcon.iconset >/dev/null 2>&1 || true

git add \
  .zcode \
  .gitignore \
  README.md \
  CHANGELOG.md \
  PROJECT_MAP.md \
  package.json \
  native \
  scripts \
  tests \
  docs

if ! git diff --cached --quiet; then
  git commit -m "release: v$VERSION"
fi

git push -u origin HEAD:main

# Publish by pushing the tag only. CI (release.yml) is the single publisher
# of the zip + latest.json + sidecars, which guarantees the published sha256
# always matches the published zip (no local/CI upload race). Pushing the
# tag also triggers that CI run.
git tag -a "$TAG" -m "release: $TAG" 2>/dev/null || true
git push origin "$TAG"

echo "Tag $TAG pushed. CI will build and publish:"
echo "  https://github.com/$OWNER/$REPO/actions?query=branch=$TAG"
