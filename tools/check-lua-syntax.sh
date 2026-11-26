#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <dir>" >&2
  exit 2
fi

if [ ! -d "$1" ]; then
  echo "error: not a directory: $1" >&2
  exit 2
fi

fail=0
count=0
while IFS= read -r -d '' f; do
  count=$((count + 1))
  if ! env -u LUA_PATH -u LUA_CPATH -u LUA_PATH_5_1 -u LUA_CPATH_5_1 luajit -b "$f" /dev/null; then  # luarocks LUA_PATH hides jit.* modules
    echo "SYNTAX FAIL: $f" >&2
    fail=1
  fi
done < <(find "$1" -name '*.lua' -print0)

# Lua 5.2+ constructs that LuaJIT accepts but the WoW client does not.
# Comment text after `--` is ignored (naive: a `--` inside a string also cuts the line,
# and --[[ block comments ]] spanning several lines are not recognised).
while IFS= read -r -d '' f; do
  hits=$(awk -v F="$f" '
    { line = $0; sub(/--.*/, "", line) }
    line ~ /(^|[^A-Za-z0-9_])goto([^A-Za-z0-9_]|$)/ ||
    line ~ /::[A-Za-z_][A-Za-z0-9_]*::/ ||
    line ~ /table\.(unpack|pack)([^A-Za-z0-9_]|$)/ {
      print F ":" NR ": Lua 5.2+ construct not available in WoW: " $0
    }' "$f")
  if [ -n "$hits" ]; then
    echo "$hits" >&2
    fail=1
  fi
done < <(find "$1" -name '*.lua' -print0)

if [ "$count" -eq 0 ]; then
  echo "warning: no .lua files found under $1" >&2
fi
echo "checked $count file(s)"
exit "$fail"
