#!/usr/bin/env bash
# Upload a built zip to CurseForge through its upload API.
# Usage: tools/curseforge-upload.sh <zip> [--list-versions]
# Env:
#   CF_API_KEY       CurseForge API token (GitHub secret; never print it)
#   CF_PROJECT_ID    CurseForge project id (repository variable)
#   CF_GAME_VERSION  game version name as CurseForge lists it, e.g. "1.60.1" (repository variable)
#   CF_RELEASE_TYPE  alpha | beta | release (default: beta)
#   CF_CHANGELOG     changelog text (markdown); default: a one-line note
set -euo pipefail

API="https://wow.curseforge.com/api"
: "${CF_API_KEY:?CF_API_KEY is not set}"

versions_json="$(curl -fsS -H "X-Api-Token: $CF_API_KEY" "$API/game/versions")"

if [ "${2:-}" = "--list-versions" ] || [ "${1:-}" = "--list-versions" ]; then
  echo "$versions_json" | jq -r ".[] | \"\\(.id)\\t\\(.name)\"" | sort -t$'\t' -k2 -V
  exit 0
fi

zip="${1:?usage: tools/curseforge-upload.sh <zip> [--list-versions]}"
: "${CF_PROJECT_ID:?CF_PROJECT_ID is not set}"
: "${CF_GAME_VERSION:?CF_GAME_VERSION is not set}"
[ -f "$zip" ] || { echo "upload: $zip not found" >&2; exit 1; }

version_id="$(echo "$versions_json" | jq -r --arg n "$CF_GAME_VERSION" '[.[] | select(.name == $n)][0].id // empty')"
if [ -z "$version_id" ]; then
  echo "upload: no CurseForge game version named \"$CF_GAME_VERSION\". Close matches:" >&2
  echo "$versions_json" | jq -r --arg n "${CF_GAME_VERSION%%.*}" '.[] | select(.name | startswith($n)) | "  \(.id)\t\(.name)"' | head -n 30 >&2
  exit 1
fi

release_type="${CF_RELEASE_TYPE:-beta}"
case "$release_type" in alpha|beta|release) ;; *) echo "upload: bad CF_RELEASE_TYPE $release_type" >&2; exit 1 ;; esac
changelog="${CF_CHANGELOG:-Release $(basename "$zip" .zip)}"
display="$(basename "$zip" .zip)"

metadata="$(jq -n --arg c "$changelog" --arg d "$display" --arg r "$release_type" --argjson v "$version_id" \
  '{changelog: $c, changelogType: "markdown", displayName: $d, gameVersions: [$v], releaseType: $r}')"

echo "upload: $display -> project $CF_PROJECT_ID, game version $CF_GAME_VERSION ($version_id), $release_type"
curl -fsS -H "X-Api-Token: $CF_API_KEY" \
  -F "metadata=$metadata" \
  -F "file=@$zip" \
  "$API/projects/$CF_PROJECT_ID/upload-file"
echo
