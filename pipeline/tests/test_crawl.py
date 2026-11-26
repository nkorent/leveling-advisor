import json
from pathlib import Path

from pipeline.crawl import crawl_outofgames
from pipeline.fetch import FetchError

FX = Path(__file__).parent / "fixtures" / "outofgames"
B = "https://outof.games/realms/forever/"
Q4763 = B + "quest/4763-the-blackwood-corrupted/"
Q965 = B + "quest/965-the-tower-of-althalaxx/"
LIST = B + "quests/"


def fx(name):
    return (FX / name).read_text(encoding="utf-8")


def list_page(hrefs, last=1):
    rows = "".join(f'<tr><td><a class="fdb-quest-link" href="{h}">q</a></td></tr>' for h in hrefs)
    links = "".join(f'<a href="/realms/forever/quests/?page={n}">{n}</a>' for n in range(1, last + 1))
    return (f'<table class="fdb-quest-table"><tbody>{rows}</tbody></table>'
            f"<nav data-pagination>{links}</nav>")


class FakeFetcher:
    def __init__(self, pages):
        self.pages = pages
        self.calls = []
        self.requests_made = 0

    def get(self, url):
        self.calls.append(url)
        self.requests_made += 1
        v = self.pages.get(url)
        if v is None and "/npc/" in url:
            v = fx("npc-3649.html")
        if v is None:
            raise FetchError(404, url)
        if isinstance(v, Exception):
            raise v
        return v


def pages(**over):
    p = {
        LIST: list_page(["/realms/forever/quest/4763-the-blackwood-corrupted/",
                         "/realms/forever/quest/965-the-tower-of-althalaxx/"]),
        Q4763: fx("quest-4763.html"),
        Q965: fx("quest-965.html"),
    }
    p.update(over)
    return p


def run(tmp_path, ff, **kw):
    return crawl_outofgames(ff, tmp_path, log=lambda *a: None, **kw)


def test_crawl_writes_quest_and_npc_json(tmp_path):
    res = run(tmp_path, FakeFetcher(pages()))
    assert res["quests"] == 2 and res["errors"] == 0
    q = json.loads((tmp_path / "quests" / "4763.json").read_text())
    assert q["id"] == 4763 and q["giver"]["id"] == 3649
    assert (tmp_path / "quests" / "965.json").exists()
    # npcs: 3649 (giver of 4763), 3657 and 3661 (giver / turn-in of 965)
    assert sorted(p.stem for p in (tmp_path / "npcs").glob("*.json")) == ["3649", "3657", "3661"]
    assert res["npcs"] == 3


def test_crawl_logs_error_and_continues(tmp_path):
    ff = FakeFetcher(pages(**{Q965: FetchError(500, Q965)}))
    res = run(tmp_path, ff)
    assert res["errors"] == 1 and res["quests"] == 1
    assert (tmp_path / "quests" / "4763.json").exists()
    assert not (tmp_path / "quests" / "965.json").exists()
    errs = json.loads((tmp_path / "errors.json").read_text())
    assert errs == [{"url": Q965, "status": 500}]


def test_parse_exception_is_logged_not_raised(tmp_path):
    res = run(tmp_path, FakeFetcher(pages(**{Q965: ValueError("boom")})))
    assert res["errors"] == 1 and res["quests"] == 1
    assert "error" in json.loads((tmp_path / "errors.json").read_text())[0]


def test_rerun_skips_parsed_quests(tmp_path):
    run(tmp_path, FakeFetcher(pages()))
    ff = FakeFetcher(pages())
    res = run(tmp_path, ff)
    assert res["quests"] == 2 and res["npcs"] == 3
    assert not [u for u in ff.calls if "/quest/" in u or "/npc/" in u]


def test_rerun_rewrites_errors_from_this_run_only(tmp_path):
    run(tmp_path, FakeFetcher(pages(**{Q965: FetchError(500, Q965)})))
    res = run(tmp_path, FakeFetcher(pages()))
    assert res["errors"] == 0
    assert json.loads((tmp_path / "errors.json").read_text()) == []


def test_max_quests_fetches_only_one_list_page(tmp_path):
    p = pages()
    p[LIST] = list_page(["/realms/forever/quest/4763-the-blackwood-corrupted/"], last=5)
    ff = FakeFetcher(p)
    res = run(tmp_path, ff, max_quests=1)
    assert [u for u in ff.calls if "/quests/" in u] == [LIST]
    assert res["quests"] == 1
    assert [p.stem for p in (tmp_path / "npcs").glob("*.json")] == ["3649"]


def test_stats_json_written(tmp_path):
    run(tmp_path, FakeFetcher(pages()))
    s = json.loads((tmp_path / "stats.json").read_text())
    assert s["quests"] == 2
    assert s["faction_none"] == 0
    assert s["factions"] == {"Alliance": 2}
    assert s["giver_kinds"] == {"npc": 2}
    assert "warnings" in s and "reward_other_count" in s


# ---------------------------------------------------------------- final review I2: refresh lists, reparse

class RecordingFetcher(FakeFetcher):
    """FakeFetcher whose get() also takes refresh= and records it."""

    def __init__(self, pages):
        super().__init__(pages)
        self.refreshed = []

    def get(self, url, refresh=False):
        if refresh:
            self.refreshed.append(url)
        return super().get(url)


NEW = "/realms/forever/quest/4762-the-cliffspring-river/"
NEW_PAGE = ('<h1 class="fdb-name">The Cliffspring River</h1>'
            '<dl class="fdb-facts"><div><dt>Quest ID</dt><dd>4762</dd></div></dl>')


def test_refresh_lists_refetches_list_pages_and_crawls_only_new_ids(tmp_path):
    two = ["/realms/forever/quest/4763-the-blackwood-corrupted/", "/realms/forever/quest/965-the-tower-of-althalaxx/"]
    run(tmp_path, FakeFetcher(pages(**{LIST: list_page(two, last=2), LIST + "?page=2": list_page([])})))
    later = pages(**{LIST: list_page(two, last=2), LIST + "?page=2": list_page([NEW]), B + NEW[len("/realms/forever/"):]: NEW_PAGE})
    ff = RecordingFetcher(later)
    res = run(tmp_path, ff, refresh_lists=True)
    assert ff.refreshed == [LIST, LIST + "?page=2"]
    assert [u for u in ff.calls if "/quest/" in u] == [B + "quest/4762-the-cliffspring-river/"]
    assert res["quests"] == 3 and res["new_quests"] == 1 and not res["list_failed"]
    assert json.loads((tmp_path / "quests" / "4762.json").read_text())["name"] == "The Cliffspring River"


def test_without_refresh_lists_list_pages_come_from_the_cache(tmp_path):
    ff = RecordingFetcher(pages())
    res = run(tmp_path, ff)
    assert ff.refreshed == [] and res["new_quests"] == 2


def test_reparse_rewrites_quest_and_npc_json_from_the_html(tmp_path):
    run(tmp_path, FakeFetcher(pages()))
    stale = tmp_path / "quests" / "4763.json"
    stale.write_text(json.dumps({"id": 4763, "name": "stale"}))
    (tmp_path / "npcs" / "3649.json").write_text(json.dumps({"id": 3649, "name": "stale"}))
    ff = RecordingFetcher(pages())
    res = run(tmp_path, ff, reparse=True)
    assert ff.refreshed == []                                   # reparse never refreshes a page
    assert json.loads(stale.read_text())["name"] == "The Blackwood Corrupted"
    assert json.loads(stale.read_text())["not_available_after_ids"] == []
    assert json.loads((tmp_path / "npcs" / "3649.json").read_text())["name"] != "stale"
    assert res["quests"] == 2 and res["new_quests"] == 0 and res["reparsed"] == 2


def test_list_page_one_failure_is_flagged(tmp_path):
    res = run(tmp_path, FakeFetcher(pages(**{LIST: FetchError(503, LIST)})))
    assert res["list_failed"] is True
    res = run(tmp_path, FakeFetcher(pages(**{LIST: list_page([])})))
    assert res["list_failed"] is True
