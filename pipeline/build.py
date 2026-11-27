"""Build: crawl JSON + QuestieDB Forever (+ census and curated zones) -> LevelingAdvisor/Data/*.lua + report.json.

Two modes:

* Census build (default). Needs data/census/maps.json and the curated zones.toml/dungeons.toml
  (read by Task 7's ``pipeline.curated``). The merge filters quests to live zones, zones carry
  yards, rects and travel links, continents come from census maps of type Continent, and every
  census ``here`` record with an NPC is checked against that NPC's outof.games spawn.
* Provisional build (``--provisional``). No census, no curated data: the live filter is off,
  zones are generated from the kept quests' giver maps (no yards or rects), there are no
  continents and no dungeons, and Meta.lua says ``provisional = true``. Travel links come from
  the curated dir's links.generated.toml when it exists and ``openmap`` is not in --without:
  each generated link whose from and to are both provisional zones is attached (faction kept,
  zone factions stay 3), the rest are dropped and counted; otherwise zones have no links. It
  exists so the addon can be tried before the in-game census.

QuestieDB Forever (``pipeline.questiedb``, the Questie source; see data/QUESTIE_SOURCE.md) fills what
outof.games lacks. Its NPC spawns are first checked against the outof.games NPC pages per uiMapID
(``merge.spawn_check``); only trusted maps feed the giver fill and the NPC records emitted for kept-quest
givers that have no outof.games page. ``--without questie`` removes all of it (data, blacklist, XP).

Zone minLevel/maxLevel are the rounded 10th and 90th percentiles (linear interpolation) of the
quest level (the estimate when no game level) over the kept quests whose giver is in the zone.

Data files are written to a staging directory next to the report (outside the addon) first and
moved into place only when all five were written, so a failed build leaves the previous files
untouched and nothing stray inside the addon.
"""
from __future__ import annotations

import importlib.util
import json
import math
import os
import shutil
import sys
import tempfile
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path

from pipeline.adjacency import adjacency_gaps
from pipeline.curated import GENERATED_SOURCES
from pipeline.emit import emit_dungeons, emit_meta, emit_npcs, emit_quests, emit_zones
from pipeline.poi import OPENMAP_COMMIT
from pipeline.merge import QUESTIE_FRIENDLY, giver_factions, merge, spawn_check
from pipeline.questiedb import load_questiedb

COORD_TOLERANCE = 5.0     # map units (0-100); a census `here` record farther than this fails
DATA_FILES = ("Meta", "Zones", "NPCs", "Dungeons", "Quests")
QUESTIEDB_SOURCE = "QuestieDB {tag} Forever (GPL-3.0)"
OPENMAP_SOURCE = "OpenMap {tag} (MIT)"
CENSUS_SOURCE = "in-game census (map sizes and rects)"
PROVISIONAL_WARNING_NO_LINKS = ("provisional build: no census and no curated zones; live-zone filter off, zones "
                                "generated from quest givers (no yards, rects or travel links), no continents, "
                                "no dungeons")
PROVISIONAL_WARNING_LINKS = ("provisional build: no census and no curated zones; live-zone filter off, zones "
                             "generated from quest givers (no yards or rects; {attached} generated travel "
                             "link(s) attached from links.generated.toml), no continents, no dungeons")
GENERATED_LINKS_FILE = "links.generated.toml"
ADJACENCY_GAPS_FILE = "adjacency-gaps.json"


class BuildInputError(Exception):
    """A required input is missing or unusable; the CLI prints it and exits 2."""


# ---------------------------------------------------------------- pure helpers

def coord_check(here: list[dict], oog_npcs: dict[int, dict], tolerance: float = COORD_TOLERANCE) -> dict:
    """Compare census `here` records ({npcID, mapID, x, y, ...}) with outof.games NPC spawns.

    Each record with an npcID is measured against the nearest spawn of that NPC on the same map
    (straight-line distance in 0-100 map units): above ``tolerance`` -> "fail", else "pass".
    Records that cannot be compared go to "unmatched" with a reason; records without an npcID
    are not checked.
    """
    out = {"tolerance": tolerance, "pass": [], "fail": [], "unmatched": []}
    for r in here or []:
        npc = r.get("npcID")
        if npc is None:
            continue
        entry = {"npcID": npc, "name": r.get("name"), "mapID": r.get("mapID"), "x": r.get("x"), "y": r.get("y")}
        if None in (entry["mapID"], entry["x"], entry["y"]):
            out["unmatched"].append({**entry, "reason": "no-position"})
            continue
        page = oog_npcs.get(int(npc))
        if page is None:
            out["unmatched"].append({**entry, "reason": "no-npc-page"})
            continue
        spawns = [s for s in page.get("spawns") or [] if s.get("map_id") == entry["mapID"]
                  and s.get("x") is not None and s.get("y") is not None]
        if not spawns:
            out["unmatched"].append({**entry, "reason": "no-spawn-on-map"})
            continue
        dist, spawn = min((math.hypot(s["x"] - entry["x"], s["y"] - entry["y"]), i) for i, s in enumerate(spawns))
        entry.update(distance=round(dist, 3), spawn=[spawns[spawn]["x"], spawns[spawn]["y"]])
        out["fail" if dist > tolerance else "pass"].append(entry)
    return out


def _percentile(values: list, p: float) -> float:
    pos = p * (len(values) - 1)
    lo = math.floor(pos)
    hi = min(lo + 1, len(values) - 1)
    return values[lo] + (values[hi] - values[lo]) * (pos - lo)


def level_range(levels) -> tuple[int | None, int | None]:
    """(rounded 10th percentile, rounded 90th percentile) of the levels; (None, None) when empty."""
    values = sorted(v for v in levels if v is not None)
    if not values:
        return None, None
    return tuple(int(math.floor(_percentile(values, p) + 0.5)) for p in (0.1, 0.9))


def zone_levels(quests: dict[int, dict]) -> dict[int, tuple]:
    """{giver uiMapID: (minLevel, maxLevel)} over the given (kept) quests."""
    by_map = defaultdict(list)
    for q in quests.values():
        by_map[q["giver"]["map_id"]].append(q.get("quest_level"))
    return {m: level_range(levels) for m, levels in by_map.items()}


def resolve_levels(map_id: int, zone: dict | None, quest_levels: dict[int, tuple],
                   map_levels: dict[int, tuple] | None) -> tuple[int | None, int | None, str]:
    """(min, max, source) for one zone: zones.toml min_level/max_level, then OpenMap Levels.lua,
    then the kept-quest percentiles. source is "toml" (both from zones.toml), "openmap", "quests",
    "none" (no data), or "toml+<source>" when zones.toml gives only one of the two."""
    zone = zone or {}
    if map_levels and map_id in map_levels:
        (lo, hi), source = map_levels[map_id], "openmap"
    elif map_id in quest_levels and quest_levels[map_id] != (None, None):
        (lo, hi), source = quest_levels[map_id], "quests"
    else:
        lo = hi = None
        source = "none"
    given = [k for k in ("min_level", "max_level") if zone.get(k) is not None]
    lo, hi = zone.get("min_level", lo), zone.get("max_level", hi)
    if len(given) == 2:
        source = "toml"
    elif given:
        source = f"toml+{source}"
    return lo, hi, source


# Zones that are not leveling zones (Contract A zone ``kind``).
ZONE_KINDS = {1453: "city", 1454: "city", 1455: "city", 1456: "city", 1457: "city", 1458: "city",
              1459: "battleground", 1460: "battleground", 1461: "battleground"}


def provisional_zones(quests: dict[int, dict], oog: dict[int, dict],
                      map_levels: dict[int, tuple] | None = None) -> dict[int, dict]:
    """One zone per distinct giver map of the kept quests (provisional build).

    name: the most common outof.games zone_name among the quests on that map ("Map <id>" when
    none has one); continent, yards and rect unknown; faction 3; live; not complete; no links
    (``provisional_links`` attaches the generated ones afterwards). Levels come from
    ``map_levels`` (OpenMap Levels.lua) when it has the zone ("levels_source" "openmap"),
    otherwise from the quest percentiles ("quests"). ``kind`` is "city" or "battleground" for
    the known capital and battleground maps (ZONE_KINDS), else absent.
    """
    names: dict[int, Counter] = defaultdict(Counter)
    for qid in sorted(quests):
        zone_name = (oog.get(qid) or {}).get("zone_name")
        counter = names[quests[qid]["giver"]["map_id"]]
        if zone_name:
            counter[zone_name] += 1
    levels = zone_levels(quests)
    zones = {}
    for map_id in sorted(names):
        lo, hi = levels[map_id]
        source = "quests"
        if map_levels and map_id in map_levels:
            (lo, hi), source = map_levels[map_id], "openmap"
        zones[map_id] = {
            "name": names[map_id].most_common(1)[0][0] if names[map_id] else f"Map {map_id}",
            "continent": None, "faction": 3, "live": True, "complete": False,
            "min_level": lo, "max_level": hi, "yards": None, "rect": None, "links": [],
            "levels_source": source,
        }
        if map_id in ZONE_KINDS:
            zones[map_id]["kind"] = ZONE_KINDS[map_id]
    return zones


def provisional_links(zones: dict[int, dict], curated_dir: Path, without=frozenset()) -> dict:
    """Attach links.generated.toml links to the provisional zones, in place; return the report entry.

    Reuses curated.load_generated_links (same validation as the census build). Only links whose
    from AND to are both in `zones` are attached; the rest count as dropped_missing_zone. Link
    factions are kept, zone factions are not touched.
    """
    from pipeline.curated import load_generated_links
    try:
        rows, _removed = load_generated_links(Path(curated_dir) / GENERATED_LINKS_FILE, without)
    except ValueError as e:
        raise BuildInputError(f"curated data rejected: {e}") from e
    attached = dropped = 0
    for src, link in rows:
        if src in zones and link["to"] in zones:
            zones[src]["links"].append(link)
            attached += 1
        else:
            dropped += 1
    return {"attached": attached, "dropped_missing_zone": dropped, "source": GENERATED_LINKS_FILE}


def _game_data(oog: dict[int, dict]) -> str | None:
    versions = Counter(q.get("game_data") for q in oog.values() if q.get("game_data"))
    return versions.most_common(1)[0][0] if versions else None


def questiedb_npcs(quests: dict[int, dict], oog_npcs: dict[int, dict], questiedb, trusted_maps) -> dict[int, dict]:
    """NPC records (parse_npc shape) for the NPC givers of kept quests that have no outof.games page
    but are in QuestieDB: its name, faction (friendlyToFaction A / H / AH; else None), minLevel as the
    level and its spawns on trusted maps only. outof.games pages always win."""
    out = {}
    for qid in sorted(quests):
        giver = quests[qid].get("giver") or {}
        nid = giver.get("id")
        if giver.get("kind") != "npc" or nid in oog_npcs or nid in out or nid not in questiedb.npcs:
            continue
        n = questiedb.npcs[nid]
        out[nid] = {"id": nid, "name": n.get("name"), "faction": QUESTIE_FRIENDLY.get(n.get("friendly")),
                    "level": n.get("level"),
                    "spawns": [dict(s) for s in questiedb.npc_spawns.get(nid) or [] if s["map_id"] in trusted_maps]}
    return out


def _npc_ids(quests: dict[int, dict]) -> set[int]:
    return {p["id"] for q in quests.values() for p in (q.get("giver"), q.get("turn_in"))
            if p and p.get("kind") == "npc" and p.get("id") is not None}


def _write_data(out_dir: Path, staging_parent: Path, writers: dict) -> dict[str, int]:
    """Write every Data file to a staging dir under staging_parent, then move them all into out_dir.

    staging_parent must lie outside the addon (the build uses the report's directory,
    data/build/), so a killed build never leaves a staging dir that tools/build.sh would package.
    Returns {file: bytes}.
    """
    staging_parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".staging-", dir=staging_parent))
    try:
        for name, write in writers.items():
            write(staging / f"{name}.lua")
        out_dir.mkdir(parents=True, exist_ok=True)
        sizes = {}
        for name in writers:
            target = out_dir / f"{name}.lua"
            shutil.move(staging / f"{name}.lua", target)   # a rename on one filesystem, else a copy
            sizes[f"{name}.lua"] = target.stat().st_size
        return sizes
    finally:
        shutil.rmtree(staging, ignore_errors=True)


# ---------------------------------------------------------------- build

def _write_json(path: Path, value) -> None:
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(value, indent=1, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, path)


def choose_dungeon_key(level, keys: list[str], dungeons: dict) -> str:
    """The dungeon a multi-listed quest belongs to, by level fit: among dungeons whose
    [min_level, max_level] contains the quest level the range centre closest to it; else the smallest
    distance to a range; ties by sorted key. Without a level: the first sorted key."""
    keys = sorted(keys)
    if level is None:
        return keys[0]

    def rank(k):
        lo, hi = dungeons[k]["min_level"], dungeons[k]["max_level"]
        dist = max(lo - level, level - hi, 0)
        return (dist, abs((lo + hi) / 2 - level), k)
    return min(keys, key=rank)


def _name_stub_starts(stubs: dict, oog_npcs: dict, questie_npcs: dict, objects: dict) -> None:
    """Set each stub's start_name from names the build already has: NPCs (outof.games, then QuestieDB)
    and QuestieDB objects. Item starters stay nameless (no item names are loaded)."""
    for stub in stubs.values():
        giver = stub["giver"] or {}
        sources = {"npc": (oog_npcs, questie_npcs), "object": (objects,)}.get(giver.get("kind"), ())
        stub["start_name"] = next((src[giver["id"]]["name"] for src in sources
                                   if (src.get(giver.get("id")) or {}).get("name")), None)


def _openmap_used(zones: dict, dungeons: dict, levels_source: dict, links_report) -> bool:
    """True when OpenMap data reached the output: zone levels, generated links or generated dungeons."""
    if "openmap" in levels_source.values() or links_report:
        return True
    rows = [*dungeons.values(), *(l for z in zones.values() for l in z.get("links") or [])]
    return any("openmap" in str(r.get("source", "")).lower() for r in rows if isinstance(r, dict))


def build(oog_quests: dict[int, dict], oog_npcs: dict[int, dict], questie: dict[int, dict],
          questie_npcs: dict[int, dict], out_dir: Path, report_path: Path, *, provisional: bool,
          census: dict | None = None, zones: dict | None = None, dungeons: dict | None = None,
          without=frozenset(), recorder: dict | None = None, questie_tag: str | None = None,
          built: str | None = None, notes=(), curated_dir: Path | None = None, questiedb=None,
          map_levels: dict | None = None) -> dict:
    """Merge, emit the five Data files into out_dir, write report_path; return the report.

    oog_quests / oog_npcs: outof.games parse_quest / parse_npc dicts by id. questie /
    questie_npcs: QuestieDBData.quests and .npcs (or dicts of the same shapes; tests pass plain dicts).
    In the CLI path they are the questiedb object's own. questiedb: the QuestieDBData itself, for the spawn check, the giver and XP fill and
    the NPCs emitted for page-less givers (questie_tag is then its commit). census: {"maps": {uiMapID: {...}},
    "here": [...]}; zones / dungeons: Task 7's load_zones / load_dungeons output. A census build
    needs all three (BuildInputError otherwise); a provisional build ignores them. curated_dir:
    a provisional build attaches its links.generated.toml (when present, and openmap is not in
    without); a census build ignores it. map_levels: {uiMapID: (min, max)} from OpenMap
    Levels.lua; levels are zones.toml's, then OpenMap's, then the quest percentiles
    (resolve_levels). The caller leaves it out under ``--without openmap``.
    """
    if not provisional:
        missing = [label for label, value in (("census", census), ("curated zones", zones),
                                              ("curated dungeons", dungeons)) if value is None]
        if missing:
            raise BuildInputError(f"census build needs {', '.join(missing)}; build with --provisional "
                                  "to try the addon without them")
    if not oog_quests:
        raise BuildInputError("no outof.games quests to build from")
    without = frozenset(without)
    out_dir, report_path = Path(out_dir), Path(report_path)

    # an NPC whose faction QuestieDB never states is unknown there, not "hostile to both": left out
    npcs = giver_factions(oog_npcs, {} if "questie" in without else
                          {i: n for i, n in questie_npcs.items() if n.get("faction_known", True)})
    live_maps = None if provisional else {int(m) for m, z in zones.items() if z.get("live")}
    if "questie" in without:
        questiedb = None
    check = spawn_check(oog_npcs, questiedb.npc_spawns) if questiedb is not None else None
    trusted = set(check["trusted"]) if check else set()
    quests, report = merge(oog_quests, questie, live_maps, recorder=recorder, without=without, npcs=npcs,
                           questiedb=questiedb, trusted_maps=trusted)
    stubs = report.pop("stubs")
    _name_stub_starts(stubs, oog_npcs, questie_npcs, getattr(questiedb, "objects", None) or {})
    report["counts"]["stubs"] = len(stubs)
    extra_npcs = questiedb_npcs(quests, oog_npcs, questiedb, trusted) if questiedb is not None else {}
    out_npcs = {**oog_npcs, **extra_npcs}
    if questiedb is not None:
        stats = questiedb.stats
        report["questiedb"].update({
            "source": QUESTIEDB_SOURCE.format(tag=questie_tag or "(commit unknown)"),
            "spawn_check": check,
            "npcs_emitted": len(extra_npcs),
            "raw": stats.get("raw"), "final": stats.get("final"), "layers": stats.get("layers"),
            "dynamic": stats.get("dynamic"),
            "lists": {k: len(stats.get(k) or []) for k in ("created", "skipped", "unresolved", "rejected",
                                                            "faction_conflicts", "dynamic_not_applied")},
            "hidden": stats.get("hidden"), "hide_on_map": stats.get("hide_on_map"),
            "spawns": stats.get("spawns"), "xp": stats.get("xp"),
        })

    dungeon_report = {"count": 0, "quests_not_kept": {}}
    links_report = None
    if provisional:
        out_zones, continents, out_dungeons = provisional_zones(quests, oog_quests, map_levels), {}, {}
        levels_source = {m: z["levels_source"] for m, z in out_zones.items()}
        generated = Path(curated_dir) / GENERATED_LINKS_FILE if curated_dir is not None else None
        if generated is not None and generated.is_file():
            removed = sorted(set(without) & set(GENERATED_SOURCES))
            if removed:
                notes = [*notes, f"provisional: {GENERATED_LINKS_FILE} not attached (--without {', '.join(removed)}); "
                                 "zones have no travel links"]
                report["warnings"].append(PROVISIONAL_WARNING_NO_LINKS)
            else:
                links_report = provisional_links(out_zones, curated_dir, without)
                report["warnings"].append(PROVISIONAL_WARNING_LINKS.format(attached=links_report["attached"]))
        else:
            report["warnings"].append(PROVISIONAL_WARNING_NO_LINKS)
        coords = {"skipped": "no census"}
    else:
        levels = zone_levels(quests)
        out_zones, levels_source = {}, {}
        for map_id, z in zones.items():
            lo, hi, levels_source[int(map_id)] = resolve_levels(int(map_id), z, levels, map_levels)
            out_zones[int(map_id)] = {**z, "min_level": lo, "max_level": hi}
        continents = census.get("maps") or {}
        out_dungeons = dungeons
        listed_by: dict[int, list[str]] = {}
        for key in sorted(dungeons):
            listed = dungeons[key].get("quests") or []
            for qid in listed:
                if qid in quests:
                    listed_by.setdefault(qid, []).append(key)
            dropped = [qid for qid in listed if qid not in quests]
            if dropped:
                dungeon_report["quests_not_kept"][key] = dropped
        multi = []
        for qid in sorted(listed_by):
            keys, q = listed_by[qid], quests[qid]
            if q.get("dungeon_key") is None:
                q["dungeon_key"] = choose_dungeon_key(q.get("quest_level"), keys, dungeons)
                if len(keys) > 1:
                    multi.append({"quest": qid, "level": q.get("quest_level"), "candidates": keys,
                                  "chosen": q["dungeon_key"]})
            if q["dungeon_key"] in keys:
                q["dungeon_quest"] = True      # listed by the dungeon: flag bit 32
        dungeon_report["dungeon_multi_listed"] = {"count": len(multi), "examples": multi[:10]}
        coords = coord_check(census.get("here") or [], oog_npcs)
        gaps = adjacency_gaps(census, out_zones)
    dungeon_report["count"] = len(out_dungeons)
    zones_report = {"count": len(out_zones), "source": "provisional (quest givers)" if provisional else "curated"}
    if not provisional:
        zones_report["adjacency_gaps"] = len(gaps)
    zones_report["levels_source"] = ({m: z["levels_source"] for m, z in sorted(out_zones.items())}
                                     if provisional else dict(sorted(levels_source.items())))
    if provisional and links_report:
        zones_report["links"] = links_report

    sources = [f"outof.games (game data {_game_data(oog_quests) or 'unknown'})"]
    if "questie" not in without:
        sources.append(QUESTIEDB_SOURCE.format(tag=questie_tag or "(commit unknown)"))
    if "openmap" not in without and _openmap_used(out_zones, out_dungeons, levels_source, links_report):
        sources.append(OPENMAP_SOURCE.format(tag=OPENMAP_COMMIT[:7]))
    if not provisional:
        sources.append(CENSUS_SOURCE)
    if recorder and "recorder" not in without:
        sources.append("recorder")
    meta = {"built": built or date.today().isoformat(), "gameData": _game_data(oog_quests), "sources": sources,
            "counts": {"quests": len(quests), "npcs": len(out_npcs)}}
    if provisional:
        meta["provisional"] = True

    sizes = _write_data(out_dir, report_path.parent, {
        "Meta": lambda p: emit_meta(meta, p),
        "Zones": lambda p: emit_zones(out_zones, continents, p),
        "NPCs": lambda p: emit_npcs(out_npcs, p),
        "Dungeons": lambda p: emit_dungeons(out_dungeons, p),
        "Quests": lambda p: emit_quests(quests, p, stubs),
    })

    report.update({
        "provisional": provisional,
        "built": meta["built"],
        "game_data": meta["gameData"],
        "questie_tag": None if "questie" in without else questie_tag,
        "coord_check": coords,
        "npcs": {"emitted": len(out_npcs), "questiedb": len(extra_npcs),
                 "kept_quest_npcs_without_page": len(_npc_ids(quests) - set(out_npcs))},
        "zones": zones_report,
        "dungeons": dungeon_report,
        "notes": list(notes),
        "outputs": sizes,
    })
    report_path.parent.mkdir(parents=True, exist_ok=True)
    if not provisional:   # rect-adjacent zones without a walk link: for a human to add or drop in the TOML
        _write_json(report_path.parent / ADJACENCY_GAPS_FILE, gaps)
    _write_json(report_path, report)
    return report


# ---------------------------------------------------------------- inputs from disk

def load_oog(oog_dir: Path) -> tuple[dict[int, dict], dict[int, dict]]:
    """outof.games crawl output: (quests by id, NPCs by id). Ignores the crawl's in-flight *.tmp files."""
    qdir = Path(oog_dir) / "quests"
    files = sorted(qdir.glob("*.json")) if qdir.is_dir() else []
    if not files:
        raise BuildInputError(f"no outof.games crawl output in {qdir} (run `python -m pipeline crawl`)")

    def read(path):
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as e:
            raise BuildInputError(f"unreadable crawl file {path}: {e}") from e

    quests = {}
    for p in files:
        q = read(p)
        quests[int(q.get("id") or p.stem)] = q
    npcs = {}
    for p in sorted((Path(oog_dir) / "npcs").glob("*.json")):
        n = read(p)
        npcs[int(n.get("id") or p.stem)] = n
    return quests, npcs


def load_questiedb_root(root: Path, blacklist: Path):
    """QuestieDBData from a QuestieDB clone and the Questie master blacklist (data/QUESTIE_SOURCE.md)."""
    try:
        return load_questiedb(Path(root), Path(blacklist))
    except FileNotFoundError as e:
        raise BuildInputError(f"{e} (vendor QuestieDB and the Questie master blacklist as described in "
                              "data/QUESTIE_SOURCE.md, or build --without questie)") from e
    except ValueError as e:
        raise BuildInputError(f"QuestieDB rejected: {e}") from e


def questiedb_tag(root: Path) -> str | None:
    """Short commit of the QuestieDB clone, read from its .git (HEAD, then the ref file or packed-refs)."""
    git = Path(root) / ".git"
    try:
        head = (git / "HEAD").read_text(encoding="utf-8").strip()
        if not head.startswith("ref:"):
            return head[:7] or None
        ref = head.split(":", 1)[1].strip()
        if (git / ref).is_file():
            return (git / ref).read_text(encoding="utf-8").strip()[:7] or None
        for line in (git / "packed-refs").read_text(encoding="utf-8").splitlines():
            parts = line.split()
            if len(parts) == 2 and parts[1] == ref:
                return parts[0][:7]
    except OSError:
        return None
    return None


def read_census(path: Path) -> dict:
    """data/census/maps.json (Task 7's `python -m pipeline census`) with integer map ids."""
    try:
        raw = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise BuildInputError(f"unreadable census {path}: {e}") from e
    return {"maps": {int(k): v for k, v in (raw.get("maps") or {}).items()},
            "areas": raw.get("areas") or {}, "here": list(raw.get("here") or [])}


def load_curated(curated_dir: Path, census: dict, notes: list | None = None,
                 without=frozenset()) -> tuple[dict, dict]:
    """zones.toml and dungeons.toml, with links.generated.toml / dungeons.generated.toml (Task 8a's
    `python -m pipeline poi`) merged in under them when those exist.

    without: a removed reference source ("openmap") takes out every generated link and
    dungeon it contributed to; curated rows stay. notes get one line per removed reference source
    and the count of generated links dropped for zones zones.toml does not define."""
    from pipeline.curated import GENERATED_SOURCES, load_dungeons_with_problems, load_zones_with_problems
    curated_dir = Path(curated_dir)
    links, gen_dungeons = curated_dir / "links.generated.toml", curated_dir / "dungeons.generated.toml"
    gen_quests = curated_dir / "dungeons.quests.generated.toml"
    try:
        zones, link_problems = load_zones_with_problems(curated_dir / "zones.toml", census,
                                                        links if links.is_file() else None, without)
        dungeons, dungeon_problems = load_dungeons_with_problems(
            curated_dir / "dungeons.toml", gen_dungeons if gen_dungeons.is_file() else None, without,
            gen_quests if gen_quests.is_file() else None)
    except ValueError as e:
        raise BuildInputError(f"curated data rejected: {e}") from e
    if notes is not None:
        for src in sorted(set(without) & set(GENERATED_SOURCES)):
            n_links = sum(1 for p in link_problems if p["type"] == "generated-link-removed" and src in p["sources"])
            n_dungeons = sum(1 for p in dungeon_problems if src in p["sources"])
            notes.append(f"{src}: {n_links} generated link(s) and {n_dungeons} generated dungeon(s) removed "
                         f"(--without {src})")
        dropped = [p for p in link_problems if p["type"] == "generated-link-dropped"]
        if dropped:
            notes.append(f"curated: {len(dropped)} generated link(s) from {links.name} dropped "
                         "(from or to a zone not in zones.toml)")
    return zones, dungeons


def _census_inputs_missing(args) -> list[str]:
    problems = []
    if not Path(args.census).is_file():
        problems.append(f"census not found: {args.census} (import it with `python -m pipeline census` "
                        "after the in-game census)")
    for name in ("zones.toml", "dungeons.toml"):
        if not (Path(args.curated) / name).is_file():
            problems.append(f"curated file not found: {Path(args.curated) / name}")
    if importlib.util.find_spec("pipeline.curated") is None:
        problems.append("curated loaders not built yet (pipeline/curated.py, Plan 2 Task 7)")
    return problems


def _load_recorder(path: Path) -> tuple[dict | None, str | None]:
    if importlib.util.find_spec("pipeline.recorder_import") is None:
        return None, (f"recorder: {path} skipped, pipeline.recorder_import is not built yet "
                      "(Plan 4a Task 8)")
    from pipeline.recorder_import import load_recorder
    recorder = load_recorder(Path(path))
    if not recorder:
        return recorder, f"recorder: {path} is missing or has no agreed quest data; building without it"
    return recorder, None


def run(args, log=print) -> int:
    """CLI entry (python -m pipeline build). 0 on success, 2 on a missing or unusable input."""
    try:
        without = frozenset(args.without or ())
        if not args.provisional:
            problems = _census_inputs_missing(args)
            if problems:
                raise BuildInputError("\n  ".join(["cannot build without the census and curated zones:", *problems,
                                                   "build with --provisional to try the addon without them"]))
        oog_quests, oog_npcs = load_oog(Path(args.oog))
        questie, questie_npcs, tag, questiedb = {}, {}, None, None
        if "questie" not in without:
            questiedb = load_questiedb_root(Path(args.questiedb), Path(args.questie_blacklist))
            questie, questie_npcs, tag = questiedb.quests, questiedb.npcs, questiedb_tag(Path(args.questiedb))
        notes, recorder, map_levels = [], None, None
        if "openmap" not in without:
            from pipeline.poi import load_openmap_levels
            try:
                map_levels = load_openmap_levels(Path(args.levels))
            except (OSError, ValueError) as e:
                notes.append(f"openmap: zone levels not read ({e}); zone levels from quest percentiles")
        else:
            notes.append("openmap: zone levels not read (--without openmap); zone levels from quest percentiles")
        if args.recorder:
            if "recorder" in without:
                notes.append(f"recorder: {args.recorder} skipped (--without recorder)")
            else:
                recorder, note = _load_recorder(Path(args.recorder))
                if note:
                    notes.append(note)
        census = zones = dungeons = None
        if not args.provisional:
            census = read_census(Path(args.census))
            zones, dungeons = load_curated(Path(args.curated), census, notes, without)
        report = build(oog_quests, oog_npcs, questie, questie_npcs, Path(args.out), Path(args.report),
                       provisional=args.provisional, census=census, zones=zones, dungeons=dungeons,
                       without=without, recorder=recorder, questie_tag=tag, notes=notes,
                       curated_dir=Path(args.curated) if args.provisional else None, questiedb=questiedb,
                       map_levels=map_levels)
    except BuildInputError as e:
        print(f"build: {e}", file=sys.stderr)
        return 2
    counts = report["counts"]
    log(f"{'provisional ' if args.provisional else ''}build: {counts['kept']} quests kept of "
        f"{counts['oog_quests']} ({counts['excluded']} excluded), {report['npcs']['emitted']} NPCs, "
        f"{report['zones']['count']} zones, {report['dungeons']['count']} dungeons")
    for name, size in report["outputs"].items():
        log(f"  {Path(args.out) / name}: {size} bytes")
    log(f"  report: {args.report}")
    for w in report["warnings"] + report["notes"]:
        log(f"  note: {w}")
    return 0
