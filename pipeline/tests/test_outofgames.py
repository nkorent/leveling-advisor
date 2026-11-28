import re
from pathlib import Path

import pytest

from pipeline.outofgames import parse_npc, parse_quest, parse_quest_list

FX = Path(__file__).parent / "fixtures" / "outofgames"
B = "https://outof.games/realms/forever/"
URL_4763 = B + "quest/4763-the-blackwood-corrupted/"
URL_965 = B + "quest/965-the-tower-of-althalaxx/"
URL_NPC = B + "npc/3649-thundris-windweaver/"


def fx(name):
    return (FX / name).read_text(encoding="utf-8")


def mini(name="Test Quest", giver_href="/realms/forever/npc/1-a-npc/", giver_marks=True,
         frames=((1439, "giver", 37.4, 40.1),), extra_facts="", side="Horde", badge="",
         giver_text="Giver NPC", mark_title="Giver NPC", reward_rows=""):
    """Minimal page with the same structure as the real fixtures.

    frames: (ui_map_id, kind, x, y) tuples; consecutive tuples with the same map
    id share one fdb-map-frame. name is raw HTML (entities allowed).
    """
    grouped = {}
    for map_id, kind, x, y in frames:
        grouped.setdefault(map_id, []).append((kind, x, y))
    frame_html = ""
    for map_id, marks in grouped.items():
        svg = ""
        for kind, x, y in marks:
            if kind == "giver" and not giver_marks:
                continue
            title = mark_title if kind == "giver" else "Thing"
            svg += (f'<g class="fdb-map-{kind}"><title>{title}</title>'
                    f'<text x="{x:.0f}%" y="{y:.0f}%">!<title>{x:.1f}, {y:.1f}</title></text></g>')
        frame_html += (
            '<div class="fdb-map-frame">'
            f'<img src="https://youre.outof.games/media/forever/maps/1.60.1.70959/{map_id}.webp" class="fdb-map-img">'
            f'<svg class="fdb-map-marks" role="group">{svg}</svg></div>'
        )
    side_html = f'<div class="oog-cd-fact"><dt>Side</dt><dd><span>{side}</span></dd></div>' if side else ""
    rewards_html = (f'<div id="rewards"><table><tbody>{reward_rows}</tbody></table></div>'
                    if reward_rows else "")
    return f"""<html><body><main>
<ul class="oog-cd-tags">{badge}</ul>
<h1 class="oog-cd-name fdb-name">{name}</h1>
<dl class="oog-cd-facts fdb-facts">
<div class="oog-cd-fact"><dt>Starts at</dt><dd><a href="{giver_href}">{giver_text}</a><span class="fdb-fact-note">Zone 37.4, 40.1</span></dd></div>
<div class="oog-cd-fact"><dt>Quest ID</dt><dd><span>777</span></dd></div>
<div class="oog-cd-fact"><dt>Required level</dt><dd><span>5</span></dd></div>
<div class="oog-cd-fact"><dt>Quest level</dt><dd><span>6</span></dd></div>
{side_html}
{extra_facts}
</dl>
<section class="fdb-quest-maps">{frame_html}</section>{rewards_html}
</main></body></html>"""


def test_quest_4763():
    q = parse_quest(fx("quest-4763.html"), URL_4763)
    assert (q["id"], q["name"], q["faction"]) == (4763, "The Blackwood Corrupted", "Alliance")
    assert (q["required_level"], q["quest_level"], q["level_source"], q["reward_level_estimate"]) == (15, None, "estimate", 18)
    assert (q["xp"], q["money_copper"]) == (1700, 2000)
    assert q["giver"] == {"kind": "npc", "id": 3649, "slug": "thundris-windweaver", "name": "Thundris Windweaver", "map_id": 1439, "x": 37.4, "y": 40.1}
    assert q["turn_in"]["id"] == 3649
    assert q["objective_points"] == [{"name": "Talisman of Corruption", "map_id": 1439, "x": 52.5, "y": 33.4}]
    assert [(r["item_id"], r["quality"]) for r in q["rewards"]["choice"]] == [(15204, 2), (15202, 2), (15203, 2)]
    assert q["rewards"]["rep"] == [{"faction": "Darnassus", "amount": 150}]
    assert q["prereq_ids"] == [4762]
    assert len(q["chain"]) == 4 and q["chain"][3]["quest_id"] == 4763
    assert q["objective_text"].startswith("Fill the Empty Cleansing Bowl at the Auberdine Moonwell.")
    assert q["chain"][0]["quest_id"] == 984 and q["chain"][3]["index"] == 4
    assert q["prereq_count"] == 1 and q["prereq_any_ids"] == [] and q["warnings"] == []
    assert q["tags"] == ["Alliance", "Requires level 15", "About level 18"]
    assert q["requirements"]["Faction"] == "Alliance" and q["requirements"]["Level"] == "15"
    assert q["zone_name"] == "Darkshore"
    assert q["repeatable"] is False and q["elite"] is False
    assert q["game_data"] == "1.60.1" and q["source_url"] == URL_4763


def test_quest_965():
    q = parse_quest(fx("quest-965.html"), URL_965)
    assert (q["required_level"], q["quest_level"], q["level_source"], q["xp"], q["money_copper"]) == (13, 18, "game", 675, 0)
    assert q["giver"] == {"kind": "npc", "id": 3657, "slug": "sentinel-elissa-starbreeze", "name": "Sentinel Elissa Starbreeze", "map_id": 1439, "x": 39.1, "y": 43.6}
    assert q["turn_in"] == {"kind": "npc", "id": 3661, "slug": "balthule-shadowstrike", "name": "Balthule Shadowstrike", "map_id": 1439, "x": 55.0, "y": 24.9}
    assert q["rewards"] == {"choice": [], "fixed": [], "rep": [{"faction": "Darnassus", "amount": 50}], "other": []}
    # live page: 10 rows (tab count 10: 9 numbered steps + 1 side-branch row without a step); brief said 6
    assert [r["index"] for r in q["chain"]] == [1, 2, 3, 4, 5, 6, None, 7, 8, 9]
    assert len(q["chain"]) == 10 and q["chain"][0] == {"index": 1, "quest_id": 965, "name": "The Tower of Althalaxx"}


def test_npc_3649():
    n = parse_npc(fx("npc-3649.html"), URL_NPC)
    assert (n["id"], n["name"], n["level"], n["faction"]) == (3649, "Thundris Windweaver", 15, "Alliance")
    assert n["spawns"] == [{"map_id": 1439, "x": 37.4, "y": 40.1}] and n["starts_count"] == 6


def test_list_page():
    hrefs, last = parse_quest_list(fx("quests-page-2.html"))
    assert len(hrefs) == 50 and last == 138
    assert hrefs[0].startswith("/realms/forever/quest/183-")


def test_entities_decoded():  # Review Focus 1
    assert parse_quest(mini(name="Raene&#x27;s Cleansing"), "u")["name"] == "Raene's Cleansing"


def test_object_giver_and_missing_coords():  # Review Focus 2
    q = parse_quest(mini(giver_href="/realms/forever/object/1234-a-crate/", giver_marks=False), "u")
    assert q["giver"]["kind"] == "object" and q["giver"]["map_id"] is None
    assert q["giver"]["id"] == 1234 and q["giver"]["x"] is None


def test_points_take_their_own_map():  # Review Focus 3
    q = parse_quest(mini(frames=[(1439, "giver", 37.4, 40.1), (1440, "objective", 14.0, 14.0)]), "u")
    assert q["objective_points"][0]["map_id"] == 1440
    assert q["giver"]["map_id"] == 1439


def test_missing_sections_never_raise():
    q = parse_quest("<html><body></body></html>", "u")
    assert q["giver"] is None and q["turn_in"] is None
    assert q["objective_points"] == [] and q["chain"] == [] and q["prereq_ids"] == []
    assert q["rewards"] == {"choice": [], "fixed": [], "rep": [], "other": []}
    assert q["name"] is None and q["xp"] is None and q["money_copper"] == 0
    n = parse_npc("<html></html>", "u")
    assert n["spawns"] == [] and n["name"] is None
    assert parse_quest_list("<html></html>") == ([], 1)


def test_faction_horde_from_side():
    assert parse_quest(mini(side="Horde"), "u")["faction"] == "Horde"


def test_faction_from_badge_when_side_missing():
    badge = '<li><a class="badge fdb-tag fdb-tag-faction fdb-faction-horde">Horde</a></li>'
    assert parse_quest(mini(side=None, badge=badge), "u")["faction"] == "Horde"


def test_faction_from_requirements_row():
    html = mini(side=None).replace("</main>", '<div id="requirements"><table><tbody><tr><td>Faction</td>'
                                   '<td><span class="fdb-faction-alliance">Alliance</span></td></tr></tbody></table></div></main>')
    assert parse_quest(html, "u")["faction"] == "Alliance"


def test_faction_none_without_signal():
    assert parse_quest(mini(side=None), "u")["faction"] is None
    assert parse_quest(mini(side="Mystery"), "u")["faction"] is None


def test_faction_explicit_both():
    assert parse_quest(mini(side="Neutral"), "u")["faction"] == "Both"
    assert parse_quest(mini(side="Both"), "u")["faction"] == "Both"


def test_two_givers_pick_mark_with_matching_title():
    frames = [(1439, "giver", 10.0, 10.0), (1440, "giver", 20.0, 20.0)]
    html = mini(frames=frames).replace("<title>Giver NPC</title>", "<title>Someone Else</title>", 1)
    q = parse_quest(html, "u")  # only the second mark is titled like the link
    assert (q["giver"]["map_id"], q["giver"]["x"]) == (1440, 20.0)
    q = parse_quest(mini(frames=frames).replace("Giver NPC</title>", "Nobody</title>"), "u")  # no title matches
    assert (q["giver"]["map_id"], q["giver"]["x"]) == (1439, 10.0)  # falls back to first


def test_turn_in_where_it_starts_uses_giver_place():
    html = mini().replace("</dl>", '<div class="oog-cd-fact"><dt>Ends at</dt><dd>'
                          '<a href="/realms/forever/npc/1-a-npc/">Giver NPC</a>'
                          '<span class="fdb-fact-note">Where it starts</span></dd></div></dl>')
    q = parse_quest(html, "u")
    assert q["turn_in"] == {**q["giver"]}
    assert q["turn_in"]["map_id"] == 1439


def _row(kind_cell, item_id, amount="1"):
    return (f'<tr><td><a class="fdb-q-rare" data-forever-item="{item_id}" href="/realms/forever/item/{item_id}-x/">x</a></td>'
            f'<td>{kind_cell}</td><td data-sort-value="{amount}">{amount}</td></tr>')


def test_reward_kinds_wrapped_and_unknown():
    rows = (_row('Choice Pick 1 of 3', 1) + _row('Choice<span class="fdb-cell-sub">Pick 1 of 3</span>', 2)
            + _row("Fixed", 3) + _row("Mystery", 4))
    r = parse_quest(mini(reward_rows=rows), "u")["rewards"]
    assert [i["item_id"] for i in r["choice"]] == [1, 2]
    assert [i["item_id"] for i in r["fixed"]] == [3]
    assert [i["item_id"] for i in r["other"]] == [4]


def test_negative_reputation():
    rows = ('<tr><td><span class="fdb-rep-name">Bloodsail</span></td><td>Reputation</td>'
            '<td data-sort-value="-25">-25</td></tr>')
    assert parse_quest(mini(reward_rows=rows), "u")["rewards"]["rep"] == [{"faction": "Bloodsail", "amount": -25}]


def test_prereq_count_mismatch_and_any_of():
    facts = '<div class="oog-cd-fact"><dt>Prerequisites</dt><dd><a href="#chain">2 quests</a></dd></div>'
    req = ('<div id="requirements"><table><tbody>'
           '<tr><td>Finish first</td><td><a href="/realms/forever/quest/5-a/">A</a></td></tr>'
           '<tr><td>Finish one of</td><td><a href="/realms/forever/quest/6-b/">B</a></td></tr>'
           '<tr><td>Race</td><td>Night Elf</td></tr></tbody></table></div>')
    q = parse_quest(mini(extra_facts=facts).replace("</main>", req + "</main>"), "u")
    assert (q["prereq_ids"], q["prereq_any_ids"], q["prereq_count"], q["warnings"]) == ([5], [6], 2, [])
    assert q["requirements"]["Race"] == "Night Elf"
    q = parse_quest(mini(extra_facts=facts.replace("2 quests", "3 quests")).replace("</main>", req + "</main>"), "u")
    assert q["warnings"] == ["prereq-count-mismatch"]


def test_elite_from_tag():
    badge = '<li><span class="badge fdb-tag">Elite</span></li>'
    q = parse_quest(mini(badge=badge), "u")
    assert q["elite"] is True and q["tags"] == ["Elite"]
    badge = '<li><span class="badge fdb-tag">Group</span></li>'
    assert parse_quest(mini(badge=badge), "u")["elite"] is False


def test_elite_badge_case_insensitive():
    assert parse_quest(mini(badge='<li><span class="badge fdb-tag">ELITE</span></li>'), "u")["elite"] is True


def test_not_available_after_quest_links():
    """Final review M3: the row's quest links are read (the text alone cannot be encoded)."""
    req = ('<div id="requirements"><table><tbody>'
           '<tr><td class="wf-muted">Level</td><td>12</td></tr>'
           '<tr><td class="wf-muted">Not available after</td><td>'
           '<span class="fdb-quest-entry"><a class="fdb-quest-link" href="/realms/forever/quest/2997-tome-of-divinity/">'
           'Tome of Divinity</a> <span class="wf-muted">(#2997)</span></span><span class="wf-muted fdb-or"> / </span>'
           '<span class="fdb-quest-entry"><a class="fdb-quest-link" href="/realms/forever/quest/3000-tome-of-divinity/">'
           'Tome of Divinity</a> <span class="wf-muted">(#3000)</span></span></td></tr>'
           '<tr><td class="wf-muted">Finish first</td><td><a href="/realms/forever/quest/5-x/">X</a></td></tr>'
           '</tbody></table></div>')
    q = parse_quest(mini().replace("</main>", req + "</main>"), "u")
    assert q["not_available_after_ids"] == [2997, 3000] and q["prereq_ids"] == [5]
    assert q["requirements"]["Not available after"] == "Tome of Divinity (#2997) / Tome of Divinity (#3000)"
    assert parse_quest(mini(), "u")["not_available_after_ids"] == []
    assert parse_quest(fx("quest-4763.html"), URL_4763)["not_available_after_ids"] == []


def test_list_last_page_from_current_when_last():
    html = ('<table class="fdb-quest-table"><tr><td><a class="fdb-quest-link" href="/realms/forever/quest/1-a/">a</a></td></tr></table>'
            '<a class="fdb-quest-link" href="/realms/forever/quest/2-b/">sidebar</a>'
            '<nav data-pagination><a href="/realms/forever/quests/?page=3">3</a>'
            '<span aria-current="page">4</span></nav>')
    assert parse_quest_list(html) == (["/realms/forever/quest/1-a/"], 4)


@pytest.mark.parametrize("side,faction", [("Horde", "Horde"), ("Alliance", "Alliance"), ("Both", "Both"),
                                          ("Neutral", "Both"), ("Mystery", None), ("Contested-ish", None)])
def test_npc_side_unknown_gives_none(side, faction):
    html, n = re.subn(r"(<dt>Side</dt>\s*<dd><span>)Alliance(</span>)", rf"\g<1>{side}\g<2>",
                      fx("npc-3649.html"))
    assert n == 1
    assert parse_npc(html, URL_NPC)["faction"] == faction


@pytest.mark.parametrize("label,expected", [
    ("Finish one of", True), ("finish any of", True), ("Finish either", True), ("FINISH ONE OF", True),
    ("Finish first", False), ("Faction", False), ("Not available after", False), ("one of", False),
])
def test_is_finish_any_label(label, expected):
    from pipeline.outofgames import is_finish_any_label
    assert is_finish_any_label(label) is expected
