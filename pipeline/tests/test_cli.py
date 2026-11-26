"""CLI fold-ins (Task 6 rulings)."""
import pipeline.__main__ as cli


def test_crawl_first_request_waits_after_robots(tmp_path, monkeypatch):
    """robots.txt counts as a request: the first crawl request waits min_interval after it."""
    seen = {}

    def fake_make_http_get(timeout):
        return lambda url, headers: (200, "User-agent: *\nDisallow:\n")

    def fake_crawl(fetcher, out, max_quests=None, log=print, **kw):
        sleeps = []
        fetcher.sleep = sleeps.append
        fetcher.http_get = lambda url, headers: (200, "<html></html>")
        fetcher.get("https://outof.games/realms/forever/quests/")
        seen["sleeps"], seen["interval"] = sleeps, fetcher.min_interval
        return {}

    monkeypatch.setattr(cli, "make_http_get", fake_make_http_get)
    monkeypatch.setattr(cli, "crawl_outofgames", fake_crawl)
    rc = cli.main(["crawl", "--cache", str(tmp_path / "raw"), "--out", str(tmp_path / "out")])
    assert rc == 0
    assert len(seen["sleeps"]) == 1
    assert 0 < seen["sleeps"][0] <= seen["interval"]
    assert seen["sleeps"][0] > seen["interval"] - 1.0


def _no_network(timeout):
    def get(url, headers):
        raise AssertionError(f"network request to {url}")
    return get


def test_crawl_reparse_is_offline(tmp_path, monkeypatch):
    """crawl --reparse re-parses the cached HTML into JSON without any request (not even robots.txt)."""
    from pathlib import Path
    from pipeline.fetch import PoliteFetcher
    fx = Path(__file__).parent / "fixtures" / "outofgames"
    cache = tmp_path / "raw"
    seed = PoliteFetcher.offline(cache)
    quest = "https://outof.games/realms/forever/quest/4763-the-blackwood-corrupted/"
    listing = ('<table class="fdb-quest-table"><tbody><tr><td><a class="fdb-quest-link" '
               'href="/realms/forever/quest/4763-the-blackwood-corrupted/">q</a></td></tr></tbody></table>')
    for url, text in (("https://outof.games/realms/forever/quests/", listing),
                      (quest, (fx / "quest-4763.html").read_text(encoding="utf-8")),
                      ("https://outof.games/realms/forever/npc/3649-thundris-windweaver/",
                       (fx / "npc-3649.html").read_text(encoding="utf-8"))):
        path = seed.cache_path(url)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    monkeypatch.setattr(cli, "make_http_get", _no_network)
    out = tmp_path / "out"
    assert cli.main(["crawl", "--reparse", "--cache", str(cache), "--out", str(out)]) == 0
    assert (out / "quests" / "4763.json").exists() and (out / "npcs" / "3649.json").exists()


def test_crawl_refresh_lists_flag_and_list_failure_exit_code(tmp_path, monkeypatch):
    seen = {}

    def fake_make_http_get(timeout):
        return lambda url, headers: (200, "User-agent: *\nDisallow:\n")

    def fake_crawl(fetcher, out, max_quests=None, log=print, **kw):
        seen.update(kw)
        return {"list_failed": seen.get("refresh_lists", False)}

    monkeypatch.setattr(cli, "make_http_get", fake_make_http_get)
    monkeypatch.setattr(cli, "crawl_outofgames", fake_crawl)
    args = ["--cache", str(tmp_path / "raw"), "--out", str(tmp_path / "out")]
    assert cli.main(["crawl", *args]) == 0 and seen == {"refresh_lists": False, "reparse": False}
    assert cli.main(["crawl", "--refresh-lists", *args]) == 2        # list page 1 failed: exit 2
    assert seen == {"refresh_lists": True, "reparse": False}
