"""Hand-maintained zones and dungeons (data/curated/*.toml) -> the dicts `pipeline.build` consumes.

Generated reference data (`python -m pipeline poi`: links.generated.toml, dungeons.generated.toml)
is merged in under the hand-maintained files, which always win. Every loaded link and dungeon
keeps a `source`: "curated" for hand-maintained rows, the generated row's own source string
("openmap") otherwise. `without` removes the generated rows that a removed source contributed
to; curated rows are never removed.
"""
from __future__ import annotations

import re
import tomllib
from pathlib import Path

LINK_KINDS = ("walk", "boat", "zeppelin", "tram", "portal", "flight")
ZONE_FACTIONS = ("Alliance", "Horde", "Contested")
ZONE_KINDS = ("city", "battleground")   # optional zones.toml `kind`; absent = a leveling zone
LINK_FACTIONS = ("Alliance", "Horde")
DUNGEON_FACTIONS = ("Alliance", "Horde", "Both")
GENERATED_SOURCES = ("openmap",)   # removable with build --without
CURATED_SOURCE = "curated"


def read_toml(path: Path) -> dict:
    """A TOML file as a dict; ValueError (naming the file) when it is not valid TOML."""
    try:
        return tomllib.loads(Path(path).read_text(encoding="utf-8"))
    except tomllib.TOMLDecodeError as e:
        raise ValueError(f"{path}: invalid TOML: {e}") from e


def _num(v) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def _coord(v, where: str) -> None:
    if not _num(v) or not 0 <= v <= 100:
        raise ValueError(f"{where}: coordinate {v!r} outside 0-100")


def _int(v, where: str, field: str) -> None:
    if not isinstance(v, int) or isinstance(v, bool):
        raise ValueError(f"{where}: {field} must be an integer, got {v!r}")


def _one_of(v, allowed, where: str, what: str) -> None:
    if v not in allowed:
        raise ValueError(f"{where}: unknown {what} {v!r} (expected one of {', '.join(allowed)})")


def name_key(name: str) -> str:
    """A name for matching: case, punctuation and a leading "The" ignored ("The Deadmines" ~ "deadmines")."""
    s = re.sub(r"[^\w\s]", "", str(name).replace("|n", " ").lower())
    s = " ".join(s.split())
    return s[4:] if s.startswith("the ") else s


def row_sources(source) -> list[str]:
    """The reference sources a generated row's source string names, e.g. "openmap" -> ["openmap"]."""
    words = set(re.findall(r"[a-z]+", source.lower())) if isinstance(source, str) else set()
    return sorted(words & set(GENERATED_SOURCES))


def _generated_source(row: dict, where: str) -> list[str]:
    sources = row_sources(row.get("source"))
    if not sources:
        raise ValueError(f"{where}: source {row.get('source')!r} names none of {', '.join(GENERATED_SOURCES)}")
    return sources


def _drop_generated(z: dict, where: str) -> set[tuple[int, str]]:
    """zones.toml `drop_generated = [[to, "kind"], ...]`: generated links this zone must not get."""
    raw = z.get("drop_generated", [])
    if not isinstance(raw, list):
        raise ValueError(f"{where}: drop_generated must be a list of [to, kind] pairs")
    out = set()
    for pair in raw:
        if not isinstance(pair, list) or len(pair) != 2:
            raise ValueError(f"{where}: drop_generated entry {pair!r} is not [to, kind]")
        _int(pair[0], where, "drop_generated 'to'")
        _one_of(pair[1], LINK_KINDS, f"{where} drop_generated", "kind")
        out.add((pair[0], pair[1]))
    return out


def _link(link: dict, where: str) -> dict:
    for field in ("to", "kind", "x", "y", "label"):
        if field not in link:
            raise ValueError(f"{where}: missing {field}")
    _int(link["to"], where, "'to'")
    _one_of(link["kind"], LINK_KINDS, where, "kind")
    if link.get("faction") is not None:
        _one_of(link["faction"], LINK_FACTIONS, where, "faction")
    _coord(link["x"], where)
    _coord(link["y"], where)
    return {"to": int(link["to"]), "kind": link["kind"], "x": link["x"], "y": link["y"],
            "label": link["label"], "faction": link.get("faction"), "source": CURATED_SOURCE}


def _generated(source, table: str):
    """Generated rows: None, a parsed table, or the path of a *.generated.toml file."""
    if source is None:
        return None
    if isinstance(source, (str, Path)):
        return read_toml(Path(source)).get(table)
    return source


def load_generated_links(generated_links, without=frozenset()) -> tuple[list[tuple[int, dict]], list[dict]]:
    """Validate generated link rows (a parsed list or the path of links.generated.toml).

    Returns ([(from uiMapID, link)], problems). Each row is validated like a curated link plus an
    int `from` and a source naming openmap; link["source"] is the row's own source
    string. A row whose source names a source in `without` is not returned; it is listed in
    problems as {type: "generated-link-removed", from, to, kind, sources}. ValueError on a bad row.
    """
    rows, problems = [], []
    for row in _generated(generated_links, "links") or []:
        where = f"generated link {row.get('from')} -> {row.get('to')}"
        if "from" not in row:
            raise ValueError(f"{where}: missing from")
        _int(row["from"], where, "'from'")
        link = _link(row, where)
        sources = _generated_source(row, where)
        link["source"] = row["source"]
        src = int(row["from"])
        if set(sources) & set(without):
            problems.append({"type": "generated-link-removed", "from": src, "to": link["to"], "kind": link["kind"],
                             "sources": sorted(set(sources) & set(without))})
            continue
        rows.append((src, link))
    return rows, problems


def load_zones(path: Path, census: dict | None, generated_links=None, without=frozenset()) -> dict[int, dict]:
    """{uiMapID: {name, continent (None when omitted), faction, live, complete, [min_level, max_level], yards, rect, links}}.

    Link: {to, kind, x, y, label, faction, source}. generated_links: rows {from, to, kind, x, y,
    label, [faction], source} (or the path of links.generated.toml); see load_zones_with_problems.
    """
    return load_zones_with_problems(path, census, generated_links, without)[0]


def load_zones_with_problems(path: Path, census: dict | None, generated_links=None,
                             without=frozenset()) -> tuple[dict, list[dict]]:
    """load_zones plus the generated links it did not use.

    Generated links are validated like curated ones (plus an int `from` and a source naming
    openmap) and added after them. Not added:
    * a link whose source names a source in `without` ({type: "generated-link-removed", sources});
    * a link from or to a zone zones.toml does not define ({type: "generated-link-dropped"});
    * a link whose (to, kind) the source zone has as a curated link or lists in its
      `drop_generated = [[to, "kind"], ...]` (intended, not listed).
    """
    raw = read_toml(path).get("zones") or {}
    zones, drops = {}, {}
    for key, z in raw.items():
        try:
            map_id = int(key)
        except ValueError:
            raise ValueError(f"zone key {key!r} is not a uiMapID") from None
        where = f"zone {map_id}"
        if census is not None and map_id not in census["maps"]:
            raise ValueError(f"{where} ({z.get('name')}) is not in the census")
        for field in ("name", "faction", "live", "complete"):
            if field not in z:
                raise ValueError(f"{where}: missing {field}")
        if "continent" in z:   # optional: a zone the census puts on no continent (Zephras Isle) has none
            _int(z["continent"], where, "continent")
        for lvl in ("min_level", "max_level"):
            if lvl in z:
                _int(z[lvl], where, lvl)
        _one_of(z["faction"], ZONE_FACTIONS, where, "faction")
        if "kind" in z:
            _one_of(z["kind"], ZONE_KINDS, where, "kind")
        cmap = (census or {}).get("maps", {}).get(map_id) or {}
        out = {"name": z["name"], "continent": z.get("continent"), "faction": z["faction"],
               "live": z["live"], "complete": z["complete"],
               "yards": cmap.get("yards"), "rect": cmap.get("rect"), "links": []}
        for lvl in ("min_level", "max_level", "kind"):
            if lvl in z:
                out[lvl] = z[lvl]
        for link in z.get("links") or []:
            out["links"].append(_link(link, f"{where} link to {link.get('to')}"))
        drops[map_id] = _drop_generated(z, where)
        zones[map_id] = out
    for map_id, z in zones.items():
        for link in z["links"]:
            if link["to"] not in zones:
                raise ValueError(f"zone {map_id}: link target {link['to']} is not a zone in {path}")

    problems = []
    curated = {map_id: {(l["to"], l["kind"]) for l in z["links"]} for map_id, z in zones.items()}
    rows, removed = load_generated_links(generated_links, without)
    problems.extend(removed)
    for src, link in rows:
        if src not in zones or link["to"] not in zones:
            missing = [m for m in (src, link["to"]) if m not in zones]
            problems.append({"type": "generated-link-dropped", "from": src, "to": link["to"], "kind": link["kind"],
                             "label": link["label"], "reason": f"not in zones.toml: {missing}"})
            continue
        if (link["to"], link["kind"]) in curated[src] | drops[src]:
            continue
        zones[src]["links"].append(link)
    return zones, problems


def _dungeon(d: dict, where: str) -> dict:
    for field in ("name", "entrance", "min_level", "max_level", "group_size", "faction", "live", "quests"):
        if field not in d:
            raise ValueError(f"{where}: missing {field}")
    _one_of(d["faction"], DUNGEON_FACTIONS, where, "faction")
    ent = d["entrance"]
    if not isinstance(ent, list) or len(ent) != 3 or not isinstance(ent[0], int) or isinstance(ent[0], bool):
        raise ValueError(f"{where}: entrance must be [mapID, x, y]")
    _coord(ent[1], f"{where} entrance")
    _coord(ent[2], f"{where} entrance")
    quests = d["quests"]
    if not isinstance(quests, list) or not all(isinstance(q, int) and not isinstance(q, bool) for q in quests):
        raise ValueError(f"{where}: every quest id must be an int")
    return {"name": d["name"], "entrance": list(ent), "min_level": d["min_level"],
            "max_level": d["max_level"], "group_size": d["group_size"], "faction": d["faction"],
            "live": d["live"], "quests": list(quests), "source": CURATED_SOURCE}


def load_dungeons(path: Path, generated=None, without=frozenset(), quests_generated=None) -> dict[str, dict]:
    """{key: {name, entrance [mapID, x, y], min_level, max_level, group_size, faction, live, quests, source}}.

    generated: {key: dungeon} (or the path of dungeons.generated.toml); see load_dungeons_with_problems.
    quests_generated: {key: {quests}} (or the path of dungeons.quests.generated.toml): quest lists for generated dungeons.
    """
    return load_dungeons_with_problems(path, generated, without, quests_generated)[0]


def load_dungeons_with_problems(path: Path, generated=None, without=frozenset(),
                                quests_generated=None) -> tuple[dict, list[dict]]:
    """load_dungeons plus the generated dungeons `without` removed.

    Generated dungeons are validated like dungeons.toml (plus a source naming openmap).
    One is added unless dungeons.toml has its key or its name (name_key), or any
    source it names is in `without` ({type: "generated-dungeon-removed", key, sources}): a
    dungeon is never kept with only part of its sources. A generated dungeon's quests come from
    quests_generated (by key); dungeons.toml entries are never touched by it.
    """
    quest_lists = _generated(quests_generated, "dungeons") or {}
    raw = read_toml(path).get("dungeons") or {}
    dungeons = {key: _dungeon(d, f"dungeon {key}") for key, d in raw.items()}
    names = {name_key(d["name"]) for d in dungeons.values()}
    problems = []
    for key, d in (_generated(generated, "dungeons") or {}).items():
        where = f"generated dungeon {key}"
        entry = _dungeon(d, where)
        sources = _generated_source(d, where)
        entry["source"] = d["source"]
        if set(sources) & set(without):
            problems.append({"type": "generated-dungeon-removed", "key": key, "name": entry["name"],
                             "sources": sorted(set(sources) & set(without))})
            continue
        if key not in dungeons and name_key(entry["name"]) not in names:
            listed = (quest_lists.get(key) or {}).get("quests")
            if listed is not None:
                _dungeon({**d, "quests": listed}, f"generated quests for {key}")
                entry["quests"] = list(listed)
            dungeons[key] = entry
    return dungeons, problems
