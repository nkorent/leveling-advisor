import json

import pytest

from pipeline.fetch import ALLOWED, FetchError, PoliteFetcher
from pipeline.robots import RobotsRules

ROBOTS = RobotsRules.parse(
    "User-agent: *\n"
    "Disallow: /realms/forever/quests/?page=*&\n"
    "Allow: /realms/forever/quests/?page=\n"
    "Disallow: /realms/forever/quests/?\n"
    "Disallow: /api/v2/forever/\n"
)
QUEST = "https://outof.games/realms/forever/quest/4763-the-blackwood-corrupted/"


class Http:
    def __init__(self, status=200, body="<html>ok</html>"):
        self.calls = []
        self.status, self.body = status, body

    def __call__(self, url, headers):
        self.calls.append((url, headers))
        return self.status, self.body


class Clock:
    def __init__(self, times):
        self.times = list(times)

    def __call__(self):
        return self.times.pop(0)


def make(tmp_path, http=None, clock=None, sleeps=None):
    sleeps = [] if sleeps is None else sleeps
    return PoliteFetcher(
        tmp_path, ROBOTS, http or Http(), clock=clock or Clock([0.0] * 10), sleep=sleeps.append
    )


def test_cache_hit_makes_no_request(tmp_path):
    http = Http()
    f = make(tmp_path, http)
    assert f.get(QUEST) == "<html>ok</html>"
    assert f.get(QUEST) == "<html>ok</html>"
    assert f.requests_made == 1 and len(http.calls) == 1
    p = f.cache_path(QUEST)
    assert p == tmp_path / "outof.games/realms/forever/quest/4763-the-blackwood-corrupted/index.html"
    meta = json.loads((p.parent / "meta.json").read_text())
    assert meta["url"] == QUEST and meta["status"] == 200 and "fetchedAt" in meta
    assert not list(p.parent.glob("*.tmp"))


def test_waits_two_seconds_between_requests(tmp_path):
    sleeps = []
    f = make(tmp_path, clock=Clock([0.0, 0.5, 2.0]), sleeps=sleeps)
    f.get(QUEST)
    f.get("https://outof.games/realms/forever/dungeons/")
    assert sleeps == [1.5]


def test_no_wait_when_interval_elapsed(tmp_path):
    sleeps = []
    f = make(tmp_path, clock=Clock([0.0, 5.0, 5.0]), sleeps=sleeps)
    f.get(QUEST)
    f.get("https://outof.games/realms/forever/dungeons/")
    assert sleeps == []


def test_disallowed_url_raises_permission_error(tmp_path):
    http = Http()
    f = make(tmp_path, http)
    with pytest.raises(PermissionError):
        f.get("https://outof.games/api/v2/forever/x")
    assert http.calls == [] and f.requests_made == 0


def test_query_not_in_allowlist_raises(tmp_path):
    http = Http()
    f = make(tmp_path, http)
    with pytest.raises(PermissionError):
        f.get("https://outof.games/realms/forever/quests/?faction=horde")
    with pytest.raises(PermissionError):
        f.get("https://outof.games/realms/forever/quests/?page=2&sort=xp")
    assert http.calls == []


def test_page_query_allowed_and_cached_under_page_dir(tmp_path):
    f = make(tmp_path)
    url = "https://outof.games/realms/forever/quests/?page=3"
    f.get(url)
    assert f.cache_path(url) == tmp_path / "outof.games/realms/forever/quests/page-3/index.html"
    assert f.cache_path(url).exists()


def test_error_status_is_not_cached(tmp_path):
    f = make(tmp_path, Http(500, ""))
    with pytest.raises(FetchError) as e:
        f.get(QUEST)
    assert e.value.status == 500
    assert not f.cache_path(QUEST).exists()
    assert not (f.cache_path(QUEST).parent / "meta.json").exists()


def test_user_agent_header(tmp_path):
    http = Http()
    make(tmp_path, http).get(QUEST)
    assert http.calls[0][1] == {"User-Agent": "LevelingAdvisorDataBuilder/0.1"}


def test_allowlist_shapes():
    ok = ["/realms/forever/quests/", "/realms/forever/quests/?page=12",
          "/realms/forever/dungeons/", "/realms/forever/dungeon/deadmines/",
          "/realms/forever/npc/3649-thundris-windweaver/"]
    bad = ["/api/v2/forever/quests", "/realms/forever/quests/?sort=xp", "/realms/forever/quest/x/"]
    import re
    assert all(any(re.match(p, s) for p in ALLOWED) for s in ok)
    assert not any(any(re.match(p, s) for p in ALLOWED) for s in bad)


@pytest.mark.parametrize("url", [
    "http://evil.example/realms/forever/dungeons/",
    "http://outof.games/realms/forever/dungeons/",
    "https:///realms/forever/dungeons/",
    "https://outof.games@evil.com/realms/forever/dungeons/",
    "https://outof.games:8443/realms/forever/dungeons/",
    "https://../realms/forever/dungeons/",
    "https://outof.games/realms/forever/dungeons/#frag",
])
def test_bad_scheme_or_host_rejected(tmp_path, url):
    http = Http()
    f = make(tmp_path, http)
    with pytest.raises(PermissionError):
        f.get(url)
    assert http.calls == [] and f.requests_made == 0
    assert list(tmp_path.rglob("*")) == []


def test_robots_check_independent_of_allowlist(tmp_path):
    robots = RobotsRules.parse("User-agent: *\nDisallow: /realms/forever/dungeons/\n")
    http = Http()
    f = PoliteFetcher(tmp_path, robots, http, clock=Clock([0.0]), sleep=lambda s: None)
    with pytest.raises(PermissionError, match="robots"):
        f.get("https://outof.games/realms/forever/dungeons/")
    assert http.calls == []


def test_allowlist_check_independent_of_robots(tmp_path):
    robots = RobotsRules.parse("User-agent: *\nDisallow:\n")
    http = Http()
    f = PoliteFetcher(tmp_path, robots, http, clock=Clock([0.0]), sleep=lambda s: None)
    with pytest.raises(PermissionError, match="allowlist"):
        f.get("https://outof.games/realms/forever/quests/?faction=horde")
    assert http.calls == []


def test_allowlist_is_fully_anchored(tmp_path):
    f = make(tmp_path)
    with pytest.raises(PermissionError):
        f.get("https://outof.games/realms/forever/dungeons/extra/")


def test_http_exception_wrapped_and_not_cached(tmp_path):
    def boom(url, headers):
        raise TimeoutError("slow")
    f = PoliteFetcher(tmp_path, ROBOTS, boom, clock=Clock([0.0]), sleep=lambda s: None)
    with pytest.raises(FetchError) as e:
        f.get(QUEST)
    assert e.value.status == 0 and isinstance(e.value.__cause__, TimeoutError)
    assert not f.cache_path(QUEST).exists()


def test_crawl_delay_raises_interval(tmp_path):
    robots = RobotsRules.parse("User-agent: *\nCrawl-delay: 5\n")
    assert robots.crawl_delay == 5.0
    sleeps = []
    f = PoliteFetcher(tmp_path, robots, Http(), clock=Clock([0.0, 0.0]), sleep=sleeps.append)
    f.get(QUEST)
    f.get("https://outof.games/realms/forever/dungeons/")
    assert sleeps == [5.0]


def test_allowlist_is_ascii_only(tmp_path):
    f = make(tmp_path)
    for url in (
        "https://outof.games/realms/forever/quests/?page=٣",
        "https://outof.games/realms/forever/quest/٤٥-x/",
    ):
        with pytest.raises(PermissionError):
            f.get(url)


def test_cache_path_escape_raises_permission_error(tmp_path):
    f = make(tmp_path)
    with pytest.raises(PermissionError):
        f.cache_path("https://outof.games/../../../etc/x/")


# ---------------------------------------------------------------- final review I2: refresh and offline reads

LIST = "https://outof.games/realms/forever/quests/"


def test_refresh_refetches_a_cached_page_politely_and_overwrites_it(tmp_path):
    http, sleeps = Http(body="old"), []
    f = make(tmp_path, http, clock=Clock([0.0, 0.5]), sleeps=sleeps)
    assert f.get(LIST) == "old"
    http.body = "new"
    assert f.get(LIST) == "old" and f.requests_made == 1       # a plain get still reads the cache
    assert f.get(LIST, refresh=True) == "new"
    assert f.requests_made == 2 and sleeps == [1.5]            # still at most one request every 2 s
    assert f.cache_path(LIST).read_text() == "new"
    assert f.get(LIST) == "new" and f.requests_made == 2


def test_failed_refresh_keeps_the_cached_page(tmp_path):
    http = Http(body="old")
    f = make(tmp_path, http)
    f.get(LIST)
    http.status, http.body = 503, ""
    with pytest.raises(FetchError):
        f.get(LIST, refresh=True)
    assert f.cache_path(LIST).read_text() == "old"


def test_refresh_keeps_the_allowlist_and_robots(tmp_path):
    http = Http()
    f = make(tmp_path, http)
    for url in ("https://outof.games/api/v2/forever/quests", "https://outof.games/realms/forever/quests/?sort=xp"):
        with pytest.raises(PermissionError):
            f.get(url, refresh=True)
    assert http.calls == []


def test_offline_fetcher_reads_the_cache_and_never_requests(tmp_path):
    from pipeline.fetch import NotCachedError
    make(tmp_path).get(QUEST)                                    # put one page in the cache

    def no_network(url, headers):
        raise AssertionError("offline fetcher made a request")
    f = PoliteFetcher.offline(tmp_path)
    f.http_get = no_network
    assert f.get(QUEST) == "<html>ok</html>"
    with pytest.raises(NotCachedError):
        f.get("https://outof.games/realms/forever/dungeons/")
    with pytest.raises(PermissionError):
        f.get(QUEST, refresh=True)                               # cannot refresh without the network
    with pytest.raises(PermissionError):
        f.get("https://outof.games/api/v2/forever/quests")       # the allowlist still applies
    assert f.requests_made == 0
