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
