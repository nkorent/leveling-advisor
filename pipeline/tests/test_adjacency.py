"""Rect adjacency: walk links computed from census rects, used only for the gap report."""
import pytest

from pipeline.adjacency import adjacency_gaps, walk_links


def _map(name, rect, continent=1, map_type=3):
    return {"name": name, "mapType": map_type, "parent": continent, "yards": [1000, 600],
            "continent": continent, "rect": rect}


# rect = [left, right, top, bottom] on the continent, 0..1
CENSUS = {"maps": {
    1: {"name": "Cont", "mapType": 2, "parent": 947, "yards": None, "continent": 1, "rect": [0, 1, 0, 1]},
    10: _map("A", [0.1, 0.3, 0.1, 0.3]),
    11: _map("B", [0.3, 0.5, 0.2, 0.4]),          # shares A's east edge over y 0.2-0.3
    12: _map("C", [0.1, 0.3, 0.3005, 0.5]),       # below A, edge within tolerance
    13: _map("D", [0.5, 0.7, 0.4, 0.6]),          # touches B only at a corner (no overlap)
    14: _map("E", [0.3, 0.4, 0.295, 0.6]),        # shares only 0.005 of A's east edge
    20: _map("F", [0.3, 0.5, 0.2, 0.4], continent=2),   # same rect as B, other continent
    21: _map("Bg", [0.3, 0.5, 0.5, 0.6], continent=1, map_type=6),
}}


def _link(links, a, b):
    return next(l for l in links if l["from"] == a and l["to"] == b)


def test_shared_edge_with_midpoint_in_each_zones_own_coordinates():
    links = walk_links(CENSUS, zone_ids={10, 11})
    ab, ba = _link(links, 10, 11), _link(links, 11, 10)
    assert ab["kind"] == "walk" and ab["label"] == "walk east"
    assert (ab["x"], ab["y"]) == (100.0, 75.0)       # A: x at its east edge, y = (0.25-0.1)/0.2
    assert ba["label"] == "walk west" and (ba["x"], ba["y"]) == (0.0, 25.0)
    assert len(links) == 2


def test_edge_tolerance_and_direction_labels_vertical():
    links = walk_links(CENSUS, zone_ids={10, 12})
    ac, ca = _link(links, 10, 12), _link(links, 12, 10)
    assert ac["label"] == "walk south" and ac["y"] == 100.0 and ac["x"] == 50.0
    assert ca["label"] == "walk north" and ca["y"] == 0.0 and ca["x"] == 50.0


def test_corner_touch_short_segment_and_other_continent_are_not_adjacent():
    links = walk_links(CENSUS, zone_ids={11, 13, 14, 20, 10})
    pairs = {(l["from"], l["to"]) for l in links}
    assert (11, 13) not in pairs and (13, 11) not in pairs      # corner only
    assert (20, 11) not in pairs and (11, 20) not in pairs      # other continent
    assert (14, 10) not in pairs                                 # shared segment 0.005 < 1% of continent


def test_default_covers_zones_only_not_continents_or_battlegrounds():
    pairs = {(l["from"], l["to"]) for l in walk_links(CENSUS)}
    assert (10, 11) in pairs
    assert not {p for p in pairs if 1 in p or 21 in p}


def _zones(*links):
    z = {10: {"name": "A", "links": []}, 11: {"name": "B", "links": []}, 12: {"name": "C", "links": []}}
    for src, to, kind in links:
        z[src]["links"].append({"to": to, "kind": kind})
    return z


def test_gap_report_lists_unlinked_pairs_once():
    gaps = adjacency_gaps(CENSUS, _zones())
    assert {(g["a"], g["b"]) for g in gaps} == {(10, 11), (10, 12), (11, 12)}
    g = gaps[0]
    assert g["a_name"] == "A" and g["b_name"] == "B"
    assert g["a_to_b"]["label"] == "walk east" and g["b_to_a"]["label"] == "walk west"


def test_gap_report_excludes_pairs_already_linked_either_way():
    gaps = adjacency_gaps(CENSUS, _zones((10, 11, "walk"), (12, 10, "walk"), (11, 12, "walk")))
    assert gaps == []


def test_gap_report_ignores_non_walk_links():
    gaps = adjacency_gaps(CENSUS, _zones((10, 11, "boat")))
    assert (10, 11) in {(g["a"], g["b"]) for g in gaps}


def test_gap_report_skips_cities_and_battlegrounds_and_unknown_zones():
    zones = _zones()
    zones[11]["kind"] = "city"
    assert {(g["a"], g["b"]) for g in adjacency_gaps(CENSUS, zones)} == {(10, 12)}
