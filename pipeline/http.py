"""Real HTTP client for PoliteFetcher: one Session, never follows redirects."""
from __future__ import annotations

import requests


def make_http_get(timeout: float = 30):
    session = requests.Session()

    def http_get(url: str, headers: dict) -> tuple[int, str]:
        resp = session.get(url, headers=headers, timeout=timeout, allow_redirects=False)
        return resp.status_code, resp.content.decode("utf-8")

    return http_get
