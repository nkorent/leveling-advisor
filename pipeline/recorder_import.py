"""Importer for in-game recorder exports (``LA1J:`` / ``LA1Z:`` strings from ``/advisor export``).

Pipeline: ``decode_export`` -> ``import_exports`` (stores ``data/recorder/<sha1>.json``) ->
``aggregate_recorder`` (raw per-source aggregates) -> ``load_recorder`` (merge-ready, agreed values).

Rule above all: under-counting agreement is fine, over-counting is not. The recorder store is
account-wide and cumulative, so exports from one account are near-supersets of each other. Payloads
are therefore grouped into *sources* (connected components sharing a details observation
``(questID, at)``) and agreement counts sources, never payloads.

Input is untrusted (public releases will accept player submissions): sizes are capped, types are
never trusted, and output file names are only ``<sha1>.json``.
"""
from __future__ import annotations

import base64
import hashlib
import json
import math
import sys
import zlib
from collections import Counter
from pathlib import Path

MAX_INPUT_CHARS = 2_000_000
MAX_DECOMPRESSED = 10 * 1024 * 1024
GIVER_RADIUS = 5.0          # map units (0-100 coordinates)
MAX_LEVEL = 70

last_conflicts: list[dict] = []   # giver disagreements found by the latest load_recorder call
last_skipped: list[str] = []      # unreadable stored payload files (names) of the latest read


# ---------------------------------------------------------------- decoding

def _int_keys(value):
    """Digit-string object keys become ints, recursively."""
    if isinstance(value, dict):
        return {(int(k) if isinstance(k, str) and k.isascii() and k.isdigit() else k): _int_keys(v)
                for k, v in value.items()}
    if isinstance(value, list):
        return [_int_keys(v) for v in value]
    return value


def _inflate(data: bytes) -> bytes:
    for wbits in (zlib.MAX_WBITS, -zlib.MAX_WBITS):      # zlib wrapper, then raw deflate
        d = zlib.decompressobj(wbits)
        try:
            out = d.decompress(data, MAX_DECOMPRESSED)
        except zlib.error:
            continue
        if d.unconsumed_tail or (len(out) >= MAX_DECOMPRESSED and not d.eof):
            raise ValueError(f"export decompresses to more than {MAX_DECOMPRESSED} bytes")
        if not d.eof:
            raise ValueError("export is truncated (incomplete compressed stream)")
        return out
    raise ValueError("export is not valid zlib or raw deflate data")


def _validated(payload) -> dict:
    if not isinstance(payload, dict):
        raise ValueError("export payload is not a JSON object")
    v = payload.get("v")
    if type(v) is not int or v != 1:
        raise ValueError(f"unsupported export version: {v!r}")
    if not isinstance(payload.get("recorder"), dict):
        raise ValueError("export has no recorder table")
    return payload


def decode_export(s: str) -> dict:
    """Decode one ``LA1J:`` / ``LA1Z:`` export string into its payload (digit keys as ints)."""
    if not isinstance(s, str):
        raise ValueError("export must be a string")
    if len(s) > MAX_INPUT_CHARS:
        raise ValueError(f"export is longer than {MAX_INPUT_CHARS} characters")
    s = s.strip()
    prefix, sep, body = s.partition(":")
    if not sep or prefix not in ("LA1J", "LA1Z"):
        raise ValueError("unknown export prefix (expected LA1J: or LA1Z:)")
    try:
        data = base64.b64decode("".join(body.split()), validate=True)
        if prefix == "LA1Z":
            data = _inflate(data)
        payload = json.loads(data.decode("utf-8"))
        return _validated(_int_keys(payload))
    except RecursionError:
        raise ValueError("export JSON is nested too deeply") from None


def import_exports(texts: list[str], out_dir: Path, stats: dict | None = None) -> list[Path]:
    """Decode each string and store it as ``out_dir/<sha1 of the raw string>.json``.

    Returns the newly written paths. Duplicates (same sha1) are skipped, undecodable strings are
    skipped; ``stats`` (optional) receives ``imported`` / ``duplicate`` / ``rejected`` counts.
    """
    out_dir = Path(out_dir)
    counts = {"imported": 0, "duplicate": 0, "rejected": 0}
    written: list[Path] = []
    for raw in texts:
        try:
            payload = decode_export(raw)
        except ValueError:
            counts["rejected"] += 1
            continue
        path = out_dir / f"{hashlib.sha1(raw.strip().encode('utf-8')).hexdigest()}.json"
        if path.exists():
            counts["duplicate"] += 1
            continue
        out_dir.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name(path.name + ".tmp")
        tmp.write_text(json.dumps(payload, sort_keys=False, ensure_ascii=False), encoding="utf-8")
        tmp.replace(path)
        written.append(path)
        counts["imported"] += 1
    if stats is not None:
        stats.update(counts)
    return written


# ---------------------------------------------------------------- aggregation

def agreed(values: list):
    """Most common value when it appears at least twice and is not tied with another such value."""
    if not values:
        return None
    ranked = Counter(values).most_common()
    value, count = ranked[0]
    if count < 2 or (len(ranked) > 1 and ranked[1][1] == count):
        return None
    return value


MAX_ID = 2**31 - 1
MAX_XP = 1_000_000


def _is_int(v) -> bool:
    return type(v) is int


def _id(v):
    return v if _is_int(v) and 1 <= v <= MAX_ID else None


_qid = _id


def _level(v):
    return v if _is_int(v) and 1 <= v <= MAX_LEVEL else None


def _xp(v):
    return v if _is_int(v) and 1 <= v <= MAX_XP else None


def _coord(v):
    if type(v) in (int, float) and math.isfinite(v) and 0 <= v <= 100:
        return float(v)
    return None


def _id_list(v) -> list[int]:
    if not isinstance(v, list):          # the Lua encoder writes an empty list as {}
        return []
    return [i for i in v if _id(i) is not None]


def _dict(v) -> dict:
    return v if isinstance(v, dict) else {}


def _extract(payload: dict) -> dict:
    """One payload's observations: {'obs': {(qid, at)}, 'fresh': int, 'q': {qid: fields}}."""
    rec = payload["recorder"]
    quests: dict[int, dict] = {}

    def slot(qid):
        return quests.setdefault(qid, {"xp": {}, "level": None, "giver": None,
                                       "choices": None, "rewards": None})

    for qid, by_level in _dict(rec.get("xp")).items():
        if _qid(qid) is None:
            continue
        if isinstance(by_level, list):     # Lua tables keyed 1..n export as arrays
            by_level = {i: v for i, v in enumerate(by_level, 1)}
        for lvl, xp in _dict(by_level).items():
            if _level(lvl) is not None and _xp(xp) is not None:
                slot(qid)["xp"][lvl] = xp
    for qid, lvl in _dict(rec.get("levels")).items():
        if _qid(qid) is not None and _level(lvl) is not None:
            slot(qid)["level"] = lvl
    obs, fresh = set(), 0
    acc = rec.get("accepted")
    for e in acc if isinstance(acc, list) else ():     # [questID, at] (Recorder.lua) or {questID, at}
        qid, at = (e[0], e[1]) if isinstance(e, list) and len(e) == 2 else (
            (e.get("questID"), e.get("at")) if isinstance(e, dict) else (None, None))
        if _qid(qid) is not None and _is_int(at) and at >= 0:
            obs.add((qid, at))
    for qid, d in _dict(rec.get("details")).items():
        if _qid(qid) is None or not isinstance(d, dict):
            continue
        at = d.get("at")
        if not _is_int(at) or at < 0:
            continue                      # cannot be tied to a source: ignore the entry entirely
        obs.add((qid, at))
        fresh = max(fresh, at)
        s = slot(qid)
        if _level(d.get("level")) is not None and _xp(d.get("xp")) is not None:
            s["xp"].setdefault(d["level"], d["xp"])
        npc, map_id = d.get("npcID"), d.get("mapID")
        x, y = _coord(d.get("x")), _coord(d.get("y"))
        if _id(npc) is not None and _id(map_id) is not None and x is not None and y is not None:
            s["giver"] = {"npc": npc, "map_id": map_id, "x": x, "y": y}
        s["choices"] = _id_list(d.get("choices"))
        s["rewards"] = _id_list(d.get("rewards"))
    return {"obs": obs, "fresh": fresh, "q": quests}


def _read_payloads(dir: Path) -> list[tuple[str, dict]]:
    """(sha1, extracted observations) per readable stored payload, sorted by file name. The names of
    the files it cannot read go to last_skipped."""
    last_skipped.clear()
    dir = Path(dir)
    if not dir.is_dir():
        return []
    out = []
    for path in sorted(dir.glob("*.json")):
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
            payload = _validated(_int_keys(raw))
            canon = json.dumps(raw["recorder"], sort_keys=True)
        except (OSError, ValueError, RecursionError):
            last_skipped.append(path.name)
            continue
        ex = _extract(payload)
        ex["canon"] = canon
        out.append((path.stem, ex))
    return out


def _sources(items: list[tuple[str, dict]]) -> list[list[tuple[str, dict]]]:
    """Group payloads into sources: components linked by a shared (questID, at) observation."""
    parent = list(range(len(items)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    seen: dict[tuple, int] = {}
    for i, (_, ex) in enumerate(items):
        for key in ex["obs"]:
            j = seen.setdefault(key, i)
            parent[find(i)] = find(j)
    canon: dict[str, int] = {}
    for i, (_, ex) in enumerate(items):            # identical recorder tables: one source
        parent[find(i)] = find(canon.setdefault(ex["canon"], i))
    groups: dict[int, list] = {}
    for i, item in enumerate(items):
        groups.setdefault(find(i), []).append(item)
    return list(groups.values())


def _freshest(group, pick):
    """Value of the payload with the greatest freshness (ties: smallest sha1) that has one."""
    best = None
    for sha, ex in group:
        value = pick(ex)
        if value is None:
            continue
        rank = (-ex["fresh"], sha)
        if best is None or rank < best[0]:
            best = (rank, value)
    return None if best is None else best[1]


def aggregate_recorder(dir: Path) -> dict[int, dict]:
    """Raw aggregates per quest, one value per SOURCE:
    ``{qid: {xp: {level: [xp]}, level: [questLevel], giver: [{npc,map_id,x,y}],
    choices: [[ids]], rewards: [[ids]], reports: n}}``."""
    agg: dict[int, dict] = {}
    for group in _sources(_read_payloads(dir)):
        qids = {q for _, ex in group for q in ex["q"]}
        for qid in qids:
            a = agg.setdefault(qid, {"xp": {}, "level": [], "giver": [], "choices": [],
                                     "rewards": [], "reports": 0})
            a["reports"] += 1
            levels = {lvl for _, ex in group for lvl in ex["q"].get(qid, {}).get("xp", {})}
            for lvl in sorted(levels):
                v = _freshest(group, lambda ex: ex["q"].get(qid, {}).get("xp", {}).get(lvl))
                a["xp"].setdefault(lvl, []).append(v)
            for field in ("level", "giver", "choices", "rewards"):
                v = _freshest(group, lambda ex: ex["q"].get(qid, {}).get(field))
                if v is not None:
                    a[field].append(v)
    return agg


def _agreed_giver(qid: int, givers: list[dict]):
    ranked = Counter((g["npc"], g["map_id"]) for g in givers).most_common()
    if not ranked:
        return None
    if ranked[0][1] < 2 or (len(ranked) > 1 and ranked[1][1] == ranked[0][1]):
        if len(ranked) > 1:
            last_conflicts.append({"quest": qid, "reason": "ambiguous giver", "givers": ranked})
        return None
    (npc, map_id), _ = ranked[0]
    pts = [(g["x"], g["y"]) for g in givers if (g["npc"], g["map_id"]) == (npc, map_id)]
    mx, my = sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)
    if any(math.hypot(x - mx, y - my) > GIVER_RADIUS for x, y in pts):
        last_conflicts.append({"quest": qid, "reason": "giver coordinates disagree", "points": pts})
        return None
    return {"npc": npc, "map_id": map_id, "x": round(mx, 1), "y": round(my, 1)}


def load_recorder(dir: Path) -> dict[int, dict]:
    """Merge-ready agreed data: ``{qid: {"xp": {playerLevel: xp}, "level": int|None, "giver": dict|None}}``.

    A quest appears only when at least one of xp / level / giver is agreed by >= 2 sources.
    """
    last_conflicts.clear()
    result: dict[int, dict] = {}
    for qid, a in sorted(aggregate_recorder(dir).items()):
        xp = {lvl: v for lvl, vals in sorted(a["xp"].items()) if (v := agreed(vals)) is not None}
        level = agreed(a["level"])
        giver = _agreed_giver(qid, a["giver"])
        if xp or level is not None or giver is not None:
            result[qid] = {"xp": xp, "level": level, "giver": giver}
    return result


# ---------------------------------------------------------------- CLI

def cmd_import_recorder(args) -> int:
    try:
        text = sys.stdin.read() if args.file == "-" else Path(args.file).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as e:
        print(f"import-recorder: cannot read {args.file}: {e}", file=sys.stderr)
        return 2
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    stats: dict = {}
    import_exports(lines, Path(args.out), stats)
    print(f"import-recorder: {stats['imported']} imported, {stats['duplicate']} duplicate, "
          f"{stats['rejected']} rejected -> {args.out}", flush=True)
    return 0
