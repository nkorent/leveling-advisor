import json
from pathlib import Path

import pytest

import pipeline.__main__ as cli
from pipeline.census import load_census

FIXTURE = Path(__file__).parent / "fixtures" / "census" / "LevelingAdvisorDiag.lua"


def test_census_maps_and_here():
    c = load_census(FIXTURE)
    assert set(c["maps"]) == {947, 1414, 1439, 1440}
    dk = c["maps"][1439]
    assert dk == {"name": "Darkshore", "mapType": 3, "parent": 1414, "yards": [6500, 4333.3],
                  "continent": 1414, "rect": [0.3, 0.4, 0.1, 0.3]}
    assert c["maps"][947]["continent"] is None and c["maps"][947]["rect"] is None
    assert c["maps"][1440]["yards"] is None
    assert c["areas"] == {148: "Darkshore", 331: "Ashenvale"}
    assert len(c["here"]) == 1
    h = c["here"][0]
    assert (h["npcID"], h["mapID"], h["x"], h["y"]) == (3516, 1439, 37.3, 40.5)
    assert isinstance(h["npcID"], int)


def test_census_is_sandboxed(tmp_path):
    p = tmp_path / "evil.lua"
    p.write_text('LevelingAdvisorDiagDB = {census={maps={}}}\nos.execute("touch pwned")\n')
    with pytest.raises(ValueError):
        load_census(p)
    assert not Path("pwned").exists()


def test_census_missing_db(tmp_path):
    p = tmp_path / "x.lua"
    p.write_text("Other = {}")
    with pytest.raises(ValueError):
        load_census(p)


def test_cli_census_converts(tmp_path, capsys):
    out = tmp_path / "maps.json"
    rc = cli.main(["census", "--input", str(FIXTURE), "--out", str(out)])
    assert rc == 0
    data = json.loads(out.read_text())
    assert "1439" in data["maps"] and len(data["here"]) == 1
    printed = capsys.readouterr().out
    assert "4 maps" in printed and "1 continents" in printed and "1 here" in printed


def test_cli_census_missing_input(tmp_path, capsys):
    rc = cli.main(["census", "--input", str(tmp_path / "nope.lua"), "--out", str(tmp_path / "m.json")])
    assert rc == 2
    assert "not found" in capsys.readouterr().err


def test_dense_areas_table_keeps_ids(tmp_path):
    p = tmp_path / "x.lua"
    p.write_text('LevelingAdvisorDiagDB = {census={maps={[1]={name="A"}}}, areas={"One","Two"}}')
    assert load_census(p)["areas"] == {1: "One", 2: "Two"}


def test_read_census_json_keys_are_ints(tmp_path):
    from pipeline.census import read_census_json
    p = tmp_path / "maps.json"
    p.write_text(json.dumps({"maps": {"1414": {"name": "Kalimdor"}}, "here": [{"npc": 1}]}), encoding="utf-8")
    assert read_census_json(p) == {"maps": {1414: {"name": "Kalimdor"}}, "areas": {}, "here": [{"npc": 1}]}


@pytest.mark.parametrize("body", ["[1, 2]", '{"maps": [1]}', "not json"])
def test_read_census_json_rejects_a_bad_file_with_valueerror(tmp_path, body):
    from pipeline.census import read_census_json
    p = tmp_path / "maps.json"
    p.write_text(body, encoding="utf-8")
    with pytest.raises(ValueError, match="unreadable census"):
        read_census_json(p)
    with pytest.raises(ValueError, match="unreadable census"):
        read_census_json(tmp_path / "missing.json")


def test_build_with_a_non_object_maps_json_exits_2(tmp_path, capsys):
    from pipeline.tests.test_build import cli_paths, write_oog
    from pipeline.tests.test_merge import oq
    write_oog(tmp_path / "oog", [oq(1)])
    (tmp_path / "census").mkdir()
    (tmp_path / "census" / "maps.json").write_text("[1, 2]", encoding="utf-8")
    (tmp_path / "curated").mkdir()
    for name in ("zones.toml", "dungeons.toml"):
        (tmp_path / "curated" / name).write_text("", encoding="utf-8")
    assert cli.main(["build", "--without", "questie", "openmap", *cli_paths(tmp_path)]) == 2
    assert "unreadable census" in capsys.readouterr().err
    assert not (tmp_path / "Data").exists()
