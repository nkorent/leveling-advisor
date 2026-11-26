# Reference POI sources (downloaded locally, git-ignored under data/vendor/)

`python -m pipeline poi` (pipeline/poi.py) reads OpenMap's places of WoW: Forever and the in-game census
(`data/census/maps.json`) and writes our own files: `data/curated/links.generated.toml` and
`data/curated/dungeons.generated.toml` (committed), plus `data/build/poi-problems.json` (not committed).
The hand-maintained `zones.toml` / `dungeons.toml` always win over the generated files.
The vendor files are not committed. Credits are in the root `NOTICE.md`.

The quest database itself (QuestieDB Forever and the Questie quest blacklist, both under
`data/vendor/` as well) is described in `data/QUESTIE_SOURCE.md`.

## OpenMap

- Project: OpenMap, https://github.com/openmap-world/openmap
- Commit: `6c2299f6e1f9bdce1bbd92145f84a05b0c6c05a7`, path `OpenMap/Data/Forever/`
- Local files: `data/vendor/openmap/Places.lua` (read by `poi`), `Levels.lua` (read by `build`: zone
  level ranges), `FlightData.lua`, `Labels.lua` (downloaded, not read), `LICENSE`
- **License:** MIT, covering OpenMap's code and data tables (not its textures made from game art,
  which are not used). The copyright and permission notice is reproduced in the root `NOTICE.md`.
- What is used, from `ns.MapPlaces`:
  - `instances` (and `unplaced`): instance names (the Group Finder's, including the Scarlet Monastery
    and Dire Maul wing names), the raid flag (raids are skipped), the Group Finder minimum and maximum
    levels, and the entrance: in world yards per continent, or a `map =` spot (0..1 on a zone map).
  - `transports`: boat, zeppelin and airship routes, `{ kind, route, continent, x, y, toContinent,
    toX, toY }` in world yards, with an optional `faction =` (none at this commit). One link per row.
  - Not used: `bosses`, `sailings`.

## From world yards to a zone (pipeline/poi.py)

1. **Continent.** OpenMap continent 0 is the Eastern Kingdoms (census uiMap 1415), 1 is Kalimdor (1414).
   The classic `WorldMapArea` continent bounds (Kalimdor left 17066.6, right -19733.2, top 12799.9,
   bottom -11733.3; Eastern Kingdoms 16000.0, -19199.9, 7466.6, -15999.9) give
   `mapX = (left - worldY) / (left - right)`, `mapY = (top - worldX) / (top - bottom)`.
   **Gate:** the bounds are used only if `left - right` and `top - bottom` reproduce the census
   continent `yards` within 1 yard; otherwise `poi` stops (exit 2). Bounds are never fitted.
2. **Zone.** Among the live zones of zones.toml on that continent whose census `rect` contains the point:
   - the one zone rect that contains it;
   - else (classic zone maps overlap, so one point is often inside two or three rects) the zone named
     in the hand-maintained `data/curated/openmap_zone_hints.toml`, by OpenMap instance or route name
     and census zone name, and only if that zone's rect contains the point (a hint beats a city rect:
     the Orgrimmar zeppelin towers stand outside the gate, in Durotar);
   - else a city rect (`kind = "city"`), which wins over the zones around it;
   - else the point goes to the problems file. Nothing is snapped to a zone.
   x, y = the point on the chosen zone's own map (0-100).
3. A continent the census does not map (OpenMap's 2991, Zephras Isle: the census has it as uiMap 2521
   with no rect) gives no link: the row goes to the problems file.

## Rules

- **Links.** From the departure zone to the arrival zone, at the departure point. Kind: boat, or
  zeppelin (an airship is a zeppelin, labelled "airship to ..."). Label "<kind> to <arrival zone>".
  Faction: OpenMap's `faction =` when present, else Horde for zeppelins (the classic rule), else none.
  A row whose two ends are in one zone (Feathermoon ↔ the Feralas coast) is a `self-link` problem.
  Every link without a link of the same kind back is reported as `missing-reverse`; none is invented.
  There are no walk, tram or portal links: OpenMap has none, and zone-to-zone travel falls back to the
  straight-line distance from the census rects.
- **Dungeons.** One per 5-player instance (and per wing), keyed by the name's initials
  (`SEED_KEYS` keeps "BFD" for Blackfathom Deeps; a dungeons.toml key for the same name is kept).
  Faction: Alliance or Horde when the entrance is in one of that faction's capitals, else Both.
- `data/build/poi-problems.json` lists every row that gave nothing, with the candidate zones and
  their coordinates, and every hint no point needed (`unused-hint`).
- zones.toml can drop generated links from a zone without replacing them:
  `drop_generated = [[to, "kind"], ...]`.

## Removing the source

`python -m pipeline build --without openmap` removes every generated link and every generated
dungeon (and OpenMap's zone levels). Rows in zones.toml and dungeons.toml are never removed. The
report notes how many rows were taken out.

## Updating

Replace the files under `data/vendor/openmap/`, update `OPENMAP_COMMIT` in pipeline/poi.py and this
file, then run `.venv/bin/python -m pipeline poi` and review the diff of the generated TOML files and
`data/build/poi-problems.json` (new ambiguous points need a hint; unused hints should go).
