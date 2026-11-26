"""Zone faction from the kept quests (curated zones.toml evidence). Never guessed."""
from __future__ import annotations

from collections import Counter, defaultdict

MIN_SINGLE_FACTION_QUESTS = 8
DOMINANCE = 0.8


def faction_split(quests: dict[int, dict]) -> dict[int, dict[str, int]]:
    """{giver uiMapID: {"Alliance": n, "Horde": n}} over the kept quests.

    Quests of both factions (or of no stated faction) are ignored. Every giver map that has a kept
    quest appears, with zero counts when all its quests are "Both".
    """
    out: dict[int, Counter] = defaultdict(Counter)
    for q in quests.values():
        counter = out[q["giver"]["map_id"]]
        if q.get("faction") in ("Alliance", "Horde"):
            counter[q["faction"]] += 1
    return {m: {"Alliance": c["Alliance"], "Horde": c["Horde"]} for m, c in out.items()}


def choose_faction(split: dict[str, int] | None, capital: str | None = None) -> str:
    """Alliance | Horde | Contested.

    A capital takes its own faction. Otherwise a zone with at least MIN_SINGLE_FACTION_QUESTS
    single-faction quests, DOMINANCE or more of them on one side, takes that side; everything else
    (including a zone with no quests) is Contested.
    """
    if capital:
        return capital
    a, h = (split or {}).get("Alliance", 0), (split or {}).get("Horde", 0)
    total = a + h
    if total >= MIN_SINGLE_FACTION_QUESTS:
        if a >= DOMINANCE * total:
            return "Alliance"
        if h >= DOMINANCE * total:
            return "Horde"
    return "Contested"
