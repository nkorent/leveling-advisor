"""Rect adjacency between zones, from the census. Used for a gap report only.

A rectangle cannot see a mountain wall, so these links are never added to the data: they are
compared with the generated and curated walk links, and the pairs that are rect-adjacent
but unlinked go to data/build/adjacency-gaps.json for a human to add or drop in the TOML.

A census ``rect`` is [left, right, top, bottom] on the zone's continent, each 0..1.
"""
from __future__ import annotations

EDGE_TOLERANCE = 0.002     # two edges are "equal" when they differ by at most this
MIN_SHARED = 0.01          # shared segment must be longer than 1% of the continent


def _zone_ids(census: dict) -> set[int]:
    return {m for m, z in census["maps"].items() if z.get("mapType") == 3 and z.get("rect")}


def _overlap(lo1: float, hi1: float, lo2: float, hi2: float) -> tuple[float, float] | None:
    lo, hi = max(lo1, lo2), min(hi1, hi2)
    return (lo, hi) if hi - lo > MIN_SHARED else None


def _local(value: float, lo: float, hi: float) -> float:
    return round((value - lo) / (hi - lo) * 100, 1)


def _edge_link(src: int, dst: int, a: list, b: list, direction: str, seg: tuple[float, float], horizontal: bool) -> dict:
    """Link from zone a (rect `a`) across the edge it shares with b; (x, y) in a's own 0-100 coordinates."""
    mid = (seg[0] + seg[1]) / 2
    left, right, top, bottom = a
    if horizontal:   # edge runs along x: crossing at the top or bottom edge
        x, y = _local(mid, left, right), 100.0 if direction == "south" else 0.0
    else:
        x, y = 100.0 if direction == "east" else 0.0, _local(mid, top, bottom)
    return {"from": src, "to": dst, "kind": "walk", "x": x, "y": y, "label": f"walk {direction}"}


def walk_links(census: dict, zone_ids=None) -> list[dict]:
    """Walk links ({from, to, kind, x, y, label}, both directions) between rect-adjacent zones.

    Two zones on the same continent are adjacent when their rects share an edge segment longer than
    1% of the continent: one's right equals the other's left (or bottom equals top) within 0.002,
    with overlapping ranges on the other axis. The crossing is the midpoint of the shared segment,
    in each zone's own 0-100 coordinates. zone_ids: the zones to consider (default: every map of
    type Zone with a rect).
    """
    maps = census["maps"]
    ids = sorted(_zone_ids(census) if zone_ids is None else {m for m in zone_ids if maps.get(m, {}).get("rect")})
    links = []
    for i, a_id in enumerate(ids):
        for b_id in ids[i + 1:]:
            a, b = maps[a_id], maps[b_id]
            if a.get("continent") is None or a.get("continent") != b.get("continent"):
                continue
            al, ar, at, ab = a["rect"]
            bl, br, bt, bb = b["rect"]
            for (a_edge, b_edge, da, db, horizontal, span) in (
                (ar, bl, "east", "west", False, _overlap(at, ab, bt, bb)),
                (al, br, "west", "east", False, _overlap(at, ab, bt, bb)),
                (ab, bt, "south", "north", True, _overlap(al, ar, bl, br)),
                (at, bb, "north", "south", True, _overlap(al, ar, bl, br)),
            ):
                if span and abs(a_edge - b_edge) <= EDGE_TOLERANCE:
                    links.append(_edge_link(a_id, b_id, a["rect"], b["rect"], da, span, horizontal))
                    links.append(_edge_link(b_id, a_id, b["rect"], a["rect"], db, span, horizontal))
    return links


def adjacency_gaps(census: dict, zones: dict[int, dict]) -> list[dict]:
    """Rect-adjacent leveling-zone pairs with no walk link between them, in either direction.

    zones: load_zones output (curated and generated links merged). Cities, battlegrounds and maps
    that are not in zones are left out. One entry per pair, lower uiMapID first:
    {a, b, a_name, b_name, a_to_b, b_to_a} where the two are the computed links (x, y, label).
    """
    leveling = {m for m, z in zones.items() if not z.get("kind")}
    linked = {(m, l["to"]) for m, z in zones.items() for l in z.get("links") or [] if l.get("kind") == "walk"}
    computed = {(l["from"], l["to"]): l for l in walk_links(census, leveling)}
    gaps = []
    for (a, b), link in sorted(computed.items()):
        if a > b or (a, b) in linked or (b, a) in linked:
            continue
        gaps.append({"a": a, "b": b, "a_name": zones[a]["name"], "b_name": zones[b]["name"],
                     "a_to_b": {k: link[k] for k in ("x", "y", "label")},
                     "b_to_a": {k: computed[(b, a)][k] for k in ("x", "y", "label")}})
    return gaps
