"""The shipped data/curated/zones.toml against the real census (skipped when the census is not built)."""
from pathlib import Path

import pytest

from pipeline.census import read_census_json
from pipeline.curated import load_generated_links, load_zones_with_problems

ROOT = Path(__file__).parents[2]
CENSUS = ROOT / "data" / "census" / "maps.json"
CURATED = ROOT / "data" / "curated"

pytestmark = pytest.mark.skipif(not CENSUS.is_file(), reason="data/census/maps.json not built")


@pytest.fixture(scope="module")
def loaded():
    census = read_census_json(CENSUS)
    zones, problems = load_zones_with_problems(CURATED / "zones.toml", census, CURATED / "links.generated.toml")
    return census, zones, problems


def test_zones_load_against_census_and_every_generated_link_attaches(loaded):
    census, zones, problems = loaded
    assert set(zones) <= set(census["maps"])
    assert problems == []
    rows, _ = load_generated_links(CURATED / "links.generated.toml")
    assert sum(len(z["links"]) for z in zones.values()) >= len(rows)
    assert all(l["to"] in census["maps"] for z in zones.values() for l in z["links"])


def test_expected_factions_and_kinds(loaded):
    _, zones, _ = loaded
    assert {zones[m]["name"]: zones[m]["faction"] for m in (1411, 1454, 1429, 1453)} == {
        "Durotar": "Horde", "Orgrimmar": "Horde", "Elwynn Forest": "Alliance", "Stormwind City": "Alliance"}
    assert zones[1454]["kind"] == "city" and zones[1459]["kind"] == "battleground"
    assert "kind" not in zones[1411]


def test_forever_zones_present_and_continentless_zone_has_no_continent(loaded):
    _, zones, _ = loaded
    assert {m: zones[m]["name"] for m in (2482, 2521, 2524, 2548, 2652)} == {
        2482: "Mount Hyjal", 2521: "Zephras Isle", 2524: "Darkspear Islands", 2548: "Riverglades",
        2652: "Shen'dralas"}
    assert zones[2521]["continent"] is None and zones[2482]["continent"] == 1414
