from pathlib import Path

import pytest

from pipeline.census import load_census
from pipeline.curated import load_dungeons, load_zones

HERE = Path(__file__).parent
CENSUS = load_census(HERE / "fixtures" / "census" / "LevelingAdvisorDiag.lua")
CURATED = HERE.parents[1] / "data" / "curated"

ZONE = '''
[zones.1439]
name = "Darkshore"
continent = 1414
faction = "Alliance"
live = true
complete = false
{extra}
[zones.1440]
name = "Ashenvale"
continent = 1414
faction = "Contested"
live = true
complete = false
'''
LINK = '''
[[zones.1439.links]]
to = {to}
kind = "{kind}"
x = {x}
y = 50
label = "go"
{faction}
'''


def zones_file(tmp_path, to=1440, kind="walk", x=50, faction="", extra="", head=""):
    p = tmp_path / "zones.toml"
    p.write_text(head + ZONE.format(extra=extra + LINK.format(to=to, kind=kind, x=x, faction=faction)))
    return p


def test_zones_get_yards_from_census(tmp_path):
    z = load_zones(zones_file(tmp_path), CENSUS)
    assert set(z) == {1439, 1440}
    dk = z[1439]
    assert dk["yards"] == [6500, 4333.3] and dk["rect"] == [0.3, 0.4, 0.1, 0.3]
    assert dk["name"] == "Darkshore" and dk["continent"] == 1414 and dk["faction"] == "Alliance"
    assert dk["live"] is True and dk["complete"] is False
    assert dk["links"][0]["to"] == 1440 and dk["links"][0]["label"] == "go"
    assert dk["links"][0]["kind"] == "walk"
    assert z[1440]["yards"] is None and z[1440]["rect"] is None


def test_unknown_link_kind_rejected(tmp_path):
    with pytest.raises(ValueError, match="kind"):
        load_zones(zones_file(tmp_path, kind="teleport"), CENSUS)


def test_tram_and_link_faction_accepted(tmp_path):
    z = load_zones(zones_file(tmp_path, kind="tram", faction='faction = "Horde"'), CENSUS)
    assert z[1439]["links"][0]["kind"] == "tram" and z[1439]["links"][0]["faction"] == "Horde"
    assert load_zones(zones_file(tmp_path), CENSUS)[1439]["links"][0]["faction"] is None


def test_unknown_faction_rejected(tmp_path):
    with pytest.raises(ValueError, match="faction"):
        load_zones(zones_file(tmp_path, faction='faction = "Contested"'), CENSUS)
    p = tmp_path / "z.toml"
    p.write_text(ZONE.format(extra="").replace('"Alliance"', '"Orcs"'))
    with pytest.raises(ValueError, match="faction"):
        load_zones(p, CENSUS)


def test_link_target_must_be_a_zone(tmp_path):
    with pytest.raises(ValueError, match="1500"):
        load_zones(zones_file(tmp_path, to=1500), CENSUS)


def test_coordinates_out_of_range_rejected(tmp_path):
    with pytest.raises(ValueError, match="0-100"):
        load_zones(zones_file(tmp_path, x=101), CENSUS)


def test_zone_missing_from_census_rejected(tmp_path):
    p = tmp_path / "zones.toml"
    p.write_text(ZONE.format(extra="") + '\n[zones.9999]\nname = "Nowhere"\ncontinent = 1414\n'
                 'faction = "Horde"\nlive = true\ncomplete = false\n')
    with pytest.raises(ValueError, match="9999"):
        load_zones(p, CENSUS)
    assert 9999 in load_zones(p, None)   # no census given: no check


def test_level_override_carried(tmp_path):
    p = tmp_path / "zones.toml"
    p.write_text(ZONE.format(extra="").replace('complete = false\n\n[zones.1440]',
                                                'complete = false\nmin_level = 10\nmax_level = 20\n\n[zones.1440]'))
    z = load_zones(p, CENSUS)
    assert (z[1439]["min_level"], z[1439]["max_level"]) == (10, 20)


def test_dungeon_fields():
    assert load_dungeons(CURATED / "dungeons.toml") == {}          # the old hand seed is gone (Task 8i)
    d = load_dungeons(CURATED / "dungeons.toml", CURATED / "dungeons.generated.toml")
    bfd = d["BFD"]                                                  # generated from OpenMap, same key
    assert bfd["name"] == "Blackfathom Deeps" and bfd["entrance"][0] == 1440
    assert (bfd["min_level"], bfd["max_level"], bfd["group_size"]) == (24, 32, 5)
    assert bfd["faction"] == "Both" and bfd["live"] is True and bfd["quests"] == []
    assert bfd["source"] == "openmap"


def dungeon_file(tmp_path, **over):
    fields = {"name": '"X"', "entrance": "[1440, 1.0, 2.0]", "min_level": "1", "max_level": "2",
              "group_size": "5", "faction": '"Both"', "live": "true", "quests": "[1, 2]"}
    fields.update(over)
    p = tmp_path / "dungeons.toml"
    p.write_text("[dungeons.X]\n" + "\n".join(f"{k} = {v}" for k, v in fields.items()) + "\n")
    return p


def test_dungeon_validation(tmp_path):
    assert load_dungeons(dungeon_file(tmp_path))["X"]["quests"] == [1, 2]
    with pytest.raises(ValueError, match="faction"):
        load_dungeons(dungeon_file(tmp_path, faction='"Neutral"'))
    with pytest.raises(ValueError, match="quest"):
        load_dungeons(dungeon_file(tmp_path, quests='[1, "2"]'))
    with pytest.raises(ValueError, match="entrance"):
        load_dungeons(dungeon_file(tmp_path, entrance="[1440, 1.0]"))
    with pytest.raises(ValueError, match="0-100"):
        load_dungeons(dungeon_file(tmp_path, entrance="[1440, 1.0, 200]"))


def test_zone_and_link_ints_type_checked(tmp_path):
    with pytest.raises(ValueError, match=r"zone 1439.*link.*'to'"):
        load_zones(zones_file(tmp_path, to='"1440"'), CENSUS)
    p = tmp_path / "z.toml"
    base = ZONE.format(extra="")
    p.write_text(base.replace("continent = 1414", 'continent = "1414"', 1))
    with pytest.raises(ValueError, match=r"zone 1439.*continent"):
        load_zones(p, CENSUS)
    p.write_text(base.replace("complete = false", 'complete = false\nmin_level = 5.5', 1))
    with pytest.raises(ValueError, match=r"zone 1439.*min_level"):
        load_zones(p, CENSUS)


def test_zone_continent_is_optional_for_continentless_zones(tmp_path):
    """A Forever zone the census gives no continent (Zephras Isle) omits it rather than invent one."""
    p = tmp_path / "z.toml"
    p.write_text(ZONE.format(extra="").replace("continent = 1414\n", "", 1))
    z = load_zones(p, CENSUS)
    assert z[1439]["continent"] is None and z[1440]["continent"] == 1414


def test_curated_zone_kind_validated(tmp_path):
    p = tmp_path / "zones.toml"
    p.write_text(ZONE.format(extra='kind = "city"\n').replace(
        "[zones.1440]", "[zones.1440]\nkind = \"battleground\"", 1))
    z = load_zones(p, CENSUS)
    assert z[1439]["kind"] == "city" and z[1440]["kind"] == "battleground"
    p.write_text(ZONE.format(extra=""))
    assert "kind" not in load_zones(p, CENSUS)[1439]
    for bad in ('"dungeon"', "3", '""'):
        p.write_text(ZONE.format(extra=f"kind = {bad}\n"))
        with pytest.raises(ValueError, match="kind"):
            load_zones(p, CENSUS)
