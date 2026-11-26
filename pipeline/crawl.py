"""Resumable crawl of outof.games quests and NPCs (all requests go through PoliteFetcher).

A plain crawl reads every page from the raw cache when it is there, and reuses the parsed JSON of
quests and NPCs it has already parsed, so a re-run only fetches what is missing. Two options refresh it
(see pipeline/README.md, "After a game patch"):

* ``refresh_lists``: the quest list pages (page 1, then 2..N from page 1's pagination) are requested
  again, politely, so quest ids added since the last crawl are found and crawled; known ids are not
  refetched.
* ``reparse``: the parsed JSON of every listed quest and of their NPCs is rebuilt from the HTML (the
  cached page; a page missing from the cache is fetched, or with an offline fetcher counted as an
  error). Use it after a parser change.

The result says ``list_failed`` when list page 1 could not be read or listed no quest (the CLI then
exits 2: a silently shrunken crawl must not look like a complete one).
"""
from __future__ import annotations

import json
import os
import re
import time
from collections import Counter
from pathlib import Path

from pipeline.fetch import FetchError
from pipeline.outofgames import parse_dungeon, parse_dungeon_list, parse_npc, parse_quest, parse_quest_list

BASE = "https://outof.games"
LIST_URL = BASE + "/realms/forever/quests/"
DUNGEON_LIST_URL = BASE + "/realms/forever/dungeons/"
_QUEST_ID_RE = re.compile(r"/quest/([0-9]+)-")


def _write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, sort_keys=True, indent=1, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, path)


def _stats(quests: list[dict]) -> dict:
    warnings, factions, kinds = Counter(), Counter(), Counter()
    none_faction = other = 0
    for q in quests:
        if q.get("faction") is None:
            none_faction += 1
        else:
            factions[q["faction"]] += 1
        warnings.update(q.get("warnings") or [])
        kinds[(q.get("giver") or {}).get("kind") or "none"] += 1
        other += len((q.get("rewards") or {}).get("other") or [])
    return {
        "quests": len(quests),
        "faction_none": none_faction,
        "factions": dict(factions),
        "reward_other_count": other,
        "warnings": dict(warnings),
        "giver_kinds": dict(kinds),
    }


def crawl_outofgames(fetcher, out_dir: Path, max_quests: int | None = None, log=print,
                     refresh_lists: bool = False, reparse: bool = False) -> dict:
    out_dir = Path(out_dir)
    errors: list[dict] = []
    started = time.monotonic()

    def get(url: str, refresh: bool = False) -> str:
        before = fetcher.requests_made
        html = fetcher.get(url, refresh=True) if refresh else fetcher.get(url)
        log(f"{'GET' if fetcher.requests_made > before else 'cached'} {url}")
        return html

    def fail(url: str, exc: Exception) -> None:
        errors.append({"url": url, "status": exc.status} if isinstance(exc, FetchError)
                      else {"url": url, "error": f"{type(exc).__name__}: {exc}"})
        log(f"ERROR {url}: {exc}")
        _write_json(out_dir / "errors.json", errors)

    _write_json(out_dir / "errors.json", errors)

    # 1-2. list pages
    hrefs: list[str] = []
    seen: set[str] = set()

    def add(found):
        for h in found:
            if h not in seen:
                seen.add(h)
                hrefs.append(h)

    last, list_failed = 1, False
    try:
        found, last = parse_quest_list(get(LIST_URL, refresh_lists))
        add(found)
        list_failed = not found
    except Exception as e:  # noqa: BLE001
        list_failed = True
        fail(LIST_URL, e)
    page = 2
    while page <= last and not (max_quests is not None and len(hrefs) >= max_quests):
        url = f"{LIST_URL}?page={page}"
        try:
            add(parse_quest_list(get(url, refresh_lists))[0])
        except Exception as e:  # noqa: BLE001
            fail(url, e)
        page += 1
    if max_quests is not None:
        hrefs = hrefs[:max_quests]
    log(f"{len(hrefs)} quest links collected")

    # 3. quests
    quests: list[dict] = []
    new_quests = reparsed = 0
    for i, href in enumerate(hrefs, 1):
        url = BASE + href
        m = _QUEST_ID_RE.search(href)
        cached = out_dir / "quests" / f"{m.group(1)}.json" if m else None
        try:
            known = cached is not None and cached.exists()
            if known and not reparse:
                q = json.loads(cached.read_text(encoding="utf-8"))
            else:
                q = parse_quest(get(url), url)
                if q.get("id") is None:
                    raise ValueError("quest page has no id")
                _write_json(out_dir / "quests" / f"{q['id']}.json", q)
                new_quests += not known
                reparsed += known
            quests.append(q)
        except Exception as e:  # noqa: BLE001
            fail(url, e)
        if i % 50 == 0:
            elapsed = time.monotonic() - started
            eta = elapsed / i * (len(hrefs) - i)
            log(f"progress: {i}/{len(hrefs)} quests, {len(errors)} errors, "
                f"{fetcher.requests_made} requests, ETA {eta / 60:.0f} min (quests only)")

    # 4-5. npcs
    npc_ids = sorted({p["id"] for q in quests for p in (q.get("giver"), q.get("turn_in"))
                      if p and p.get("kind") == "npc"})
    slugs = {p["id"]: p.get("slug") for q in quests for p in (q.get("giver"), q.get("turn_in"))
             if p and p.get("kind") == "npc"}
    npcs = 0
    for i, nid in enumerate(npc_ids, 1):
        path = out_dir / "npcs" / f"{nid}.json"
        if path.exists() and not reparse:
            npcs += 1
            continue
        url = f"{BASE}/realms/forever/npc/{nid}-{slugs.get(nid) or 'x'}/"
        try:
            npc = parse_npc(get(url), url)
            npc["id"] = nid
            _write_json(path, npc)
            npcs += 1
        except Exception as e:  # noqa: BLE001
            fail(url, e)
        if i % 50 == 0:
            log(f"progress: {i}/{len(npc_ids)} npcs, {len(errors)} errors, {fetcher.requests_made} requests")

    _write_json(out_dir / "stats.json", _stats(quests))
    log(f"{len(quests)} quests ({new_quests} new, {reparsed} re-parsed), {npcs} npcs, {len(errors)} errors")
    return {"quests": len(quests), "new_quests": new_quests, "reparsed": reparsed, "npcs": npcs,
            "errors": len(errors), "requests": fetcher.requests_made, "list_failed": list_failed}


def crawl_dungeons(fetcher, out_dir: Path, log=print, refresh_lists: bool = False) -> dict:
    """The dungeon list page, then every dungeon page it links (no quest or NPC pages).

    HTML is cached by the fetcher, so a re-run requests only missing pages; every page is parsed again
    on each run into out_dir/dungeons/<slug>.json. refresh_lists requests the dungeon list page again.
    """
    out_dir = Path(out_dir)
    errors: list[dict] = []

    def get(url: str, refresh: bool = False) -> str:
        before = fetcher.requests_made
        html = fetcher.get(url, refresh=True) if refresh else fetcher.get(url)
        log(f"{'GET' if fetcher.requests_made > before else 'cached'} {url}")
        return html

    def fail(url: str, exc: Exception) -> None:
        errors.append({"url": url, "status": exc.status} if isinstance(exc, FetchError)
                      else {"url": url, "error": f"{type(exc).__name__}: {exc}"})
        log(f"ERROR {url}: {exc}")

    hrefs: list[str] = []
    list_failed = False
    try:
        hrefs = parse_dungeon_list(get(DUNGEON_LIST_URL, refresh_lists))
        list_failed = not hrefs
    except Exception as e:  # noqa: BLE001
        list_failed = True
        fail(DUNGEON_LIST_URL, e)
    log(f"{len(hrefs)} dungeon links collected")
    dungeons = 0
    for href in hrefs:
        url = BASE + href
        try:
            d = parse_dungeon(get(url))
            if not d.get("slug") or not d.get("name"):
                raise ValueError("dungeon page has no name or slug")
            _write_json(out_dir / "dungeons" / f"{d['slug']}.json", d)
            dungeons += 1
        except Exception as e:  # noqa: BLE001
            fail(url, e)
    _write_json(out_dir / "dungeons-errors.json", errors)
    return {"dungeons": dungeons, "errors": len(errors), "requests": fetcher.requests_made,
            "list_failed": list_failed}
