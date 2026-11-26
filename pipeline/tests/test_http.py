from pipeline import http


class FakeResp:
    status_code = 200
    content = "bod\u00e9 \u2019".encode("utf-8")


class FakeSession:
    instances = []

    def __init__(self):
        self.calls = []
        FakeSession.instances.append(self)

    def get(self, url, **kw):
        self.calls.append((url, kw))
        return FakeResp()


def test_make_http_get_uses_one_session_no_redirects(monkeypatch):
    FakeSession.instances.clear()
    monkeypatch.setattr(http.requests, "Session", FakeSession)
    get = http.make_http_get(timeout=7)
    assert get("https://outof.games/x/", {"User-Agent": "ua"}) == (200, "bod\u00e9 \u2019")
    get("https://outof.games/y/", {})
    assert len(FakeSession.instances) == 1
    url, kw = FakeSession.instances[0].calls[0]
    assert url == "https://outof.games/x/"
    assert kw == {"headers": {"User-Agent": "ua"}, "timeout": 7, "allow_redirects": False}
