"""Quest objectives (Contract A field 26), the objective count rule and the point -> objective index
of field 13 (Task 8 of the dungeon-chains plan)."""
import pytest

from pipeline.objectives import Names, build_objectives, count_in_text, rows_from_ids

WOLF_TEXT = "Bring 8 pieces of Tough Wolf Meat to Eagan Peltskinner outside Northshire Abbey."


def names(**kw):
    base = {
        "npcs": {299: "Young Wolf", 69: "Timber Wolf", 704: "Ragged Timber Wolf", 705: "Ragged Young Wolf",
                 706: "Frostmane Troll Whelp", 1501: "Mindless Zombie", 1502: "Wretched Zombie",
                 6: "Kobold Vermin", 7: "Kobold Worker", 2060: "Councilman Smithers", 2061: "Councilman Thatcher",
                 9: "Young Wolf", 10: "Lazy Peon"},
        "objects": {5: "Wanted Poster", 50: "Battered Chest", 51: "Battered Chest", 52: "Old Crate"},
        "items": {750: {"name": "Tough Wolf Meat", "npc_drops": [704, 69, 299, 705, 9], "object_drops": []},
                  3910: {"name": "Snuff", "npc_drops": [], "object_drops": [52, 50, 51]},
                  5952: {"name": "Corrupted Brain Stem", "npc_drops": [1501], "object_drops": [50]},
                  2001: {"name": "Wolf Fang", "npc_drops": [299], "object_drops": []}},
        "npc_spawns": {705: [{"map_id": 1429, "x": 1.0, "y": 1.0}], 69: [{"map_id": 1436, "x": 1.0, "y": 1.0}]},
        "object_spawns": {},
    }
    base.update(kw)
    return Names(**base)


def point(name, map_id=1429, x=45.2, y=35.2):
    return {"map_id": map_id, "x": x, "y": y, "name": name}


# ---------------------------------------------------------------- the count rule

@pytest.mark.parametrize("text,aliases,expected", [
    (WOLF_TEXT, ["Tough Wolf Meat"], 8),                                            # quest 33
    ("Deeg in Booty Bay wants you to bring him 15 shares of Snuff.", ["Snuff"], 15),   # quest 587
    ("Gershala Nightwhisper in Auberdine wants 8 Corrupt Brain stems.", ["Corrupted Brain Stem"], 8),   # 1275
    ("Kill 10 Young Wolves.", ["Young Wolf"], 10),                                   # plural "-ves"
    ("Kill Magistrate Burnside and 5 Hillsbrad Councilmen.", ["Hillsbrad Councilman"], 5),
    ("Kill Magistrate Burnside and 5 Hillsbrad Councilmen.", ["Magistrate Burnside"], None),
    ("Destroy 5 Eggs of Onyxia, then return.", ["Egg of Onyxia destroyed", "Egg of Onyxia"], 5),
    ("Kill 10 of the Defias Trappers.", ["Defias Trapper"], 10),
    # another capitalised name sits between the number and this one: not next to it
    ("Kill 10 Kobold Vermin and Kobold Workers.", ["Kobold Worker"], None),
    ("Kill 10 Kobold Vermin and Kobold Workers.", ["Kobold Vermin"], 10),
    # two different numbers next to the name: ambiguous
    ("Bring 8 Gnoll Paws, or 5 Gnoll Paws if you are in a hurry.", ["Gnoll Paw"], None),
    # the same number twice is still one integer
    ("Bring 8 Gnoll Paws. Yes, 8 Gnoll Paws.", ["Gnoll Paw"], 8),
    # a number that is not right before the name never counts, even the only number of the text
    ("Banish 6 Portals at Mannoroc Coven.", ["Portals Banished", "Demon Portal Guardian"], None),
    ("Bring 3 totems to the 2 elders.", ["Something Else"], None),
    ("Gather one of each and bring 4 ashes.", ["Strange Ash"], None),
    ("Find the three tablets.", ["Tablet of Creation"], None),
    # a number inside a name is never a count
    ("Find Gelkak's First Mate, the Threshwackonator 4100, and lead it back.",
     ["Gelkak's First Mate", "The Threshwackonator 4100"], None),
    ("Bring Nar'thalas Almanac, Vol. 74 to Raene.", ["Nar'thalas Almanac, Vol. 74"], None),
    ("Speak with Captain Placeholder in Auberdine.", ["Captain Placeholder"], None),
    ("Version 1.60 changed nothing.", ["Nothing"], None),                            # a decimal is no integer
    (None, ["Snuff"], None),
    ("", ["Snuff"], None),
    # real texts: eye/eyes, a hyphen, an abbreviation's period, and the longer name a shorter one begins
    ("Salma Saldean wants 3 Stringy Vulture Meat, 3 Goretusk Snouts, 3 Murloc Eyes, 3 Okra.", ["Murloc Eye"], 3),
    ("Slay 15 Firegut Ogre-Mages, 7 Firegut Ogres, and 7 Firegut Ogre Brutes.", ["Firegut Ogre Mage"], 15),
    ("Slay 15 Firegut Ogre-Mages, 7 Firegut Ogres, and 7 Firegut Ogre Brutes.", ["Firegut Ogre"], 7),
    ("Slay 15 Firegut Ogre-Mages, 8 Firegut Ogres, and 7 Firegut Ogre Brutes.", ["Firegut Ogre Brute"], 7),
    # spelled-out numbers next to the name count too
    ("Kill two Mutated Venture Co. Drones, two Venture Co. Patrollers, and two Venture Co. Lookouts.",
     ["Venture Co. Patroller"], 2),
    ("Chef Breanna of Lakeshire wants five pieces of Tough Condor Meat, five Great Goretusk Snouts and five "
     "helpings of Crisp Spider Meat.", ["Great Goretusk Snout"], 5),
    ("Bring three Blasted Boar Lungs, two Scorpok Pincers, and one Basilisk Brain to Bloodmage Drazial.",
     ["Scorpok Pincer"], 2),
    ("Bring three Blasted Boar Lungs, two Scorpok Pincers, and one Basilisk Brain to Bloodmage Drazial.",
     ["Basilisk Brain"], 1),
    ("Free nine Servants of Razelikh, three Servants of Sevine.", ["Servants of Razelikh Freed", "Servant of Razelikh"],
     9),
])
def test_count_rule(text, aliases, expected):
    assert count_in_text(text, aliases) == expected


# Fix round 1: real one-objective texts whose number is not the objective's count. The rule that took the
# only number of a one-objective quest's text is gone; the number must sit right before the name.
FALSE_COUNTS = [
    (5621, "Find Sentinel Shaya and heal her wounds using Lesser Heal (Rank 2). Afterwards, grant her Power Word: "
           "Fortitude and then return to Laurna Morninglight in Dolanaar.", ["Sentinel Shaya"]),
    (5650, "Find Deathguard Kel and heal his wounds using Lesser Heal (Rank 2). Afterwards, grant him Power Word: "
           "Fortitude and then return to Dark Cleric Beryl in Brill.", ["Deathguard Kel"]),
    (5801, "Take the Skeleton Key Mold and 2 Thorium Bars to the top of Fire Plume Ridge in Un'Goro Crater. Use the "
           "Skeleton Key Mold by the lava lake to forge the Unfinished Skeleton Key.\nBring the Unfinished Skeleton "
           "Key to Falla Sagewind in Darnassus.", ["Unfinished Skeleton Key"]),
    (76160, "Gather 8 Windfury Cones north of Thunder Bluff, use them with the Mortar and Pestle, then return to "
            "Boarton Shadetotem in Thunder Bluff with the result.", ["Pine Salve"]),
    (1016, "Collect 5 Intact Elemental Bracers and use the Divining Scroll on them. Afterwards, bring the Divined "
           "Scroll to Sentinel Velene Starstrike at the Silverwind Refuge.", ["Divined Scroll"]),
    (4244, "Find a Mithril Casing and return to A-Me 01 in Un'Goro Crater.", ["Mithril Casing"]),
    (3124, "Kill 10 Frayfeather Hippogryphs of any type, then use the Muisek Vessel to shrink and capture them.",
     ["Hippogryph Muisek"]),
    (3125, "Kill 8 Sprite Darters or Sprite Dragons. Use the Muisek Vessel to shrink and capture the fallen Faerie "
           "Dragons.", ["Faerie Dragon Muisek"]),
    (3126, "Kill 3 Wandering Forest Walkers. Use the Muisek Vessel to shrink and capture the fallen Treants.",
     ["Treant Muisek"]),
    (3127, "Kill 7 Land Walkers or Cliff Giants. Use the Muisek Vessel to shrink and capture the fallen Mountain "
           "Giants.", ["Mountain Giant Muisek"]),
    # a word-stem version of the old rule still got this one wrong ("Rot")
    (6022, "Travel to Corin's Crossing to the east and slaughter the Scourge that inhabit the town. Collect 7 pieces "
           "of Living Rot in under 10 minutes. Use the Mortar and Pestle to grind the Living Rot into Coagulated Rot.",
     ["Coagulated Rot"]),
]


@pytest.mark.parametrize("qid,text,aliases", FALSE_COUNTS, ids=[str(c[0]) for c in FALSE_COUNTS])
def test_a_number_that_does_not_quantify_the_objective_is_no_count(qid, text, aliases):
    assert count_in_text(text, aliases) is None


@pytest.mark.parametrize("text", [
    "Bring Gizmos (2 Gizmos are spares) to Bob.",    # in parentheses
    "Bring Gizmos to the level 4 gizmo vault.",      # after Level
    "Bring Gizmos to the Rank 4 gizmo pile.",        # after Rank
    "Bring Gizmos to unit X-7 4 gizmos away.",       # after (or inside) a hyphenated token
    "Bring Gizmos to unit 04 gizmo hall.",           # a designation with a leading zero
])
def test_numbers_that_are_never_quantities(text):
    assert count_in_text(text, ["Gizmo"]) is None


def test_count_rule_ignores_numbers_inside_any_objective_name_of_the_quest():
    text = "Bring 4 Gizmos to the Threshwackonator 4100 gizmos bay."
    assert count_in_text(text, ["Gizmo"], exclude=["The Threshwackonator 4100"]) == 4
    assert count_in_text(text, ["Gizmo"]) is None     # 4 and 4100 both right before "gizmos"


# ---------------------------------------------------------------- objectives from QuestieDB

def test_questiedb_kinds_names_and_skipped_groups():
    rows = [{"group": 1, "id": 6, "text": None},                 # kill: the NPC's name
            {"group": 2, "id": 5, "text": "Wanted Poster read"},  # object: its in-game text
            {"group": 3, "id": 750, "text": None},               # item
            {"group": 1, "id": 10, "text": "Peons Awoken"},      # an NPC objective with its own text: an event
            {"group": 5, "id": 2060, "ids": [2060, 2061], "text": None},   # kill credit: the base NPC
            {"group": 4, "id": 72, "text": None},                # reputation: not an objective with a name
            {"group": 6, "id": 12345, "text": None}]             # spell: neither
    obs, idx = build_objectives(rows, [], "Kill 3 Kobold Vermin.", names())
    assert [(o["kind"], o["id"], o["name"]) for o in obs] == [
        ("npc", 6, "Kobold Vermin"), ("object", 5, "Wanted Poster read"), ("item", 750, "Tough Wolf Meat"),
        ("other", 10, "Peons Awoken"), ("npc", 2060, "Councilman Smithers")]
    assert obs[0]["count"] == 3 and all(o["count"] is None for o in obs[1:])
    assert idx == []


def test_kill_credit_dummies_are_events_without_a_name():
    """Forever's credit NPCs ("Credit", "DNT KILL CREDIT", "[DNT] Kill Credit: ...") name nothing."""
    dummies = names(npcs={270573: "Credit", 255013: "DNT KILL CREDIT", 253370: "[DNT] Kill Credit: Place Explosives"})
    rows = [{"group": 1, "id": i, "text": None} for i in (270573, 255013, 253370)]
    obs, idx = build_objectives(rows, [point("DNT KILL CREDIT")], "Place the three vials.", dummies)
    assert [(o["kind"], o["id"], o["name"]) for o in obs] == [("other", 270573, None), ("other", 255013, None),
                                                               ("other", 253370, None)]
    assert idx == [2]          # the point at the dummy NPC is still that objective's place


def test_unknown_entity_keeps_its_place_without_a_name():
    obs, _ = build_objectives([{"group": 3, "id": 999, "text": None}], [], "Bring the thing.", names())
    assert obs == [{"kind": "item", "id": 999, "name": None, "count": None, "from": None, "from_kind": None,
                    "from_more": False}]


def test_a_count_needs_the_objective_name():
    """Fix round 1: a number counts only right before the objective's name, so an objective whose name
    nobody knows (ids only) has no count; with its name, quest 587 needs 15."""
    text = "Deeg in Booty Bay wants you to bring him 15 shares of Snuff."
    obs, _ = build_objectives(rows_from_ids({"objective_item_ids": [3910]}), [], text, Names())
    assert [(o["kind"], o["id"], o["count"]) for o in obs] == [("item", 3910, None)]
    obs, _ = build_objectives(rows_from_ids({"objective_item_ids": [3910]}), [], text, names())
    assert [(o["kind"], o["id"], o["name"], o["count"]) for o in obs] == [("item", 3910, "Snuff", 15)]


def test_rows_from_ids_keeps_the_group_order():
    z = {"objective_creature_ids": [6], "objective_object_ids": [5], "objective_item_ids": [750, 2001]}
    assert rows_from_ids(z) == [{"group": 1, "id": 6, "text": None}, {"group": 2, "id": 5, "text": None},
                                {"group": 3, "id": 750, "text": None}, {"group": 3, "id": 2001, "text": None}]
    assert rows_from_ids({}) == []


# ---------------------------------------------------------------- where an item comes from

def test_item_from_names_prefer_point_names_then_the_quest_maps_then_ids():
    """750 drops from five NPCs (two named Young Wolf): Young Wolf is a point of the quest, Ragged
    Young Wolf (705) spawns on its map 1429, then the rest by id; four distinct names -> three + more."""
    obs, _ = build_objectives([{"group": 3, "id": 750, "text": None}], [point("Young Wolf")], WOLF_TEXT,
                              names(), maps={1429})
    o = obs[0]
    assert o["from"] == ["Young Wolf", "Ragged Young Wolf", "Timber Wolf"]
    assert (o["from_kind"], o["from_more"]) == ("npc", True)
    assert o["count"] == 8


def test_item_found_in_objects_only():
    obs, _ = build_objectives([{"group": 3, "id": 3910, "text": None}], [], "Bring 15 shares of Snuff.",
                              names())
    o = obs[0]
    assert (o["from"], o["from_kind"], o["from_more"]) == (["Battered Chest", "Old Crate"], "object", False)


def test_item_with_npc_and_object_sources_names_the_npcs():
    obs, _ = build_objectives([{"group": 3, "id": 5952, "text": None}], [], "x", names())
    assert (obs[0]["from"], obs[0]["from_kind"]) == (["Mindless Zombie"], "npc")


# ---------------------------------------------------------------- point -> objective index

def test_points_match_by_name_and_by_drop_source():
    rows = [{"group": 1, "id": 6, "text": None}, {"group": 3, "id": 750, "text": None}]
    pts = [point("Tough Wolf Meat"), point("Kobold Vermin"), point("ragged  timber wolf"), point("Strange Glow"),
           point("TOUGH WOLF MEAT")]
    obs, idx = build_objectives(rows, pts, WOLF_TEXT, names())
    assert idx == [2, 1, 2, None, 2]
    assert obs[1]["count"] == 8


def test_a_point_matches_an_objective_by_its_entity_name_too():
    """An objective named by its in-game text ("Peons Awoken") still owns the points named after its NPC."""
    obs, idx = build_objectives([{"group": 1, "id": 10, "text": "Peons Awoken"}], [point("Lazy Peon")], "x", names())
    assert idx == [1] and obs[0]["name"] == "Peons Awoken"


def test_a_row_listed_twice_is_one_objective():
    """QuestieDB lists some objective rows twice (Basic Campfire in The Great Outdoors): one objective."""
    row = {"group": 2, "id": 52, "text": None}
    obs, idx = build_objectives([row, dict(row)], [point("Old Crate"), point("Old Crate")], "Open 1 old crate.",
                                names())
    assert [(o["kind"], o["id"], o["name"], o["count"]) for o in obs] == [("object", 52, "Old Crate", 1)]
    assert idx == [1, 1]


def test_ambiguous_points_get_no_index():
    """A mob that drops two required items, or two objectives on the same object: never guess."""
    rows = [{"group": 3, "id": 750, "text": None}, {"group": 3, "id": 2001, "text": None},
            {"group": 2, "id": 50, "text": "Open the first chest"}, {"group": 2, "id": 51, "text": "Open the second"}]
    _, idx = build_objectives(rows, [point("Young Wolf"), point("Battered Chest"), point("Wolf Fang")], "x", names())
    assert idx == [None, None, 2]


# ---------------------------------------------------------------- outof.games fallback

def test_fallback_to_point_names_when_questiedb_has_no_objectives():
    pts = [point("Tough Wolf Meat"), point("Kobold Vermin"), point("Strange Glow"), point("Tough Wolf Meat"),
           point("Battered Chest"), point("Young Wolf")]
    obs, idx = build_objectives([], pts, "Collect 8 Tough Wolf Meat and investigate the Strange Glow.", names())
    assert [(o["kind"], o["id"], o["name"], o["count"]) for o in obs] == [
        ("item", 750, "Tough Wolf Meat", 8),
        ("npc", 6, "Kobold Vermin", None),
        ("other", None, "Strange Glow", None),
        ("object", None, "Battered Chest", None),     # two objects share the name: no id
        ("npc", None, "Young Wolf", None),            # two NPCs share the name: no id
    ]
    assert obs[0]["from"] == ["Young Wolf", "Timber Wolf", "Ragged Timber Wolf"]
    assert idx == [1, 2, 3, 1, 4, 5]


def test_fallback_name_counts_like_any_objective():
    obs, idx = build_objectives([], [point("Strange Glow"), point("Strange Glow")], "Investigate 3 strange glows.",
                                Names())
    assert [(o["kind"], o["name"], o["count"]) for o in obs] == [("other", "Strange Glow", 3)]
    assert idx == [1, 1]
    obs, _ = build_objectives([], [point("Strange Glow")], "Find 3 of them.", Names())
    assert obs[0]["count"] is None


def test_no_objectives_and_no_points():
    assert build_objectives([], [], "Talk to Bob.", names()) == ([], [])
    assert build_objectives(None, None, None, Names()) == ([], [])
