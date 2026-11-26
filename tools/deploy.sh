#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <addon-dir>" >&2
  exit 2
fi

if [ ! -d "$1" ]; then
  echo "error: addon dir not found: $1" >&2
  exit 1
fi

# Resolve to the real path so `.` and trailing slashes yield the true folder name.
src="$(cd -- "$1" && pwd -P)"
name="$(basename "$src")"

# rsync --delete is destructive: never let it target the AddOns root or a non-addon folder.
case "$name" in
  ""|"."|".."|"/")
    echo "error: refusing unsafe addon folder name: '$name' (from $src)" >&2
    exit 2
    ;;
esac
if [ ! -f "$src/$name.toc" ]; then
  echo "error: $src does not contain $name.toc; not an addon folder, refusing to deploy" >&2
  exit 2
fi

addons="/Applications/World of Warcraft/_forever_/Interface/AddOns"
if [ ! -d "$addons" ]; then
  echo "error: AddOns folder does not exist: $addons" >&2
  exit 1
fi

if [ -L "$addons/$name" ]; then
  echo "error: $addons/$name is a symlink; refusing to deploy through it" >&2
  exit 2
fi

target="$addons/$name/"
rsync -a --delete --exclude='.DS_Store' --exclude='.git*' --exclude='*.swp' "$src/" "$target"
echo "Deployed to: $target"
echo "Reminder: a new addon needs a client restart; existing addons only need /reload."
