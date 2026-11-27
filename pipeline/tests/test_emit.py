"""Lua emitter (Task 6): Contract A layout, read back with PUC Lua 5.1 (the WoW client's Lua)."""
import copy
import math
import shutil
import subprocess
from pathlib import Path

import lupa.lua51 as lua51
import pytest

from pipeline.emit import (encode_stub, HEADER, emit_dungeons, emit_meta, emit_npcs, emit_quests, emit_zones,
                           encode_quest, lua_literal)
from pipeline.merge import merge
from pipeline.outofgames import parse_npc
from pipeline.tests.test_merge import FX, fixture_quest, fixture_questie

ROOT = Path(__file__).resolve().parents[2]


def load_lua(*paths):
    """Run each file as the client does, chunk("LevelingAdvisor", ns), into one ns; return ns."""
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    run = lua.eval("""function(src, name, ns)
        local f, err = loadstring(src, name)
        if not f then error(err) end
        f("LevelingAdvisor", ns)
        return ns
    end""")
    ns = lua.table()
    for p in paths:
        run(Path(p).read_text(encoding="utf-8"), "@" + str(p), ns)
    return ns


def lua_values(t):
    return None if t is None else list(t.values())


def luajit():
    """Path of luajit (engine-smoke and check-lua-syntax use it), or None."""
    return shutil.which("luajit") or next(
        (p for p in ("/opt/homebrew/bin/luajit", "/usr/local/bin/luajit") if Path(p).exists()), None)


_MERGED = {}


def merged_4763():
    """Fixture 4763 merged with the Questie fixture (Task 5 output, live map 1439)."""
    if not _MERGED:
        quests, _ = merge({4763: fixture_quest(4763)}, fixture_questie(), {1439})
        _MERGED[4763] = quests[4763]
    return copy.deepcopy(_MERGED[4763])


def mq(qid=100, **kw):
    """A merged quest shaped like pipeline.merge.merge output (no optional data)."""
    q = {
        "id": qid, "name": "Some Quest", "faction": "Alliance", "race_mask": None, "class_mask": None,
        "required_level": 10, "quest_level": 12, "level_source": "game", "zone_map_id": 1439,
        "elite": False, "class_quest": False, "new_in_forever": False, "unverified": False,
        "repeatable": False, "dungeon_quest": False, "group_size": None,
        "giver": {"kind": "npc", "id": 7, "map_id": 1439, "x": 40.0, "y": 50.0},
        "turn_in": {"kind": "npc", "id": 7, "map_id": 1439, "x": 40.0, "y": 50.0},
        "objective_points": [], "objective_text": None,
        "items": {"provided": [], "required": []},
        "rewards": {"choice": [], "fixed": [], "money": None, "rep": [], "spell_id": None},
        "xp": 500, "xp_source": "game", "prereq": {"all": [], "any": []},
        "exclusive_to": None, "breadcrumb_of": None, "chain": None, "dungeon_key": None,
        "changed_in_forever": False, "required_max_level": None, "recorded_xp": None,
        "source_url": "u", "provenance": {},
    }
    q.update(kw)
    return q


def emit_one(tmp_path, q):
    emit_quests({q["id"]: q}, tmp_path / "Quests.lua")
    return load_lua(tmp_path / "Quests.lua").Data.quests[q["id"]]


# ---------------------------------------------------------------- brief tests (amended by the rulings)

def test_quest_round_trip(tmp_path):
    emit_quests({4763: merged_4763()}, tmp_path / "Quests.lua")
    q = load_lua(tmp_path / "Quests.lua").Data.quests[4763]
    assert q[1] == "The Blackwood Corrupted" and q[2] == 1 and q[3] is None
    assert list(q[11].values()) == [1, 3649, 1439, 37.4, 40.1]
    # The brief's `q[7] == 2` predates Task 5: the merge now takes Questie's game level 18
    # over the outof.games reward-level estimate, so levelSource is 1 (game data).
    assert q[17] == 1700 and q[7] == 1
    assert q[9] & 4 == 0                    # not new in Forever
    assert [c[1] for c in q[16].choice.values()] == [15204, 15202, 15203]
    assert q[16].money == 2000
    assert list(q[19].all.values()) == [4762]
    assert q[19].any is None or len(list(q[19].any.values())) == 0


def test_new_unverified_flags(tmp_path):
    q = emit_one(tmp_path, mq(new_in_forever=True, unverified=True))
    assert q[9] == 4 | 8


def test_strings_escaped(tmp_path):
    name = 'Say "Hi"\n'
    text = "back\\slash\ttab\rcr \x01 \x7f Raene’s ]] [[ -- not a comment"
    q = emit_one(tmp_path, mq(name=name, objective_text=text))
    assert q[1] == name and q[14] == text


# ---------------------------------------------------------------- Contract A encoding

def test_full_record_positions(tmp_path):
    q = emit_one(tmp_path, mq(
        900, name="N", faction="Horde", race_mask=2, class_mask=1, required_level=20, quest_level=24,
        level_source="estimate", zone_map_id=1411, group_size=5,
        giver={"kind": "object", "id": 55, "map_id": 1411, "x": 1.04, "y": 99.96},
        turn_in={"kind": "item", "id": 66, "map_id": 1412, "x": 10.0, "y": 20.0},
        objective_points=[{"map_id": 1411, "x": 5.0, "y": 6.0}, {"map_id": 1413, "x": 7.0, "y": 8.0}],
        objective_text="Kill 10 boars.",
        items={"provided": [11, 12], "required": [{"item_id": 13, "count": 4}]},
        rewards={"choice": [{"item_id": 21, "count": 1}], "fixed": [{"item_id": 22, "count": 5}],
                 "money": 150, "rep": [{"faction": "Orgrimmar", "amount": 250}], "spell_id": 777},
        xp=1300, xp_source="recorder", prereq={"all": [1, 2], "any": [3]}, exclusive_to=[4, 5],
        breadcrumb_of=6, chain={"chain_id": 8, "index": 2, "length": 3}, dungeon_key="RFC",
        required_max_level=30))
    assert (q[1], q[2], q[3], q[4], q[5], q[6], q[7], q[8]) == ("N", 2, 2, 1, 20, 24, 2, 1411)
    assert q[10] == 5
    assert lua_values(q[11]) == [2, 55, 1411, 1.0, 100.0]       # coordinates with 1 decimal
    assert lua_values(q[12]) == [3, 66, 1412, 10, 20]
    assert [lua_values(p) for p in q[13].values()] == [[1411, 5, 6], [1413, 7, 8]]
    assert q[14] == "Kill 10 boars."
    assert lua_values(q[15].provided) == [11, 12]
    assert [lua_values(r) for r in q[15].required.values()] == [[13, 4]]
    assert [lua_values(r) for r in q[16].choice.values()] == [[21, 1]]
    assert [lua_values(r) for r in q[16].fixed.values()] == [[22, 5]]
    assert q[16].money == 150 and q[16].spellID == 777
    assert [lua_values(r) for r in q[16].rep.values()] == [["Orgrimmar", 250]]
    assert q[17] == 1300 and q[18] == 3
    assert lua_values(q[19].all) == [1, 2] and lua_values(q[19].any) == [3]
    assert lua_values(q[20]) == [4, 5] and q[21] == 6
    assert lua_values(q[22]) == [8, 2, 3] and q[23] == "RFC" and q[24] == 30


def test_field_24_required_max_level(tmp_path):
    emit_quests({1: mq(1, required_max_level=29), 2: mq(2)}, tmp_path / "Quests.lua")
    quests = load_lua(tmp_path / "Quests.lua").Data.quests
    assert quests[1][24] == 29
    assert quests[2][24] is None
    assert encode_quest(mq(1, required_max_level=29))[23] == 29     # 0-based list index 23 == Lua 24


def test_field_25_unavailable_after(tmp_path):
    """Final review C1: QuestieDB availableUntilCompleted / disabledByQuest (and oog "Not available
    after" links beyond exclusiveTo) as Contract A field 25; empty is nil."""
    emit_quests({1: mq(1, unavailable_after=[1302, 420]), 2: mq(2, unavailable_after=[]), 3: mq(3)},
                tmp_path / "Quests.lua")
    quests = load_lua(tmp_path / "Quests.lua").Data.quests
    assert lua_values(quests[1][25]) == [1302, 420]
    assert quests[2][25] is None and quests[3][25] is None
    assert encode_quest(mq(1, unavailable_after=[7]))[24] == [7]     # 0-based list index 24 == Lua 25


@pytest.mark.parametrize("flag, bit", [("elite", 1), ("class_quest", 2), ("new_in_forever", 4),
                                       ("unverified", 8), ("repeatable", 16), ("dungeon_quest", 32)])
def test_flags_bitfield_each_flag(tmp_path, flag, bit):
    assert emit_one(tmp_path, mq(**{flag: True}))[9] == bit


def test_flags_bitfield_all_and_none(tmp_path):
    flags = ("elite", "class_quest", "new_in_forever", "unverified", "repeatable", "dungeon_quest")
    assert emit_one(tmp_path, mq(**{f: True for f in flags}))[9] == 63
    assert emit_one(tmp_path, mq())[9] == 0


@pytest.mark.parametrize("kind, code", [("npc", 1), ("object", 2), ("item", 3)])
def test_kind_encoding(tmp_path, kind, code):
    place = {"kind": kind, "id": 42, "map_id": 1439, "x": 10.0, "y": 20.0}
    q = emit_one(tmp_path, mq(giver=place, turn_in=dict(place)))
    assert q[11][1] == code and q[12][1] == code


def test_unknown_kind_rejected(tmp_path):
    with pytest.raises(ValueError):
        emit_quests({1: mq(1, giver={"kind": "spell", "id": 1, "map_id": 1, "x": 1.0, "y": 1.0})},
                    tmp_path / "Quests.lua")


@pytest.mark.parametrize("faction, code", [("Alliance", 1), ("Horde", 2), ("Both", 3)])
def test_faction_encoding(tmp_path, faction, code):
    assert emit_one(tmp_path, mq(faction=faction))[2] == code


@pytest.mark.parametrize("source, code", [("game", 1), ("estimate", 2), ("recorder", 3)])
def test_level_and_xp_source_encoding(tmp_path, source, code):
    q = emit_one(tmp_path, mq(level_source=source, xp_source=source))
    assert q[7] == code and q[18] == code


def test_questiedb_xp_source_is_game_data(tmp_path):
    """Contract A has no QuestieDB code: QuestieDB XP (classic tables and trace-observed game
    values) is written as 1, game data, like Questie-filled levels; the report keeps "questiedb"."""
    assert emit_one(tmp_path, mq(xp=700, xp_source="questiedb"))[18] == 1
    with pytest.raises(ValueError):
        emit_quests({1: mq(1, level_source="questiedb")}, tmp_path / "Quests.lua")


def test_unknown_enum_rejected(tmp_path):
    with pytest.raises(ValueError):
        emit_quests({1: mq(1, faction="Neutral")}, tmp_path / "Quests.lua")
    with pytest.raises(ValueError):
        emit_quests({1: mq(1, level_source="guess")}, tmp_path / "Quests.lua")


def test_empty_optional_parts_are_nil(tmp_path):
    q = emit_one(tmp_path, mq(turn_in=None, xp=None, xp_source=None))
    for pos in (3, 4, 10, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24):
        assert q[pos] is None, pos


def test_turn_in_without_coordinates_keeps_kind_and_id(tmp_path):
    q = emit_one(tmp_path, mq(turn_in={"kind": "npc", "id": 9, "map_id": None, "x": None, "y": None}))
    assert (q[12][1], q[12][2], q[12][3], q[12][4], q[12][5]) == (1, 9, None, None, None)


def test_quests_file_layout(tmp_path):
    emit_quests({1: mq(1)}, tmp_path / "Quests.lua")
    lines = (tmp_path / "Quests.lua").read_text(encoding="utf-8").splitlines()
    assert lines[0] == HEADER == "-- Generated by pipeline/emit.py. Do not edit."
    assert lines[1] == "local _, ns = ..."
    assert lines[2] == "ns.Data = ns.Data or {}"


def many_quests(n=20000):
    """n distinct records: more constants than LuaJIT allows in one function (65536)."""
    return {i: mq(i, name=f"Quest {i}", objective_text=f"Text {i}",
                  giver={"kind": "npc", "id": i, "map_id": 1439, "x": 1.0, "y": 2.0},
                  turn_in={"kind": "npc", "id": i + 1, "map_id": 1439, "x": 3.0, "y": 4.0},
                  objective_points=[{"map_id": 1439, "x": 5.0, "y": 6.0}],
                  prereq={"all": [i - 1], "any": []}, chain={"chain_id": 1, "index": 1, "length": 2})
            for i in range(1, n + 1)}


def test_many_quests_load_in_lua51(tmp_path):
    emit_quests(many_quests(), tmp_path / "Quests.lua")
    loaded = load_lua(tmp_path / "Quests.lua").Data.quests
    assert loaded[1][1] == "Quest 1" and loaded[20000][14] == "Text 20000"
    assert sum(1 for _ in loaded.keys()) == 20000


@pytest.mark.skipif(luajit() is None, reason="luajit not installed")
def test_many_quests_split_below_luajit_constant_limit(tmp_path):
    """LuaJIT allows 65536 constants per function: the file must not put every record in one."""
    emit_quests(many_quests(), tmp_path / "Quests.lua")
    proc = subprocess.run([luajit(), "-b", str(tmp_path / "Quests.lua"), "/dev/null"],
                          capture_output=True, text=True, env={})
    assert proc.returncode == 0, proc.stderr


def test_decodes_through_core_db(tmp_path):
    """The real decoder (LevelingAdvisor/Core/DB.lua) reads the emitted record."""
    emit_quests({4763: merged_4763(), 1: mq(1)}, tmp_path / "Quests.lua")
    ns = load_lua(tmp_path / "Quests.lua", ROOT / "LevelingAdvisor/Core/DB.lua")
    db = ns.DB.new(ns.Data)
    q = db.quest(db, 4763)
    assert (q.name, q.faction, q.requiredLevel, q.level, q.zone) == ("The Blackwood Corrupted", 1, 15, 18, 1439)
    assert (q.giver.kind, q.giver.id, q.giver.mapID, q.giver.x, q.giver.y) == (1, 3649, 1439, 37.4, 40.1)
    assert q.newInForever is False and q.elite is False
    assert lua_values(q.prereq.all) == [4762] and lua_values(q.prereq.any) == []
    assert (q.chain.id, q.chain.index, q.chain.length) == (984, 4, 4)
    assert [(p.mapID, p.x, p.y) for p in q.points.values()] == [(1439, 52.5, 33.4)]
    assert lua_values(db.questsInZone(db, 1439)) == [1, 4763]
    plain = db.quest(db, 1)
    assert lua_values(plain.points) == [] and lua_values(plain.exclusiveTo) == []


def full_stub(**kw):
    s = {"name": "Old Gods", "level": 60, "required_level": 58, "faction": "Horde", "race_mask": 178,
         "class_mask": 1, "prereq": {"all": [6564], "any": [5]},
         "giver": {"kind": "item", "id": 9, "map_id": 1440, "x": 1.0, "y": 2.0}, "start_name": "Damp Note",
         "reason": "no-giver-coords"}
    s.update(kw)
    return s


def test_stub_record_positions():
    assert encode_stub(full_stub()) == [
        "Old Gods", 60, 58, 2, 178, 1, {"all": [6564], "any": [5]},
        {"kind": 3, "name": "Damp Note", "mapID": 1440}, "no-giver-coords"]
    bare = encode_stub({"name": "X", "reason": "needs-rep", "faction": None, "giver": None, "prereq": None})
    assert bare == ["X", None, None, None, None, None, None, None, "needs-rep"]
    nameless = encode_stub(full_stub(start_name=None, giver={"kind": "npc", "id": 1}))
    assert nameless[7] == {"kind": 1}


def test_quests_file_has_stub_table(tmp_path):
    emit_quests({1: mq(1)}, tmp_path / "Quests.lua", stubs={6564: full_stub(), 6000: full_stub(name="Z")})
    data = load_lua(tmp_path / "Quests.lua").Data
    assert data.quests[1][1] == "Some Quest"
    stub = data.questStubs[6564]
    assert (stub[1], stub[2], stub[3], stub[4], stub[5], stub[6], stub[9]) == ("Old Gods", 60, 58, 2, 178, 1, "no-giver-coords")
    assert (stub[8].kind, stub[8].name, stub[8].mapID) == (3, "Damp Note", 1440)
    assert lua_values(stub[7].all) == [6564]
    assert data.questStubs[6000][1] == "Z"


def test_stub_table_present_and_empty_without_stubs(tmp_path):
    emit_quests({1: mq(1)}, tmp_path / "Quests.lua")
    assert lua_values(load_lua(tmp_path / "Quests.lua").Data.questStubs) == []


def test_stub_file_loads_under_luajit(tmp_path):
    emit_quests({1: mq(1)}, tmp_path / "Quests.lua", stubs={i: full_stub() for i in range(1, 450)})
    proc = subprocess.run([luajit(), "-b", str(tmp_path / "Quests.lua"), "/dev/null"],
                          capture_output=True, text=True, env={})
    assert proc.returncode == 0, proc.stderr


# ---------------------------------------------------------------- lua_literal

@pytest.mark.parametrize("value, text", [
    (None, "nil"), (True, "true"), (False, "false"), (0, "0"), (-5, "-5"), (37.4, "37.4"),
    ("a", '"a"'), ([], "{}"), ([1, None, 3], "{1, nil, 3}"), ([1, None, None], "{1}"),
    ({"name": "x", "n": 2}, '{name = "x", n = 2}'),
    ({1439: True}, "{[1439] = true}"),
    ({"end": 1, "two words": 2, "goto": 3}, '{["end"] = 1, ["two words"] = 2, ["goto"] = 3}'),
    ({"a": None, "b": 1}, "{b = 1}"),
])
def test_lua_literal(value, text):
    assert lua_literal(value) == text


@pytest.mark.parametrize("bad", [math.nan, math.inf, object(), {(1, 2): 3}])
def test_lua_literal_rejects_unrepresentable(bad):
    with pytest.raises((ValueError, TypeError)):
        lua_literal(bad)


def test_lua_literal_round_trips_through_lua51():
    value = {"s": "q\"uote\\ \n\r\t\0 \x1f é", "f": 0.123456789, "big": 2 ** 40, "neg": -1.5,
             "nested": [[1, 2], {"k": [True, False]}]}
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    t = lua.eval(lua_literal(value))
    assert t.s == value["s"] and t.f == value["f"] and t.big == value["big"] and t.neg == -1.5
    assert lua_values(t.nested[1]) == [1, 2] and lua_values(t.nested[2].k) == [True, False]


# ---------------------------------------------------------------- NPCs, zones, dungeons, meta

def test_npcs_shape(tmp_path):
    thundris = parse_npc((FX / "outofgames" / "npc-3649.html").read_text(encoding="utf-8"),
                         "https://outof.games/realms/forever/npc/3649-thundris-windweaver/")
    npcs = {
        3649: thundris,
        2: {"id": 2, "name": "Grunt", "level": 20, "faction": "Horde",
            "spawns": [{"map_id": 1411, "x": 10.04, "y": 20.0}, {"map_id": 1454, "x": 1.0, "y": 2.0}]},
        3: {"id": 3, "name": "Both Sides", "level": None, "faction": "Both", "spawns": []},
        4: {"id": 4, "name": "Unknown Side", "level": 5, "faction": None, "spawns": []},
    }
    emit_npcs(npcs, tmp_path / "NPCs.lua")
    loaded = load_lua(tmp_path / "NPCs.lua").Data.npcs
    t = loaded[3649]
    assert (t[1], t[2], t[3]) == ("Thundris Windweaver", 1, 15)
    assert [lua_values(s) for s in t[4].values()] == [[1439, 37.4, 40.1]]
    g = loaded[2]
    assert (g[1], g[2], g[3]) == ("Grunt", 2, 20)
    assert [lua_values(s) for s in g[4].values()] == [[1411, 10.0, 20], [1454, 1, 2]]
    assert (loaded[3][2], loaded[3][3]) == (3, None)
    assert loaded[4][2] is None
    assert loaded[3][4] is None or lua_values(loaded[3][4]) == []


def test_emit_zones_and_continents(tmp_path):
    zones = {
        1439: {"name": "Darkshore", "continent": 1414, "faction": "Alliance", "live": True, "complete": True,
               "min_level": 10, "max_level": 20, "yards": [6000.0, 4000.0], "rect": [0.38, 0.52, 0.12, 0.33],
               "links": [{"to": 1440, "kind": "walk", "x": 45.04, "y": 90.0, "label": "walk south"},
                         {"to": 1411, "kind": "zeppelin", "x": 1.0, "y": 2.0, "label": "zep", "faction": "Horde"}]},
        1440: {"name": "Ashenvale", "continent": 1414, "faction": "Contested", "live": False, "complete": False,
               "min_level": None, "max_level": None, "yards": None, "rect": None, "links": []},
    }
    census_maps = {1414: {"name": "Kalimdor", "mapType": 2, "yards": [36800.0, 24533.3]},
                   947: {"name": "Azeroth", "mapType": 1, "yards": None},
                   1439: {"name": "Darkshore", "mapType": 3, "yards": [6000.0, 4000.0]}}
    emit_zones(zones, census_maps, tmp_path / "Zones.lua")
    data = load_lua(tmp_path / "Zones.lua").Data
    d = data.zones[1439]
    assert (d.name, d.continent, d.faction, d.minLevel, d.maxLevel, d.live, d.complete) == (
        "Darkshore", 1414, 1, 10, 20, True, True)
    assert lua_values(d.yards) == [6000, 4000] and lua_values(d.rect) == [0.38, 0.52, 0.12, 0.33]
    walk, zep = d.links[1], d.links[2]
    assert (walk.to, walk.kind, walk.x, walk.y, walk.label, walk.faction) == (1440, "walk", 45.0, 90, "walk south", None)
    assert (zep.kind, zep.faction) == ("zeppelin", 2)
    a = data.zones[1440]
    assert (a.faction, a.live, a.complete, a.minLevel, a.yards, a.rect) == (3, False, False, None, None, None)
    assert lua_values(a.links) == []
    assert sorted(data.continents.keys()) == [1414]
    assert data.continents[1414].name == "Kalimdor" and lua_values(data.continents[1414].yards) == [36800, 24533.3]


def test_emit_zones_rejects_unknown_link_kind_and_faction(tmp_path):
    zone = {"name": "Z", "continent": None, "faction": "Alliance", "live": True, "complete": True, "links": []}
    with pytest.raises(ValueError):
        emit_zones({1: dict(zone, links=[{"to": 2, "kind": "teleport", "x": 1, "y": 1, "label": "?"}])}, {},
                   tmp_path / "Zones.lua")
    with pytest.raises(ValueError):
        emit_zones({1: dict(zone, faction="Neutral")}, {}, tmp_path / "Zones.lua")


def test_emit_dungeons(tmp_path):
    dungeons = {"BFD": {"name": "Blackfathom Deeps", "entrance": [1440, 14.04, 14.0], "min_level": 22,
                        "max_level": 28, "group_size": 5, "faction": "Contested", "live": True,
                        "quests": [1199, 1275]},
                "Hall of Thanes": {"name": "Hall of Thanes", "entrance": [1437, 1.0, 2.0], "min_level": 30,
                                   "max_level": 35, "group_size": 5, "faction": "Alliance", "live": False,
                                   "quests": []}}
    emit_dungeons(dungeons, tmp_path / "Dungeons.lua")
    data = load_lua(tmp_path / "Dungeons.lua").Data.dungeons
    b = data.BFD
    assert (b.name, b.minLevel, b.maxLevel, b.groupSize, b.faction, b.live) == (
        "Blackfathom Deeps", 22, 28, 5, 3, True)
    assert lua_values(b.entrance) == [1440, 14.0, 14] and lua_values(b.quests) == [1199, 1275]
    h = data["Hall of Thanes"]
    assert (h.faction, h.live) == (1, False)


def test_emit_meta(tmp_path):
    emit_meta({"built": "2026-11-25", "gameData": "1.60.1", "sources": ["outof.games", "Questie v11.38.0"],
               "counts": {"quests": 2, "npcs": 1}, "provisional": True}, tmp_path / "Meta.lua")
    meta = load_lua(tmp_path / "Meta.lua").Data.meta
    assert (meta.built, meta.gameData, meta.provisional) == ("2026-11-25", "1.60.1", True)
    assert lua_values(meta.sources) == ["outof.games", "Questie v11.38.0"]
    assert (meta.counts.quests, meta.counts.npcs) == (2, 1)


def test_files_share_one_namespace(tmp_path):
    emit_meta({"built": "x"}, tmp_path / "Meta.lua")
    emit_zones({}, {}, tmp_path / "Zones.lua")
    emit_npcs({}, tmp_path / "NPCs.lua")
    emit_dungeons({}, tmp_path / "Dungeons.lua")
    emit_quests({1: mq(1)}, tmp_path / "Quests.lua")
    data = load_lua(*(tmp_path / f"{n}.lua" for n in ("Meta", "Zones", "NPCs", "Dungeons", "Quests"))).Data
    assert data.meta.built == "x" and data.quests[1][1] == "Some Quest"
    assert lua_values(data.zones) == [] and lua_values(data.continents) == []
    assert lua_values(data.npcs) == [] and lua_values(data.dungeons) == []


@pytest.mark.skipif(luajit() is None, reason="luajit not installed")
def test_forever_race_mask_is_an_exact_integer_literal(tmp_path):
    """Task 8c: race masks carry the Skyborne bits (2^32, 2^33) as plain integer literals, which
    LuaJIT / Lua 5.1 doubles hold exactly; the decoder returns the same number."""
    mask = 2 ** 32 + 8
    emit_quests({1: mq(1, race_mask=mask), 2: mq(2, race_mask=77 + 2 ** 32 + 178 + 2 ** 33)}, tmp_path / "Quests.lua")
    text = (tmp_path / "Quests.lua").read_text(encoding="utf-8")
    assert "4294967304" in text and "12884902143" in text and "e+" not in text
    ns = load_lua(tmp_path / "Quests.lua", ROOT / "LevelingAdvisor/Core/DB.lua")
    db = ns.DB.new(ns.Data)
    assert db.quest(db, 1).raceMask == mask
    script = tmp_path / "check.lua"
    script.write_text("local ns = {}\nassert(loadfile(arg[1]))('LevelingAdvisor', ns)\n"
                      "local m = ns.Data.quests[1][3]\n"
                      "assert(m == 2^32 + 8, 'exact')\n"
                      "assert(math.floor(m / 2^32) % 2 == 1 and math.floor(m / 8) % 2 == 1, 'bits')\n"
                      "assert(math.floor(m / 1) % 2 == 0, 'human bit clear')\n", encoding="utf-8")
    proc = subprocess.run([luajit(), str(script), str(tmp_path / "Quests.lua")], capture_output=True, text=True,
                          env={})
    assert proc.returncode == 0, proc.stderr
