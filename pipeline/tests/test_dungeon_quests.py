"""Plan 2 Task 8g: dungeon quest lists from outof.games dungeon pages."""
import json
from pathlib import Path

import pytest

from pipeline.crawl import crawl_dungeons
from pipeline.curated import load_dungeons
from pipeline.dungeon_quests import build_quest_lists, match_dungeons, write_quests_toml
from pipeline.fetch import PoliteFetcher
from pipeline.outofgames import parse_dungeon, parse_dungeon_list
from pipeline.robots import RobotsRules

FX = Path(__file__).parent / "fixtures" / "outofgames"
B = "https://outof.games/realms/forever/"
ROBOTS = (Path(__file__).parents[2] / "data" / "raw" / "outof.games" / "robots.txt")


def fx(name):
    return (FX / name).read_text(encoding="utf-8")


def test_parse_dungeon_quest_ids():
    d = parse_dungeon(fx("dungeon-blackfathom-deeps.html"))
    assert d["name"] == "Blackfathom Deeps" and d["slug"] == "blackfathom-deeps"
    assert d["quest_ids"] == [971, 1275, 78916, 1199, 1200, 6564, 6563, 6562, 78917, 6565, 6921, 6561, 6922,
                              1198, 1740]
    assert 9999 not in d["quest_ids"]          # the "Related" decoy link is not a dungeon quest
    assert (d["min_level"], d["max_level"], d["zone_name"]) == (19, 24, "Ashenvale")
    s = parse_dungeon(fx("dungeon-the-stockade.html"))
    assert s["slug"] == "the-stockade" and s["quest_ids"] == [386, 377, 387, 388, 378, 391]
    assert s["zone_name"] == "Stormwind City"


def test_parse_dungeon_list_finds_pages_not_slugs():
    html = ('<a href="/realms/forever/dungeon/foo-bar/">x</a><a href="/realms/forever/dungeon/foo-bar/">x</a>'
            '<a href="/realms/forever/dungeons/">all</a><a href="/realms/forever/quest/1-a/">q</a>')
    assert parse_dungeon_list(html) == ["/realms/forever/dungeon/foo-bar/"]


GEN = {
    "SMLIB": {"name": "Scarlet Monastery - Library"}, "SMARM": {"name": "Scarlet Monastery - Armory"},
    "DEAD": {"name": "Deadmines"}, "STOCK": {"name": "Stormwind Stockade"}, "DMN": {"name": "Dire Maul - North"},
    "DROWN": {"name": "The Drowned City"}, "HALL": {"name": "The Hall of Thanes"}, "EXC": {"name": "Excavation Site: Wetlands"},
    "ZF": {"name": "Zul'Farrak"}, "ST": {"name": "Sunken Temple"}, "KROL": {"name": "Krol'dok Stronghold"}, "SHAPE": {"name": "Shaper's Terrace"},
}


def test_dungeon_name_matching():
    pages = [{"name": n, "slug": n.lower().replace(" ", "-")} for n in (
        "THE DEADMINES", "The Stockade", "Dire Maul North", "Scarlet Monastery - Library", "Drowned City",
        "Hall of Thanes", "Excavation Site Wetlands", "Zulfarrak", "Krol'dok Stronghold", "Shapers Terrace",
        "Scarlet Monastery", "Barrow Deeps", "The Temple of Atal'Hakkar")]
    m, unmatched = match_dungeons(pages, GEN)
    by = {p["name"]: keys for p, keys in m}
    assert by["THE DEADMINES"] == ["DEAD"]
    assert by["Dire Maul North"] == ["DMN"]
    assert by["Scarlet Monastery - Library"] == ["SMLIB"]
    assert by["Drowned City"] == ["DROWN"] and by["Hall of Thanes"] == ["HALL"]
    assert by["Excavation Site Wetlands"] == ["EXC"] and by["Zulfarrak"] == ["ZF"]
    assert by["Krol'dok Stronghold"] == ["KROL"] and by["Shapers Terrace"] == ["SHAPE"]
    # a whole-complex page matches every wing; a page whose words all sit in one OpenMap name matches it
    assert sorted(by["Scarlet Monastery"]) == ["SMARM", "SMLIB"]
    assert by["The Stockade"] == ["STOCK"] and by["The Temple of Atal'Hakkar"] == ["ST"]
    assert [p["name"] for p in unmatched] == ["Barrow Deeps"]


def test_dungeon_word_match_must_be_unambiguous():
    """A page whose words all occur in two dungeon names (and that is no complex) stays unmatched."""
    gen = {"UBRS": {"name": "Upper Blackrock Spire"}, "LBRS": {"name": "Lower Blackrock Spire"},
           "BRD": {"name": "Blackrock Depths"}}
    pages = [{"name": n, "slug": n.lower().replace(" ", "-")} for n in (
        "Blackrock Spire", "Upper Blackrock Spire", "Blackrock Depths")]
    m, unmatched = match_dungeons(pages, gen)
    assert {p["name"]: keys for p, keys in m} == {"Upper Blackrock Spire": ["UBRS"], "Blackrock Depths": ["BRD"]}
    assert [p["name"] for p in unmatched] == ["Blackrock Spire"]


def test_dungeon_quests_merge_by_key(tmp_path):
    pages = [{"name": "Deadmines", "slug": "the-deadmines", "quest_ids": [1, 2, 3, 999]},
             {"name": "Scarlet Monastery", "slug": "scarlet-monastery", "quest_ids": [2]},
             {"name": "Maraudon", "slug": "maraudon", "quest_ids": []}]
    gen = dict(GEN, MARA={"name": "Maraudon"})
    lists, report = build_quest_lists(pages, gen, known_quest_ids={1, 2, 3})
    assert lists == {"DEAD": [1, 2, 3], "SMARM": [2], "SMLIB": [2], "MARA": []}
    assert report["ambiguous_wing"] == {"Scarlet Monastery": ["SMARM", "SMLIB"]}
    assert report["zero_quests"] == ["DMN", "DROWN", "EXC", "HALL", "KROL", "MARA", "SHAPE", "ST", "STOCK", "ZF"]
    assert report["dropped_unknown_quests"] == {"DEAD": [999]}

    toml = tmp_path / "dungeons.quests.generated.toml"
    write_quests_toml(lists, toml)
    assert "outof.games" in toml.read_text().splitlines()[0]

    entry = lambda name, q: (f'name = "{name}"\nentrance = [1440, 1.0, 2.0]\nmin_level = 1\nmax_level = 9\n'
                             f'group_size = 5\nfaction = "Both"\nlive = true\nquests = {q}\n')
    (tmp_path / "dungeons.toml").write_text('[dungeons.DEAD]\n' + entry("Deadmines", "[7]"))
    gen_toml = tmp_path / "dungeons.generated.toml"
    gen_toml.write_text("".join(f'[dungeons.{k}]\n' + entry(v["name"], "[]") + 'source = "openmap"\n\n'
                                for k, v in gen.items() if k in ("DEAD", "SMLIB")))
    d = load_dungeons(tmp_path / "dungeons.toml", gen_toml, quests_generated=toml)
    assert d["DEAD"]["quests"] == [7]            # curated wins
    assert d["SMLIB"]["quests"] == [2]           # generated list merged by key


class Clock:
    def __init__(self):
        self.t = 0.0
        self.sleeps = []

    def now(self):
        return self.t

    def sleep(self, s):
        self.sleeps.append(s)
        self.t += s


@pytest.mark.skipif(not ROBOTS.is_file(), reason="data/raw/outof.games/robots.txt not fetched (data/raw is not in git)")
def test_dungeon_crawl_respects_robots_and_interval(tmp_path):
    robots = RobotsRules.parse(ROBOTS.read_text(encoding="utf-8"), agent="LevelingAdvisorDataBuilder")
    assert not robots.allowed("/api/v2/forever/quests/")
    clock, urls = Clock(), []
    list_html = ('<a href="/realms/forever/dungeon/the-stockade/">s</a>'
                 '<a href="/realms/forever/dungeon/blackfathom-deeps/">b</a>')
    pages = {B + "dungeons/": list_html,
             B + "dungeon/the-stockade/": fx("dungeon-the-stockade.html"),
             B + "dungeon/blackfathom-deeps/": fx("dungeon-blackfathom-deeps.html")}

    def http_get(url, headers):
        urls.append((url, clock.now(), headers["User-Agent"]))
        return 200, pages[url]

    f = PoliteFetcher(tmp_path / "raw", robots, http_get, clock=clock.now, sleep=clock.sleep)
    out = tmp_path / "out"
    res = crawl_dungeons(f, out, log=lambda *a: None)
    assert res["dungeons"] == 2 and res["requests"] == 3 and res["errors"] == 0
    assert [u for u, _, _ in urls] == [B + "dungeons/", B + "dungeon/the-stockade/", B + "dungeon/blackfathom-deeps/"]
    times = [t for _, t, _ in urls]
    assert all(b - a >= 2.0 for a, b in zip(times, times[1:]))
    assert all("/api/v2/forever/" not in u and "/quest/" not in u and "/npc/" not in u for u, _, _ in urls)
    assert {ua for _, _, ua in urls} == {"LevelingAdvisorDataBuilder/0.1"}
    assert json.loads((out / "dungeons" / "the-stockade.json").read_text())["quest_ids"][0] == 386
    # a re-run is served from the cache: no new requests
    res2 = crawl_dungeons(f, out, log=lambda *a: None)
    assert res2["requests"] == 3 and len(urls) == 3


def test_listed_dungeon_quest_gets_key_and_flag(tmp_path):
    from pipeline.tests.test_build import (build, census_fixture, dungeons_fixture, fixture_quest,
                                           fixture_questie, load_data, oq, thundris, zones_fixture)
    oog = {4763: fixture_quest(4763), 501: oq(501, quest_level=24, tags=["Alliance"])}   # no Dungeon tag
    build(oog, {3649: thundris()}, fixture_questie(), {}, tmp_path / "Data", tmp_path / "r.json",
          provisional=False, census=census_fixture(), zones=zones_fixture(), dungeons=dungeons_fixture(),
          built="2026-11-25")
    q = load_data(tmp_path / "Data").quests[501]
    assert q[23] == "BFD"
    assert q[9] & 32          # Contract A field 9 flags, bit 32 dungeon_quest


def test_dungeon_key_by_level_fit():
    from pipeline.build import choose_dungeon_key
    d = {"LBS": {"min_level": 45, "max_level": 55}, "UBS": {"min_level": 55, "max_level": 60},
         "A": {"min_level": 10, "max_level": 20}, "B": {"min_level": 10, "max_level": 20},
         "X": {"min_level": 30, "max_level": 34}, "Y": {"min_level": 40, "max_level": 44}}
    assert choose_dungeon_key(58, ["LBS", "UBS"], d) == "UBS"
    assert choose_dungeon_key(48, ["UBS", "LBS"], d) == "LBS"
    assert choose_dungeon_key(55, ["LBS", "UBS"], d) == "UBS"      # both contain 55: centre 57.5 is nearer
    assert choose_dungeon_key(15, ["B", "A"], d) == "A"            # tie -> sorted key
    assert choose_dungeon_key(38, ["X", "Y"], d) == "Y"            # none contains: smallest distance
    assert choose_dungeon_key(37, ["Y", "X"], d) == "X"            # equal distance -> sorted key
    assert choose_dungeon_key(None, ["UBS", "LBS"], d) == "LBS"


def test_single_word_subset_never_matches():
    gen = {"SS": {"name": "Stormwind Stockade"}, "ST": {"name": "Sunken Temple"}}
    m, unmatched = match_dungeons([{"name": "Temple"}, {"name": "The Stockade Prison"}], gen)
    assert m == [] and len(unmatched) == 2
    m, _ = match_dungeons([{"name": "Stormwind Stockade Annex"}], gen)
    assert m == []                                                 # extra words are not a subset
    m, _ = match_dungeons([{"name": "Sunken Temple"}], gen)
    assert m[0][1] == ["ST"]


def test_cli_dungeon_crawl_exits_2_when_list_page_fails(tmp_path, monkeypatch):
    import pipeline.__main__ as cli
    monkeypatch.setattr(cli, "make_http_get", lambda timeout: (lambda url, h: (200, "User-agent: *\nDisallow:\n")
                                                              if url.endswith("robots.txt") else (503, "")))
    monkeypatch.setattr("pipeline.fetch.time.sleep", lambda s: None)
    rc = cli.main(["crawl", "--dungeons", "--cache", str(tmp_path / "raw"), "--out", str(tmp_path / "out")])
    assert rc == 2
