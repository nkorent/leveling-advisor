#!/usr/bin/env bash
# Release build: checks, then dist/LevelingAdvisor-<version>.zip.
# Usage: tools/build.sh [--allow-missing-data]
# Env: LA_BUILD_SKIP_TESTS=1 skips busted (used by the build spec);
#      LA_ADDON_DIR overrides the addon directory (used by the build spec).
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

DIST="$ROOT/dist"
STAGE="$DIST/LevelingAdvisor"
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
echo "dist/LevelingAdvisor-$VERSION$SUFFIX.zip"
