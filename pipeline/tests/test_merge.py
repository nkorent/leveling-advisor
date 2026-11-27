"""Merge of outof.games (primary) with Questie (Classic authority) — Task 5 + rulings."""
import copy
from pathlib import Path

import pytest

from pipeline.merge import giver_factions, merge
from pipeline.outofgames import parse_quest

FX = Path(__file__).parent / "fixtures"
LIVE = {1439}

_QUESTIE_FIELDS = (
    "name", "required_level", "quest_level", "race_mask", "class_mask", "starter_npcs",
    "starter_objects", "starter_items", "finisher_npcs", "pre_all", "pre_any", "exclusive_to",
    "breadcrumb_of", "source_item_id", "objective_creature_ids", "objective_object_ids",
    "objective_item_ids", "required_skill", "required_min_rep", "required_max_rep",
    "required_max_level", "required_specialization", "parent_quest", "required_spell",
    "available_until_completed", "available_starting_with", "disabled_by_quest", "required_ranks",
    "next_quest_in_chain", "race_mask_origin")


def place(kind="npc", ident=1, map_id=1439, x=40.0, y=50.0):
    return {"kind": kind, "id": ident, "slug": f"{kind}-{ident}", "name": f"{kind} {ident}",
            "map_id": map_id, "x": x, "y": y}


def oq(qid=100, **kw):
    """A quest dict shaped exactly like pipeline.outofgames.parse_quest output."""
    q = {
        "id": qid, "name": "Some Quest", "zone_name": "Darkshore", "faction": "Alliance",
        "required_level": 10, "quest_level": 12, "level_source": "game", "reward_level_estimate": None,
        "xp": 500, "money_copper": 100, "repeatable": False, "elite": False,
        "giver": place(), "turn_in": place(),
        "objective_text": "Do the thing.", "objective_points": [],
        "rewards": {"choice": [], "fixed": [], "rep": [], "other": []},
        "prereq_ids": [], "prereq_any_ids": [], "prereq_count": None, "not_available_after_ids": [],
        "chain": [], "tags": ["Alliance"], "requirements": {"Level": "10", "Faction": "Alliance"},
        "warnings": [], "game_data": "1.60.1",
        "source_url": f"https://outof.games/realms/forever/quest/{qid}-some-quest/",
    }
    q.update(kw)
    return q


def estimate(level=14, **kw):
    """oog quest without a game quest level (only the reward-level estimate)."""
    return oq(quest_level=None, level_source="estimate", reward_level_estimate=level, **kw)


def qq(qid=100, **kw):
    """A quest dict shaped exactly like pipeline.questiedb.QuestieDBData.quests values. Its race mask
    is Era-origin unless race_mask_origin says otherwise (a Forever-layer 77 stays literal)."""
    q = {f: None for f in _QUESTIE_FIELDS}
    q.update(id=qid, name="Some Quest", required_level=10, quest_level=12, starter_npcs=[1],
             finisher_npcs=[1], repeatable=False, hidden=False, race_mask_origin="era")
    q.update(kw)
    return q


def run(oogs, questies=(), live_maps=LIVE, **kw):
    return merge({q["id"]: q for q in oogs}, {q["id"]: q for q in questies}, live_maps, **kw)


def fixture_quest(qid):
    html = (FX / "outofgames" / f"quest-{qid}.html").read_text(encoding="utf-8")
    return parse_quest(html, f"https://outof.games/realms/forever/quest/{qid}-x/")


def fixture_questie():
    """Questie-shaped quests matching the outof.games fixture pages (965, 4762, 4763)."""
    return {q["id"]: q for q in (
        qq(965, name="The Tower of Althalaxx", required_level=13, quest_level=18, starter_npcs=[3657],
           finisher_npcs=[3661]),
        qq(4762, name="Synthetic Pre", required_level=10, quest_level=10, race_mask=77, starter_npcs=[2],
           finisher_npcs=[2], source_item_id=5555),
        qq(4763, name="The Blackwood Corrupted", required_level=15, quest_level=18, race_mask=77,
           starter_npcs=[3649], finisher_npcs=[3649], pre_any=[4762], source_item_id=12346,
           objective_item_ids=[12355]),
    )}


# ---------------------------------------------------------------- brief tests

def test_questie_fills_missing_race_mask():
    quests, _ = run([oq()], [qq(race_mask=8)])
    q = quests[100]
    assert q["changed_in_forever"] is False
    assert q["race_mask"] == 8
    assert q["provenance"]["race_mask"] == "questie"


def test_outofgames_wins_when_both_present():
    o = oq(requirements={"Level": "10", "Race": "Human, Dwarf", "Class": "Paladin"})
    quests, _ = run([o], [qq(race_mask=77, class_mask=1, quest_level=11)])
    q = quests[100]
    assert q["race_mask"] == 1 | 4 and q["class_mask"] == 2
    assert q["provenance"]["race_mask"] == "outofgames"
    assert q["provenance"]["class_mask"] == "outofgames"
    assert q["quest_level"] == 12 and q["level_source"] == "game"
    assert q["provenance"]["quest_level"] == "outofgames"


def test_changed_in_forever_blocks_restrictions():
    """Review Focus 5, as amended by the restrictive-safe ruling: Questie disagrees on the
    giver -> changed, conflict reported, Questie quest level and prerequisites not applied
    (oog lists its own), only the item fields are still filled from Questie."""
    o = estimate(14, giver=place(ident=999), prereq_ids=[50], prereq_count=1)
    z = qq(starter_npcs=[1], quest_level=12, pre_any=[60], source_item_id=7, objective_item_ids=[8])
    quests, report = run([o], [z])
    q = quests[100]
    assert q["changed_in_forever"] is True
    assert report["conflicts"][100] == ["giver", "prereq"]
    assert q["prereq"] == {"all": [50], "any": []}
    assert q["provenance"]["prereq"] == "outofgames"
    assert q["quest_level"] == 14 and q["level_source"] == "estimate"
    assert q["provenance"]["quest_level"] == "outofgames"
    assert q["items"] == {"provided": [7], "required": [{"item_id": 8, "count": 1}]}
    assert report["counts"]["changed_in_forever"] == 1


def test_new_quest_is_unverified_without_race_limit():
    quests, report = run([oq(90001)], [qq(100)])
    q = quests[90001]
    assert q["new_in_forever"] is True and q["unverified"] is True
    assert q["race_mask"] is None and q["class_mask"] is None
    assert q["changed_in_forever"] is False
    assert report["counts"]["new_in_forever"] == 1


def test_excludes_quest_without_giver_coords():
    """Review Focus 2: no giver, or a giver without coordinates -> excluded, no exception;
    object and item givers with coordinates are kept."""
    oogs = [
        oq(1, giver=None),
        oq(2, giver=place(kind="object", ident=5, map_id=None, x=None, y=None)),
        oq(3, giver=place(y=None)),
        oq(4, giver=place(kind="object", ident=5)),
        oq(5, giver=place(kind="item", ident=6)),
    ]
    quests, report = run(oogs)
    assert report["excluded"] == {1: "no-giver-coords", 2: "no-giver-coords", 3: "no-giver-coords"}
    assert sorted(quests) == [4, 5]
    assert quests[4]["giver"] == {"kind": "object", "id": 5, "map_id": 1439, "x": 40.0, "y": 50.0}
    assert quests[5]["giver"]["kind"] == "item"


def test_excludes_non_live_zone():
    quests, report = run([oq(1), oq(2, giver=place(map_id=1440))], live_maps={1439})
    assert sorted(quests) == [1]
    assert report["excluded"] == {2: "zone-not-live"}
    assert report["live_filter"] == "on"


@pytest.mark.parametrize("name", [
    "[DNT] Foo", "[DNT] Placeholder", "[PH] Thing", "[unused] Old", "[TEST] Foo", "Deprecated Quest",
    "UNUSED quest", "Test", "test", "Test 2", "Test Quest", "zzOld", "zzOld Quest", "ZZ Something",
    "DNT", "PH", "dnt", "ph"])
def test_excludes_test_names(name):
    quests, report = run([oq(name=name)])
    assert quests == {}
    assert report["excluded"] == {100: "test-name"}


@pytest.mark.parametrize("name", [
    "Test Your Theory", "Test of Faith", "Test of Lore", "Test of Endurance", "The Test", "Phase One",
    "DNT Delivery", "Photographs",
    "Testament of Light", "Unusual Delivery", "Buzzbox 827"])
def test_keeps_names_that_only_look_like_tests(name):
    quests, _ = run([oq(name=name)])
    assert list(quests) == [100]


def test_without_questie_flag():
    o = estimate(14)
    z = qq(race_mask=77, quest_level=12, exclusive_to=[7], source_item_id=9, required_max_level=20)
    quests, report = run([o], [z], without={"questie"})
    q = quests[100]
    assert q["new_in_forever"] is True and q["unverified"] is True
    assert q["race_mask"] is None and q["exclusive_to"] is None and q["required_max_level"] is None
    assert q["items"] == {"provided": [], "required": []}
    assert q["quest_level"] == 14 and q["level_source"] == "estimate"
    assert "questie" not in q["provenance"].values()
    assert report["counts"]["questie_quests"] == 0


def test_without_rejects_unknown_source():
    with pytest.raises(ValueError):
        run([oq()], without={"wowhead"})


# ---------------------------------------------------------------- exclusion reasons (ruling)

def test_excludes_questie_hidden():
    _, report = run([oq()], [qq(hidden=True)])
    assert report["excluded"] == {100: "questie-hidden"}


def test_hidden_questie_quest_still_counts_as_not_new():
    _, report = run([oq()], [qq(hidden=True)])
    assert report["counts"]["new_in_forever"] == 0


def test_excludes_no_faction():
    _, report = run([oq(faction=None)])
    assert report["excluded"] == {100: "no-faction"}


def test_excludes_prereq_unclear():
    o = oq(prereq_ids=[5], prereq_count=2, warnings=["prereq-count-mismatch"])
    _, report = run([o])
    assert report["excluded"] == {100: "prereq-unclear"}


@pytest.mark.parametrize("field,value", [("required_skill", [185, 15]), ("required_specialization", 20219)])
def test_excludes_needs_skill(field, value):
    _, report = run([oq()], [qq(**{field: value})])
    assert report["excluded"] == {100: "needs-skill"}


@pytest.mark.parametrize("field,value", [("required_min_rep", [92, 3000]), ("required_max_rep", [72, 9000])])
def test_excludes_needs_rep(field, value):
    _, report = run([oq()], [qq(**{field: value})])
    assert report["excluded"] == {100: "needs-rep"}


def test_excludes_raid_and_pvp_tags():
    _, report = run([oq(1, tags=["Alliance", "Raid"]), oq(2, tags=["Alliance", "PvP"])])
    assert report["excluded"] == {1: "raid", 2: "pvp"}


def test_excludes_no_data_when_no_level_known():
    o = oq(quest_level=None, level_source="estimate", reward_level_estimate=None)
    _, report = run([o], [qq(quest_level=-1)])
    assert report["excluded"] == {100: "no-data"}


def test_exclusion_order_follows_ruling():
    o = oq(name="Test Quest", giver=None, faction=None, tags=["Raid"])
    _, report = run([o], [qq(hidden=True)])
    assert report["excluded"] == {100: "test-name"}
    _, report = run([oq(giver=None, faction=None)], [qq(hidden=True)])
    assert report["excluded"] == {100: "questie-hidden"}
    _, report = run([oq(giver=None, faction=None)])
    assert report["excluded"] == {100: "no-giver-coords"}
    _, report = run([oq(tags=["PvP"], giver=place(map_id=5))], [qq(required_skill=[1, 1])])
    assert report["excluded"] == {100: "needs-skill"}


def test_excluded_quests_counted_per_reason():
    _, report = run([oq(1, giver=None), oq(2, giver=None), oq(3, faction=None), oq(4)])
    c = report["counts"]
    assert c["excluded_by_reason"] == {"no-giver-coords": 2, "no-faction": 1}
    assert c["oog_quests"] == 4 and c["kept"] == 1 and c["excluded"] == 3


# ---------------------------------------------------------------- data-driven additions

def test_excludes_needs_rep_from_outofgames_requirements_row():
    o = oq(requirements={"Level": "60", "Reputation": "Darkspear Raiders: Exalted or better"})
    _, report = run([o])
    assert report["excluded"] == {100: "needs-rep"}


def test_excludes_needs_skill_from_profession_tag():
    _, report = run([oq(tags=["Both", "Fishing"])])
    assert report["excluded"] == {100: "needs-skill"}


def test_excludes_seasonal_and_event_tags():
    _, report = run([oq(1, tags=["Seasonal"]), oq(2, tags=["Invasion"])])
    assert report["excluded"] == {1: "seasonal", 2: "event"}


def test_not_available_after_without_quest_links_is_exclusive_unclear():
    """The row's quest links are what encodes it; without them (even with a Questie exclusive_to, which
    might list fewer quests) the quest is excluded."""
    reqs = {"Level": "10", "Not available after": "Your First Horse (#97171)"}
    _, report = run([oq(requirements=reqs)])
    assert report["excluded"] == {100: "exclusive-unclear"}
    _, report = run([oq(requirements=reqs)], [qq(exclusive_to=[97171])])
    assert report["excluded"] == {100: "exclusive-unclear"}
    stale = oq(requirements=reqs)
    del stale["not_available_after_ids"]                  # JSON from before the parser read the links
    _, report = run([stale], [qq(exclusive_to=[97171])])
    assert report["excluded"] == {100: "exclusive-unclear"}
    assert any("crawl --reparse" in w for w in report["warnings"])


def test_not_available_after_links_beyond_questie_go_to_unavailable_after():
    """M3: a row naming more quests than Questie's exclusive_to is encoded in full (the extra ids in
    unavailable_after, which only Eligibility reads); ids already in exclusive_to are not repeated."""
    reqs = {"Level": "10", "Not available after": "A (#97171) / B (#97172)"}
    quests, report = run([oq(requirements=reqs, not_available_after_ids=[97171, 97172])], [qq(exclusive_to=[97171])])
    assert report["excluded"] == {}
    assert quests[100]["exclusive_to"] == [97171] and quests[100]["unavailable_after"] == [97172]
    assert quests[100]["provenance"]["unavailable_after"] == "outofgames"
    quests, report = run([oq(requirements=reqs, not_available_after_ids=[97171, 97172])])
    assert report["excluded"] == {} and quests[100]["exclusive_to"] is None
    assert quests[100]["unavailable_after"] == [97171, 97172]
    quests, _ = run([oq(requirements=reqs, not_available_after_ids=[97171])], [qq(exclusive_to=[97171])])
    assert quests[100]["unavailable_after"] is None


def test_race_row_with_only_unknown_races_is_excluded():
    o = oq(requirements={"Level": "10", "Race": "Pandaren"})
    _, report = run([o])
    assert report["excluded"] == {100: "race-unclear"}
    assert report["unknown_names"]["race"] == {"Pandaren": 1}


def test_race_row_keeps_known_bits_when_mixed_with_unknown():
    o = oq(requirements={"Level": "10", "Race": "Night Elf, Pandaren"})
    quests, report = run([o])
    assert quests[100]["race_mask"] == 8
    assert report["unknown_names"]["race"] == {"Pandaren": 1}


def test_class_row_with_only_unknown_classes_is_excluded():
    o = oq(requirements={"Level": "10", "Class": "Death Knight"})
    _, report = run([o])
    assert report["excluded"] == {100: "class-unclear"}


def test_undead_and_scourge_are_the_same_bit():
    quests, _ = run([oq(1, faction="Horde", requirements={"Race": "Undead"}),
                     oq(2, faction="Horde", requirements={"Race": "Scourge, Orc"})])
    assert quests[1]["race_mask"] == 16 and quests[2]["race_mask"] == 18


def test_oog_race_row_of_other_faction_is_conflict():
    _, report = run([oq(faction="Alliance", requirements={"Race": "Undead"})])
    assert report["excluded"] == {100: "faction-conflict"}


def test_full_class_row():
    row = "Warrior, Paladin, Hunter, Rogue, Priest, Shaman, Mage, Druid"
    quests, _ = run([oq(requirements={"Class": row})])
    assert quests[100]["class_mask"] == 1 | 2 | 4 | 8 | 16 | 64 | 128 | 1024
    assert quests[100]["class_quest"] is False      # 8 of 9 classes is not a class quest


def test_class_quest_flag_only_for_one_or_two_classes():
    row = "Warrior, Paladin, Hunter, Rogue, Priest, Shaman, Mage, Druid"
    q, _ = run([oq(requirements={"Class": row})])
    assert q[100]["class_mask"] == 1247 and q[100]["class_quest"] is False   # mask kept, no flag
    q, _ = run([oq(requirements={"Class": "Rogue"})])
    assert q[100]["class_mask"] == 8 and q[100]["class_quest"] is True
    q, _ = run([oq(requirements={"Class": "Rogue, Mage"})])
    assert q[100]["class_mask"] == 8 | 128 and q[100]["class_quest"] is True
    q, _ = run([oq(requirements={"Class": "Rogue, Mage, Priest"})])
    assert q[100]["class_quest"] is False


# ---------------------------------------------------------------- faction (ruling)

@pytest.mark.parametrize("mask,faction", [
    (77, "Alliance"), (8, "Alliance"), (1 | 64, "Alliance"),
    (178, "Horde"), (2, "Horde"), (16 | 128, "Horde"),
    (255, "Both"), (1 | 2, "Both")])
def test_faction_from_questie_race_mask(mask, faction):
    quests, report = run([oq(faction=None)], [qq(race_mask=mask)], npcs={1: "Both"})
    q = quests[100]
    assert q["faction"] == faction
    assert q["provenance"]["faction"] == "questie"
    assert report["counts"]["faction_from_questie"] == 1


@pytest.mark.parametrize("mask", [0, None])
def test_no_faction_when_questie_mask_unrestricted(mask):
    _, report = run([oq(faction=None)], [qq(race_mask=mask)])
    assert report["excluded"] == {100: "no-faction"}


def test_outofgames_faction_wins_over_questie_mask():
    quests, report = run([oq(faction="Both")], [qq(race_mask=255)], npcs={1: "Both"})
    assert quests[100]["faction"] == "Both" and quests[100]["provenance"]["faction"] == "outofgames"
    assert quests[100]["race_mask"] is None
    assert report["counts"]["faction_from_questie"] == 0


# ---------------------------------------------------------------- whole-faction masks (ruling 2)

@pytest.mark.parametrize("oog_faction", [None, "Alliance"])
def test_questie_mask_77_becomes_alliance_without_race_limit(oog_faction):
    quests, report = run([oq(faction=oog_faction)], [qq(race_mask=77)])
    q = quests[100]
    assert q["race_mask"] is None and "race_mask" not in q["provenance"]
    assert q["faction"] == "Alliance"
    assert q["provenance"]["faction"] == ("questie" if oog_faction is None else "outofgames")


@pytest.mark.parametrize("oog_faction", [None, "Horde"])
def test_questie_mask_178_becomes_horde_without_race_limit(oog_faction):
    quests, _ = run([oq(faction=oog_faction)], [qq(race_mask=178)])
    assert quests[100]["race_mask"] is None and quests[100]["faction"] == "Horde"


@pytest.mark.parametrize("mask", [255, 255 + 2 ** 32 + 2 ** 33])
def test_questie_all_races_mask_becomes_none(mask):
    quests, _ = run([oq(faction=None)], [qq(race_mask=mask)], npcs={1: "Both"})
    assert quests[100]["race_mask"] is None and quests[100]["faction"] == "Both"


@pytest.mark.parametrize("mask", [255 | 512, 77 | 178 | 1024, 255 + 2 ** 32])
def test_questie_other_superset_masks_are_emitted_in_full(mask):
    """Task 8c amendment: only the exact whole-faction masks drop; nothing else loses bits."""
    quests, _ = run([oq(faction=None)], [qq(race_mask=mask)], npcs={1: "Both"})
    assert quests[100]["race_mask"] == mask and quests[100]["faction"] == "Both"


def test_questie_mask_77_with_oog_horde_is_faction_conflict():
    quests, report = run([oq(faction="Horde")], [qq(race_mask=77)])
    assert quests == {} and report["excluded"] == {100: "faction-conflict"}


def test_questie_mask_178_with_oog_both_is_faction_conflict():
    """oog says both factions, Questie says Horde only: dropping the mask would show it to
    Alliance players, so the disagreement excludes it."""
    _, report = run([oq(faction="Both")], [qq(race_mask=178)])
    assert report["excluded"] == {100: "faction-conflict"}


def test_specific_race_mask_stays():
    quests, _ = run([oq(faction="Alliance")], [qq(race_mask=1 | 4)])
    assert quests[100]["race_mask"] == 5 and quests[100]["provenance"]["race_mask"] == "questie"


def test_specific_race_mask_of_other_faction_is_conflict():
    _, report = run([oq(faction="Alliance")], [qq(race_mask=2 | 128)])
    assert report["excluded"] == {100: "faction-conflict"}


def test_oog_race_row_is_not_normalised():
    """An explicit Forever Race row naming the four classic Alliance races stays a race mask."""
    quests, _ = run([oq(requirements={"Race": "Human, Dwarf, Night Elf, Gnome"})])
    assert quests[100]["race_mask"] == 77


# ---------------------------------------------------------------- changed_in_forever (ruling)

def test_changed_by_required_level_beyond_two():
    _, report = run([oq(1, required_level=13), oq(2, required_level=12)],
                    [qq(1, required_level=10), qq(2, required_level=10)])
    assert report["conflicts"] == {1: ["required_level"]}


def test_changed_giver_compares_object_and_item_starters():
    oogs = [oq(1, giver=place(kind="object", ident=5)), oq(2, giver=place(kind="item", ident=6)),
            oq(3, giver=place(kind="object", ident=1))]
    qs = [qq(1, starter_npcs=None, starter_objects=[5]), qq(2, starter_npcs=None, starter_items=[6]),
          qq(3, starter_npcs=[1])]   # same id, but Questie says NPC 1, not object 1
    _, report = run(oogs, qs)
    assert report["conflicts"] == {3: ["giver"]}


def test_prereq_sets_compared_across_all_and_any():
    """oog 'Finish first' 4762 vs Questie preQuestSingle 4762 is the same set: not changed."""
    o = oq(prereq_ids=[4762], prereq_count=1)
    _, report = run([o], [qq(pre_any=[4762])])
    assert report["conflicts"] == {}


def test_prereq_not_compared_when_one_side_lists_none():
    _, report = run([oq()], [qq(pre_all=[5])])
    assert report["conflicts"] == {}


def test_changed_keeps_questie_masks_without_oog_rows():
    o = oq(giver=place(ident=999))
    z = qq(race_mask=8, class_mask=8, exclusive_to=[7], breadcrumb_of=9, pre_all=[3], pre_any=[4])
    quests, report = run([o], [z])
    q = quests[100]
    assert report["conflicts"] == {100: ["giver"]}
    assert q["race_mask"] == 8 and q["class_mask"] == 8
    assert q["provenance"]["race_mask"] == "questie" and q["provenance"]["class_mask"] == "questie"
    assert q["exclusive_to"] == [7] and q["breadcrumb_of"] == 9
    assert q["prereq"] == {"all": [3], "any": [4]} and q["provenance"]["prereq"] == "questie"


def test_changed_uses_oog_masks_from_requirement_rows():
    o = oq(giver=place(ident=999), requirements={"Race": "Orc, Troll", "Class": "Rogue"}, faction="Horde")
    quests, _ = run([o], [qq(race_mask=77, class_mask=1)])
    q = quests[100]
    assert q["changed_in_forever"] is True
    assert q["race_mask"] == 2 | 128 and q["class_mask"] == 8
    assert q["provenance"]["race_mask"] == "outofgames"


def test_unchanged_questie_fills_exclusive_breadcrumb_and_items():
    z = qq(exclusive_to=[7, 8], breadcrumb_of=9, source_item_id=11, objective_item_ids=[12, 13],
           required_max_level=30)
    quests, _ = run([oq()], [z])
    q = quests[100]
    assert q["exclusive_to"] == [7, 8] and q["breadcrumb_of"] == 9
    assert q["items"] == {"provided": [11], "required": [{"item_id": 12, "count": 1},
                                                        {"item_id": 13, "count": 1}]}
    assert q["required_max_level"] == 30
    assert q["provenance"]["items"] == "questie" and q["provenance"]["required_max_level"] == "questie"


# ---------------------------------------------------------------- prerequisites mapping (ruling)

def test_negative_questie_prereq_ids_are_made_positive():
    quests, _ = run([oq(1), oq(2, prereq_ids=[4976, 4962], prereq_count=2)],
                    [qq(1, pre_all=[4976, -4962]), qq(2, pre_all=[4976, -4962])])
    assert quests[1]["prereq"] == {"all": [4976, 4962], "any": []}
    assert quests[2]["changed_in_forever"] is False   # same set once the sign is dropped


def test_prereq_mapping():
    quests, _ = run([oq(prereq_ids=[1, 2], prereq_any_ids=[3, 4], prereq_count=4)])
    assert quests[100]["prereq"] == {"all": [1, 2], "any": [3, 4]}


def test_prereq_empty_lists_stay_empty():
    quests, _ = run([oq()])
    assert quests[100]["prereq"] == {"all": [], "any": []}
    assert "prereq" not in quests[100]["provenance"]


def test_unchanged_questie_prereqs_fill_when_oog_lists_none():
    quests, _ = run([oq()], [qq(pre_any=[5, 6])])
    assert quests[100]["prereq"] == {"all": [], "any": [5, 6]}
    assert quests[100]["provenance"]["prereq"] == "questie"


# ---------------------------------------------------------------- levels (ruling)

def test_level_from_outofgames_game_data():
    quests, _ = run([oq(quest_level=20)], [qq(quest_level=18)])
    assert quests[100]["quest_level"] == 20 and quests[100]["level_source"] == "game"


def test_level_from_questie_when_oog_only_estimates():
    quests, _ = run([estimate(14)], [qq(quest_level=12)])
    q = quests[100]
    assert q["quest_level"] == 12 and q["level_source"] == "game"
    assert q["provenance"]["quest_level"] == "questie"


@pytest.mark.parametrize("questie_level", [-1, 0, None])
def test_questie_scaling_level_is_unknown(questie_level):
    quests, _ = run([estimate(14)], [qq(quest_level=questie_level)])
    assert quests[100]["quest_level"] == 14 and quests[100]["level_source"] == "estimate"


def test_excludes_no_data_when_no_required_level():
    _, report = run([oq(1, required_level=None), oq(2, required_level=None)], [qq(2, required_level=None)])
    assert report["excluded"] == {1: "no-data", 2: "no-data"}


def test_changed_quest_gets_no_questie_required_level():
    o = oq(required_level=None, giver=place(ident=999))
    quests, report = run([o], [qq(required_level=9)])
    assert report["conflicts"] == {100: ["giver"]}
    assert report["excluded"] == {100: "no-data"}


def test_required_level_falls_back_to_questie():
    quests, _ = run([oq(required_level=None)], [qq(required_level=9)])
    assert quests[100]["required_level"] == 9
    assert quests[100]["provenance"]["required_level"] == "questie"


# ---------------------------------------------------------------- chain (ruling)

def test_chain_965_from_fixture():
    o = fixture_quest(965)
    quests, report = merge({965: o}, fixture_questie(), {1439})
    q = quests[965]
    assert q["chain"] == {"chain_id": 965, "index": 1, "length": 9}
    assert q["changed_in_forever"] is False and report["conflicts"] == {}
    assert q["quest_level"] == 18 and q["level_source"] == "game"


def test_chain_4763_from_fixture():
    quests, _ = merge({4763: fixture_quest(4763)}, fixture_questie(), {1439})
    assert quests[4763]["chain"] == {"chain_id": 984, "index": 4, "length": 4}


def test_chain_length_is_consistent_across_members():
    """Real shape: a member's page can list fewer steps than another member's page (and a
    side-branch row without a step number). Every kept member gets the longest length."""
    long_rows = [{"index": 1, "quest_id": 965, "name": "T"}, {"index": 2, "quest_id": 966, "name": "T"},
                 {"index": 3, "quest_id": 967, "name": "T"}, {"index": None, "quest_id": 976, "name": "S"},
                 {"index": 4, "quest_id": 970, "name": "T"}]
    short_rows = long_rows[:3]
    quests, _ = run([oq(965, chain=short_rows), oq(966, chain=long_rows), oq(976, chain=long_rows)])
    assert quests[965]["chain"] == {"chain_id": 965, "index": 1, "length": 4}
    assert quests[966]["chain"] == {"chain_id": 965, "index": 2, "length": 4}
    assert quests[976]["chain"] is None          # its row has no step number


def test_chain_none_without_first_step():
    rows = [{"index": 2, "quest_id": 101, "name": "B"}, {"index": 3, "quest_id": 100, "name": "C"}]
    quests, _ = run([oq(chain=rows)])
    assert quests[100]["chain"] is None


def test_chain_none_when_quest_not_listed():
    quests, _ = run([oq()])
    assert quests[100]["chain"] is None


# ---------------------------------------------------------------- fixtures end to end

def test_fixture_4763_merged_with_questie():
    quests, report = merge({4763: fixture_quest(4763)}, fixture_questie(), {1439})
    q = quests[4763]
    assert q["name"] == "The Blackwood Corrupted" and q["faction"] == "Alliance"
    assert q["changed_in_forever"] is False and q["new_in_forever"] is False
    assert q["race_mask"] is None and q["class_mask"] is None   # Questie 77 = whole Alliance
    assert q["required_level"] == 15
    assert q["quest_level"] == 18 and q["level_source"] == "game"
    assert q["provenance"]["quest_level"] == "questie"
    assert q["prereq"] == {"all": [4762], "any": []}
    assert q["giver"] == {"kind": "npc", "id": 3649, "map_id": 1439, "x": 37.4, "y": 40.1}
    assert q["zone_map_id"] == 1439
    assert q["xp"] == 1700 and q["xp_source"] == "game"
    assert q["rewards"]["choice"] == [{"item_id": 15204, "count": 1}, {"item_id": 15202, "count": 1},
                                      {"item_id": 15203, "count": 1}]
    assert q["rewards"]["money"] == 2000
    assert q["rewards"]["rep"] == [{"faction": "Darnassus", "amount": 150}]
    assert q["items"] == {"provided": [12346], "required": [{"item_id": 12355, "count": 1}]}
    assert q["objective_points"] == [{"map_id": 1439, "x": 52.5, "y": 33.4}]
    assert report["excluded"] == {}


# ---------------------------------------------------------------- flags (ruling)

def test_flags():
    oogs = [oq(1, elite=True), oq(2, tags=["Alliance", "Dungeon"]), oq(3, repeatable=True), oq(4),
            oq(5, requirements={"Class": "Mage"})]
    quests, _ = run(oogs, [qq(4, repeatable=True)])
    assert quests[1]["elite"] is True and quests[2]["elite"] is False
    assert quests[2]["dungeon_quest"] is True and quests[2]["group_size"] == 5
    assert quests[1]["dungeon_quest"] is False and quests[1]["group_size"] is None
    assert quests[3]["repeatable"] is True and quests[4]["repeatable"] is True
    assert quests[1]["repeatable"] is False
    assert quests[5]["class_quest"] is True and quests[1]["class_quest"] is False
    assert quests[4]["new_in_forever"] is False and quests[1]["new_in_forever"] is True


def test_flag_provenance():
    quests, _ = run([oq(1, elite=True, tags=["Dungeon"]), oq(2), oq(3, repeatable=True)],
                    [qq(2, repeatable=True)])
    p1, p2, p3 = (quests[i]["provenance"] for i in (1, 2, 3))
    assert p1["elite"] == "outofgames" and p1["dungeon_quest"] == "outofgames"
    assert p1["group_size"] == "outofgames" and "group_size" not in p2
    assert p2["repeatable"] == "questie" and p3["repeatable"] == "outofgames"


# ---------------------------------------------------------------- tags and requirement rows (fix round 1)

@pytest.mark.parametrize("tag", [
    "Lunar Festival", "Midsummer", "Hallow's End", "Hallow\u2019s End", "Winter Veil", "Love is in the Air",
    "Noblegarden", "Children's Week", "Harvest Festival", "Brewfest", "BREWFEST", "midsummer",
    "Fire Festival", "Some Festival of Lights", "Seasonal"])
def test_holiday_tags_are_seasonal(tag):
    _, report = run([oq(tags=["Alliance", tag])])
    assert report["excluded"] == {100: "seasonal"}
    assert report["unknown_tags"] == {}


def test_legendary_tag_is_raid():
    _, report = run([oq(tags=["Alliance", "Legendary"])])
    assert report["excluded"] == {100: "raid"}
    assert report["unknown_tags"] == {}


def test_camping_special_epic_stay_reported_only():
    quests, report = run([oq(tags=["Alliance", "Camping", "Special", "Epic"])])
    assert list(quests) == [100]
    assert report["unknown_tags"] == {"Camping": 1, "Special": 1, "Epic": 1}


def test_darkmoon_faire_tag_is_event():
    _, report = run([oq(tags=["Alliance and Horde", "Darkmoon Faire"])])
    assert report["excluded"] == {100: "event"}


@pytest.mark.parametrize("tag", ["Nightmare Incursions", "Ahn'Qiraj War", "Ahn\u2019Qiraj War",
                                 "Blackrock Eruption"])
def test_event_tags(tag):
    _, report = run([oq(tags=["Alliance and Horde", tag])])
    assert report["excluded"] == {100: "event"} and report["unknown_tags"] == {}


def test_treasure_map_and_camping_stay_reported_only():
    quests, report = run([oq(tags=["Alliance", "Treasure Map", "Camping"])])
    assert list(quests) == [100] and report["unknown_tags"] == {"Treasure Map": 1, "Camping": 1}


def test_unknown_tags_and_requirements_are_counted_not_excluded():
    o1 = oq(1, tags=["Alliance", "Requires level 10", "About level 12", "Special", "Shiny"],
            requirements={"Level": "10", "Finish one of": "A / B", "Mood": "Happy"})
    o2 = oq(2, tags=["Special"], requirements={"Mood": "Sad", "Weather": "Rain"})
    quests, report = run([o1, o2])
    assert sorted(quests) == [1, 2]
    assert report["unknown_tags"] == {"Special": 2, "Shiny": 1}
    assert report["unknown_requirements"] == {"Mood": 2, "Weather": 1}


def test_class_tag_sets_class_mask():
    """8249 "Junkboxes Needed": Rogue category tag, no Class row, Questie class mask 0."""
    quests, _ = run([oq(8249, faction="Both", tags=["Alliance and Horde", "Rogue"])], [qq(8249, class_mask=0)],
                    npcs={1: "Both"})
    q = quests[8249]
    assert q["class_mask"] == 8 and q["provenance"]["class_mask"] == "tag" and q["class_quest"] is True


def test_class_tag_loses_to_class_row_and_questie_mask():
    quests, report = run([oq(1, tags=["Rogue"], requirements={"Class": "Mage"}), oq(2, tags=["Rogue"])],
                         [qq(2, class_mask=1)])
    assert quests[1]["class_mask"] == 128 and quests[1]["provenance"]["class_mask"] == "outofgames"
    assert quests[2]["class_mask"] == 1 and quests[2]["provenance"]["class_mask"] == "questie"
    assert report["unknown_tags"] == {}


def test_without_questie_warns():
    _, report = run([oq()], [qq()], without={"questie"})
    assert "questie-disabled: skill/rep/race restrictions from Questie not applied" in report["warnings"]
    _, report = run([oq()], [qq()])
    assert report["warnings"] == []


# ---------------------------------------------------------------- giver faction (fix round 1)

def test_both_quest_with_horde_giver_becomes_horde():
    quests, report = run([oq(faction="Both", giver=place(ident=211022))], npcs={211022: "Horde"})
    q = quests[100]
    assert q["faction"] == "Horde" and q["provenance"]["faction"] == "giver"
    assert report["counts"]["faction_from_giver"] == 1
    assert report["counts"]["among_kept"]["faction_from_giver"] == 1


def test_alliance_quest_with_horde_giver_is_faction_conflict():
    _, report = run([oq(faction="Alliance", giver=place(ident=7))], npcs={7: "Horde"})
    assert report["excluded"] == {100: "faction-conflict"}


def test_giver_of_both_factions_changes_nothing():
    quests, report = run([oq(faction="Both")], npcs={1: "Both"})
    assert quests[100]["faction"] == "Both" and quests[100]["provenance"]["faction"] == "outofgames"
    assert report["counts"]["faction_from_giver"] == 0


@pytest.mark.parametrize("npcs", [{}, {1: None}, None, {2: "Horde"}])
def test_both_quest_with_giver_of_unknown_faction_is_excluded(npcs):
    _, report = run([oq(faction="Both")], npcs=npcs)
    assert report["excluded"] == {100: "giver-faction-unknown"}
    assert report["counts"]["excluded_by_reason"] == {"giver-faction-unknown": 1}


def test_unknown_giver_faction_only_matters_for_both_quests():
    quests, report = run([oq(1, faction="Alliance"), oq(2, faction="Both", giver=place(kind="object", ident=7)),
                          oq(3, faction="Horde", requirements={})], npcs={})
    assert sorted(quests) == [1, 2, 3] and report["excluded"] == {}


def test_giver_faction_ignores_object_and_item_givers():
    quests, _ = run([oq(faction="Both", giver=place(kind="object", ident=7))], npcs={7: "Horde"})
    assert quests[100]["faction"] == "Both"


def test_giver_narrowing_settles_whole_faction_mask():
    """oog Both + Questie 178 alone is a conflict; a Horde giver narrows it to Horde first."""
    quests, report = run([oq(faction="Both", giver=place(ident=7))], [qq(race_mask=178, starter_npcs=[7])],
                         npcs={7: "Horde"})
    assert report["excluded"] == {} and quests[100]["faction"] == "Horde"


def test_giver_factions_combines_outofgames_and_questie():
    oog_npcs = {211022: {"id": 211022, "faction": "Horde"}, 3649: {"id": 3649, "faction": None},
                5: {"id": 5, "faction": "Both"}}
    questie_npcs = {3649: {"name": "Thundris", "friendly": "A"}, 5497: {"name": "Jennea", "friendly": "A"},
                    3216: {"name": "Neeru", "friendly": "H"}, 2663: {"name": "Narkk", "friendly": "AH"},
                    99: {"name": "Morgaine", "friendly": None}, 5: {"name": "X", "friendly": "H"}}
    f = giver_factions(oog_npcs, questie_npcs)
    assert f[211022] == "Horde"          # oog only
    assert f[3649] == "Alliance"         # oog None -> Questie fallback
    assert f[5497] == "Alliance" and f[3216] == "Horde" and f[2663] == "Both"
    assert f[99] is None
    assert f[5] == "Horde"               # oog Both narrowed by Questie H (restrictive combine)


ABSENT = "absent"   # NPC not in Questie's npcDB at all
NIL = None          # NPC in Questie's npcDB with friendlyToFaction nil (hostile to both)


def combine(oog_faction, questie_friendly, npc=7):
    oog_npcs = {npc: {"id": npc, "faction": oog_faction}}
    questie_npcs = {} if questie_friendly == ABSENT else {npc: {"name": "N", "friendly": questie_friendly}}
    return giver_factions(oog_npcs, questie_npcs).get(npc)


@pytest.mark.parametrize("oog_faction,questie,expected", [
    ("Alliance", ABSENT, "Alliance"), ("Alliance", "A", "Alliance"), ("Alliance", "AH", "Alliance"),
    ("Horde", ABSENT, "Horde"), ("Horde", "H", "Horde"), ("Horde", "AH", "Horde")])
def test_combine_row1_single_faction_kept(oog_faction, questie, expected):
    assert combine(oog_faction, questie) == expected


@pytest.mark.parametrize("oog_faction,questie", [("Alliance", "H"), ("Horde", "A")])
def test_combine_row2_opposite_factions_conflict(oog_faction, questie):
    assert combine(oog_faction, questie) == "Conflict"


@pytest.mark.parametrize("questie,expected", [("A", "Alliance"), ("H", "Horde")])
def test_combine_row3_both_narrowed_by_questie(questie, expected):
    assert combine("Both", questie) == expected


@pytest.mark.parametrize("questie", ["AH", ABSENT])
def test_combine_row4_both_stays_both(questie):
    assert combine("Both", questie) == "Both"


def test_combine_row5_both_with_questie_hostile_to_both_is_unknown():
    assert combine("Both", NIL) is None


@pytest.mark.parametrize("questie,expected", [("A", "Alliance"), ("H", "Horde"), ("AH", "Both"),
                                              (NIL, None), (ABSENT, None)])
def test_combine_row6_no_oog_faction_uses_questie(questie, expected):
    assert combine(None, questie) == expected
    if questie != ABSENT:   # NPC without an outof.games page at all
        assert giver_factions({}, {7: {"name": "N", "friendly": questie}}).get(7) == expected


@pytest.mark.parametrize("oog_faction", ["Alliance", "Horde"])
def test_combine_single_faction_with_questie_hostile_to_both_keeps_oog(oog_faction):
    """Option (b): a single outof.games faction wins over Questie nil (never widens)."""
    assert combine(oog_faction, NIL) == oog_faction


def test_questie_hostile_npc_with_oog_horde_narrows_and_conflicts():
    npcs = giver_factions({7: {"id": 7, "faction": "Horde"}}, {7: {"name": "N", "friendly": None}})
    quests, report = run([oq(1, faction="Both", giver=place(ident=7)),
                          oq(2, faction="Alliance", giver=place(ident=7))], npcs=npcs)
    assert quests[1]["faction"] == "Horde" and quests[1]["provenance"]["faction"] == "giver"
    assert report["excluded"] == {2: "faction-conflict"}


@pytest.mark.parametrize("faction", ["Alliance", "Horde", "Both"])
def test_conflicting_giver_is_faction_conflict_for_any_quest(faction):
    _, report = run([oq(faction=faction, giver=place(ident=7))], npcs={7: "Conflict"})
    assert report["excluded"] == {100: "faction-conflict"}


def test_questie_npc_fallback_end_to_end():
    qnpcs = {5497: {"name": "Jennea Cannon", "friendly": "A"}, 99: {"name": "Morgaine the Sly", "friendly": None}}
    quests, report = run([oq(84394, faction="Both", giver=place(ident=5497))], npcs=giver_factions({}, qnpcs))
    assert quests[84394]["faction"] == "Alliance" and quests[84394]["provenance"]["faction"] == "giver"


# ---------------------------------------------------------------- rewards and items (ruling)

def test_other_rewards_merged_into_fixed_and_counted():
    rewards = {"choice": [{"item_id": 1, "count": 1, "quality": 2}],
               "fixed": [{"item_id": 2, "count": 3, "quality": 1}],
               "rep": [{"faction": "Darnassus", "amount": 50}],
               "other": [{"item_id": 4, "count": 1, "quality": 1}, {"item_id": 5, "count": 2, "quality": 1}]}
    quests, report = run([oq(rewards=rewards, money_copper=250)])
    r = quests[100]["rewards"]
    assert r == {"choice": [{"item_id": 1, "count": 1}],
                 "fixed": [{"item_id": 2, "count": 3}, {"item_id": 4, "count": 1}, {"item_id": 5, "count": 2}],
                 "money": 250, "rep": [{"faction": "Darnassus", "amount": 50}], "spell_id": None}
    assert report["counts"]["rewards_other"] == 2


def test_merge_does_not_mutate_inputs():
    o, z = oq(rewards={"choice": [], "fixed": [], "rep": [], "other": [{"item_id": 4, "count": 1, "quality": 1}]}), qq()
    o0, z0 = copy.deepcopy(o), copy.deepcopy(z)
    run([o], [z])
    assert o == o0 and z == z0


# ---------------------------------------------------------------- provisional mode (ruling)

def test_provisional_mode_without_live_maps():
    quests, report = run([oq(1, giver=place(map_id=9999)), oq(2, giver=None)], live_maps=None)
    assert sorted(quests) == [1]
    assert report["live_filter"] == "off"
    assert report["excluded"] == {2: "no-giver-coords"}


# ---------------------------------------------------------------- recorder (ruling)

def test_recorder_overrides():
    rec = {100: {"xp": {12: 520, 13: 480}, "level": 13, "giver": None}}
    quests, _ = run([estimate(11)], recorder=rec)
    q = quests[100]
    assert q["quest_level"] == 13 and q["level_source"] == "recorder"
    assert q["provenance"]["quest_level"] == "recorder"
    assert q["recorded_xp"] == {12: 520, 13: 480} and q["provenance"]["recorded_xp"] == "recorder"
    assert q["new_in_forever"] is True and q["unverified"] is False


def test_recorder_giver_fills_missing_giver():
    rec = {100: {"xp": {}, "level": None, "giver": {"npc": 77, "map_id": 1439, "x": 1.5, "y": 2.5}}}
    quests, report = run([oq(giver=None)], recorder=rec)
    q = quests[100]
    assert q["giver"] == {"kind": "npc", "id": 77, "map_id": 1439, "x": 1.5, "y": 2.5}
    assert q["provenance"]["giver"] == "recorder" and q["zone_map_id"] == 1439
    assert q["quest_level"] == 12 and q["level_source"] == "game"


def test_without_recorder_keeps_unverified():
    rec = {100: {"xp": {12: 520}, "level": 13, "giver": None}}
    quests, _ = run([estimate(11)], recorder=rec, without={"recorder"})
    q = quests[100]
    assert q["unverified"] is True and q["recorded_xp"] is None and q["level_source"] == "estimate"


# ---------------------------------------------------------------- QuestieDB Forever (Task 8c)

SA, SH = 2 ** 32, 2 ** 33          # High Order Skyborne (race 95), Windshaper Skyborne (race 96)
ALLIANCE_ROW = "Human, Dwarf, Night Elf, Gnome, High Order Skyborne"


def qdb_data(npcs=None, npc_spawns=None, object_spawns=None, xp=None):
    from pipeline.questiedb import QuestieDBData
    return QuestieDBData(npcs=npcs or {}, npc_spawns=npc_spawns or {}, object_spawns=object_spawns or {},
                         xp=xp or {})


def spot(map_id=1439, x=40.0, y=50.0):
    return {"map_id": map_id, "x": x, "y": y}


def npc(friendly="A", name="N", level=10):
    return {"name": name, "friendly": friendly, "level": level}


@pytest.mark.parametrize("mask,faction", [(77, "Alliance"), (77 + SA, "Alliance"), (178, "Horde"),
                                          (178 + SH, "Horde"), (255, "Both"), (255 + SA + SH, "Both")])
def test_race_mask_forever_bits_whole_faction(mask, faction):
    quests, _ = run([oq(faction=None)], [qq(race_mask=mask)], npcs={1: "Both"})
    assert quests[100]["race_mask"] is None and quests[100]["faction"] == faction


def test_race_mask_forever_bits():
    quests, report = run([oq(1), oq(2), oq(3, faction="Horde", requirements={"Race": "Windshaper Skyborne"}),
                          oq(4, requirements={"Race": "Night Elf, High Order Skyborne"}),
                          oq(5, requirements={"Race": ALLIANCE_ROW}),
                          oq(6, requirements={"Race": "Human, Dwarf, Night Elf, Gnome"})],
                         [qq(1, race_mask=8 + SA), qq(2, race_mask=SA)])
    assert quests[1]["race_mask"] == 8 + SA and quests[1]["provenance"]["race_mask"] == "questie"
    assert quests[2]["race_mask"] == SA                       # Skyborne-only: kept as is
    assert quests[3]["race_mask"] == SH
    assert quests[4]["race_mask"] == 8 + SA and quests[4]["provenance"]["race_mask"] == "outofgames"
    assert quests[5]["race_mask"] is None and quests[5]["faction"] == "Alliance"   # every Alliance race
    assert quests[6]["race_mask"] == 77                       # no Skyborne: the 1.60.1 row stays literal
    assert report["excluded"] == {}
    assert report["counts"]["among_kept"]["skyborne_race_mask"] == 4


def test_skyborne_mask_gives_faction():
    quests, report = run([oq(1, faction=None), oq(2, faction="Horde")], [qq(1, race_mask=SA), qq(2, race_mask=SA)])
    assert quests[1]["faction"] == "Alliance"
    assert report["excluded"] == {2: "faction-conflict"}


def test_spawn_trust_per_map():
    from pipeline.merge import spawn_check
    oog = {i: {"id": i, "spawns": [spot(1429, 10.0 * i, 10.0)]} for i in (1, 2, 3, 4)}
    oog.update({i: {"id": i, "spawns": [spot(1430, 10.0 * i, 20.0)]} for i in (5, 6, 7)})
    oog.update({i: {"id": i, "spawns": [spot(1431, 10.0 * i, 30.0)]} for i in (8, 9)})
    oog[10] = {"id": 10, "spawns": []}                        # zero-spawn page: not comparable
    oog[11] = {"id": 11, "spawns": [spot(1429, 90.0, 90.0)]}  # Questie has it on another map only
    qdb = {1: [spot(1429, 10.0, 12.9)], 2: [spot(1429, 20.0, 10.0)], 3: [spot(1429, 31.0, 11.0)],
           4: [spot(1429, 40.0, 10.0)],
           5: [spot(1430, 50.0, 20.0)], 6: [spot(1430, 60.0, 23.1)],            # 3.1 away: no match
           7: [spot(1430, 70.0, 20.0), spot(1430, 10.0, 90.0)],                 # one spawn far off: no match
           8: [spot(1431, 80.0, 30.0)], 9: [spot(1431, 90.0, 30.0)],
           10: [spot(1429, 1.0, 1.0)], 11: [spot(1432, 90.0, 90.0)], 12: [spot(1429, 5.0, 5.0)]}
    check = spawn_check(oog, qdb)
    m = check["maps"]
    assert (m[1429]["comparable"], m[1429]["matched"], m[1429]["trusted"]) == (4, 4, True)
    assert (m[1430]["comparable"], m[1430]["matched"], m[1430]["trusted"]) == (3, 1, False)
    assert (m[1431]["comparable"], m[1431]["matched"], m[1431]["trusted"]) == (2, 2, False)   # < 3 NPCs
    assert m[1432] == {**m[1432], "comparable": 0, "questie_only": 1, "trusted": False}
    assert check["trusted"] == [1429]
    assert check["overall"] == {**check["overall"], "comparable": 9, "matched": 7}


def test_giver_fill_single_candidate():
    qdb = qdb_data(npcs={7: npc("A")}, npc_spawns={7: [spot(x=40.0, y=50.0), spot(x=41.0, y=51.0)]},
                   object_spawns={5000: [spot(x=12.0, y=13.0)]})
    oogs = [oq(1, giver=None), oq(2, giver=place(ident=7, map_id=None, x=None, y=None)),
            oq(3, giver=None)]
    zs = [qq(1, starter_npcs=[7]), qq(2, starter_npcs=[7]), qq(3, starter_npcs=None, starter_objects=[5000])]
    quests, report = run(oogs, zs, npcs={7: "Alliance"}, questiedb=qdb, trusted_maps={1439})
    for qid in (1, 2):
        q = quests[qid]
        assert q["giver"] == {"kind": "npc", "id": 7, "map_id": 1439, "x": 40.5, "y": 50.5}
        assert q["provenance"]["giver"] == "questiedb" and q["zone_map_id"] == 1439
        assert q["changed_in_forever"] is False
    assert quests[3]["giver"] == {"kind": "object", "id": 5000, "map_id": 1439, "x": 12.0, "y": 13.0}
    fill = report["questiedb"]["giver_fill"]
    assert fill["filled"] == 3 and fill["filled_kept"] == 3 and fill["ambiguous"] == 0


def test_giver_fill_faction_narrowing():
    qdb = qdb_data(npcs={7: npc("A"), 8: npc("H"), 9: npc("AH"), 10: npc(None)},
                   npc_spawns={i: [spot(x=10.0 * i, y=10.0)] for i in (7, 8, 9, 10)})
    npcs = {7: "Alliance", 8: "Horde", 9: "Both"}
    quests, report = run([oq(1, giver=None), oq(2, faction="Horde", giver=None), oq(3, faction="Both", giver=None),
                          oq(4, giver=None)],
                         [qq(1, starter_npcs=[7, 8]), qq(2, starter_npcs=[7, 8]), qq(3, starter_npcs=[7, 8]),
                          qq(4, starter_npcs=[9, 10])],
                         npcs=npcs, questiedb=qdb, trusted_maps={1439})
    assert quests[1]["giver"]["id"] == 7 and quests[2]["giver"]["id"] == 8
    assert quests[4]["giver"]["id"] == 9                       # nil friendlyToFaction lacks Alliance
    assert report["excluded"] == {3: "questie-giver-ambiguous"}  # "Both": two usable NPCs
    quests, report = run([oq(5, faction="Horde", giver=None)], [qq(5, starter_npcs=[7])], npcs=npcs,
                         questiedb=qdb, trusted_maps={1439})
    assert report["excluded"] == {5: "no-giver-coords"}         # no candidate of its faction
    assert report["questiedb"]["giver_fill"]["no_usable_why"] == {"wrong-faction": 1}


def test_giver_ambiguous_scattered_spawns():
    qdb = qdb_data(npcs={i: npc("A") for i in (7, 8, 9, 10, 11)},
                   npc_spawns={7: [spot(x=10.0, y=10.0), spot(x=17.1, y=10.0)],     # 3.55 from the mean
                               8: [spot(x=10.0, y=10.0), spot(x=21.0, y=10.0)],     # 5.5 from the mean
                               9: [spot(1439, 10.0, 10.0), spot(1440, 10.0, 10.0)],  # two trusted maps
                               10: [spot(1499, 10.0, 10.0)],                          # untrusted map only
                               11: [spot(1439, 30.0, 30.0), spot(1499, 80.0, 80.0)]})  # untrusted one ignored
    zs = [qq(1, starter_npcs=[7]), qq(2, starter_npcs=[8]), qq(3, starter_npcs=[9]), qq(4, starter_npcs=[10]),
          qq(5, starter_npcs=[7, 11])]
    quests, report = run([oq(i, giver=None) for i in (1, 2, 3, 4, 5)], zs, npcs={i: "Alliance" for i in range(7, 12)},
                         questiedb=qdb, trusted_maps={1439, 1440})
    assert quests[1]["giver"] == {"kind": "npc", "id": 7, "map_id": 1439, "x": 13.55, "y": 10.0}
    # ambiguous: scattered (2), split across maps (3), two usable candidates (5); quest 4's only
    # candidate has no spawn on a trusted map: nothing to choose from, so it stays no-giver-coords
    assert report["excluded"] == {2: "questie-giver-ambiguous", 3: "questie-giver-ambiguous",
                                  4: "no-giver-coords", 5: "questie-giver-ambiguous"}
    fill = report["questiedb"]["giver_fill"]
    assert fill["ambiguous"] == 3 and fill["no_usable"] == 1
    assert fill["ambiguous_why"] == {"several-usable": 1, "scattered": 1, "several-maps": 1}
    assert fill["no_usable_why"] == {"untrusted-map-only": 1}


def test_giver_candidate_without_spawns_stays_no_giver_coords():
    qdb = qdb_data(npcs={7: npc("A"), 8: npc("A")}, npc_spawns={8: [spot(1499, 10.0, 10.0)]})
    quests, report = run([oq(1, giver=place(ident=7, map_id=None, x=None, y=None)), oq(2, giver=None)],
                         [qq(1, starter_npcs=[7]), qq(2, starter_npcs=[7, 8])],
                         npcs={7: "Alliance", 8: "Alliance"}, questiedb=qdb, trusted_maps={1439})
    assert report["excluded"] == {1: "no-giver-coords", 2: "no-giver-coords"}
    assert report["questiedb"]["giver_fill"]["no_usable_why"] == {"no-spawns": 1, "no-trusted-spawns": 1}


def test_giver_fill_skipped_when_changed_in_forever():
    """A quest QuestieDB disagrees on (here: required level 10 vs 20) does not get its giver point
    from QuestieDB: the disagreeing source must not be what makes it routable."""
    qdb = qdb_data(npcs={7: npc("A")}, npc_spawns={7: [spot()]})
    quests, report = run([oq(1, giver=None), oq(2, giver=None)],
                         [qq(1, starter_npcs=[7], required_level=20), qq(2, starter_npcs=[7])],
                         npcs={7: "Alliance"}, questiedb=qdb, trusted_maps={1439})
    assert report["excluded"] == {1: "no-giver-coords"}
    assert report["conflicts"] == {1: ["required_level"]}
    assert quests[2]["provenance"]["giver"] == "questiedb"
    assert report["questiedb"]["giver_fill"]["skipped_changed"] == 1


def test_oog_race_row_gives_the_faction_when_oog_faction_is_missing():
    quests, report = run([oq(1, faction=None, requirements={"Race": ALLIANCE_ROW}),
                          oq(2, faction=None, requirements={"Race": "Orc, Windshaper Skyborne"}),
                          oq(3, faction=None, requirements={"Race": "Human, Orc"})],
                         [qq(1, race_mask=178), qq(3)], npcs={1: "Both"})
    assert quests[1]["faction"] == "Alliance" and quests[1]["race_mask"] is None
    assert quests[1]["provenance"]["faction"] == "outofgames"     # the row beats the QuestieDB mask
    assert quests[2]["faction"] == "Horde" and quests[2]["race_mask"] == 2 + SH
    assert report["excluded"] == {3: "no-faction"}                # a two-faction row gives no faction


def test_giver_npc_id_must_match_starter():
    qdb = qdb_data(npcs={7: npc("A"), 9: npc("A")}, npc_spawns={7: [spot()], 9: [spot()]})
    o = oq(giver=place(ident=9, map_id=None, x=None, y=None))
    quests, report = run([o], [qq(starter_npcs=[7])], npcs={7: "Alliance", 9: "Alliance"}, questiedb=qdb,
                         trusted_maps={1439})
    assert report["excluded"] == {100: "no-giver-coords"}
    assert report["conflicts"] == {100: ["giver"]}


def test_item_start_not_filled():
    qdb = qdb_data(npcs={7: npc("A")}, npc_spawns={7: [spot()]})
    quests, report = run([oq(1, giver=place(kind="item", ident=9000, map_id=None, x=None, y=None)),
                          oq(2, giver=None)],
                         [qq(1, starter_npcs=[7], starter_items=[9000]),
                          qq(2, starter_npcs=None, starter_items=[9000])],
                         npcs={7: "Alliance"}, questiedb=qdb, trusted_maps={1439})
    assert report["excluded"] == {1: "no-giver-coords", 2: "no-giver-coords"}


def test_giver_fill_needs_a_questie_quest_and_coords_only():
    """A quest absent from QuestieDB gets no candidates; an oog giver with coordinates is never replaced."""
    qdb = qdb_data(npcs={7: npc("A")}, npc_spawns={7: [spot(x=70.0, y=70.0)]})
    quests, report = run([oq(1, giver=None), oq(2, giver=place(ident=7))], [qq(2, starter_npcs=[7])],
                         npcs={7: "Alliance"}, questiedb=qdb, trusted_maps={1439})
    assert report["excluded"] == {1: "no-giver-coords"}
    assert quests[2]["giver"]["x"] == 40.0 and quests[2]["provenance"]["giver"] == "outofgames"


def test_xp_fill_only_when_oog_missing():
    agreeing = [oq(i, quest_level=10, xp=500) for i in range(1, 10)] + [oq(10, quest_level=10, xp=300)]
    oogs = agreeing + [oq(20, quest_level=12, xp=None), oq(21, quest_level=12, xp=None),
                      oq(22, quest_level=12, xp=650)]
    xp = {**{i: (10, 510) for i in range(1, 10)}, 10: (10, 500), 20: (12, 700), 21: (14, 900), 22: (12, 700)}
    quests, report = run(oogs, [qq(i) for i in (1, 20, 21, 22)], questiedb=qdb_data(xp=xp))
    check = report["questiedb"]["xp_check"]
    assert (check["both"], check["same_level"], check["agree"]) == (11, 11, 9) and check["fill"] is False
    assert quests[20]["xp"] is None                           # 9/11 = 82 % < 90 %: no fill
    xp[10] = (10, 300)
    quests, report = run(oogs, [qq(i) for i in (1, 20, 21, 22)], questiedb=qdb_data(xp=xp))
    assert report["questiedb"]["xp_check"]["fill"] is True
    assert quests[20]["xp"] == 700 and quests[20]["xp_source"] == "questiedb"
    assert quests[20]["provenance"]["xp"] == "questiedb"
    assert quests[21]["xp"] is None                           # QuestieDB's XP is for level 14, the quest is 12
    assert quests[22]["xp"] == 650 and quests[22]["xp_source"] == "game"
    assert report["questiedb"]["xp_filled"] == 1


def test_without_questie_removes_questiedb():
    qdb = qdb_data(npcs={7: npc("A")}, npc_spawns={7: [spot()]}, xp={1: (12, 700)})
    quests, report = run([oq(1, xp=None), oq(2, giver=None)], [qq(1), qq(2, starter_npcs=[7])],
                         npcs={1: "Alliance"}, questiedb=qdb, trusted_maps={1439}, without={"questie"})
    assert quests[1]["xp"] is None
    assert report["excluded"] == {2: "no-giver-coords"}
    assert "questiedb" not in report


def test_questiedb_forever_created_quest_is_new_in_forever():
    """QuestieDB Forever contains Forever-new quests; one created by a Forever layer (not in the Era
    data) still counts as new in Forever and stays unverified until a recorder sighting."""
    quests, report = run([oq(1), oq(2)], [qq(1, new_in_forever=True), qq(2, new_in_forever=False)])
    assert quests[1]["new_in_forever"] is True and quests[1]["unverified"] is True
    assert quests[2]["new_in_forever"] is False and quests[2]["unverified"] is False
    assert report["counts"]["new_in_forever"] == 1


def test_dynamic_one_faction_restriction_applied_or_excluded():
    """A gating field only one faction's dynamic corrections set (fixture quest 400: Horde
    preQuestSingle {401}; real quest 1198: Alliance breadcrumbForQuestId 1200) is applied for a quest of
    that single faction, and a quest of both factions is excluded as faction-fix-unclear."""
    from pipeline.questiedb import load_questiedb
    z = load_questiedb(FX / "questiedb" / "root", FX / "questiedb" / "QuestieQuestBlacklist.lua").quests[400]
    assert z["faction_fixes"] == {"Alliance": {"pre_any": None}, "Horde": {"pre_any": [401]}}
    npcs = {30: "Alliance", 31: "Horde"}
    for faction, giver, expected in (("Horde", 31, [401]), ("Alliance", 30, [])):
        quests, _ = run([oq(400, faction=faction, giver=place(ident=giver))], [z], npcs=npcs)
        assert quests[400]["prereq"] == {"all": [], "any": expected}, faction
    _, report = run([oq(400, faction="Both", giver=place(ident=30))], [z], npcs={30: "Both"})
    assert report["excluded"] == {400: "faction-fix-unclear"}

    fixes = {"Alliance": {"breadcrumb_of": 1200}, "Horde": {"breadcrumb_of": None}}
    zq = qq(1198, starter_npcs=[1], faction_fixes=fixes)
    quests, report = run([oq(1198, faction="Alliance"), oq(1199, faction="Horde"),
                          oq(1200, faction="Both", giver=place(ident=9))],
                         [zq, {**zq, "id": 1199}, {**zq, "id": 1200, "starter_npcs": [9]}],
                         npcs={1: "Both", 9: "Alliance"})
    assert quests[1198]["breadcrumb_of"] == 1200 and quests[1198]["provenance"]["breadcrumb_of"] == "questie"
    assert quests[1199]["breadcrumb_of"] is None
    assert quests[1200]["faction"] == "Alliance" and quests[1200]["breadcrumb_of"] == 1200   # narrowed by giver
    assert report["counts"]["faction_fixes_applied"] == 3


# ---------------------------------------------------------------- required breadcrumbs
def test_breadcrumb_dropped_when_target_requires_it():
    a = oq(363, prereq_ids=[], prereq_any_ids=[])
    b_all = oq(364, prereq_ids=[363])
    c = oq(365, prereq_ids=[])
    d_any = oq(366, prereq_any_ids=[365, 999])
    e = oq(367)
    f = oq(368, prereq_ids=[])
    zs = [qq(363, breadcrumb_of=364), qq(365, breadcrumb_of=366), qq(367, breadcrumb_of=368)]
    quests, report = run([a, b_all, c, d_any, e, f], zs)
    assert quests[363]["breadcrumb_of"] is None
    assert quests[365]["breadcrumb_of"] == 366  # any-only: keeps the eligibility guard
    assert "breadcrumb_of" not in quests[363]["provenance"]
    assert quests[367]["breadcrumb_of"] == 368  # a true optional breadcrumb stays
    assert report["breadcrumb_dropped_required"] == [
        {"quest": 363, "target": 364}]
    assert report["counts"]["breadcrumb_dropped_required"] == 1
    assert report["counts"]["breadcrumb_kept_any"] == 1


# ---------------------------------------------------------------- final review: availability gates (C1)

def test_available_starting_with_goes_to_prereq_all_never_any():
    quests, report = run([oq()], [qq(available_starting_with=92514)])
    assert report["excluded"] == {}
    assert quests[100]["prereq"] == {"all": [92514], "any": []}
    assert quests[100]["provenance"]["prereq_gate"] == "questie"
    # oog prerequisites stay; the gate is added to all (even when oog lists it among "any")
    quests, _ = run([oq(prereq_ids=[5], prereq_any_ids=[92514, 7])], [qq(available_starting_with=92514)])
    assert quests[100]["prereq"] == {"all": [5, 92514], "any": [92514, 7]}
    quests, _ = run([oq(prereq_ids=[92514])], [qq(available_starting_with=92514)])
    assert quests[100]["prereq"] == {"all": [92514], "any": []} and "prereq_gate" not in quests[100]["provenance"]
    assert run([oq()], [qq(available_starting_with=92514)])[1]["counts"]["gates"]["prereq_added"] == 1


def test_until_completed_and_disabled_by_go_to_unavailable_after_not_exclusive_to():
    quests, report = run([oq(1282)], [qq(1282, available_until_completed=1302, disabled_by_quest=420)])
    assert report["excluded"] == {}
    q = quests[1282]
    assert q["unavailable_after"] == [1302, 420] and q["exclusive_to"] is None
    assert q["provenance"]["unavailable_after"] == "questie"
    assert report["counts"]["gates"]["unavailable_after"] == 1
    # with an oog "Not available after" row the Questie gate is kept too (no gate is dropped)
    reqs = {"Level": "10", "Not available after": "A (#235) / B (#742)"}
    quests, _ = run([oq(6382, requirements=reqs, not_available_after_ids=[235, 742])],
                    [qq(6382, exclusive_to=[235, 742], available_until_completed=6383)])
    assert quests[6382]["exclusive_to"] == [235, 742] and quests[6382]["unavailable_after"] == [6383]


@pytest.mark.parametrize("field,value,reason", [
    ("parent_quest", 338, "parent-quest"), ("required_spell", 12345, "needs-spell"),
    ("required_spell", -12345, "needs-spell"), ("required_ranks", [[171, 225]], "needs-rank")])
def test_gates_v1_cannot_check_are_excluded(field, value, reason):
    _, report = run([oq()], [qq(**{field: value})])
    assert report["excluded"] == {100: reason}
    assert report["counts"]["excluded_by_reason"] == {reason: 1}


@pytest.mark.parametrize("gate", [{"available_starting_with": 5}, {"available_until_completed": 5},
                                  {"disabled_by_quest": 5}, {"parent_quest": 5}])
def test_changed_in_forever_quest_with_a_gate_is_gate_unclear(gate):
    changed = oq(required_level=10)
    quests, report = run([changed], [qq(required_level=30, **gate)])   # > 2 apart: changed in Forever
    assert report["conflicts"] == {100: ["required_level"]}
    assert report["excluded"] == {100: "gate-unclear"}
    quests, report = run([changed], [qq(required_level=30)])            # no gate: kept as before
    assert report["excluded"] == {} and quests[100]["changed_in_forever"]


def test_changed_quest_with_a_gate_in_either_faction_view_is_gate_unclear():
    npcs = {1: "Alliance"}
    for static, alliance in ((None, 5), (5, None)):
        fixes = {"Alliance": {"available_until_completed": alliance}, "Horde": {"available_until_completed": None}}
        _, report = run([oq(1, faction="Alliance", giver=place(ident=1), required_level=10)],
                        [qq(1, required_level=30, available_until_completed=static, faction_fixes=fixes)], npcs=npcs)
        assert report["excluded"] == {1: "gate-unclear"}, (static, alliance)


def test_faction_dependent_gate_uses_the_quests_faction_and_never_widens():
    fixes = {"Alliance": {"parent_quest": None}, "Horde": {"parent_quest": 5}}
    npcs = {1: "Alliance", 2: "Horde"}
    quests, report = run([oq(1, faction="Alliance", giver=place(ident=1)), oq(2, faction="Horde", giver=place(ident=2))],
                         [qq(1, faction_fixes=fixes), qq(2, starter_npcs=[2], faction_fixes=fixes)], npcs=npcs)
    assert 1 in quests and report["excluded"] == {2: "parent-quest"}
    # the stored (static) value gates too: a faction fix never lifts an exclusion
    fixes = {"Alliance": {"required_spell": None}, "Horde": {"required_spell": 9}}
    _, report = run([oq(1, faction="Alliance", giver=place(ident=1))], [qq(1, required_spell=9, faction_fixes=fixes)],
                    npcs=npcs)
    assert report["excluded"] == {1: "needs-spell"}
    fixes = {"Alliance": {"available_until_completed": 7}, "Horde": {"available_until_completed": None}}
    quests, _ = run([oq(1, faction="Alliance", giver=place(ident=1))], [qq(1, faction_fixes=fixes)], npcs=npcs)
    assert quests[1]["unavailable_after"] == [7]


def test_next_quest_in_chain_is_reported_not_used():
    quests, report = run([oq(1), oq(2, prereq_ids=[1]), oq(3), oq(5), oq(6)],
                         [qq(1, next_quest_in_chain=2), qq(3, next_quest_in_chain=4), qq(5, next_quest_in_chain=6)])
    assert all(q["prereq"]["all"] in ([], [1]) and q["unavailable_after"] is None for q in quests.values())
    nq = report["next_quest_in_chain"]
    assert (nq["kept_with_next"], nq["next_not_kept"], nq["next_kept_without_prereq"]) == (3, 1, 1)
    assert {(e["quest"], e["why"]) for e in nq["examples"]} == {(3, "next_not_kept"), (5, "next_kept_without_prereq")}


# ---------------------------------------------------------------- final review: race mask origin (8c #3)

@pytest.mark.parametrize("mask,faction", [(77, "Alliance"), (178, "Horde"), (255, "Both")])
def test_era_masks_are_whole_faction_only_from_the_era_layer(mask, faction):
    quests, _ = run([oq(faction=None)], [qq(race_mask=mask, race_mask_origin="era")], npcs={1: "Both"})
    assert quests[100]["race_mask"] is None and quests[100]["faction"] == faction
    for origin in ("forever", None):        # a Forever layer's 77 (or an unknown origin) is a literal mask
        quests, _ = run([oq(faction=None)], [qq(race_mask=mask, race_mask_origin=origin)], npcs={1: "Both"})
        assert quests[100]["race_mask"] == mask and quests[100]["faction"] == faction, origin
        assert not quests[100]["race_mask"] & (SA | SH)


def test_faction_fix_race_mask_uses_its_own_origin():
    fixes = {"Alliance": {"race_mask": 77, "race_mask_origin": "forever"},
             "Horde": {"race_mask": 178, "race_mask_origin": "era"}}
    npcs = {1: "Alliance", 2: "Horde"}
    quests, _ = run([oq(1, faction="Alliance", giver=place(ident=1)), oq(2, faction="Horde", giver=place(ident=2))],
                    [qq(1, race_mask=255, faction_fixes=fixes), qq(2, starter_npcs=[2], race_mask=255, faction_fixes=fixes)],
                    npcs=npcs)
    assert quests[1]["race_mask"] == 77 and quests[2]["race_mask"] is None


# ---------------------------------------------------------------- final review: badge case (T5)

@pytest.mark.parametrize("tag,reason", [("RAID", "raid"), ("raid", "raid"), ("legendary", "raid"), ("pvp", "pvp"),
                                        ("PVP", "pvp"), ("darkmoon faire", "event"), ("INVASION", "event"),
                                        ("Ahn’qiraj  War", "event"), ("alchemy", "needs-skill"),
                                        ("first aid", "needs-skill"), ("BREWFEST", "seasonal")])
def test_badges_match_case_insensitively(tag, reason):
    _, report = run([oq(tags=["Alliance", tag])])
    assert report["excluded"] == {100: reason}
    assert report["unknown_tags"] == {}


def test_lower_case_dungeon_and_class_badges():
    quests, _ = run([oq(tags=["alliance", "dungeon", "rogue"])])
    assert quests[100]["dungeon_quest"] and quests[100]["group_size"] == 5 and quests[100]["class_mask"] == 8


# ---------------------------------------------------------------- final review: Questie data problems (T4, M1, M2)

def qdb_problems(hidden_ids=(), problems=None):
    from pipeline.questiedb import QuestieDBData
    return QuestieDBData(hidden_ids=frozenset(hidden_ids), quest_problems=problems or {})


def test_blacklisted_id_missing_from_questiedb_is_hidden():
    _, report = run([oq(100), oq(101)], [], questiedb=qdb_problems(hidden_ids={100, 99999}), trusted_maps=set())
    assert report["excluded"] == {100: "questie-hidden"}
    _, report = run([oq(100)], [], questiedb=qdb_problems(hidden_ids={100}), without={"questie"})
    assert report["excluded"] == {}           # building without Questie drops its blacklist too


def test_quests_with_a_dropped_questie_correction_are_excluded():
    problems = {100: "correction-skipped", 101: "correction-unclear"}
    _, report = run([oq(100), oq(101), oq(102)], [qq(101)], questiedb=qdb_problems(problems=problems),
                    trusted_maps=set())
    assert report["excluded"] == {100: "correction-skipped", 101: "correction-unclear"}


def _stub_inputs(**c_kw):
    """A (kept) needs B (no giver coords) needs C (rep-gated); D is excluded and unreferenced."""
    return [
        oq(1, name="A", prereq_ids=[2]),
        oq(2, name="B", giver=None, prereq_ids=[3], faction="Both", tags=[], requirements={}),
        oq(3, name="C", **c_kw),
        oq(4, name="D", giver=None),
    ], [qq(3, required_min_rep=[92, 3000])]


def test_stubs_cover_excluded_prerequisites_transitively():
    oogs, questies = _stub_inputs()
    quests, report = run(oogs, questies)
    assert sorted(quests) == [1]
    assert report["excluded"] == {2: "no-giver-coords", 3: "needs-rep", 4: "no-giver-coords"}
    stubs = report["stubs"]
    assert set(stubs) == {2, 3}
    assert stubs[2]["name"] == "B" and stubs[2]["reason"] == "no-giver-coords"
    assert stubs[2]["prereq"]["all"] == [3]
    assert stubs[3]["reason"] == "needs-rep" and stubs[3]["giver"]["id"] == 1
    assert 4 not in stubs


def test_stubs_empty_when_nothing_excluded_is_needed():
    _, report = run([oq(1), oq(2, giver=None)])
    assert report["stubs"] == {}


def test_stub_faction_none_when_fix_unclear():
    fixes = {"Alliance": {"pre_any": None}, "Horde": {"pre_any": [401]}}
    oogs = [oq(1, prereq_ids=[400]), oq(400, name="B", faction="Both", giver=place(ident=30))]
    quests, report = run(oogs, [qq(400, starter_npcs=[30], faction_fixes=fixes)], npcs={30: "Both"})
    assert report["excluded"] == {400: "faction-fix-unclear"}
    assert report["stubs"][400]["faction"] is None
    assert report["stubs"][400]["reason"] == "faction-fix-unclear"


def test_stub_faction_none_when_faction_conflict():
    """The sources disagree on the faction (here an Alliance quest from a Horde-only giver), so the
    stub's faction is unclear: None, never one side that blocks the other (R6)."""
    oogs = [oq(1, prereq_ids=[400]), oq(400, name="B", faction="Alliance", giver=place(ident=30))]
    quests, report = run(oogs, npcs={30: "Horde", 1: "Alliance"})
    assert sorted(quests) == [1]
    assert report["excluded"] == {400: "faction-conflict"}
    assert report["stubs"][400]["faction"] is None
    assert report["stubs"][400]["reason"] == "faction-conflict"
