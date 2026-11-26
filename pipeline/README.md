# Data pipeline

Offline Python pipeline that politely crawls outof.games and generates the addon's Lua data.

Setup (from the repo root):

    python3.12 -m venv .venv
    .venv/bin/pip install --index-url https://pypi.org/simple requests==2.34.2 beautifulsoup4==4.15.0 lxml==6.1.3 lupa==2.8 pytest==9.2.0
    .venv/bin/pytest pipeline/tests -q

Dependencies install with `--index-url https://pypi.org/simple`.

Commands (from the repo root):

    .venv/bin/python -m pipeline crawl                  # outof.games -> data/build/outofgames/ (resumable)
    .venv/bin/python -m pipeline crawl --refresh-lists  # same, but list pages are requested again (new quest ids)
    .venv/bin/python -m pipeline crawl --reparse        # rebuild the parsed JSON from the cached HTML (offline)
    .venv/bin/python -m pipeline build                  # -> LevelingAdvisor/Data/*.lua + data/build/report.json
    .venv/bin/python -m pipeline build --provisional    # same, before the in-game census exists
    .venv/bin/python -m pipeline poi                    # OpenMap + census -> data/curated/*.generated.toml
    luajit tools/engine-smoke.lua                       # run the real engine on the generated Data files

`build` needs `data/census/maps.json` and `data/curated/{zones,dungeons}.toml`; without them it exits 2.
`--provisional` builds without both: zones come from the quest givers' maps (no yards, rects or travel
links), there are no continents or dungeons, and `Meta.lua` says `provisional = true`. The Questie source
is QuestieDB's Forever flavor (`--questiedb data/vendor/QuestieDB`) plus Questie master's quest blacklist
(`--questie-blacklist`); see `data/QUESTIE_SOURCE.md`. `--without questie` or `--without recorder`
rebuilds without that source; `--recorder DIR` adds recorder exports.

`poi` reads `data/vendor/openmap/Places.lua`, `data/census/maps.json`, `data/curated/zones.toml` and
`data/curated/openmap_zone_hints.toml` (see `data/REFERENCE_SOURCES.md`) and writes
`data/curated/links.generated.toml` (boat and zeppelin links) and `data/curated/dungeons.generated.toml`
(committed) plus `data/build/poi-problems.json` (missing reverse links, self-links, points with no zone or
on overlapping zone maps without a hint, unused hints). OpenMap's world yards become zone coordinates
through the classic continent bounds, which must reproduce the census continent yards within 1 yard
(otherwise `poi` exits 2). `build` merges the generated files in under `zones.toml` and `dungeons.toml`,
which always win; generated links from or to a zone that `zones.toml` does not define are dropped
(counted in the report notes), and a zone can drop generated links with
`drop_generated = [[to, "kind"], ...]`. `build --without openmap` removes the generated rows.

## Crawl cache and refreshing after a game patch

`crawl` caches every page under `data/raw/` and never requests a cached page again; it also reuses the
parsed JSON in `data/build/outofgames/`. A plain re-run therefore only fetches pages that are missing
(for example after errors). It does **not** notice new or changed quests. Two options do:

- `--refresh-lists` requests the quest list pages again (page 1, then pages 2..N from page 1's
  pagination; about 140 requests at the usual 2 s pace, robots.txt read first, never `/api/v2/forever/`),
  then crawls the quest and NPC pages of ids not seen before. Known quests are not refetched.
  With `--dungeons` it refreshes the dungeon list page.
- `--reparse` rebuilds every quest and NPC JSON from the cached HTML. On its own it makes no request at
  all (not even robots.txt); pages missing from the cache are listed in `errors.json`. With
  `--refresh-lists` it also fetches missing pages politely. Run it after a parser change.

Both exit with status 2 when list page 1 fails or lists no quest, so a shrunken crawl is never taken
for a complete one.

Per-patch procedure (after a Forever patch changes quests):

1. `crawl --refresh-lists` to find and crawl the new quest ids (and their NPCs).
2. For quests the patch changed (patch notes, recorder disagreements, an outof.games "Game data"
   version newer than `Meta.lua`'s `gameData`): delete their cached pages,
   `data/raw/outof.games/realms/forever/quest/<id>-*/`, and their JSON,
   `data/build/outofgames/quests/<id>.json`, then run `crawl` again; only those pages are requested.
   To refetch everything, move `data/raw/outof.games/realms/forever/quest/` aside first (about 6,900
   requests, roughly four hours).
3. `crawl --dungeons --refresh-lists`, then `dungeon-quests`, when dungeons changed.
4. `build`, then check `data/build/report.json`: kept/excluded counts, `excluded_by_reason`,
   `unknown_tags`, `unknown_requirements` and `warnings` against the previous build, and commit the
   rebuilt `LevelingAdvisor/Data/*.lua` with the new counts in the build notes.
