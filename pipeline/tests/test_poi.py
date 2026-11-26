"""Reference POI import (OpenMap + the census): transport links and dungeon references."""
import json
import tomllib
from pathlib import Path

import pytest

from pipeline.__main__ import main
from pipeline.curated import load_dungeons, load_zones
from pipeline.poi import (CONTINENT_BOUNDS, ZoneHints, check_bounds, dungeons_toml, links_toml, load_openmap_places,
                          load_zone_hints, locate, read_census, reference_dungeons, transport_links,
                          world_to_continent)

HERE = Path(__file__).parent
FIX = HERE / "fixtures" / "poi"
ROOT = HERE.parents[1]
VENDOR_OPENMAP = ROOT / "data" / "vendor" / "openmap" / "Places.lua"
CENSUS = ROOT / "data" / "census" / "maps.json"
CURATED = ROOT / "data" / "curated"

KALIMDOR_YARDS = [36799.8125, 24533.19921875]          # the real census values
EASTERN_KINGDOMS_YARDS = [35199.8984375, 23466.599609375]


def types(problems):
    return [p["type"] for p in problems]


def census_maps(**zones):
    """A census {"maps": ...} with both continents (real yards) plus the given zones."""
    maps = {1414: {"name": "Kalimdor", "mapType": 2, "parent": 947, "yards": list(KALIMDOR_YARDS),
                   "continent": 1414, "rect": [0, 1, 0, 1]},
            1415: {"name": "Eastern Kingdoms", "mapType": 2, "parent": 947, "yards": list(EASTERN_KINGDOMS_YARDS),
                   "continent": 1415, "rect": [0, 1, 0, 1]}}
    for key, (name, continent, rect) in zones.items():
        maps[int(key.removeprefix("m"))] = {"name": name, "mapType": 3, "parent": continent, "yards": [1000, 666],
                                            "continent": continent, "rect": rect}
    return {"maps": maps, "areas": {}, "here": []}


def world(continent, mx, my):
    """The world point (x, y yards) at continent-normalized (mx, my): the inverse of world_to_continent."""
    left, right, top, bottom = CONTINENT_BOUNDS[continent]
    return top - my * (top - bottom), left - mx * (left - right)


def zone(name, continent, rect, live=True, kind=None):
    z = {"name": name, "continent": continent, "rect": rect, "live": live}
    if kind:
        z["kind"] = kind
    return z


# ---------------------------------------------------------------- bounds gate and conversion

def test_world_to_continent_formulas():
    left, right, top, bottom = CONTINENT_BOUNDS[1414]
    assert world_to_continent(1414, top, left) == (0.0, 0.0)            # world X points north, Y west
    assert world_to_continent(1414, bottom, right) == (1.0, 1.0)
    mx, my = world_to_continent(1414, 4249.1, 748.4)    # (left - y) / (left - right), (top - x) / (top - bottom)
    assert mx == pytest.approx((17066.6 - 748.4) / (17066.6 + 19733.2))
    assert my == pytest.approx((12799.9 - 4249.1) / (12799.9 + 11733.3))
    assert world_to_continent(1415, 7466.6, 16000.0) == (0.0, 0.0)
    assert CONTINENT_BOUNDS == {1414: (17066.6, -19733.2, 12799.9, -11733.3),
                                1415: (16000.0, -19199.9, 7466.6, -15999.9)}


def test_bounds_gate_accepts_the_census_yards():
    report = check_bounds(census_maps())
    assert set(report) == {1414, 1415}
    assert all(abs(d) <= 1.0 for r in report.values() for d in r["difference"])


@pytest.mark.parametrize("continent, yards", [(1414, [36801.0, 24533.2]), (1414, [36799.8, 24531.0]),
                                              (1415, [35199.9, 23468.0]), (1415, None)])
def test_bounds_gate_rejects_a_bad_yards_value(continent, yards):
    census = census_maps()
    census["maps"][continent]["yards"] = yards
    with pytest.raises(ValueError, match=str(continent)):
        check_bounds(census)


def test_bounds_gate_needs_both_continents():
    census = census_maps()
    del census["maps"][1415]
    with pytest.raises(ValueError, match="1415"):
        check_bounds(census)


# ---------------------------------------------------------------- zone choice

ZONES = {
    1: zone("Big", 1414, [0.0, 0.5, 0.0, 0.5]),
    2: zone("Small", 1414, [0.2, 0.3, 0.2, 0.3]),                       # inside Big
    3: zone("Town", 1414, [0.4, 0.45, 0.4, 0.45], kind="city"),         # inside Big
    4: zone("Dead", 1414, [0.6, 0.9, 0.6, 0.9], live=False),
    5: zone("East", 1415, [0.0, 1.0, 0.0, 1.0]),
    6: zone("Arena", 1414, [0, 0, 0, 0], kind="battleground"),
    7: zone("Isle", None, None),
}


def test_one_live_zone_rect_gives_the_zone():
    place, problem = locate(ZONES, 1414, 0.1, 0.05)
    assert problem is None and place == (1, 20.0, 10.0, "rect")


def test_a_city_rect_wins():
    place, problem = locate(ZONES, 1414, 0.42, 0.43)
    assert problem is None and place == (3, 40.0, 60.0, "city")


def test_a_hint_beats_the_city_rect():
    hints = ZoneHints({"transports": {"Town - Elsewhere": [1]}})
    place, problem = locate(ZONES, 1414, 0.42, 0.43, hints, "transports", ["Town - Elsewhere"])
    assert problem is None and place == (1, 84.0, 86.0, "hint")
    assert hints.unused() == []


def test_a_hint_outside_the_point_leaves_the_city_rule():
    """A route hint names the zone of another end of the route: here the city rect still decides."""
    hints = ZoneHints({"transports": {"Town - Elsewhere": [5]}})
    place, problem = locate(ZONES, 1414, 0.42, 0.43, hints, "transports", ["Town - Elsewhere"])
    assert problem is None and place == (3, 40.0, 60.0, "city")
    assert hints.unused() == [{"type": "unused-hint", "table": "transports", "name": "Town - Elsewhere"}]


def test_point_outside_every_rect_is_a_problem_never_snapped():
    for mx, my in ((0.55, 0.05), (0.95, 0.95)):
        place, problem = locate(ZONES, 1414, mx, my)
        assert place is None and problem == {"type": "no-zone", "candidates": []}


def test_not_live_zone_is_no_candidate():
    place, problem = locate(ZONES, 1414, 0.7, 0.7)                     # only Dead's rect
    assert place is None and problem["type"] == "no-zone"


def test_overlapping_zone_rects_without_a_hint_are_ambiguous():
    place, problem = locate(ZONES, 1414, 0.25, 0.25)
    assert place is None
    assert problem == {"type": "ambiguous-zone", "candidates": [
        {"map": 1, "name": "Big", "x": 50.0, "y": 50.0}, {"map": 2, "name": "Small", "x": 50.0, "y": 50.0}]}


def test_hint_picks_among_overlapping_rects_and_is_validated():
    hints = ZoneHints({"instances": {"Deep Caves": [2]}})
    place, problem = locate(ZONES, 1414, 0.25, 0.22, hints, "instances", ["Deep Caves"])
    assert problem is None and place == (2, 50.0, 20.0, "hint")
    assert hints.unused() == []

    order = ZoneHints({"transports": {"A - B": [5, 1, 2]}})            # first hinted zone that contains it
    place, _ = locate(ZONES, 1414, 0.25, 0.22, order, "transports", ["A - B"])
    assert place[0] == 1

    outside = ZoneHints({"instances": {"Deep Caves": [5, 4]}})         # neither rect contains the point
    place, problem = locate(ZONES, 1414, 0.25, 0.22, outside, "instances", ["Deep Caves"])
    assert place is None and problem["type"] == "hint-outside" and problem["hint"] == ["East", "Dead"]
    assert [c["map"] for c in problem["candidates"]] == [1, 2]


def test_hint_not_consulted_when_the_rect_decides():
    hints = ZoneHints({"instances": {"Deep Caves": [2]}})
    place, _ = locate(ZONES, 1414, 0.1, 0.05, hints, "instances", ["Deep Caves"])
    assert place[0] == 1
    assert hints.unused() == [{"type": "unused-hint", "table": "instances", "name": "Deep Caves"}]


def test_conflicting_hints_for_one_point():
    hints = ZoneHints({"instances": {"Old Abbey - Garden": [1], "Old Abbey": [2]}})
    place, problem = locate(ZONES, 1414, 0.25, 0.25, hints, "instances", ["Old Abbey - Garden", "Old Abbey"])
    assert place is None and problem["type"] == "conflicting-hints"


# ---------------------------------------------------------------- hints file

def test_zone_hints_file_resolves_census_names(tmp_path):
    census = census_maps(m1440=("Ashenvale", 1414, [0.4, 0.5, 0.3, 0.4]), m1428=("Burning Steppes", 1415, None),
                         m1427=("Searing Gorge", 1415, None))
    p = tmp_path / "openmap_zone_hints.toml"
    p.write_text('[instances]\n"Blackfathom Deeps" = "Ashenvale"   # Zoram Strand\n'
                 '"Lower Blackrock Spire" = ["Burning Steppes", "Searing Gorge"]\n'
                 '[transports]\n"Rut\'theran - Auberdine" = "Ashenvale"\n', encoding="utf-8")
    hints = load_zone_hints(p, census)
    assert hints.tables == {"instances": {"Blackfathom Deeps": [1440], "Lower Blackrock Spire": [1428, 1427]},
                            "transports": {"Rut'theran - Auberdine": [1440]}}


@pytest.mark.parametrize("text, match", [
    ('[instances]\n"X" = "Nowhere"\n', "Nowhere"),                     # not a census zone name: no uiMapIDs from memory
    ('[instances]\n"X" = "Kalimdor"\n', "Kalimdor"),                    # a continent, not a zone
    ('[instances]\n"X" = 1440\n', "zone name"),
    ('[instances]\n"X" = []\n', "zone name"),
    ('[dungeons]\n"X" = "Ashenvale"\n', "dungeons"),
])
def test_zone_hints_file_rejects_what_it_cannot_resolve(tmp_path, text, match):
    census = census_maps(m1440=("Ashenvale", 1414, [0.4, 0.5, 0.3, 0.4]))
    p = tmp_path / "hints.toml"
    p.write_text(text, encoding="utf-8")
    with pytest.raises(ValueError, match=match):
        load_zone_hints(p, census)


# ---------------------------------------------------------------- transports

TZONES = {
    10: zone("Portside", 1414, [0.1, 0.3, 0.1, 0.3]),
    11: zone("Harbor Town", 1414, [0.5, 0.55, 0.5, 0.55], kind="city"),
    12: zone("Plains", 1414, [0.4, 0.7, 0.4, 0.7]),
    20: zone("Eastshore", 1415, [0.1, 0.4, 0.1, 0.4]),
}


def row(kind, route, a, b, faction=None):
    (c1, mx1, my1), (c2, mx2, my2) = a, b
    cont = {0: 1415, 1: 1414}
    x1, y1 = world(cont[c1], mx1, my1) if c1 in cont else (mx1, my1)
    x2, y2 = world(cont[c2], mx2, my2) if c2 in cont else (mx2, my2)
    r = {"kind": kind, "route": route, "continent": c1, "x": x1, "y": y1, "to_continent": c2, "to_x": x2, "to_y": y2}
    if faction:
        r["faction"] = faction
    return r


PORT, EAST, PLAINS, HARBOR = (1, 0.2, 0.2), (0, 0.25, 0.25), (1, 0.6, 0.6), (1, 0.52, 0.52)


def test_transport_links_kind_label_faction_and_coordinates():
    places = {"transports": [row("boat", "Port - East", PORT, EAST), row("boat", "Port - East", EAST, PORT),
                             row("zeppelin", "Plains - East", PLAINS, EAST),
                             row("zeppelin", "Harbor - Port", HARBOR, PORT),
                             row("airship", "Port - East", PORT, EAST),
                             row("boat", "Charter", PORT, EAST, faction="Alliance")]}
    links, problems = transport_links(places, TZONES)
    got = [(l["from"], l["to"], l["kind"], l["label"], l["faction"]) for l in links]
    assert got == [(10, 20, "boat", "boat to Eastshore", None), (20, 10, "boat", "boat to Portside", None),
                   (12, 20, "zeppelin", "zeppelin to Eastshore", "Horde"),        # zeppelins are Horde (classic)
                   (11, 10, "zeppelin", "zeppelin to Portside", "Horde"),         # the city rect wins over Plains
                   (10, 20, "zeppelin", "airship to Eastshore", None),            # airship -> zeppelin
                   (10, 20, "boat", "boat to Eastshore", "Alliance")]             # OpenMap's faction field
    assert links[0] == {"from": 10, "to": 20, "kind": "boat", "x": 50.0, "y": 50.0, "label": "boat to Eastshore",
                        "faction": None, "source": "openmap"}
    assert (links[2]["x"], links[2]["y"]) == (66.7, 66.7)                          # departure, on Plains' own map
    missing = [(p["from"], p["to"], p["kind"]) for p in problems if p["type"] == "missing-reverse"]
    assert missing == [(12, 20, "zeppelin"), (11, 10, "zeppelin"), (10, 20, "zeppelin")]
    assert set(types(problems)) == {"missing-reverse"}


def test_unusable_transport_rows_go_to_problems():
    places = {"transports": [row("airship", "Port - Isle", PORT, (2991, 1848.3, 569.1)),     # not on the census
                             row("airship", "Port - Isle", (2991, 1848.3, 569.1), PORT),
                             row("boat", "Short Hop", PORT, (1, 0.15, 0.25)),                # both ends in Portside
                             row("boat", "Off The Map", PORT, (1, 0.95, 0.95)),
                             row("gryphon", "Port - East", PORT, EAST)]}
    links, problems = transport_links(places, TZONES)
    assert links == []
    assert types(problems) == ["unknown-continent", "unknown-continent", "self-link", "no-zone", "unknown-kind"]
    assert problems[0]["end"] == "to" and problems[0]["continent"] == 2991 and problems[0]["route"] == "Port - Isle"
    assert problems[1]["end"] == "from"
    assert problems[2]["map"] == 10 and problems[2]["route"] == "Short Hop"
    assert problems[3]["end"] == "to"


def test_transport_hint_by_route_name():
    zones = {**TZONES, 13: zone("Hills", 1414, [0.15, 0.35, 0.15, 0.35])}          # overlaps Portside
    places = {"transports": [row("boat", "Port - East", PORT, EAST), row("boat", "Port - East", EAST, PORT)]}
    links, problems = transport_links(places, zones)
    assert links == [] and types(problems) == ["ambiguous-zone", "ambiguous-zone"]
    hints = ZoneHints({"transports": {"Port - East": [10]}})
    links, problems = transport_links(places, zones, hints)
    assert [(l["from"], l["to"]) for l in links] == [(10, 20), (20, 10)] and problems == []


# ---------------------------------------------------------------- dungeons

DZONES = {
    1440: zone("Ashenvale", 1414, [0.40, 0.50, 0.30, 0.40]),
    1420: zone("Tirisfal Glades", 1415, [0.45, 0.50, 0.15, 0.25]),
    1422: zone("Western Plaguelands", 1415, [0.46, 0.56, 0.17, 0.30]),
    1458: zone("Undercity", 1415, [0.44, 0.45, 0.24, 0.25], kind="city"),
    1437: zone("Wetlands", 1415, [0.45, 0.50, 0.45, 0.50]),
    1445: zone("Dustwallow Marsh", 1414, [0.55, 0.65, 0.65, 0.75]),
}


def test_reference_dungeons_from_openmap():
    places = load_openmap_places(FIX / "openmap_places.lua")
    hints = ZoneHints({"instances": {"Old Abbey": [1420]}})
    dungeons, problems = reference_dungeons(places, DZONES, hints, {"CAVE": "Deep Caves"})
    caves = dungeons["CAVE"]                                            # a curated key for the same name is kept
    assert caves == {"name": "Deep Caves", "entrance": [1440, 43.4, 48.5], "min_level": 22, "max_level": 32,
                     "group_size": 5, "faction": "Both", "live": True, "quests": [], "source": "openmap"}
    assert dungeons["OAG"]["name"] == "Old Abbey - Garden" and dungeons["OAG"]["entrance"] == [1420, 55.2, 44.9]
    assert (dungeons["OAV"]["min_level"], dungeons["OAV"]["max_level"]) == (36, 44)
    assert dungeons["SR"]["entrance"] == [1458, 72.5, 11.4] and dungeons["SR"]["faction"] == "Horde"
    assert "Big Lair" not in {d["name"] for d in dungeons.values()}       # raids are skipped
    assert types(problems) == ["no-zone", "no-entrance"]
    assert problems[0]["names"] == ["Lost Vault"] and problems[1]["name"] == "Unplaced Den"
    assert hints.unused() == []


def test_dungeon_without_hint_or_levels_or_known_map_reported():
    places = {"instances": [
        {"continent": 0, "x": 2892.2, "y": -811.3, "map": None, "members": [
            {"id": 189, "name": "Old Abbey - Garden", "raid": False, "min_level": 30, "max_level": 38}]},
        {"continent": None, "x": 0.5, "y": 0.5, "map": 9999, "members": [
            {"id": 1, "name": "Far Place", "raid": False, "min_level": 1, "max_level": 5}]},
        {"continent": None, "x": 0.5, "y": 0.5, "map": 1440, "members": [
            {"id": 2, "name": "No Levels", "raid": False, "min_level": None, "max_level": None}]},
        {"continent": 2991, "x": 1.0, "y": 1.0, "map": None, "members": [
            {"id": 3, "name": "Isle Den", "raid": False, "min_level": 1, "max_level": 5}]}],
        "unplaced": [{"id": 0, "name": "Big Raid", "raid": True, "min_level": 60, "max_level": 60}]}
    dungeons, problems = reference_dungeons(places, DZONES)
    assert dungeons == {}
    assert types(problems) == ["ambiguous-zone", "unknown-map", "no-levels", "unknown-continent"]
    assert [c["name"] for c in problems[0]["candidates"]] == ["Tirisfal Glades", "Western Plaguelands"]


def test_blackfathom_deeps_keeps_its_key():
    members = [("Blackfathom Deeps", 24, 32), ("Blackrock Depths", 52, 60), ("Stratholme", 58, 60),
               ("Scholomance", 58, 60)]
    places = {"instances": [{"continent": None, "x": 0.1 * i, "y": 0.5, "map": 1440, "members": [
        {"id": i, "name": n, "raid": False, "min_level": lo, "max_level": hi}]} for i, (n, lo, hi) in
        enumerate(members, 1)]}
    dungeons, _ = reference_dungeons(places, DZONES)
    assert {k: d["name"] for k, d in dungeons.items()} == {
        "BFD": "Blackfathom Deeps", "BD": "Blackrock Depths", "S": "Scholomance", "S2": "Stratholme"}
    again, _ = reference_dungeons(places, DZONES)
    assert again == dungeons
    taken, _ = reference_dungeons(places, DZONES, seed_keys={"BD": "Somewhere Else"})
    assert "BD" not in taken and taken["BD2"]["name"] == "Blackrock Depths" and taken["BFD"]


def test_dungeons_toml_quotes_keys_that_are_not_bare():
    d = {"name": "X", "entrance": [1, 2.0, 3.0], "min_level": 1, "max_level": 2, "group_size": 5,
         "faction": "Both", "live": True, "quests": [], "source": "openmap"}
    text = dungeons_toml({"A B": d, "C.D": d, 'E"F': d, "OK_1-2": d})
    assert '[dungeons."A B"]' in text and '[dungeons."C.D"]' in text and '[dungeons."E\\"F"]' in text
    assert "[dungeons.OK_1-2]" in text
    assert set(tomllib.loads(text)["dungeons"]) == {"A B", "C.D", 'E"F', "OK_1-2"}


# ---------------------------------------------------------------- loaders

def test_openmap_places_parsed():
    places = load_openmap_places(FIX / "openmap_places.lua")
    first = places["instances"][0]
    assert (first["continent"], first["x"], first["y"], first["map"]) == (1, 4249.1, 748.4, None)
    assert first["members"] == [{"id": 48, "name": "Deep Caves", "raid": False, "min_level": 22, "max_level": 32}]
    spot = places["instances"][3]
    assert (spot["continent"], spot["x"], spot["y"], spot["map"]) == (None, 0.725, 0.114, 1458)
    assert [m["name"] for m in places["instances"][1]["members"]] == ["Old Abbey - Garden", "Old Abbey - Vault"]
    assert places["instances"][2]["members"][0]["raid"] is True
    assert places["unplaced"] == [{"id": 0, "name": "Unplaced Den", "raid": False, "min_level": 10, "max_level": 15}]
    boat, back = places["transports"]
    assert boat == {"kind": "boat", "route": "Saltmere - Mossvale", "continent": 0, "x": -3905.2, "y": -585.8,
                    "to_continent": 1, "to_x": -4016.4, "to_y": -4740.6}
    assert back["faction"] == "Alliance" and back["continent"] == 1


def test_openmap_transport_faction_validated(tmp_path):
    p = tmp_path / "places.lua"
    p.write_text('local _, ns = ...\nns.MapPlaces = { transports = {\n'
                 '  { "boat", "R", 0, 1.0, 2.0, 1, 3.0, 4.0, faction = "Neutral" } } }\n', encoding="utf-8")
    with pytest.raises(ValueError, match="faction"):
        load_openmap_places(p)
    p.write_text('local _, ns = ...\nns.MapPlaces = { transports = {\n'
                 '  { "boat", "R", 0, 1.0, 2.0, 1, 3.0, 4.0, colour = "red" } } }\n', encoding="utf-8")
    with pytest.raises(ValueError, match="colour"):
        load_openmap_places(p)


def test_openmap_sandboxed(tmp_path):
    p = tmp_path / "evil.lua"
    p.write_text('local _, ns = ...\nos.execute("echo no")\nns.MapPlaces = {instances = {}}\n', encoding="utf-8")
    with pytest.raises(ValueError, match="os"):
        load_openmap_places(p)


def test_read_census_keys_are_ints(tmp_path):
    p = tmp_path / "maps.json"
    p.write_text(json.dumps({"maps": {"1414": {"name": "Kalimdor"}}, "areas": {}, "here": []}), encoding="utf-8")
    assert read_census(p)["maps"] == {1414: {"name": "Kalimdor"}}


# ---------------------------------------------------------------- merge into curated

ZONES_TOML = '''
[zones.1439]
name = "Darkshore"
continent = 1414
faction = "Alliance"
live = true
complete = false

[[zones.1439.links]]
to = 1440
kind = "walk"
x = 50.0
y = 90.0
label = "walk south"

[zones.1440]
name = "Ashenvale"
continent = 1414
faction = "Contested"
live = true
complete = false
'''


def gen_link(frm, to, kind="boat", x=10.0, y=10.0, label="boat to Ashenvale", faction=None):
    link = {"from": frm, "to": to, "kind": kind, "x": x, "y": y, "label": label, "source": "openmap"}
    if faction:
        link["faction"] = faction
    return link


def test_generated_links_merge(tmp_path):
    from pipeline.curated import load_zones_with_problems
    p = tmp_path / "zones.toml"
    p.write_text(ZONES_TOML, encoding="utf-8")
    generated = [gen_link(1439, 1440, kind="walk", x=43.3, y=94.0, label="walk south"),   # curated (1440, walk) wins
                 gen_link(1439, 1440, faction="Alliance"),
                 gen_link(1440, 1439, x=29.1, y=14.8, label="boat to Darkshore"),
                 gen_link(1440, 1500, label="boat to Elsewhere"),                         # target not in zones.toml
                 gen_link(1500, 1439)]                                                    # source not in zones.toml
    zones, problems = load_zones_with_problems(p, None, generated)
    assert [(l["to"], l["kind"], l["x"], l["faction"]) for l in zones[1439]["links"]] == [
        (1440, "walk", 50.0, None), (1440, "boat", 10.0, "Alliance")]
    assert [(l["to"], l["kind"], l["x"], l["y"]) for l in zones[1440]["links"]] == [(1439, "boat", 29.1, 14.8)]
    assert set(zones[1440]["links"][0]) == {"to", "kind", "x", "y", "label", "faction", "source"}
    assert zones[1440]["links"][0]["source"] == "openmap" and zones[1439]["links"][0]["source"] == "curated"
    dropped = [(d["from"], d["to"]) for d in problems]
    assert dropped == [(1440, 1500), (1500, 1439)] and {d["type"] for d in problems} == {"generated-link-dropped"}
    assert load_zones(p, None, generated) == zones                                       # same return type as before
    assert load_zones(p, None) == load_zones(p, None, None)


def test_generated_links_validated_like_curated(tmp_path):
    p = tmp_path / "zones.toml"
    p.write_text(ZONES_TOML, encoding="utf-8")
    with pytest.raises(ValueError, match="kind"):
        load_zones(p, None, [gen_link(1439, 1440, kind="teleport")])
    with pytest.raises(ValueError, match="0-100"):
        load_zones(p, None, [gen_link(1439, 1440, x=101.0)])
    with pytest.raises(ValueError, match="faction"):
        load_zones(p, None, [gen_link(1439, 1440, faction="Contested")])
    with pytest.raises(ValueError, match="from"):
        load_zones(p, None, [{k: v for k, v in gen_link(1439, 1440).items() if k != "from"}])
    with pytest.raises(ValueError, match="label"):
        load_zones(p, None, [{k: v for k, v in gen_link(1439, 1440).items() if k != "label"}])


def test_generated_links_read_from_file(tmp_path):
    p = tmp_path / "zones.toml"
    p.write_text(ZONES_TOML, encoding="utf-8")
    g = tmp_path / "links.generated.toml"
    g.write_text('[[links]]\nfrom = 1440\nto = 1439\nkind = "boat"\nx = 29.1\ny = 14.8\nlabel = "boat to Darkshore"\n'
                 'source = "openmap"\n', encoding="utf-8")
    zones = load_zones(p, None, g)
    assert zones[1440]["links"] == [{"to": 1439, "kind": "boat", "x": 29.1, "y": 14.8, "label": "boat to Darkshore",
                                     "faction": None, "source": "openmap"}]


DUNGEONS_TOML = '''
[dungeons.SEED]
name = "Seed Caves"
entrance = [1440, 50.0, 50.0]
min_level = 20
max_level = 30
group_size = 5
faction = "Both"
live = true
quests = [1]
'''


def gen_dungeon(name, entrance=(1440, 16.5, 11.0), faction="Both"):
    return {"name": name, "entrance": list(entrance), "min_level": 24, "max_level": 32, "group_size": 5,
            "faction": faction, "live": True, "quests": [], "source": "openmap"}


def test_generated_dungeons_merge(tmp_path):
    p = tmp_path / "dungeons.toml"
    p.write_text(DUNGEONS_TOML, encoding="utf-8")
    generated = {"SEED": gen_dungeon("Something Else"),             # same key: curated wins
                 "SC": gen_dungeon("seed  caves"),                  # same name (case/space-insensitive): curated wins
                 "RFC": gen_dungeon("Ragefire Chasm", (1454, 53.0, 48.9), "Horde")}
    d = load_dungeons(p, generated)
    assert set(d) == {"SEED", "RFC"}
    assert d["SEED"]["name"] == "Seed Caves" and d["SEED"]["quests"] == [1]
    assert d["RFC"] == {"name": "Ragefire Chasm", "entrance": [1454, 53.0, 48.9], "min_level": 24, "max_level": 32,
                        "group_size": 5, "faction": "Horde", "live": True, "quests": [], "source": "openmap"}
    assert d["SEED"]["source"] == "curated"
    with pytest.raises(ValueError, match="faction"):
        load_dungeons(p, {"X": gen_dungeon("X", faction="Neutral")})
    with pytest.raises(ValueError, match="0-100"):
        load_dungeons(p, {"X": gen_dungeon("X", entrance=(1, 101.0, 1.0))})
    assert load_dungeons(p) == load_dungeons(p, None)


def test_load_curated_passes_generated_files(tmp_path):
    from pipeline.build import load_curated
    (tmp_path / "zones.toml").write_text(ZONES_TOML, encoding="utf-8")
    (tmp_path / "dungeons.toml").write_text(DUNGEONS_TOML, encoding="utf-8")
    zones, dungeons = load_curated(tmp_path, None)
    assert len(zones[1440]["links"]) == 0 and set(dungeons) == {"SEED"}
    (tmp_path / "links.generated.toml").write_text(
        '[[links]]\nfrom = 1440\nto = 1439\nkind = "boat"\nx = 29.1\ny = 14.8\nlabel = "boat to Darkshore"\n'
        'source = "openmap"\n'
        '[[links]]\nfrom = 1440\nto = 1500\nkind = "boat"\nx = 1.0\ny = 1.0\nlabel = "boat to Elsewhere"\n'
        'source = "openmap"\n',
        encoding="utf-8")
    (tmp_path / "dungeons.generated.toml").write_text(
        '[dungeons.RFC]\nname = "Ragefire Chasm"\nentrance = [1454, 53.0, 48.9]\nmin_level = 13\nmax_level = 18\n'
        'group_size = 5\nfaction = "Horde"\nlive = true\nquests = []\nsource = "openmap"\n',
        encoding="utf-8")
    notes = []
    zones, dungeons = load_curated(tmp_path, None, notes)
    assert [l["to"] for l in zones[1440]["links"]] == [1439] and set(dungeons) == {"SEED", "RFC"}
    assert len(notes) == 1 and "1 generated link" in notes[0]


def test_drop_generated_in_zones_toml(tmp_path):
    p = tmp_path / "zones.toml"
    p.write_text(ZONES_TOML.replace('complete = false\n\n[[zones.1439.links]]',
                                    'complete = false\ndrop_generated = [[1440, "boat"]]\n\n[[zones.1439.links]]'),
                 encoding="utf-8")
    generated = [gen_link(1439, 1440, faction="Alliance"),
                 gen_link(1439, 1440, x=20.0, faction="Alliance"),
                 gen_link(1439, 1440, kind="zeppelin", label="zeppelin to Ashenvale", faction="Horde"),
                 gen_link(1440, 1439, label="boat to Darkshore")]
    zones, problems = __import__("pipeline.curated", fromlist=["x"]).load_zones_with_problems(p, None, generated)
    assert [(l["to"], l["kind"]) for l in zones[1439]["links"]] == [(1440, "walk"), (1440, "zeppelin")]
    assert [(l["to"], l["kind"]) for l in zones[1440]["links"]] == [(1439, "boat")]   # only zone 1439 drops it
    assert problems == [] and "drop_generated" not in zones[1439]


@pytest.mark.parametrize("value, match", [("[[1440]]", "drop_generated"), ('[["1440", "walk"]]', "drop_generated"),
                                          ('[[1440, "teleport"]]', "kind"), ('"1440"', "drop_generated"),
                                          ('[[1440, "walk", 3]]', "drop_generated")])
def test_drop_generated_validated(tmp_path, value, match):
    p = tmp_path / "zones.toml"
    p.write_text(ZONES_TOML.replace('complete = false\n\n[[zones.1439.links]]',
                                    f'complete = false\ndrop_generated = {value}\n\n[[zones.1439.links]]'),
                 encoding="utf-8")
    with pytest.raises(ValueError, match=match):
        load_zones(p, None)


def test_generated_rows_need_a_known_source(tmp_path):
    z = tmp_path / "zones.toml"
    z.write_text(ZONES_TOML, encoding="utf-8")
    d = tmp_path / "dungeons.toml"
    d.write_text(DUNGEONS_TOML, encoding="utf-8")
    no_source = {k: v for k, v in gen_link(1440, 1439).items() if k != "source"}
    for source in (None, "somewhere"):
        row = no_source if source is None else dict(no_source, source=source)
        with pytest.raises(ValueError, match="source"):
            load_zones(z, None, [row])
    with pytest.raises(ValueError, match="source"):
        load_dungeons(d, {"X": {k: v for k, v in gen_dungeon("X").items() if k != "source"}})


def test_without_openmap_removes_generated_rows(tmp_path):
    from pipeline.curated import load_dungeons_with_problems, load_zones_with_problems
    z = tmp_path / "zones.toml"
    z.write_text(ZONES_TOML, encoding="utf-8")
    d = tmp_path / "dungeons.toml"
    d.write_text(DUNGEONS_TOML, encoding="utf-8")
    links = [gen_link(1439, 1440), gen_link(1440, 1439, label="boat to Darkshore")]
    zones, problems = load_zones_with_problems(z, None, links, without={"openmap"})
    assert [l["source"] for zz in zones.values() for l in zz["links"]] == ["curated"]   # curated never dropped
    assert [(p["type"], p["sources"]) for p in problems] == [("generated-link-removed", ["openmap"])] * 2
    dungeons, problems = load_dungeons_with_problems(d, {"RFC": gen_dungeon("Ragefire Chasm")}, without={"openmap"})
    assert set(dungeons) == {"SEED"} and [p["key"] for p in problems] == ["RFC"]


def write_census_build(tmp_path, with_generated=True):
    from pipeline.tests.test_build import census_fixture, cli_paths, write_oog
    from pipeline.tests.test_merge import oq
    write_oog(tmp_path / "oog", [oq(1)])
    census = census_fixture()
    (tmp_path / "census").mkdir()
    (tmp_path / "census" / "maps.json").write_text(json.dumps({"maps": {str(k): v for k, v in census["maps"].items()},
                                                               "areas": {}, "here": []}), encoding="utf-8")
    cur = tmp_path / "curated"
    cur.mkdir()
    (cur / "zones.toml").write_text(ZONES_TOML, encoding="utf-8")
    (cur / "dungeons.toml").write_text(DUNGEONS_TOML, encoding="utf-8")
    if with_generated:
        (cur / "links.generated.toml").write_text(
            '[[links]]\nfrom = 1439\nto = 1440\nkind = "boat"\nx = 30.0\ny = 40.0\nlabel = "boat to Ashenvale"\n'
            'source = "openmap"\n'
            '[[links]]\nfrom = 1440\nto = 1439\nkind = "zeppelin"\nx = 29.1\ny = 14.8\nlabel = "zeppelin to Darkshore"\n'
            'faction = "Horde"\nsource = "openmap"\n', encoding="utf-8")
        (cur / "dungeons.generated.toml").write_text(
            '[dungeons.RFC]\nname = "Ragefire Chasm"\nentrance = [1440, 52.6, 49.0]\nmin_level = 13\n'
            'max_level = 18\ngroup_size = 5\nfaction = "Both"\nlive = true\nquests = []\nsource = "openmap"\n',
            encoding="utf-8")
    return cli_paths(tmp_path)


def emitted(tmp_path):
    from pipeline.tests.test_build import load_data
    data = load_data(tmp_path / "Data")
    links = {m: [(l.to, l.kind) for l in data.zones[m].links.values()] if data.zones[m].links else []
             for m in (1439, 1440)}
    return links, sorted(data.dungeons.keys()), json.loads((tmp_path / "report.json").read_text(encoding="utf-8"))


def test_build_without_openmap_drops_its_generated_rows(tmp_path):
    paths = write_census_build(tmp_path / "all")
    assert main(["build", "--without", "questie", *paths]) == 0
    links, dungeons, _ = emitted(tmp_path / "all")
    assert sorted(links[1439]) == [(1440, "boat"), (1440, "walk")] and dungeons == ["RFC", "SEED"]
    assert links[1440] == [(1439, "zeppelin")]
    for name in ("Zones.lua", "Dungeons.lua"):                     # source stays out of the Lua (Contract A)
        text = (tmp_path / "all" / "Data" / name).read_text(encoding="utf-8")
        assert "source" not in text and "openmap" not in text and "curated" not in text

    paths = write_census_build(tmp_path / "noom")
    assert main(["build", "--without", "questie", "openmap", *paths]) == 0
    links, dungeons, report = emitted(tmp_path / "noom")
    assert links == {1439: [(1440, "walk")], 1440: []} and dungeons == ["SEED"]
    assert "openmap: 2 generated link(s) and 1 generated dungeon(s) removed (--without openmap)" in report["notes"]


def test_only_known_sources(tmp_path, capsys):
    from pipeline.merge import REMOVABLE_SOURCES
    from pipeline.curated import GENERATED_SOURCES
    assert REMOVABLE_SOURCES == {"questie", "recorder", "openmap"} and GENERATED_SOURCES == ("openmap",)
    paths = write_census_build(tmp_path)
    with pytest.raises(SystemExit) as e:
        main(["build", "--without", "bogus", *paths])
    err = capsys.readouterr().err
    assert e.value.code == 2 and "invalid choice: 'bogus'" in err
    with pytest.raises(SystemExit) as e:
        main(["poi", "--bogus", "x.lua"])
    err = capsys.readouterr().err
    assert e.value.code == 2 and "unrecognized arguments: --bogus" in err


# ---------------------------------------------------------------- CLI

CLI_ZONES = {"m1440": ("Ashenvale", 1414, [0.40, 0.50, 0.30, 0.40]),
             "m1420": ("Tirisfal Glades", 1415, [0.45, 0.50, 0.15, 0.25]),
             "m1422": ("Western Plaguelands", 1415, [0.46, 0.56, 0.17, 0.30]),
             "m1458": ("Undercity", 1415, [0.44, 0.45, 0.24, 0.25]),
             "m1437": ("Wetlands", 1415, [0.45, 0.50, 0.45, 0.50]),
             "m1445": ("Dustwallow Marsh", 1414, [0.55, 0.65, 0.65, 0.75])}


def write_poi_inputs(tmp_path, census=None):
    census = census or census_maps(**CLI_ZONES)
    census_path = tmp_path / "census" / "maps.json"
    census_path.parent.mkdir(parents=True)
    census_path.write_text(json.dumps({"maps": {str(k): v for k, v in census["maps"].items()}, "areas": {},
                                       "here": []}), encoding="utf-8")
    curated = tmp_path / "curated"
    curated.mkdir()
    zones = ""
    for key, (name, continent, _) in CLI_ZONES.items():
        kind = 'kind = "city"\n' if name == "Undercity" else ""
        zones += (f'[zones.{key[1:]}]\nname = "{name}"\ncontinent = {continent}\nfaction = "Contested"\n'
                  f'live = true\ncomplete = false\n{kind}\n')
    (curated / "zones.toml").write_text(zones, encoding="utf-8")
    (curated / "dungeons.toml").write_text(DUNGEONS_TOML.replace("Seed Caves", "Deep Caves"), encoding="utf-8")
    (curated / "openmap_zone_hints.toml").write_text(
        '[instances]\n"Old Abbey" = "Tirisfal Glades"   # wings share one entrance\n'
        '[transports]\n"Nowhere Route" = "Wetlands"\n', encoding="utf-8")
    problems = tmp_path / "build" / "poi-problems.json"
    return ["poi", "--openmap", str(FIX / "openmap_places.lua"), "--census", str(census_path),
            "--curated", str(curated), "--problems", str(problems)], curated, problems


def test_poi_cli_writes_files(tmp_path, capsys):
    argv, curated, problems_path = write_poi_inputs(tmp_path)
    assert main(argv) == 0
    links_text = (curated / "links.generated.toml").read_text(encoding="utf-8")
    dungeons_text = (curated / "dungeons.generated.toml").read_text(encoding="utf-8")
    for text in (links_text, dungeons_text):
        header = text.splitlines()[0]
        assert header.startswith("# Generated by `python -m pipeline poi` from OpenMap "
                                 "6c2299f6e1f9bdce1bbd92145f84a05b0c6c05a7 (MIT) and the in-game census")
    links = tomllib.loads(links_text)["links"]
    assert links == [{"from": 1437, "to": 1445, "kind": "boat", "x": 42.4, "y": 69.2,
                      "label": "boat to Dustwallow Marsh", "source": "openmap"},          # no faction key for "both"
                     {"from": 1445, "to": 1437, "kind": "boat", "x": 42.6, "y": 35.5, "label": "boat to Wetlands",
                      "faction": "Alliance", "source": "openmap"}]
    dungeons = tomllib.loads(dungeons_text)["dungeons"]
    assert set(dungeons) == {"SEED", "OAG", "OAV", "SR"}                    # the curated key for "Deep Caves"
    assert dungeons["SEED"]["entrance"] == [1440, 43.4, 48.5]
    assert dungeons["OAG"]["entrance"] == [1420, 55.2, 44.9]                # by the hint (Tirisfal and WPL overlap)
    report = json.loads(problems_path.read_text(encoding="utf-8"))
    assert {"links", "dungeons", "hints", "bounds", "counts"} <= set(report)
    assert report["hints"] == [{"type": "unused-hint", "table": "transports", "name": "Nowhere Route"}]
    assert report["counts"]["hints_used"] == 1
    assert types(report["dungeons"]) == ["no-zone", "no-entrance"]
    out = capsys.readouterr().out
    assert "links" in out and "dungeons" in out and "problems" in out and "hints" in out
    assert not list(curated.glob("*.tmp")) and not list(problems_path.parent.glob("*.tmp"))

    # what was written is accepted by the curated loaders
    z = load_zones(curated / "zones.toml", None, curated / "links.generated.toml")
    assert [l["to"] for l in z[1437]["links"]] == [1445] and [l["to"] for l in z[1445]["links"]] == [1437]
    d = load_dungeons(curated / "dungeons.toml", curated / "dungeons.generated.toml")
    assert d["SEED"]["source"] == "curated" and d["OAG"]["source"] == "openmap"


def test_poi_cli_missing_input_or_failed_gate_exits_2(tmp_path, capsys):
    argv, curated, _ = write_poi_inputs(tmp_path / "a")
    argv[argv.index("--openmap") + 1] = str(tmp_path / "nope.lua")
    assert main(argv) == 2
    assert "nope.lua" in capsys.readouterr().err
    assert not (curated / "links.generated.toml").exists()

    bad = census_maps(**CLI_ZONES)
    bad["maps"][1414]["yards"] = [36700.0, 24533.2]
    argv, curated, _ = write_poi_inputs(tmp_path / "b", bad)
    assert main(argv) == 2
    assert "1414" in capsys.readouterr().err
    assert not (curated / "links.generated.toml").exists()


# ---------------------------------------------------------------- real data (anchors)

REAL = VENDOR_OPENMAP.is_file() and CENSUS.is_file()


@pytest.fixture(scope="module")
def real():
    census = read_census(CENSUS)
    check_bounds(census)
    zones = load_zones(CURATED / "zones.toml", census)
    hints = load_zone_hints(CURATED / "openmap_zone_hints.toml", census)
    places = load_openmap_places(VENDOR_OPENMAP)
    links, link_problems = transport_links(places, zones, hints)
    dungeons, dungeon_problems = reference_dungeons(places, zones, hints, {})
    return {"census": census, "zones": zones, "hints": hints, "places": places, "links": links,
            "link_problems": link_problems, "dungeons": dungeons, "dungeon_problems": dungeon_problems}


def dock(real, continent, x, y):
    """The zone (uiMapID) an OpenMap transport point lands in; the point must be one of OpenMap's."""
    rows = real["places"]["transports"]
    assert any((r["continent"], r["x"], r["y"]) == (continent, x, y) for r in rows) or \
        any((r["to_continent"], r["to_x"], r["to_y"]) == (continent, x, y) for r in rows)
    route = next(r["route"] for r in rows if (r["continent"], r["x"], r["y"]) == (continent, x, y))
    cont = {0: 1415, 1: 1414}[continent]
    place, problem = locate(real["zones"], cont, *world_to_continent(cont, x, y), ZoneHints(real["hints"].tables),
                            "transports", [route])
    assert problem is None, problem
    return place[0]


pytestmark_real = pytest.mark.skipif(not REAL, reason="OpenMap Places.lua or data/census/maps.json not present")


@pytestmark_real
def test_anchor_blackfathom_deeps_in_ashenvale(real):
    bfd = real["dungeons"]["BFD"]
    assert bfd["name"] == "Blackfathom Deeps" and bfd["entrance"][0] == 1440
    assert 10 <= bfd["entrance"][1] <= 20 and 8 <= bfd["entrance"][2] <= 18
    assert (bfd["min_level"], bfd["max_level"]) == (24, 32)


@pytestmark_real
def test_anchor_docks(real):
    assert dock(real, 1, -1005.6, -3841.6) == 1413                     # Ratchet: The Barrens
    assert dock(real, 0, -14277.7, 582.9) == 1434                      # Booty Bay: Stranglethorn Vale
    for x, y in ((-3905.2, -585.8), (-3709.5, -575.1)):                # Menethil: Wetlands
        assert dock(real, 0, x, y) == 1437
    for x, y in ((6594.4, 759.8), (6406.2, 823.1), (6548.3, 942.2)):   # Auberdine: Darkshore
        assert dock(real, 1, x, y) == 1439
    assert dock(real, 1, 8532.0, 1023.7) in (1438, 1457)               # Rut'theran: Teldrassil (or Darnassus)
    for x, y in ((1360.9, -4631.3), (1318.1, -4658.0)):                # Orgrimmar's zeppelin towers, outside
        assert dock(real, 1, x, y) == 1411                              # the gate: Durotar (a hint beats the city rect)
    for x, y in ((-12464.0, 231.6), (-12406.9, 211.8)):                # Grom'gol: Stranglethorn Vale
        assert dock(real, 0, x, y) == 1434


@pytestmark_real
def test_real_links_and_dungeons(real):
    links = real["links"]
    kinds = {l["kind"] for l in links}
    assert kinds <= {"boat", "zeppelin"} and links
    assert all(l["faction"] == "Horde" for l in links if l["kind"] == "zeppelin")
    assert all(l["faction"] is None for l in links if l["kind"] == "boat")
    pairs = {(l["from"], l["to"], l["kind"]) for l in links}
    assert {(1434, 1413, "boat"), (1413, 1434, "boat"), (1437, 1445, "boat"), (1445, 1437, "boat"),
            (1438, 1439, "boat"), (1439, 1438, "boat")} <= pairs
    assert not any(l["from"] == l["to"] for l in links)
    selfs = [p for p in real["link_problems"] if p["type"] == "self-link"]
    assert [p["route"] for p in selfs] == ["Feathermoon - Feralas"] * 2
    airships = [p for p in real["link_problems"] if p["type"] == "unknown-continent"]
    assert len(airships) == 4 and {p["continent"] for p in airships} == {2991}
    names = {d["name"] for d in real["dungeons"].values()}
    assert {"Dire Maul - North", "Dire Maul - East", "Dire Maul - West", "Scarlet Monastery - Library",
            "Ragefire Chasm", "Stormwind Stockade"} <= names
    assert not names & {"Molten Core", "Blackwing Lair", "Onyxia's Lair", "Zul'Gurub"}
    assert [d["faction"] for d in real["dungeons"].values() if d["name"] == "Ragefire Chasm"] == ["Horde"]
    assert [d["faction"] for d in real["dungeons"].values() if d["name"] == "Stormwind Stockade"] == ["Alliance"]
    assert all(d["source"] == "openmap" for d in real["dungeons"].values())


@pytestmark_real
def test_real_hints_are_all_needed_and_used(real):
    hints = ZoneHints(real["hints"].tables)
    transport_links(real["places"], real["zones"], hints)
    reference_dungeons(real["places"], real["zones"], hints, {})
    assert hints.unused() == []


@pytestmark_real
def test_committed_generated_files_are_current(real):
    seeds = {k: d["name"] for k, d in load_dungeons(CURATED / "dungeons.toml").items()}
    dungeons, _ = reference_dungeons(real["places"], real["zones"], ZoneHints(real["hints"].tables), seeds)
    assert (CURATED / "links.generated.toml").read_text(encoding="utf-8") == links_toml(real["links"])
    assert (CURATED / "dungeons.generated.toml").read_text(encoding="utf-8") == dungeons_toml(dungeons)
