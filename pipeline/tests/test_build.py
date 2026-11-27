"""build command (Task 6 + rulings): provisional and census builds, coordinate check, CLI."""
import importlib.util
import json
import subprocess
from pathlib import Path

import pytest

from pipeline.__main__ import main
from pipeline import build as build_module
from pipeline.build import BuildInputError, build, coord_check, level_range
from pipeline.outofgames import parse_npc
from pipeline.tests.test_emit import load_lua, lua_values, luajit
from pipeline.tests.test_merge import FX, fixture_quest, fixture_questie, oq, place

DATA_FILES = ("Meta", "Zones", "NPCs", "Dungeons", "Quests")


def thundris():
    return parse_npc((FX / "outofgames" / "npc-3649.html").read_text(encoding="utf-8"),
                     "https://outof.games/realms/forever/npc/3649-thundris-windweaver/")


def load_data(out_dir):
    return load_lua(*(Path(out_dir) / f"{n}.lua" for n in DATA_FILES)).Data


def provisional_oog():
    return {q["id"]: q for q in [
        oq(1, zone_name="Darkshore", quest_level=12, giver=place(map_id=1439)),
        oq(2, zone_name="Darkshore", quest_level=14, giver=place(map_id=1439)),
        oq(3, zone_name="Auberdine", quest_level=20, giver=place(map_id=1439)),
        oq(4, zone_name="Ashenvale", quest_level=22, giver=place(map_id=1440)),
    ]}


# ---------------------------------------------------------------- coordinate check

def test_coord_check_threshold():
    npcs = {7: {"id": 7, "spawns": [{"map_id": 1439, "x": 50.0, "y": 50.0},
                                    {"map_id": 1440, "x": 54.9, "y": 50.0}]}}
    here = [{"npcID": 7, "mapID": 1439, "x": 54.9, "y": 50.0},
            {"npcID": 7, "mapID": 1439, "x": 55.1, "y": 50.0},
            {"npcID": 7, "mapID": 1439, "x": 50.0, "y": 45.0}]
    result = coord_check(here, npcs)
    assert [(r["x"], r["y"]) for r in result["pass"]] == [(54.9, 50.0), (50.0, 45.0)]
    assert [(r["x"], r["y"]) for r in result["fail"]] == [(55.1, 50.0)]
    assert result["fail"][0]["distance"] == pytest.approx(5.1)
    assert result["pass"][0]["distance"] == pytest.approx(4.9)


def test_coord_check_uses_nearest_spawn_on_the_same_map_only():
    npcs = {7: {"id": 7, "spawns": [{"map_id": 1440, "x": 10.0, "y": 10.0},
                                    {"map_id": 1439, "x": 90.0, "y": 90.0},
                                    {"map_id": 1439, "x": 11.0, "y": 10.0}]}}
    result = coord_check([{"npcID": 7, "mapID": 1439, "x": 10.0, "y": 10.0}], npcs)
    assert len(result["pass"]) == 1 and result["pass"][0]["distance"] == pytest.approx(1.0)


def test_coord_check_unmatched_and_ignored_records():
    npcs = {7: {"id": 7, "spawns": [{"map_id": 1440, "x": 10.0, "y": 10.0}]}}
    here = [{"npcID": 7, "mapID": 1439, "x": 10.0, "y": 10.0},     # no spawn on that map
            {"npcID": 8, "mapID": 1439, "x": 10.0, "y": 10.0},     # no outof.games page
            {"npcID": 7, "mapID": 1440, "x": None, "y": None},     # no position
            {"mapID": 1439, "x": 1.0, "y": 1.0}]                   # no NPC: not checked
    result = coord_check(here, npcs)
    assert result["pass"] == [] and result["fail"] == []
    assert [r["reason"] for r in result["unmatched"]] == ["no-spawn-on-map", "no-npc-page", "no-position"]


# ---------------------------------------------------------------- zone levels

@pytest.mark.parametrize("levels, expected", [
    ([12, 14, 20], (12, 19)),          # p10 = 12.4, p90 = 18.8
    ([22], (22, 22)),
    ([], (None, None)),
    ([10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20], (11, 19)),
    ([1, 2], (1, 2)),                  # p10 = 1.1, p90 = 1.9
])
def test_level_range_percentiles(levels, expected):
    assert level_range(levels) == expected


# ---------------------------------------------------------------- provisional build

def test_provisional_zones(tmp_path):
    report = build(provisional_oog(), {}, {}, {}, tmp_path / "Data", tmp_path / "report.json",
                   provisional=True, built="2026-11-25")
    data = load_data(tmp_path / "Data")
    z = data.zones[1439]
    assert z.name == "Darkshore"
    assert (z.continent, z.faction, z.live, z.complete, z.yards, z.rect) == (None, 3, True, False, None, None)
    assert lua_values(z.links) == []
    assert (z.minLevel, z.maxLevel) == (12, 19)
    a = data.zones[1440]
    assert (a.name, a.minLevel, a.maxLevel) == ("Ashenvale", 22, 22)
    assert sorted(data.zones.keys()) == [1439, 1440]
    assert lua_values(data.continents) == [] and lua_values(data.dungeons) == []
    assert data.meta.provisional is True and data.meta.built == "2026-11-25"
    assert data.meta.counts.quests == 4
    assert report["provisional"] is True
    assert any("provisional" in w for w in report["warnings"])
    assert report["coord_check"] == {"skipped": "no census"}
    assert report["live_filter"] == "off"
    on_disk = json.loads((tmp_path / "report.json").read_text(encoding="utf-8"))
    assert on_disk["provisional"] is True and on_disk["counts"]["kept"] == 4


def gen_links(tmp_path, *rows):
    """A tmp curated dir holding links.generated.toml with the given (from, to, kind, faction) rows."""
    d = tmp_path / "curated"
    d.mkdir()
    text = ""
    for src, to, kind, faction in rows:
        text += (f'[[links]]\nfrom = {src}\nto = {to}\nkind = "{kind}"\nx = 50.5\ny = 12.7\n'
                 f'label = "{kind} {src} to {to}"\n' + (f'faction = "{faction}"\n' if faction else "")
                 + 'source = "openmap"\n\n')
    (d / "links.generated.toml").write_text(text, encoding="utf-8")
    return d


def build_prov(tmp_path, curated, **kw):
    return build(provisional_oog(), {}, {}, {}, tmp_path / "Data", tmp_path / "report.json",
                 provisional=True, curated_dir=curated, **kw)


LEVELS_LUA = """local _, ns = ...
ns.MapLevels = {
  [1439] = { 10, 20 },   -- Darkshore
}
"""


def test_provisional_zone_levels_from_openmap(tmp_path):
    levels = {1439: (10, 20)}
    report = build(provisional_oog(), {}, {}, {}, tmp_path / "Data", tmp_path / "report.json",
                   provisional=True, map_levels=levels)
    z = load_data(tmp_path / "Data").zones
    assert (z[1439].minLevel, z[1439].maxLevel) == (10, 20)       # not the 12-20 quest percentiles
    assert (z[1440].minLevel, z[1440].maxLevel) == (22, 22)       # no entry: quest percentiles
    assert report["zones"]["levels_source"] == {1439: "openmap", 1440: "quests"} or \
        report["zones"]["levels_source"] == {"1439": "openmap", "1440": "quests"}
    assert load_openmap_levels_for_test(tmp_path) == {1439: (10, 20)}


def load_openmap_levels_for_test(tmp_path):
    from pipeline.poi import load_openmap_levels
    p = tmp_path / "Levels.lua"
    p.write_text(LEVELS_LUA, encoding="utf-8")
    return load_openmap_levels(p)


def test_provisional_zone_levels_cli_and_without_openmap(tmp_path):
    write_oog(tmp_path / "oog", [oq(1, quest_level=12, giver=place(map_id=1439)),
                                 oq(2, quest_level=50, giver=place(map_id=1439))])
    lv = tmp_path / "Levels.lua"
    lv.write_text(LEVELS_LUA, encoding="utf-8")
    args = ["build", "--provisional", "--without", "questie", "--levels", str(lv), *cli_paths(tmp_path)]
    assert main(args) == 0
    z = load_data(tmp_path / "Data").zones[1439]
    assert (z.minLevel, z.maxLevel) == (10, 20)
    assert main([*args, "--without", "openmap"]) == 0
    z = load_data(tmp_path / "Data").zones[1439]
    assert (z.minLevel, z.maxLevel) == (16, 46)                  # quest percentiles again
    report = json.loads((tmp_path / "report.json").read_text(encoding="utf-8"))
    assert set(report["zones"]["levels_source"].values()) == {"quests"}


def test_provisional_zone_kind_city_battleground(tmp_path):
    oog = {q["id"]: q for q in [oq(i + 1, giver=place(map_id=m)) for i, m in enumerate(
        (1439, 1453, 1454, 1455, 1456, 1457, 1458, 1459, 1460, 1461))]}
    build(oog, {}, {}, {}, tmp_path / "Data", tmp_path / "report.json", provisional=True)
    z = load_data(tmp_path / "Data").zones
    assert z[1439].kind is None
    assert [z[m].kind for m in (1453, 1454, 1455, 1456, 1457, 1458)] == ["city"] * 6
    assert [z[m].kind for m in (1459, 1460, 1461)] == ["battleground"] * 3


def test_provisional_attaches_generated_links(tmp_path):
    curated = gen_links(tmp_path, (1439, 1440, "walk", None), (1440, 1439, "walk", None),
                        (1439, 1453, "boat", "Alliance"))
    report = build_prov(tmp_path, curated)
    data = load_data(tmp_path / "Data")
    links = lua_values(data.zones[1439].links)
    assert len(links) == 1 and links[0]["to"] == 1440 and links[0]["kind"] == "walk"
    assert links[0]["faction"] is None
    back = lua_values(data.zones[1440].links)
    assert [l["to"] for l in back] == [1439]
    assert report["zones"]["links"] == {"attached": 2, "dropped_missing_zone": 1,
                                        "source": "links.generated.toml"}
    assert data.zones[1439].faction == 3
    assert any("2 generated travel link" in w for w in report["warnings"])
    assert not any("no travel links" in w or "no yards, rects or travel links" in w for w in report["warnings"])


def test_provisional_link_faction_kept(tmp_path):
    curated = gen_links(tmp_path, (1439, 1440, "boat", "Alliance"))
    build_prov(tmp_path, curated)
    data = load_data(tmp_path / "Data")
    assert lua_values(data.zones[1439].links)[0]["faction"] == 1
    assert data.zones[1439].faction == 3 and data.zones[1440].faction == 3


def test_provisional_without_openmap_has_no_links(tmp_path):
    curated = gen_links(tmp_path, (1439, 1440, "boat", None))
    report = build_prov(tmp_path, curated, without={"openmap"})
    data = load_data(tmp_path / "Data")
    assert lua_values(data.zones[1439].links) == []
    assert "links" not in report["zones"]
    assert any("--without openmap" in n and "no travel links" in n for n in report["notes"])
    assert any("or travel links" in w for w in report["warnings"])


def test_provisional_without_generated_file_unchanged(tmp_path):
    empty = tmp_path / "curated"
    empty.mkdir()
    report = build_prov(tmp_path, empty)
    data = load_data(tmp_path / "Data")
    assert lua_values(data.zones[1439].links) == []
    assert "links" not in report["zones"] and report["notes"] == []
    assert report["warnings"] == [build_module.PROVISIONAL_WARNING_NO_LINKS]


def test_provisional_zone_name_falls_back_to_map_id(tmp_path):
    oog = {5: oq(5, zone_name=None, giver=place(map_id=1234))}
    build(oog, {}, {}, {}, tmp_path / "Data", tmp_path / "report.json", provisional=True)
    assert load_data(tmp_path / "Data").zones[1234].name == "Map 1234"


def test_provisional_build_emits_npcs_and_counts_missing_givers(tmp_path):
    oog = {4763: fixture_quest(4763), 6: oq(6, giver=place(ident=555), turn_in=place(ident=556))}
    report = build(oog, {3649: thundris()}, fixture_questie(), {}, tmp_path / "Data", tmp_path / "report.json",
                   provisional=True)
    data = load_data(tmp_path / "Data")
    assert data.npcs[3649][1] == "Thundris Windweaver"
    assert data.npcs[555] is None              # Questie-only/no page: skipped (loader has no spawns)
    assert report["npcs"]["emitted"] == 1
    assert report["npcs"]["kept_quest_npcs_without_page"] == 2
    assert data.meta.counts.npcs == 1


# ---------------------------------------------------------------- census build (fixtures)

def census_fixture():
    return {
        "maps": {
            947: {"name": "Azeroth", "mapType": 1, "parent": 946, "yards": None, "continent": None, "rect": None},
            1414: {"name": "Kalimdor", "mapType": 2, "parent": 947, "yards": [36800.0, 24533.3],
                   "continent": 1414, "rect": None},
            1439: {"name": "Darkshore", "mapType": 3, "parent": 1414, "yards": [6000.0, 4000.0],
                   "continent": 1414, "rect": [0.38, 0.52, 0.12, 0.33]},
            1440: {"name": "Ashenvale", "mapType": 3, "parent": 1414, "yards": [5800.0, 3866.0],
                   "continent": 1414, "rect": [0.30, 0.55, 0.33, 0.50]},
        },
        "areas": {},
        "here": [{"npcID": 3649, "mapID": 1439, "x": 37.6, "y": 40.0, "name": "Thundris Windweaver"},
                 {"npcID": 3649, "mapID": 1439, "x": 50.0, "y": 50.0, "name": "Thundris Windweaver"}],
    }


def zones_fixture():
    """Shaped like Task 7's load_zones() output (yards and rect filled from the census)."""
    return {
        1439: {"name": "Darkshore", "continent": 1414, "faction": "Alliance", "live": True, "complete": True,
               "yards": [6000.0, 4000.0], "rect": [0.38, 0.52, 0.12, 0.33],
               "links": [{"to": 1440, "kind": "walk", "x": 45.0, "y": 90.0, "label": "walk south"}]},
        1440: {"name": "Ashenvale", "continent": 1414, "faction": "Contested", "live": False, "complete": False,
               "yards": [5800.0, 3866.0], "rect": [0.30, 0.55, 0.33, 0.50],
               "links": [{"to": 1439, "kind": "walk", "x": 40.0, "y": 5.0, "label": "walk north"}]},
    }


def dungeons_fixture():
    """Shaped like Task 7's load_dungeons() output."""
    return {"BFD": {"name": "Blackfathom Deeps", "entrance": [1440, 14.0, 14.0], "min_level": 22, "max_level": 28,
                    "group_size": 5, "faction": "Contested", "live": True, "quests": [501, 9999]}}


def test_census_build_curated_levels_and_kind_win(tmp_path):
    zones = zones_fixture()
    zones[1439] = {**zones[1439], "min_level": 5, "max_level": 9, "kind": "city"}
    build({4763: fixture_quest(4763)}, {3649: thundris()}, fixture_questie(), {}, tmp_path / "Data",
          tmp_path / "report.json", provisional=False, census=census_fixture(), zones=zones,
          dungeons=dungeons_fixture(), map_levels={1439: (30, 40)})
    d = load_data(tmp_path / "Data").zones[1439]
    assert (d.minLevel, d.maxLevel, d.kind) == (5, 9, "city")


def test_census_build_with_fixtures(tmp_path):
    oog = {4763: fixture_quest(4763),
           500: oq(500, giver=place(map_id=1440)),
           501: oq(501, quest_level=24, tags=["Alliance", "Dungeon"])}
    report = build(oog, {3649: thundris()}, fixture_questie(), {}, tmp_path / "Data", tmp_path / "report.json",
                   provisional=False, census=census_fixture(), zones=zones_fixture(),
                   dungeons=dungeons_fixture(), built="2026-11-25")
    data = load_data(tmp_path / "Data")
    assert report["provisional"] is False and report["live_filter"] == "on"
    assert report["excluded"] == {500: "zone-not-live"}
    d = data.zones[1439]
    assert (d.name, d.continent, d.faction, d.live, d.complete) == ("Darkshore", 1414, 1, True, True)
    assert lua_values(d.yards) == [6000, 4000] and lua_values(d.rect) == [0.38, 0.52, 0.12, 0.33]
    assert (d.minLevel, d.maxLevel) == (19, 23)        # kept 4763 (18) and 501 (24): p10 18.6, p90 23.4
    assert d.links[1].label == "walk south"
    assert data.zones[1440].live is False and data.zones[1440].minLevel is None
    assert sorted(data.continents.keys()) == [1414] and data.continents[1414].name == "Kalimdor"
    bfd = data.dungeons.BFD
    assert lua_values(bfd.entrance) == [1440, 14, 14] and bfd.faction == 3 and bfd.minLevel == 22
    assert data.quests[501][23] == "BFD" and data.quests[4763][23] is None
    assert data.meta.provisional is None
    assert [r["npcID"] for r in report["coord_check"]["pass"]] == [3649]
    assert [r["npcID"] for r in report["coord_check"]["fail"]] == [3649]
    assert report["dungeons"]["quests_not_kept"] == {"BFD": [9999]}


def test_zone_level_override_beats_computed_levels(tmp_path):
    def run(zones, sub):
        oog = {4763: fixture_quest(4763), 501: oq(501, quest_level=24, tags=["Alliance", "Dungeon"])}
        build(oog, {3649: thundris()}, fixture_questie(), {}, tmp_path / sub / "Data", tmp_path / sub / "r.json",
              provisional=False, census=census_fixture(), zones=zones, dungeons=dungeons_fixture(),
              built="2026-11-25")
        return load_data(tmp_path / sub / "Data").zones[1439]

    assert (run(zones_fixture(), "a").minLevel, run(zones_fixture(), "b").maxLevel) == (19, 23)
    zones = zones_fixture()
    zones[1439] = {**zones[1439], "min_level": 5, "max_level": 9}
    d = run(zones, "c")
    assert (d.minLevel, d.maxLevel) == (5, 9)


@pytest.mark.parametrize("missing", ["census", "zones", "dungeons"])
def test_census_build_requires_every_input(tmp_path, missing):
    kw = {"census": census_fixture(), "zones": zones_fixture(), "dungeons": dungeons_fixture()}
    kw[missing] = None
    with pytest.raises(BuildInputError):
        build({1: oq(1)}, {}, {}, {}, tmp_path / "Data", tmp_path / "report.json", provisional=False, **kw)
    assert not (tmp_path / "Data").exists()


# ---------------------------------------------------------------- CLI

def write_oog(root: Path, quests, npcs=()):
    for q in quests:
        p = root / "quests" / f"{q['id']}.json"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(q), encoding="utf-8")
    for n in npcs:
        p = root / "npcs" / f"{n['id']}.json"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(n), encoding="utf-8")
    (root / "quests" / "99.json.tmp").write_text("{not json", encoding="utf-8")   # crawl's in-flight file


def cli_paths(tmp_path, questiedb=None, blacklist=None):
    return ["--oog", str(tmp_path / "oog"), "--questiedb", str(questiedb or tmp_path / "no-questiedb"),
            "--questie-blacklist", str(blacklist or tmp_path / "no-blacklist.lua"),
            "--curated", str(tmp_path / "curated"), "--census", str(tmp_path / "census" / "maps.json"),
            "--out", str(tmp_path / "Data"), "--report", str(tmp_path / "report.json")]


def test_cli_non_provisional_without_census_exits_2(tmp_path, capsys):
    write_oog(tmp_path / "oog", [oq(1)])
    rc = main(["build", "--without", "questie", *cli_paths(tmp_path)])
    assert rc == 2
    err = capsys.readouterr().err
    assert "census" in err and "--provisional" in err
    assert not (tmp_path / "Data").exists() and not (tmp_path / "report.json").exists()


def test_cli_provisional_build(tmp_path):
    write_oog(tmp_path / "oog", [fixture_quest(4763), oq(2, faction="Both", giver=place(ident=3649))],
              [dict(thundris(), id=3649)])
    rc = main(["build", "--provisional", "--without", "questie", *cli_paths(tmp_path)])
    assert rc == 0
    data = load_data(tmp_path / "Data")
    assert data.quests[4763][1] == "The Blackwood Corrupted"
    assert data.quests[2][2] == 1                       # "Both" narrowed by the Alliance giver
    assert data.meta.provisional is True
    report = json.loads((tmp_path / "report.json").read_text(encoding="utf-8"))
    assert report["provisional"] is True and report["counts"]["kept"] == 2
    assert "questie-disabled: skill/rep/race restrictions from Questie not applied" in report["warnings"]
    assert set(report["outputs"]) == {f"{n}.lua" for n in DATA_FILES}


def test_cli_missing_questiedb_exits_2(tmp_path, capsys):
    write_oog(tmp_path / "oog", [oq(1)])
    assert main(["build", "--provisional", *cli_paths(tmp_path)]) == 2
    err = capsys.readouterr().err
    assert "QuestieDB" in err and "--without questie" in err
    assert not (tmp_path / "Data").exists()


def test_cli_missing_blacklist_exits_2(tmp_path, capsys):
    write_oog(tmp_path / "oog", [oq(1)])
    assert main(["build", "--provisional", *cli_paths(tmp_path, questiedb=QDB_ROOT)]) == 2
    assert "no-blacklist.lua" in capsys.readouterr().err


def test_cli_rejected_questiedb_exits_2(tmp_path, capsys):
    import shutil
    root = tmp_path / "qdb"
    shutil.copytree(QDB_ROOT, root)
    fixes = root / "src/corrections/Forever/foreverQuestFixes.lua"
    fixes.write_text('os.execute("touch pwned")\n' + fixes.read_text(encoding="utf-8"), encoding="utf-8")
    write_oog(tmp_path / "oog", [oq(1)])
    assert main(["build", "--provisional", *cli_paths(tmp_path, questiedb=root, blacklist=QDB_BLACKLIST)]) == 2
    assert "QuestieDB" in capsys.readouterr().err


def test_cli_missing_crawl_exits_2(tmp_path, capsys):
    assert main(["build", "--provisional", "--without", "questie", *cli_paths(tmp_path)]) == 2
    assert "outof.games" in capsys.readouterr().err


def test_cli_rejects_unknown_without_source(tmp_path):
    with pytest.raises(SystemExit) as e:
        main(["build", "--provisional", "--without", "outofgames", *cli_paths(tmp_path)])
    assert e.value.code == 2


@pytest.mark.skipif(importlib.util.find_spec("pipeline.recorder_import") is not None,
                    reason="recorder importer exists; the note is only for its absence")
def test_cli_recorder_without_importer_is_noted(tmp_path):
    write_oog(tmp_path / "oog", [oq(1)])
    (tmp_path / "recorder").mkdir()
    rc = main(["build", "--provisional", "--without", "questie", "--recorder", str(tmp_path / "recorder"),
               *cli_paths(tmp_path)])
    assert rc == 0
    report = json.loads((tmp_path / "report.json").read_text(encoding="utf-8"))
    assert any("recorder" in n and "skipped" in n for n in report["notes"])


@pytest.mark.skipif(luajit() is None, reason="luajit not installed")
def test_emitted_files_compile_with_luajit(tmp_path):
    write_oog(tmp_path / "oog", [fixture_quest(4763), oq(2)], [dict(thundris(), id=3649)])
    assert main(["build", "--provisional", "--without", "questie", *cli_paths(tmp_path)]) == 0
    for name in DATA_FILES:
        proc = subprocess.run([luajit(), "-b", str(tmp_path / "Data" / f"{name}.lua"), "/dev/null"],
                              capture_output=True, text=True, env={})
        assert proc.returncode == 0, proc.stderr


# ---------------------------------------------------------------- staging (fix round)

def test_staging_dir_is_outside_the_addon(tmp_path, monkeypatch):
    """Files are staged next to the report, never inside the addon's Data dir, and cleaned up."""
    import pipeline.build as b
    seen = []
    real = b.emit_meta
    monkeypatch.setattr(b, "emit_meta", lambda meta, p: (seen.append(Path(p).parent), real(meta, p)))
    out, report = tmp_path / "addon" / "Data", tmp_path / "build" / "report.json"
    build(provisional_oog(), {}, {}, {}, out, report, provisional=True)
    assert len(seen) == 1
    assert seen[0].parent == report.parent and seen[0].name.startswith(".staging-")
    assert not seen[0].exists()
    assert sorted(p.name for p in out.iterdir()) == sorted(f"{n}.lua" for n in DATA_FILES)
    assert [p.name for p in report.parent.iterdir()] == ["report.json"]


def test_failed_build_leaves_previous_data_and_no_staging(tmp_path, monkeypatch):
    import pipeline.build as b
    out, report = tmp_path / "addon" / "Data", tmp_path / "build" / "report.json"
    build(provisional_oog(), {}, {}, {}, out, report, provisional=True)
    before = {p.name: p.read_bytes() for p in out.iterdir()}
    report.unlink()

    def boom(quests, p, stubs=None):
        Path(p).write_text("partial", encoding="utf-8")
        raise RuntimeError("emit failed")
    monkeypatch.setattr(b, "emit_quests", boom)
    with pytest.raises(RuntimeError):
        build(provisional_oog(), {}, {}, {}, out, report, provisional=True, built="2099-01-01")
    assert {p.name: p.read_bytes() for p in out.iterdir()} == before
    assert list(report.parent.iterdir()) == []


# ---------------------------------------------------------------- QuestieDB Forever (Task 8c)

QDB_ROOT = FX / "questiedb" / "root"
QDB_BLACKLIST = FX / "questiedb" / "QuestieQuestBlacklist.lua"


def qdb_oog_npcs():
    """outof.games pages agreeing with three fixture QuestieDB NPCs on uiMapID 1429 (so it is trusted)."""
    return [{"id": i, "name": f"N{i}", "level": 10, "faction": f, "spawns": [{"map_id": 1429, "x": x, "y": x}],
             "starts_count": 1} for i, f, x in ((13, "Horde", 40.0), (30, "Alliance", 30.0), (31, "Horde", 31.0))]


def test_build_with_questiedb_fixture(tmp_path):
    """Quest 300 has no outof.games giver; QuestieDB's only starter, NPC 20 (no oog page), has one
    spawn on trusted 1429: the giver is filled and NPC 20 is emitted from QuestieDB."""
    write_oog(tmp_path / "oog", [oq(300, zone_name="Elwynn Forest", giver=None, required_level=5),
                                 oq(201, giver=place(ident=10, map_id=None, x=None, y=None))], qdb_oog_npcs())
    rc = main(["build", "--provisional", *cli_paths(tmp_path, questiedb=QDB_ROOT, blacklist=QDB_BLACKLIST)])
    assert rc == 0
    data = load_data(tmp_path / "Data")
    giver = lua_values(data.quests[300][11])
    assert giver == [1, 20, 1429, 44.4, 55.5]
    assert data.quests[300][3] == 8 + 2 ** 32                # Night Elf + High Order Skyborne, in full
    assert data.npcs[20][1] == "Forever Giver" and data.npcs[20][2] == 1 and data.npcs[20][3] == 12
    assert [lua_values(s) for s in lua_values(data.npcs[20][4])] == [[1429, 44.4, 55.5]]
    assert data.npcs[13][1] == "N13"                         # outof.games pages are still emitted
    assert any("QuestieDB" in v and "Forever (GPL-3.0)" in v for v in lua_values(data.meta.sources))
    report = json.loads((tmp_path / "report.json").read_text(encoding="utf-8"))
    q = report["questiedb"]
    assert q["spawn_check"]["trusted"] == [1429]
    assert q["giver_fill"]["filled_kept"] == 1
    assert q["npcs_emitted"] == 1 and report["npcs"]["questiedb"] == 1
    assert list(q["layers"]["Quest"]) == ["legacy", "generated", "traces", "relation-traces", "authored"]
    # one candidate (NPC 10) whose spawns are all on untrusted 1453: no usable point; the quest is
    # excluded first because three of its fixture corrections were rejected (correction-unclear)
    assert q["giver_fill"]["no_usable"] == 1 and q["giver_fill"]["no_usable_why"] == {"untrusted-map-only": 1}
    assert report["excluded"][str(201)] == "correction-unclear"


def test_build_without_questie_needs_no_questiedb(tmp_path):
    write_oog(tmp_path / "oog", [oq(300, giver=None), oq(2)], qdb_oog_npcs())
    rc = main(["build", "--provisional", "--without", "questie", *cli_paths(tmp_path)])
    assert rc == 0
    report = json.loads((tmp_path / "report.json").read_text(encoding="utf-8"))
    assert "questiedb" not in report and report["excluded"] == {"300": "no-giver-coords"}
    data = load_data(tmp_path / "Data")
    assert not any("QuestieDB" in v for v in lua_values(data.meta.sources))


def test_questiedb_tag_reads_the_clone_head(tmp_path):
    from pipeline.build import questiedb_tag
    git = tmp_path / "QuestieDB" / ".git"
    (git / "refs" / "heads").mkdir(parents=True)
    (git / "HEAD").write_text("ref: refs/heads/master\n")
    assert questiedb_tag(tmp_path / "QuestieDB") is None
    (git / "packed-refs").write_text("# pack-refs with: peeled\n6c9c71280e1295e96985825bcc49c79d470f01ea "
                                     "refs/heads/master\n")
    assert questiedb_tag(tmp_path / "QuestieDB") == "6c9c712"
    (git / "refs" / "heads" / "master").write_text("0123456789abcdef0123456789abcdef01234567\n")
    assert questiedb_tag(tmp_path / "QuestieDB") == "0123456"
    (git / "HEAD").write_text("fedcba9876543210fedcba9876543210fedcba98\n")   # detached
    assert questiedb_tag(tmp_path / "QuestieDB") == "fedcba9"


def test_npc_faction_never_stated_by_questiedb_is_unknown_not_hostile(tmp_path):
    """NPC 22 was created by a QuestieDB Forever layer without friendlyToFaction: its oog "Both" side
    stands. NPC 99 is Era data with nil friendlyToFaction (hostile to both): the "Both" quest is excluded."""
    pages = [{"id": i, "name": f"N{i}", "level": 10, "faction": "Both", "spawns": [], "starts_count": 1}
             for i in (22, 99)]
    write_oog(tmp_path / "oog", [oq(1, faction="Both", giver=place(ident=22)),
                                 oq(2, faction="Both", giver=place(ident=99))], pages)
    rc = main(["build", "--provisional", *cli_paths(tmp_path, questiedb=QDB_ROOT, blacklist=QDB_BLACKLIST)])
    assert rc == 0
    report = json.loads((tmp_path / "report.json").read_text(encoding="utf-8"))
    assert report["excluded"] == {"2": "giver-faction-unknown"}


def test_curated_levels_openmap_precedence(tmp_path):
    """TOML min/max, then OpenMap Levels.lua, then quest percentiles; levels_source says which."""
    zones = zones_fixture()
    zones[1439] = {**zones[1439], "min_level": 5, "max_level": 9}       # TOML wins
    zones[1441] = {"name": "Third", "continent": 1414, "faction": "Contested", "live": True, "complete": False,
                   "yards": None, "rect": None, "links": []}            # OpenMap fills it
    census = census_fixture()
    census["maps"][1441] = {"name": "Third", "mapType": 3, "parent": 1414, "yards": None, "continent": 1414,
                            "rect": None}
    oog = {4763: fixture_quest(4763), 501: oq(501, quest_level=24, tags=["Alliance", "Dungeon"]),
           502: oq(502, quest_level=30, giver=place(map_id=1441))}
    report = build(oog, {3649: thundris()}, fixture_questie(), {}, tmp_path / "Data", tmp_path / "report.json",
                   provisional=False, census=census, zones=zones, dungeons=dungeons_fixture(),
                   map_levels={1439: (30, 40), 1441: (31, 36), 1440: (1, 2)}, built="2026-11-25")
    z = load_data(tmp_path / "Data").zones
    assert (z[1439].minLevel, z[1439].maxLevel) == (5, 9)
    assert (z[1441].minLevel, z[1441].maxLevel) == (31, 36)             # not the quest level 30
    assert (z[1440].minLevel, z[1440].maxLevel) == (1, 2)               # OpenMap even without kept quests
    assert report["zones"]["levels_source"] == {1439: "toml", 1440: "openmap", 1441: "openmap"}

    report = build(oog, {3649: thundris()}, fixture_questie(), {}, tmp_path / "Data2", tmp_path / "r2.json",
                   provisional=False, census=census, zones=zones_fixture(), dungeons=dungeons_fixture(),
                   map_levels=None, built="2026-11-25")
    assert report["zones"]["levels_source"] == {1439: "quests", 1440: "none"}
    assert (load_data(tmp_path / "Data2").zones[1439].minLevel) == 19


def test_census_build_writes_adjacency_gap_report(tmp_path):
    zones = zones_fixture()
    for z in zones.values():
        z["links"] = []                                   # rect-adjacent Darkshore/Ashenvale, no link
    report = build({4763: fixture_quest(4763)}, {3649: thundris()}, fixture_questie(), {}, tmp_path / "Data",
                   tmp_path / "out" / "report.json", provisional=False, census=census_fixture(), zones=zones,
                   dungeons=dungeons_fixture(), built="2026-11-25")
    gaps = json.loads((tmp_path / "out" / "adjacency-gaps.json").read_text(encoding="utf-8"))
    assert [(g["a"], g["b"], g["a_to_b"]["label"]) for g in gaps] == [(1439, 1440, "walk south")]
    assert report["zones"]["adjacency_gaps"] == 1
    build({4763: fixture_quest(4763)}, {3649: thundris()}, fixture_questie(), {}, tmp_path / "Data",
          tmp_path / "out" / "report.json", provisional=False, census=census_fixture(), zones=zones_fixture(),
          dungeons=dungeons_fixture(), built="2026-11-25")
    assert json.loads((tmp_path / "out" / "adjacency-gaps.json").read_text(encoding="utf-8")) == []


def test_provisional_build_writes_no_adjacency_report(tmp_path):
    build(provisional_oog(), {}, {}, {}, tmp_path / "Data", tmp_path / "out" / "report.json", provisional=True)
    assert not (tmp_path / "out" / "adjacency-gaps.json").exists()


def test_meta_sources_name_openmap_and_census_only_when_used(tmp_path):
    oog = {4763: fixture_quest(4763)}

    def sources(name, **kw):
        build(oog, {3649: thundris()}, fixture_questie(), {}, tmp_path / name, tmp_path / f"{name}.json",
              provisional=False, census=census_fixture(), zones=zones_fixture(), dungeons=dungeons_fixture(),
              built="2026-11-25", **kw)
        return lua_values(load_data(tmp_path / name).meta.sources)

    used = sources("a", map_levels={1439: (30, 40)})
    assert any(v.startswith("OpenMap ") and v.endswith(" (MIT)") for v in used)
    assert any("census" in v for v in used)
    removed = sources("b", map_levels=None, without=frozenset({"openmap"}))
    assert not any("OpenMap" in v for v in removed) and any("census" in v for v in removed)
