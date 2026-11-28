#!/usr/bin/env bash
# Release build: checks, then dist/LevelingAdvisor-<version>.zip.
# Usage: tools/build.sh [--allow-missing-data]
# Env: LA_BUILD_SKIP_TESTS=1 skips busted (used by the build spec);
#      LA_ADDON_DIR overrides the addon directory (used by the build spec);
#      LA_DIST_DIR overrides the output directory (default dist/; the build spec
#      builds into a temp dir so it never touches a real release zip).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDON="${LA_ADDON_DIR:-$ROOT/LevelingAdvisor}"
ALLOW_MISSING=0
case "${1:-}" in
  "") ;;
  --allow-missing-data) ALLOW_MISSING=1 ;;
  *) echo "usage: $0 [--allow-missing-data]" >&2; exit 2 ;;
esac

cd "$ROOT"

command -v zip >/dev/null 2>&1 || { echo "error: zip not found" >&2; exit 1; }

# The output dir, made and resolved first (before any work, and long before
# anything in it is deleted). The stage dir (DIST/LevelingAdvisor) is emptied
# below, so a DIST that would make it the repo or the addon source, or a DIST
# inside the addon source, is refused. A missing addon dir fails the syntax check.
DIST="${LA_DIST_DIR:-$ROOT/dist}"
mkdir -p "$DIST"
DIST="$(cd "$DIST" && pwd)"
STAGE="$DIST/LevelingAdvisor"
DIST_REAL="$(cd "$DIST" && pwd -P)"
ROOT_REAL="$(cd "$ROOT" && pwd -P)"
ADDON_REAL="$(cd "$ADDON" 2>/dev/null && pwd -P)" || ADDON_REAL="$ROOT_REAL/LevelingAdvisor"
for keep in "$ROOT_REAL" "$ROOT_REAL/LevelingAdvisor" "$ADDON_REAL"; do
  case "$keep/" in
    "$DIST_REAL/LevelingAdvisor/"*)
      echo "build: refusing LA_DIST_DIR=$DIST: the build would delete $keep" >&2; exit 2 ;;
  esac
done
for src in "$ROOT_REAL/LevelingAdvisor" "$ADDON_REAL"; do
  case "$DIST_REAL/" in
    "$src/"*) echo "build: refusing LA_DIST_DIR=$DIST: it is inside the addon source $src" >&2; exit 2 ;;
  esac
done

echo "== syntax check"
"$ROOT/tools/check-lua-syntax.sh" "$ADDON" || { echo "build: syntax check failed" >&2; exit 1; }

if [ "${LA_BUILD_SKIP_TESTS:-0}" != "1" ]; then
  echo "== tests"
  export PATH="/opt/homebrew/bin:$HOME/.luarocks/bin:$PATH"
  command -v luarocks >/dev/null 2>&1 || { echo "error: luarocks not found" >&2; exit 1; }
  eval "$(luarocks --lua-version=5.1 path)"
  busted || { echo "build: tests failed" >&2; exit 1; }
fi

missing=0
for f in Meta Zones NPCs Dungeons Quests; do
  if [ ! -f "$ADDON/Data/$f.lua" ]; then
    echo "build: missing Data/$f.lua" >&2
    missing=1
  fi
done
if [ "$missing" = 1 ] && [ "$ALLOW_MISSING" = 0 ]; then
  echo "build: data files missing (pass --allow-missing-data to build anyway)" >&2
  exit 1
fi

VERSION="$(sed -n 's/^## Version:[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*$/\1/p' "$ADDON/LevelingAdvisor.toc" | head -n 1)"
if [ -z "$VERSION" ]; then
  echo "build: no ## Version: in TOC" >&2
  exit 1
fi

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$ADDON/LevelingAdvisor.toc" "$ADDON/Bindings.xml" "$STAGE/"
cp -R "$ADDON/Core" "$ADDON/Engine" "$ADDON/UI" "$ADDON/Media" "$STAGE/"
[ -d "$ADDON/Data" ] && cp -R "$ADDON/Data" "$STAGE/"
cp "$ROOT/LICENSE" "$ROOT/README.md" "$ROOT/NOTICE.md" "$STAGE/"
find "$STAGE" -name '.DS_Store' -delete

SUFFIX=""
if [ "$missing" = 0 ] && grep -Eq 'provisional[[:space:]]*=[[:space:]]*true' "$ADDON/Data/Meta.lua"; then
  SUFFIX="-provisional"
  echo "WARNING: provisional data in this build — not a final release."
fi
if [ "$missing" = 1 ]; then
  SUFFIX="-nodata"
  echo "WARNING: no quest data in this build — for testing only, not for release."
fi
ZIP="$DIST/LevelingAdvisor-$VERSION$SUFFIX.zip"
rm -f "$ZIP"
(cd "$DIST" && zip -rq "$ZIP" LevelingAdvisor)
echo "${ZIP#"$ROOT"/}"
