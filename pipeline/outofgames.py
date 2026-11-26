"""Parsers for outof.games WoW Forever pages (quest, NPC, quest list).

Values are located by their labels (dt/dd pairs, table headers, CSS classes),
never by position. A missing section yields None / an empty list, never an
exception. HTML entities are decoded by the parser.

Quest chain rows: ``index`` is the numbered step, or None for a side-branch
row that the site renders without a step number.
"""
from __future__ import annotations

import re

from bs4 import BeautifulSoup

_ENTITY_RE = re.compile(r"/realms/forever/(npc|object|item)/(\d+)-([a-z0-9-]+)/?")
_QUEST_HREF_RE = re.compile(r"/realms/forever/quest/(\d+)-")
_MAP_FILE_RE = re.compile(r"/(\d+)\.webp(?:\?.*)?$")
_QUALITY = {"poor": 0, "common": 1, "uncommon": 2, "rare": 3, "epic": 4}
_COIN = {"gold": 10000, "silver": 100, "copper": 1}


def _soup(html: str) -> BeautifulSoup:
    return BeautifulSoup(html, "lxml")


def _text(node) -> str:
    return " ".join(node.get_text(" ", strip=True).split()) if node else ""


def _int(s: str | None) -> int | None:
    m = re.search(r"-?\d[\d,]*", s or "")
    return int(m.group(0).replace(",", "")) if m else None


def _facts(soup) -> dict:
    """Quick facts: label -> dd element."""
    out = {}
    for div in soup.select("dl.fdb-facts > div"):
        dt, dd = div.find("dt"), div.find("dd")
        if dt and dd:
            out.setdefault(_text(dt), dd)
    return out


def _stats(soup) -> dict:
    out = {}
    for div in soup.select("dl.fdb-stats > div"):
        dt, dd = div.find("dt"), div.find("dd")
        if dt and dd:
            out.setdefault(_text(dt), dd)
    return out


def _coords(s: str) -> tuple[float, float] | None:
    m = re.fullmatch(r"\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*", s or "")
    return (round(float(m.group(1)), 1), round(float(m.group(2)), 1)) if m else None


def _marks(soup) -> list[dict]:
    """Every map mark: kind, name, map_id, x, y (map_id from its own frame)."""
    marks = []
    for frame in soup.select("div.fdb-map-frame"):
        img = frame.find("img")
        m = _MAP_FILE_RE.search(img.get("src", "")) if img else None
        map_id = int(m.group(1)) if m else None
        for g in frame.select("svg.fdb-map-marks > g"):
            kind = next((c[len("fdb-map-"):] for c in g.get("class", [])
                         if c in ("fdb-map-giver", "fdb-map-ender", "fdb-map-objective", "fdb-map-spawn")), None)
            if kind is None:
                continue
            title = g.find("title", recursive=False)
            xy_title = g.find(["text", "circle"])
            xy_title = xy_title.find("title") if xy_title else None
            xy = _coords(_text(xy_title)) if xy_title else None
            if xy is None:
                continue
            marks.append({"kind": kind, "name": _text(title), "map_id": map_id, "x": xy[0], "y": xy[1]})
    return marks


def _pick_mark(marks, mark_kind, name):
    """Mark of this kind titled like the link text, else the first of the kind."""
    of_kind = [m for m in marks if m["kind"] == mark_kind]
    return next((m for m in of_kind if m["name"] == name), of_kind[0] if of_kind else None)


def _place(dd, marks, mark_kind, fallback_kind=None) -> dict | None:
    """Giver / turn-in from a Quick facts dd plus the matching map mark.

    fallback_kind: when the dd's note says "Where it starts" and there is no mark
    of mark_kind, use the mark of this kind (the giver's place).
    """
    if dd is None:
        return None
    a = dd.find("a", href=_ENTITY_RE)
    if a is None:
        return None
    kind, ident, slug = _ENTITY_RE.search(a["href"]).groups()
    name = _text(a)
    mark = _pick_mark(marks, mark_kind, name)
    if mark is None and fallback_kind and "where it starts" in _text(dd).lower():
        mark = _pick_mark(marks, fallback_kind, name)
    return {
        "kind": kind, "id": int(ident), "slug": slug, "name": name,
        "map_id": mark["map_id"] if mark else None,
        "x": mark["x"] if mark else None,
        "y": mark["y"] if mark else None,
    }


def _item(a, count) -> dict:
    quality = next((_QUALITY[c[len("fdb-q-"):]] for c in a.get("class", [])
                    if c.startswith("fdb-q-") and c[len("fdb-q-"):] in _QUALITY), None)
    return {"item_id": int(a["data-forever-item"]), "count": count, "quality": quality}


def _rewards(soup) -> dict:
    out = {"choice": [], "fixed": [], "rep": [], "other": []}
    panel = soup.select_one("#rewards")
    for tr in (panel.select("tbody tr") if panel else []):
        tds = tr.find_all("td")
        if len(tds) < 3:
            continue
        kind = (next(tds[1].stripped_strings, "")).lower()
        if kind.startswith("reputation"):
            amount = _int(tds[2].get("data-sort-value") or _text(tds[2]))
            if amount is not None:
                out["rep"].append({"faction": _text(tds[0]), "amount": amount})
            continue
        a = tds[0].find("a", attrs={"data-forever-item": True})
        if a is None:
            continue
        count = _int(tds[2].get("data-sort-value") or _text(tds[2])) or 1
        if kind.startswith("choice"):
            bucket = "choice"
        elif kind.startswith(("fixed", "guaranteed")):
            bucket = "fixed"
        else:
            bucket = "other"
        out[bucket].append(_item(a, count))
    return out


def _requirements(soup) -> dict:
    """Requirements table: label -> raw text (includes any Race / Class rows)."""
    out = {}
    for tr in soup.select("#requirements tbody tr"):
        tds = tr.find_all("td")
        if len(tds) >= 2:
            out.setdefault(_text(tds[0]), _text(tds[1]))
    return out


def _prereqs(soup) -> tuple[list[int], list[int]]:
    """(all-required ids from "Finish first", any-of ids from "Finish one of" etc.)"""
    required, any_of = [], []
    for tr in soup.select("#requirements tbody tr"):
        tds = tr.find_all("td")
        if len(tds) < 2:
            continue
        label = _text(tds[0]).lower()
        ids = [int(_QUEST_HREF_RE.search(a["href"]).group(1))
               for a in tds[1].find_all("a", href=_QUEST_HREF_RE)]
        if label == "finish first":
            required += ids
        elif label.startswith("finish") and ("one of" in label or "any" in label or "either" in label):
            any_of += ids
    return required, any_of


def _not_available_after(soup) -> list[int]:
    """Quest ids linked in the Requirements "Not available after" row (empty when absent or unlinked)."""
    ids = []
    for tr in soup.select("#requirements tbody tr"):
        tds = tr.find_all("td")
        if len(tds) >= 2 and _text(tds[0]).lower() == "not available after":
            ids += [int(_QUEST_HREF_RE.search(a["href"]).group(1))
                    for a in tds[1].find_all("a", href=_QUEST_HREF_RE)]
    return list(dict.fromkeys(ids))


def _faction(soup, facts, requirements) -> str | None:
    """Side fact, then faction badge, then Requirements "Faction" row; else None."""
    def norm(text):
        t = (text or "").strip().lower()
        if t == "alliance":
            return "Alliance"
        if t == "horde":
            return "Horde"
        if t in ("both", "neutral", "any", "both factions"):
            return "Both"
        return None

    found = norm(_text(facts["Side"])) if "Side" in facts else None
    if found:
        return found
    badge = soup.select_one("a.fdb-tag-faction, span.fdb-tag-faction")
    if badge:
        for cls in badge.get("class", []):
            if cls in ("fdb-faction-alliance", "fdb-faction-horde"):
                return norm(cls.rsplit("-", 1)[1])
        found = norm(_text(badge))
        if found:
            return found
    for tr in soup.select("#requirements tbody tr"):
        tds = tr.find_all("td")
        if len(tds) >= 2 and _text(tds[0]) == "Faction":
            span = tds[1].select_one("[class*=fdb-faction-]")
            for cls in (span.get("class", []) if span else []):
                if cls in ("fdb-faction-alliance", "fdb-faction-horde"):
                    return norm(cls.rsplit("-", 1)[1])
            found = norm(_text(tds[1]))
            if found:
                return found
    return None


def _chain(soup, quest_id) -> list[dict]:
    out = []
    for tr in soup.select("table.fdb-chain tbody tr"):
        tds = tr.find_all("td")
        if len(tds) < 2:
            continue
        index = _int(_text(tds[0]))
        a = tds[1].find("a", href=_QUEST_HREF_RE)
        if a is not None:
            qid, name = int(_QUEST_HREF_RE.search(a["href"]).group(1)), _text(a)
        else:  # the current quest is rendered without a link
            qid, name = (quest_id if "is-current" in tr.get("class", []) else None), _text(tds[1].find("strong"))
        out.append({"index": index, "quest_id": qid, "name": name})
    return out


def _money(stats) -> int:
    dd = stats.get("Money")
    total = 0
    for span in (dd.select("[class*=fdb-coin-]") if dd else []):
        for cls in span.get("class", []):
            unit = cls.replace("fdb-coin-", "")
            if cls.startswith("fdb-coin-") and unit in _COIN:
                total += (_int(span.find(string=True, recursive=False)) or 0) * _COIN[unit]
    return total


def parse_quest(html: str, url: str) -> dict:
    soup = _soup(html)
    facts, stats, marks = _facts(soup), _stats(soup), _marks(soup)

    def fact(label):
        return _text(facts[label]) if label in facts else None

    h1 = soup.select_one("h1.fdb-name")
    quest_id = _int(fact("Quest ID"))
    if quest_id is None:
        m = _QUEST_HREF_RE.search(url or "")
        quest_id = int(m.group(1)) if m else None

    requirements = _requirements(soup)
    prereq_ids, prereq_any_ids = _prereqs(soup)
    prereq_count = _int(fact("Prerequisites"))
    warnings = []
    if prereq_count is not None and len(prereq_ids) + len(prereq_any_ids) != prereq_count:
        warnings.append("prereq-count-mismatch")
    quest_level = _int(fact("Quest level"))
    estimate = _int(fact("Reward level")) if quest_level is None else None

    objectives = [_text(p) for p in soup.select("p.fdb-objective-line")]
    zone = facts.get("Zone")
    tags = [_text(t) for t in soup.select("ul.oog-cd-tags li")]

    return {
        "id": quest_id,
        "name": _text(h1) or None,
        "faction": _faction(soup, facts, requirements),
        "required_level": _int(fact("Required level")),
        "quest_level": quest_level,
        "level_source": "game" if quest_level is not None else "estimate",
        "reward_level_estimate": estimate,
        "xp": _int(_text(stats["Experience"])) if "Experience" in stats else None,
        "money_copper": _money(stats),
        "repeatable": (fact("Repeatable") or "").lower() == "yes",
        "elite": any(t.lower() == "elite" for t in tags),
        "tags": tags,
        "zone_name": _text(zone) or None if zone is not None else None,
        "giver": _place(facts.get("Starts at"), marks, "giver"),
        "turn_in": _place(facts.get("Ends at"), marks, "ender", fallback_kind="giver"),
        "objective_text": "\n".join(objectives) or None,
        "objective_points": [{k: m[k] for k in ("name", "map_id", "x", "y")}
                             for m in marks if m["kind"] == "objective"],
        "rewards": _rewards(soup),
        "prereq_ids": prereq_ids,
        "prereq_any_ids": prereq_any_ids,
        "prereq_count": prereq_count,
        "not_available_after_ids": _not_available_after(soup),
        "requirements": requirements,
        "warnings": warnings,
        "chain": _chain(soup, quest_id),
        "game_data": fact("Game data"),
        "source_url": url,
    }


# NPC "Side" fact -> faction; any other text (unknown side) gives None, never "Both".
_NPC_SIDE = {"alliance": "Alliance", "horde": "Horde", "both": "Both", "both factions": "Both",
             "alliance and horde": "Both", "neutral": "Both"}


def parse_npc(html: str, url: str) -> dict:
    soup = _soup(html)
    facts, stats = _facts(soup), _stats(soup)
    h1 = soup.select_one("h1.fdb-name")
    npc_id = _int(_text(facts["NPC ID"])) if "NPC ID" in facts else None
    if npc_id is None:
        m = re.search(r"/npc/(\d+)-", url or "")
        npc_id = int(m.group(1)) if m else None
    side = _text(facts["Side"]) if "Side" in facts else None
    starts = None
    if "Quests" in stats:
        starts = _int(_text(stats["Quests"]))
    return {
        "id": npc_id,
        "name": _text(h1) or None,
        "level": _int(_text(facts["Level"])) if "Level" in facts else None,
        "faction": _NPC_SIDE.get((side or "").strip().lower()),
        "spawns": [{k: m[k] for k in ("map_id", "x", "y")} for m in _marks(soup) if m["kind"] == "spawn"],
        "starts_count": starts,
    }


def parse_quest_list(html: str) -> tuple[list[str], int]:
    soup = _soup(html)
    hrefs, seen = [], set()
    for a in soup.select("table.fdb-quest-table a.fdb-quest-link"):
        href = a.get("href", "")
        if _QUEST_HREF_RE.match(href) and href not in seen:
            seen.add(href)
            hrefs.append(href)
    pages = [int(m.group(1)) for a in soup.select("nav[data-pagination] a[href]")
             if (m := re.search(r"[?&]page=(\d+)", a["href"]))]
    current = soup.select_one("nav[data-pagination] [aria-current=page]")
    if current is not None and (n := _int(_text(current))) is not None:
        pages.append(n)
    return hrefs, max(pages, default=1)


_DUNGEON_HREF_RE = re.compile(r"^/realms/forever/dungeon/[a-z0-9-]+/$")


def parse_dungeon_list(html: str) -> list[str]:
    """Dungeon page paths linked from the dungeon list page, in page order (never built from slugs)."""
    hrefs, seen = [], set()
    for a in _soup(html).find_all("a", href=True):
        href = a["href"]
        if _DUNGEON_HREF_RE.match(href) and href not in seen:
            seen.add(href)
            hrefs.append(href)
    return hrefs


def parse_dungeon(html: str) -> dict:
    """{name, slug, quest_ids, min_level?, max_level?, zone_name?} from a dungeon page.

    Quest ids come only from the Quests tab (``table.fdb-dungeon-quests``); quest links anywhere
    else on the page (related / recent widgets) are ignored.
    """
    soup = _soup(html)
    out: dict = {"name": _text(soup.select_one("h1.fdb-name")), "slug": None, "quest_ids": []}
    canon = soup.find("link", rel="canonical")
    m = re.search(r"/dungeon/([a-z0-9-]+)/?$", canon.get("href", "")) if canon else None
    out["slug"] = m.group(1) if m else None
    seen = set()
    for a in soup.select("table.fdb-dungeon-quests a.fdb-quest-link"):
        qm = _QUEST_HREF_RE.match(a.get("href", ""))
        if qm and int(qm.group(1)) not in seen:
            seen.add(int(qm.group(1)))
            out["quest_ids"].append(int(qm.group(1)))
    facts = _facts(soup)
    lm = re.fullmatch(r"\s*(\d+)\s*-\s*(\d+)\s*", _text(facts.get("Level range")))
    if lm:
        out["min_level"], out["max_level"] = int(lm.group(1)), int(lm.group(2))
    ent = facts.get("Entrance")
    zone = _text(ent.find("span")) if ent is not None and ent.find("span") else ""
    if zone:
        out["zone_name"] = zone
    return out

