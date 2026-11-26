"""Polite, cached, throttled fetcher. Every crawl goes through PoliteFetcher.get."""
from __future__ import annotations

import json
import os
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable
from urllib.parse import urlsplit

from pipeline.robots import RobotsRules

USER_AGENT = "LevelingAdvisorDataBuilder/0.1"

# Our own allowlist, stricter than robots.txt. Matched against path[?query].
ALLOWED = [
    r"^/realms/forever/quests/(\?page=[0-9]+)?$",
    r"^/realms/forever/quest/[0-9]+-[a-z0-9-]+/$",
    r"^/realms/forever/npc/[0-9]+-[a-z0-9-]+/$",
    r"^/realms/forever/dungeons/$",
    r"^/realms/forever/dungeon/[a-z0-9-]+/$",
]
_ALLOWED_RE = [re.compile(p) for p in ALLOWED]
HOST = "outof.games"


class FetchError(Exception):
    def __init__(self, status: int, url: str = ""):
        super().__init__(f"HTTP {status} for {url}")
        self.status = status
        self.url = url


class NotCachedError(Exception):
    """An offline fetcher was asked for a page that is not in the cache."""


def _path_and_query(url: str) -> str:
    parts = urlsplit(url)
    return parts.path + (f"?{parts.query}" if parts.query else "")


def _atomic_write(path: Path, text: str) -> None:
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


class PoliteFetcher:
    """Throttled, cached, robots- and allowlist-checked fetcher.

    The real http_get MUST NOT follow redirects (requests: allow_redirects=False)
    so that a 3xx comes back as a status and raises FetchError instead of
    silently leaving the checked URL. Any exception raised by http_get
    (timeout, connection error) is wrapped as FetchError(0, url).

    A cached page is returned as is, unless get(url, refresh=True) asks for it again: that request
    is throttled, robots- and allowlist-checked like any other, and replaces the cached page only on
    success. ``PoliteFetcher.offline(cache_dir)`` reads the cache only: it never makes a request and
    raises NotCachedError for a page that is not cached (and PermissionError for a refresh).
    """

    def __init__(
        self,
        cache_dir: Path,
        robots: RobotsRules,
        http_get: Callable[[str, dict], tuple[int, str]],
        clock=time.monotonic,
        sleep=time.sleep,
        min_interval: float = 2.0,
    ):
        self.cache_dir = Path(cache_dir)
        self.robots = robots
        self.http_get = http_get
        self.clock = clock
        self.sleep = sleep
        self.min_interval = min_interval
        self.requests_made = 0
        self._last_start: float | None = None
        self.is_offline = False

    @classmethod
    def offline(cls, cache_dir: Path) -> "PoliteFetcher":
        """A cache-only fetcher (crawl --reparse): no robots.txt, no request, ever."""
        def no_request(url, headers):
            raise PermissionError("offline fetcher: no requests")
        f = cls(cache_dir, RobotsRules(), no_request)
        f.is_offline = True
        return f

    def cache_path(self, url: str) -> Path:
        parts = urlsplit(url)
        path = parts.path if parts.path.endswith("/") else parts.path + "/"
        m = re.fullmatch(r"page=([0-9]+)", parts.query)
        if m:
            path += f"page-{m.group(1)}/"
        result = self.cache_dir / (parts.netloc + path + "index.html")
        if not result.resolve().is_relative_to(self.cache_dir.resolve()):
            raise PermissionError(f"cache path escapes cache dir: {url!r}")
        return result

    def _check_allowed(self, url: str) -> str:
        """Validate url and return the canonical URL to request."""
        try:
            parts = urlsplit(url)
            port = parts.port
        except ValueError as e:
            raise PermissionError(f"malformed URL: {url!r}") from e
        if (
            parts.scheme != "https"
            or parts.hostname != HOST
            or parts.username is not None
            or parts.password is not None
            or port is not None
            or parts.fragment
            or parts.netloc != HOST
        ):
            raise PermissionError(f"URL not permitted: {url!r}")
        pq = _path_and_query(url)
        if not self.robots.allowed(pq):
            raise PermissionError(f"robots.txt disallows {url}")
        if not any(r.fullmatch(pq) for r in _ALLOWED_RE):
            raise PermissionError(f"not in allowlist: {url}")
        return f"https://{HOST}{pq}"

    def get(self, url: str, refresh: bool = False) -> str:
        url = self._check_allowed(url)
        page = self.cache_path(url)
        if self.is_offline:
            if refresh:
                raise PermissionError(f"offline fetcher cannot refresh {url}")
            if not page.exists():
                raise NotCachedError(f"not in the cache: {url}")
        if page.exists() and not refresh:
            return page.read_text(encoding="utf-8")

        now = self.clock()
        if self._last_start is not None:
            interval = max(self.min_interval, self.robots.crawl_delay or 0)
            wait = interval - (now - self._last_start)
            if wait > 0:
                self.sleep(wait)
                now += wait
        self._last_start = now

        self.requests_made += 1
        try:
            status, body = self.http_get(url, {"User-Agent": USER_AGENT})
        except FetchError:
            raise
        except Exception as e:
            raise FetchError(0, url) from e
        if status != 200:
            raise FetchError(status, url)

        page.parent.mkdir(parents=True, exist_ok=True)
        meta = {
            "url": url,
            "fetchedAt": datetime.now(timezone.utc).isoformat(),
            "status": status,
        }
        # meta first: the page file's existence is what marks an entry as cached.
        _atomic_write(page.parent / "meta.json", json.dumps(meta))
        _atomic_write(page, body)
        return body
