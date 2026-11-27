"""Merge outof.games quests (primary, Forever 1.60.1) with QuestieDB Forever (the Questie source).

The output is the quest set the addon recommends from, so the rule throughout is:
never keep a quest the player might not be able to get; when in doubt, exclude.

Inputs: ``oog`` maps quest id -> ``pipeline.outofgames.parse_quest`` dict; ``questie``
maps quest id -> a ``pipeline.questiedb.QuestieDBData.quests`` dict (QuestieDB Forever with
every correction layer applied; its ``faction_fixes`` holds the gating fields whose Dynamic
Corrections differ by faction); ``recorder`` (optional) maps quest id -> ``{"xp": {level: xp}, "level": int | None,
"giver": {npc, map_id, x, y} | None}`` with values already agreed upstream; ``npcs`` (optional)
maps NPC id -> "Alliance" | "Horde" | "Both" | "Conflict" | None, built with ``giver_factions()``
from the outof.games NPC JSON and the QuestieDB Forever NPCs (their friendlyToFaction; pass an
empty map when building without Questie); ``questiedb`` (optional) is the QuestieDBData itself
and ``trusted_maps`` the uiMapIDs ``spawn_check()`` trusts, for the giver and XP fill. Only
quests present in ``oog`` are merged.

Precedence per field: recorder > outof.games > Questie. Questie fills a field only when
outof.games has no value; a quest whose giver, required level (> 2 apart) or prerequisite
set disagrees with Questie (its Forever starters, levels and prerequisites) is
``changed_in_forever`` and goes in the conflict report. For such quests Questie's restriction
fields are still kept when outof.games has nothing explicit (restrictive-safe: race/class
masks, exclusive_to, breadcrumb_of, prerequisites), but Questie's quest level and required
level are not used.

QuestieDB availability gates (questMeta fields 25, 30 and 33-36), applied through every correction
layer like the other Questie fields; a gate only ever narrows a quest:
  availableStartingWith X  X is added to ``prereq["all"]`` (never ``any``: that would widen it), unless
                           ``all`` already lists it; ``provenance["prereq_gate"]`` = "questie"
  availableUntilCompleted X, disabledByQuest X
                           X goes into ``unavailable_after`` (Contract A field 25): the quest is
                           ineligible once X is completed or in the log. Only Eligibility reads it, never
                           Route's mutual-exclusion pruning (an exclusiveTo there would drop one of two
                           chained quests). disabledByQuest really ends when X is turned in; treating it
                           as permanent is the restrictive reading.
  parentQuest              excluded (parent-quest): only available while the parent is in the log
  requiredSpell / requiredRanks  excluded (needs-spell / needs-rank): v1 cannot check either
outof.games states none of these facts, except that its "Not available after" row names quests that
end the quest; that row's quest ids (``not_available_after_ids``) not already in ``exclusive_to`` are
added to ``unavailable_after`` too, so no gate from either source is dropped. A changed_in_forever
quest with any QuestieDB gate is excluded (gate-unclear) instead of using the gate: spec §5.2 says not
to trust Questie's restriction fields for it, and dropping the gate would breach the anti-goal.
QuestieDB's nextQuestInChain is not used; ``report["next_quest_in_chain"]`` counts kept quests whose
successor is not kept or does not list them as a prerequisite.

Questie data problems: an outof.games quest whose id the Questie blacklist hides is questie-hidden even
when QuestieDB lacks it (``questiedb.hidden_ids``); one with a QuestieDB correction that could not be
applied (``questiedb.quest_problems``) is excluded as correction-skipped or correction-unclear.

Faction-dependent QuestieDB data: when Alliance and Horde Dynamic Corrections give a gating field
different values (``faction_fixes``), a quest of one faction (after the giver narrowing) uses its
faction's values; a quest of both factions (or of no known faction) is faction-fix-unclear.

Giver fill (QuestieDB, only when the recorder and outof.games give no giver with map, x and y,
and never for a changed_in_forever quest): the candidates are the oog NPC (or object) giver when QuestieDB's quest lists it among its
starters of that kind, or, with no oog giver, QuestieDB's NPC and object starters (item starters
never). For an Alliance or Horde quest, NPC candidates whose friendlyToFaction lacks that
faction are dropped. A candidate is usable when its spawns on trusted maps all lie on one
uiMapID within GIVER_SPREAD map units of their mean, which becomes the giver point. Exactly one
usable candidate becomes the giver (provenance "questiedb"). Two or more usable candidates, or none
usable because a candidate's trusted spawns are scattered or split across maps, make the quest
questie-giver-ambiguous; with no candidate, or only candidates without a spawn on a trusted map (or
of the wrong faction), it stays no-giver-coords.

XP: outof.games > QuestieDB (``xp_source`` "questiedb"), used only when ``xp_check()`` finds the
two agree (same level -> within XP_TOLERANCE) on at least XP_MIN_AGREEMENT of the quests that
have both, and only when QuestieDB's XP level equals the merged quest level.

Each merged quest uses the Contract A field names (Quests.lua) in snake case, with
enums as strings that the emitter encodes: ``faction`` "Alliance" | "Horde" | "Both";
place ``kind`` "npc" | "object" | "item"; ``level_source`` "game" | "estimate" | "recorder";
``xp_source`` "game" | "questiedb". The flag bits of Contract A field 9 are separate booleans
(``elite``, ``class_quest`` (set only when the class mask allows 1 or 2 of the 9 classes; the mask
itself is always kept, so eligibility still bars the other classes), ``new_in_forever``, ``unverified``, ``repeatable``,
``dungeon_quest``). Extra fields: ``id``, ``changed_in_forever``, ``required_max_level``
(Questie, for eligibility), ``recorded_xp`` (recorder), ``source_url`` and ``provenance``
({field: "outofgames" | "questie" | "questiedb" | "recorder" | "giver" | "tag"} for every
filled field).

Race masks carry the Forever ChrRaces bits: races 1..9 are 2^(id-1), High Order Skyborne
(raceID 95, Alliance) 2^32, Windshaper Skyborne (96, Horde) 2^33. A whole-faction mask means no
race restriction plus that faction: Questie 77 + 2^32 (Alliance), 178 + 2^33 (Horde), 255 + 2^32 +
2^33 (Both); Questie 77, 178 and 255 only when the mask's origin is the Era data or the legacy
Classic fixes (``race_mask_origin`` "era": those rows predate Skyborne), never when a Forever layer
wrote it (a literal mask that leaves Skyborne out); and an explicit outof.games Race row listing every
race of a faction including its Skyborne.
Every other mask is kept in full, Forever bits included; an oog row of the classic Alliance
races without Skyborne stays 77 (1.60.1 game data). No bit is ever dropped.

Class mask: Class row > Questie mask > a class-category badge (e.g. "Rogue"), provenance "tag".

Faction: outof.games (its faction, else the single faction its Race row implies) > derived from
the Questie race mask; then the giver: a "Both" quest
whose NPC giver is friendly to one faction only is narrowed to that faction (provenance
"giver"); an Alliance quest from a Horde-only giver (or the reverse), or any quest from a
giver whose two NPC sources contradict each other ("Conflict"), is a faction-conflict; a
"Both" quest whose NPC giver's faction is unknown is excluded.

Chains: every kept quest of a chain gets the longest length any member's page reports.

Objectives (Contract A field 26, ``pipeline.objectives``): built from the QuestieDB objective rows
(``objectives``; a plain Questie dict's ``objective_*_ids`` otherwise) with QuestieDB's NPC, object and
item names and drop sources, else from the outof.games point names; each objective point gets the
1-based index of its objective (``objective``, None when unmatched). Required items (field 15) take the
count of their item objective, from the objective text by the same never-guessing rule: None when the
text does not say, never a placeholder 1 (provenance ``objectives``: "questiedb" | "outofgames").

Exclusion reasons, checked in this order (first match wins; * = added from the crawl data,
accepted by the controller):
  test-name          name matches TEST_NAME_RE (placeholder, deprecated or test quest)
  questie-hidden     the Questie quest blacklist (Forever client) hides the quest id, whether or not
                     QuestieDB has the quest
  correction-skipped a QuestieDB correction row for this id was skipped (no such quest, no name)
  correction-unclear a QuestieDB correction to a gating field of this quest could not be applied
                     (unresolved or rejected value), or a Dynamic Correction creates it for one faction only
  questie-giver-ambiguous  giver without map/x/y and QuestieDB cannot settle one point: two or more
                     usable candidates, or a candidate's trusted spawns scattered or on several maps
  no-giver-coords    no giver, or giver without map/x/y, and no usable QuestieDB candidate (none,
                     none with a spawn on a trusted map, or a changed_in_forever quest): cannot be routed to
  no-faction         faction unknown from both sources
  faction-conflict   quest faction disagrees with the race mask's or the giver's single faction,
                     or the giver's NPC sources contradict each other
  giver-faction-unknown  "Both" quest whose NPC giver has no known faction: may be one-faction
  faction-fix-unclear  QuestieDB's Dynamic Corrections set a gating field differently for Alliance
                     and Horde, and the quest is not of a single faction: which applies is unknown
  no-data            no quest level or no required level: eligibility cannot be judged
  prereq-unclear     oog prerequisite count does not match the quests it lists
  race-unclear*      Race row names only races without a known bit
  class-unclear*     Class row names only classes without a known bit
  exclusive-unclear* "Not available after" row whose quest links could not be read
  gate-unclear       changed_in_forever quest with a QuestieDB availability gate
  parent-quest       QuestieDB parentQuest: available only while another quest is in the log
  needs-skill        Questie skill/specialization, or* an oog profession badge (v1 cannot check)
  needs-rep          Questie min/max reputation, or* an oog Reputation row (v1 cannot check)
  needs-spell        QuestieDB requiredSpell (v1 cannot check known spells)
  needs-rank         QuestieDB requiredRanks (profession ranks; v1 cannot check)
  raid               Raid or Legendary badge: raid-tier, not leveling content
  pvp                PvP badge
  seasonal*          Seasonal or holiday badge (Brewfest, Midsummer, any "...Festival"...):
                     only available during the holiday
  event*             Invasion, Darkmoon Faire, Nightmare Incursions, Ahn'Qiraj War or Blackrock
                     Eruption badge: only available during an event / war effort
  zone-not-live      giver map not in live_maps (skipped when live_maps is None)

Badges are matched case-insensitively (curly apostrophes and extra spaces normalised).
Badges and Requirements labels the merge does not interpret never exclude; they are counted
in ``report["unknown_tags"]`` / ``report["unknown_requirements"]`` for auditing the crawl.
Race and class names a row lists without a known bit are counted in ``report["unknown_names"]``.

Required breadcrumbs: a post-pass over the merged quests clears ``breadcrumb_of`` on quest A when
A is in its target B's final ``prereq["all"]`` (A is a required step, not an optional lead-in; the
oog prerequisite wins over Questie's flag, e.g. 363 -> 364). ``provenance["breadcrumb_of"]`` is
removed with it. The pairs are listed in ``report["breadcrumb_dropped_required"]`` as
``{"quest": A, "target": B}`` and counted in ``report["counts"]["breadcrumb_dropped_required"]``.
When A is only in B's ``prereq["any"]`` the flag stays (B can finish through another member, so
A's "unavailable once B is done" rule still matters); those pairs are counted in
``report["counts"]["breadcrumb_kept_any"]``.
"""
from __future__ import annotations

import math
import re
from collections import Counter, defaultdict

from pipeline.objectives import Names, build_objectives, rows_from_ids

TEST_NAME_RE = re.compile(
    r"(?i)^(\[(dnt|ph|unused|test)\]|(dnt|ph)$|deprecated\b|unused\b|zz|test\s*\d*$|test quest\b)")

SKYBORNE_ALLIANCE = 2 ** 32           # High Order Skyborne, raceID 95 (Forever ChrRaces 1.60.1)
SKYBORNE_HORDE = 2 ** 33              # Windshaper Skyborne, raceID 96
SKYBORNE_BITS = SKYBORNE_ALLIANCE + SKYBORNE_HORDE
ERA_ALLIANCE_RACES = 1 + 4 + 8 + 64   # 77
ERA_HORDE_RACES = 2 + 16 + 32 + 128   # 178
ERA_ALL_RACES = ERA_ALLIANCE_RACES + ERA_HORDE_RACES   # 255
ALLIANCE_RACES = ERA_ALLIANCE_RACES + SKYBORNE_ALLIANCE
HORDE_RACES = ERA_HORDE_RACES + SKYBORNE_HORDE
ALL_RACES = ALLIANCE_RACES + HORDE_RACES
# Masks meaning "every race of the faction": no race restriction, only the faction. The Era-origin
# 77/178/255 rows predate Skyborne; an oog Race row is whole-faction only when it lists Skyborne too.
WHOLE_FACTION_MASKS = {ALLIANCE_RACES: "Alliance", HORDE_RACES: "Horde", ALL_RACES: "Both"}
ERA_WHOLE_FACTION_MASKS = {ERA_ALLIANCE_RACES: "Alliance", ERA_HORDE_RACES: "Horde", ERA_ALL_RACES: "Both"}
RACE_BITS = {"human": 1, "orc": 2, "dwarf": 4, "night elf": 8, "undead": 16, "scourge": 16,
             "tauren": 32, "gnome": 64, "troll": 128,
             "high order skyborne": SKYBORNE_ALLIANCE, "windshaper skyborne": SKYBORNE_HORDE}
CLASS_BITS = {"warrior": 1, "paladin": 2, "hunter": 4, "rogue": 8, "priest": 16, "shaman": 64,
              "mage": 128, "warlock": 256, "druid": 1024}
SINGLE_FACTIONS = ("Alliance", "Horde")
CONFLICT = "Conflict"   # giver_factions(): outof.games and QuestieDB name opposite factions
QUESTIE_FRIENDLY = {"A": "Alliance", "H": "Horde", "AH": "Both"}
# QuestieDB giver fill (Task 8c): spawn trust check and the usable-spawn rule.
SPAWN_MATCH_DISTANCE = 3.0     # map units: a QuestieDB spawn this close to an oog spawn matches
TRUST_MIN_NPCS = 3             # comparable NPCs a uiMapID needs before it can be trusted
TRUST_MIN_RATE = 0.8           # share of them that must match
GIVER_SPREAD = 5.0             # map units: a candidate's trusted spawns must all lie this close to their mean
XP_TOLERANCE = 0.05            # oog and QuestieDB XP at the same level agree within 5 %
XP_MIN_AGREEMENT = 0.9         # below this agreement QuestieDB XP is not used

# oog badges meaning a profession is needed (v1 cannot check professions -> "needs-skill").
PROFESSION_TAGS = frozenset({
    "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering", "First Aid", "Fishing",
    "Herbalism", "Leatherworking", "Mining", "Skinning", "Tailoring", "Jewelcrafting"})
EVENT_TAGS = frozenset({"Invasion", "Darkmoon Faire", "Nightmare Incursions", "Ahn'Qiraj War",
                        "Blackrock Eruption"})
RAID_TAGS = frozenset({"Raid", "Legendary"})
# Holiday badges (lower-case, straight apostrophe); any badge containing "festival" also counts.
SEASONAL_TAGS = frozenset({"seasonal", "lunar festival", "midsummer", "hallow's end", "winter veil",
                           "love is in the air", "noblegarden", "children's week", "harvest festival",
                           "brewfest"})
# Badges the merge interprets (besides level badges and class-category badges).
HANDLED_TAGS = frozenset({"Alliance", "Horde", "Alliance and Horde", "Elite", "Repeatable", "Dungeon",
                          "PvP"}) | PROFESSION_TAGS | EVENT_TAGS | RAID_TAGS
_LEVEL_TAG_RE = re.compile(r"^(requires level|quest level|about level) [0-9]+$")


def _norm_tag(tag: str) -> str:
    """Badge text as matched: lower case, curly apostrophe straightened, whitespace collapsed."""
    return " ".join(str(tag).replace("\u2019", "'").split()).lower()


def _tag_keys(tags) -> frozenset:
    return frozenset(_norm_tag(t) for t in tags)


PROFESSION_KEYS, EVENT_KEYS, RAID_KEYS, HANDLED_KEYS = (
    _tag_keys(PROFESSION_TAGS), _tag_keys(EVENT_TAGS), _tag_keys(RAID_TAGS), _tag_keys(HANDLED_TAGS))
NOT_AVAILABLE_AFTER = "Not available after"
# Requirements labels the merge (or parse_quest's prerequisite reader) interprets.
HANDLED_REQUIREMENTS = frozenset({"Level", "Faction", "Race", "Races", "Class", "Classes",
                                  NOT_AVAILABLE_AFTER, "Reputation", "Finish first"})
STARTER_FIELD = {"npc": "starter_npcs", "object": "starter_objects", "item": "starter_items"}
# Sources a build can leave out (--without). questie and recorder are merge inputs; openmap
# feeds only the generated travel links and dungeons (removed in build.load_curated) and zone levels.
REMOVABLE_SOURCES = frozenset({"questie", "recorder", "openmap"})
QUESTIE_DISABLED_WARNING = "questie-disabled: skill/rep/race restrictions from Questie not applied"

# Exclusion reasons in the order they are checked (see the module docstring).
EXCLUSION_ORDER = (
    "test-name", "questie-hidden", "correction-skipped", "correction-unclear", "questie-giver-ambiguous",
    "no-giver-coords", "no-faction", "faction-conflict", "giver-faction-unknown", "faction-fix-unclear", "no-data",
    "prereq-unclear", "race-unclear", "class-unclear", "exclusive-unclear", "gate-unclear", "parent-quest",
    "needs-skill", "needs-rep", "needs-spell", "needs-rank", "raid", "pvp", "seasonal", "event", "zone-not-live")
# QuestieDB availability gates (pipeline.questie._GATES output names), any of which makes a
# changed_in_forever quest gate-unclear.
GATE_FIELDS = ("available_starting_with", "available_until_completed", "disabled_by_quest", "parent_quest",
               "required_spell", "required_ranks")
_FLAG_KEYS = ("changed_in_forever", "new_in_forever", "unverified", "rewards_other",
              "faction_from_questie", "faction_from_giver", "giver_from_questiedb", "xp_from_questiedb",
              "skyborne_race_mask")


def giver_factions(oog_npcs: dict, questie_npcs: dict) -> dict[int, str | None]:
    """{npc_id: "Alliance" | "Horde" | "Both" | "Conflict" | None} for the giver-faction check.

    oog_npcs: {id: pipeline.outofgames.parse_npc dict}; questie_npcs: {id: {"friendly": ...}} as in
    QuestieDBData.npcs (in a build: the QuestieDB Forever
    friendlyToFaction). The two are combined restrictively:

      outof.games       Questie                              result
      Alliance/Horde    absent, same faction or AH           that faction
      Alliance/Horde    the opposite single faction          "Conflict"
      Alliance/Horde    nil (present, hostile to both)       that faction (a single faction wins)
      Both              A or H                               that single faction
      Both              AH or absent                         Both
      Both              nil (present, hostile to both)       None
      None / no page    A / H / AH / nil / absent            Alliance / Horde / Both / None / None

    No combination widens: the result is never broader than either source's single faction.
    """
    oog = {int(i): (n or {}).get("faction") for i, n in (oog_npcs or {}).items()}
    questie = {int(i): QUESTIE_FRIENDLY.get((n or {}).get("friendly")) for i, n in (questie_npcs or {}).items()}
    out: dict[int, str | None] = {}
    for nid in oog.keys() | questie.keys():
        mine = oog.get(nid) if oog.get(nid) in ("Alliance", "Horde", "Both") else None
        if nid not in questie:
            out[nid] = mine
            continue
        theirs = questie[nid]   # None: present in Questie but hostile to both
        if mine is None:
            out[nid] = theirs
        elif theirs is None:
            out[nid] = None if mine == "Both" else mine
        elif mine == "Both":
            out[nid] = theirs
        elif theirs in ("Both", mine):
            out[nid] = mine
        else:
            out[nid] = CONFLICT
    return out


def spawn_check(oog_npcs: dict, questie_spawns: dict, distance: float = SPAWN_MATCH_DISTANCE,
                min_npcs: int = TRUST_MIN_NPCS, min_rate: float = TRUST_MIN_RATE) -> dict:
    """Which uiMapIDs' QuestieDB NPC spawns agree with outof.games, so the giver fill may use them.

    oog_npcs: {id: parse_npc dict}; questie_spawns: QuestieDBData.npc_spawns. An NPC is comparable
    on a uiMapID when both sources have spawns of it there; it matches when every QuestieDB spawn
    of it on that map lies within ``distance`` map units of some oog spawn on the same map. A map
    is trusted with at least ``min_npcs`` comparable NPCs of which at least ``min_rate`` match.
    NPCs QuestieDB places on a map where oog has none of their spawns count as ``questie_only``.
    Returns {"maps": {uiMapID: tallies + "rate" + "trusted"}, "trusted": [uiMapID, ...],
    "overall": totals, plus the thresholds}.
    """
    maps: dict = {}
    for nid, page in (oog_npcs or {}).items():
        theirs = (questie_spawns or {}).get(int(nid))
        mine = [s for s in (page or {}).get("spawns") or []
                if None not in (s.get("map_id"), s.get("x"), s.get("y"))]
        if not theirs or not mine:
            continue
        oog_by_map, questie_by_map = defaultdict(list), defaultdict(list)
        for s in mine:
            oog_by_map[s["map_id"]].append(s)
        for s in theirs:
            questie_by_map[s["map_id"]].append(s)
        for map_id, points in questie_by_map.items():
            t = maps.setdefault(map_id, {"comparable": 0, "matched": 0, "spawns": 0, "spawns_matched": 0,
                                         "questie_only": 0})
            if map_id not in oog_by_map:
                t["questie_only"] += 1
                continue
            near = [min(math.hypot(p["x"] - s["x"], p["y"] - s["y"]) for s in oog_by_map[map_id]) <= distance
                    for p in points]
            t["comparable"] += 1
            t["matched"] += all(near)
            t["spawns"] += len(near)
            t["spawns_matched"] += sum(near)
    for t in maps.values():
        t["rate"] = round(t["matched"] / t["comparable"], 4) if t["comparable"] else None
        t["trusted"] = t["comparable"] >= min_npcs and t["matched"] / t["comparable"] >= min_rate - 1e-9
    overall = {k: sum(t[k] for t in maps.values()) for k in ("comparable", "matched", "spawns", "spawns_matched",
                                                             "questie_only")}
    overall["rate"] = round(overall["matched"] / overall["comparable"], 4) if overall["comparable"] else None
    return {"distance": distance, "min_npcs": min_npcs, "min_rate": min_rate,
            "maps": {m: maps[m] for m in sorted(maps)}, "trusted": sorted(m for m, t in maps.items() if t["trusted"]),
            "overall": overall}


def xp_check(oog: dict[int, dict], questie_xp: dict) -> dict:
    """Do outof.games XP and QuestieDB XP mean the same thing? Compared on quests with both: at the
    same level they must be equal or within XP_TOLERANCE of the oog value. ``fill`` is True when at
    least XP_MIN_AGREEMENT of the same-level quests agree."""
    both = [(o, questie_xp[qid]) for qid, o in oog.items() if o.get("xp") is not None and qid in questie_xp]
    same = [(o, z) for o, z in both if o.get("quest_level") is not None and o["quest_level"] == z[0]]
    agree = sum(1 for o, z in same if abs(o["xp"] - z[1]) <= XP_TOLERANCE * o["xp"])
    rate = round(agree / len(same), 4) if same else None
    return {"both": len(both), "same_level": len(same), "agree": agree, "rate": rate,
            "tolerance": XP_TOLERANCE, "min_agreement": XP_MIN_AGREEMENT,
            "fill": rate is not None and rate >= XP_MIN_AGREEMENT}


class _Fill:
    """QuestieDB Forever data the merge fills from (giver points and XP)."""

    def __init__(self, questiedb, trusted_maps, use_xp: bool):
        self.npcs = questiedb.npcs or {}
        self.spawns = {"npc": questiedb.npc_spawns or {}, "object": questiedb.object_spawns or {}}
        self.trusted = frozenset(trusted_maps or ())
        self.xp = questiedb.xp or {}
        self.use_xp = use_xp


def _usable_point(spawns, trusted) -> tuple[dict | None, str | None]:
    """(point, None) with the mean of a candidate's trusted-map spawns, when they all lie on one
    uiMapID within GIVER_SPREAD map units of that mean; otherwise (None, why it is not usable)."""
    if not spawns:
        return None, "no-spawns"
    points = [s for s in spawns if s["map_id"] in trusted]
    if not points:
        return None, "untrusted-map-only"
    if len({s["map_id"] for s in points}) != 1:
        return None, "several-maps"
    x = sum(s["x"] for s in points) / len(points)
    y = sum(s["y"] for s in points) / len(points)
    if any(math.hypot(s["x"] - x, s["y"] - y) > GIVER_SPREAD for s in points):
        return None, "scattered"
    return {"map_id": points[0]["map_id"], "x": round(x, 2), "y": round(y, 2)}, None


def _questiedb_giver(oog_giver: dict | None, z: dict | None, faction: str | None,
                     fill: _Fill) -> tuple[dict | None, str, str | None]:
    """(giver place or None, status, why) for a giver without coordinates.

    status: "filled"; "ambiguous" (two or more usable candidates -- why "several-usable" -- or no
    usable one because a candidate's trusted spawns are "scattered" or on "several-maps"); "no-usable"
    (every candidate lacks a spawn on a trusted map -- why "no-spawns", "untrusted-map-only", or
    "no-trusted-spawns" when the candidates differ -- or was dropped by the faction rule, why
    "wrong-faction"); "no-candidates".

    Candidates: the oog NPC (or object) giver when QuestieDB's quest lists it among its starters of
    that kind; with no oog giver, QuestieDB's NPC and object starters. Item starters never. For an
    Alliance or Horde quest, NPC candidates whose friendlyToFaction lacks that faction are dropped
    (objects have no friendlyToFaction). Exactly one candidate with a usable point is the giver.
    """
    if z is None or (oog_giver and oog_giver.get("kind") not in ("npc", "object")):
        return None, "no-candidates", None
    if oog_giver and oog_giver.get("id") is not None:
        kind = oog_giver["kind"]
        candidates = [(kind, oog_giver["id"])] if oog_giver["id"] in (z.get(STARTER_FIELD[kind]) or []) else []
    else:
        candidates = ([("npc", i) for i in z.get("starter_npcs") or []]
                      + [("object", i) for i in z.get("starter_objects") or []])
    if not candidates:
        return None, "no-candidates", None
    if faction in SINGLE_FACTIONS:
        letter = faction[0]
        candidates = [(k, i) for k, i in candidates
                      if k != "npc" or letter in ((fill.npcs.get(i) or {}).get("friendly") or "")]
        if not candidates:
            return None, "no-usable", "wrong-faction"
    usable, why = [], []
    for kind, ident in candidates:
        point, reason = _usable_point(fill.spawns[kind].get(ident), fill.trusted)
        if point is not None:
            usable.append({"kind": kind, "id": ident, **point})
        why.append(reason)
    if len(usable) == 1:
        return usable[0], "filled", None
    if usable:
        return None, "ambiguous", "several-usable"
    spread = [r for r in why if r in ("scattered", "several-maps")]
    if spread:
        return None, "ambiguous", spread[0]
    return None, "no-usable", why[0] if len(set(why)) == 1 else "no-trusted-spawns"


def _place(p: dict | None) -> dict | None:
    if p is None:
        return None
    return {k: p.get(k) for k in ("kind", "id", "map_id", "x", "y")}


def _has_coords(p: dict | None) -> bool:
    return p is not None and all(p.get(k) is not None for k in ("map_id", "x", "y"))


def _row(requirements: dict, *labels: str) -> str | None:
    return next((requirements[label] for label in labels if label in requirements), None)


def _ids(values) -> list[int]:
    """Quest ids with Questie's sign markers dropped (abs), duplicates removed, order kept."""
    return list(dict.fromkeys(abs(v) for v in values or []))


def _parse_names(text: str, table: dict[str, int]) -> tuple[int | None, list[str]]:
    """'Human, Dwarf' -> (mask of the known names or None, [unknown names])."""
    mask, unknown = 0, []
    for part in re.split(r"[,/]", text or ""):
        name = " ".join(part.split())
        if not name:
            continue
        bit = table.get(name.lower())
        if bit is None:
            unknown.append(name)
        else:
            mask |= bit
    return (mask or None), unknown


def _class_quest(class_mask) -> bool:
    """Contract A flag bit 2: the class mask allows only 1 or 2 of the 9 classes. A mask that
    allows most classes (e.g. everyone but Warlock) is a restriction, not a class quest."""
    if not class_mask:
        return False
    return 0 < sum(1 for bit in CLASS_BITS.values() if class_mask & bit) <= 2


def _faction_from_mask(mask: int | None) -> str | None:
    if not mask:
        return None
    alliance, horde = mask & ALLIANCE_RACES, mask & HORDE_RACES
    if alliance and horde:
        return "Both"
    return "Alliance" if alliance else "Horde" if horde else None


def _race(mask: int | None, era_whole_faction: bool) -> tuple[int | None, str | None]:
    """Race mask -> (race mask to keep, faction it implies).

    A whole-faction mask becomes no race mask plus that faction; every other mask is kept in full
    (Forever bits included). era_whole_faction: the Era-origin 77/178/255 also count as whole
    faction (Questie/QuestieDB masks; not an explicit oog Race row, which is 1.60.1 game data).
    """
    if not mask:
        return None, None
    whole = WHOLE_FACTION_MASKS.get(mask) or (ERA_WHOLE_FACTION_MASKS.get(mask) if era_whole_faction else None)
    if whole:
        return None, whole
    return mask, _faction_from_mask(mask)


def _questie_race(zq: dict) -> tuple[int | None, str | None]:
    """Questie/QuestieDB race mask -> (race mask to keep, faction it implies). 77/178/255 count as
    whole-faction only with ``race_mask_origin`` "era"; any other or no origin keeps them literal."""
    return _race(zq.get("race_mask"), era_whole_faction=zq.get("race_mask_origin") == "era")


def _is_seasonal(tag: str) -> bool:
    low = _norm_tag(tag)
    return low in SEASONAL_TAGS or "festival" in low


def _unknown_tags(tags) -> list[str]:
    return [t for t in tags if _norm_tag(t) not in HANDLED_KEYS and _norm_tag(t) not in CLASS_BITS
            and not _is_seasonal(t) and not _LEVEL_TAG_RE.match(_norm_tag(t))]


def _unknown_requirements(requirements) -> list[str]:
    def handled(label):
        low = label.lower()
        return label in HANDLED_REQUIREMENTS or (
            low.startswith("finish") and ("one of" in low or "any" in low or "either" in low))
    return [label for label in requirements if not handled(label)]


def _changes(o: dict, z: dict | None, giver: dict | None) -> list[str]:
    """Reasons why outof.games and Questie disagree (empty when not changed)."""
    if z is None:
        return []
    out = []
    if giver is not None and giver.get("id") not in (z.get(STARTER_FIELD.get(giver.get("kind"))) or []):
        out.append("giver")
    a, b = o.get("required_level"), z.get("required_level")
    if a is not None and b is not None and abs(a - b) > 2:
        out.append("required_level")
    mine = set(_ids(o.get("prereq_ids"))) | set(_ids(o.get("prereq_any_ids")))
    theirs = set(_ids(z.get("pre_all"))) | set(_ids(z.get("pre_any")))
    if mine and theirs and mine != theirs:
        out.append("prereq")
    return out


def _chain(qid: int, rows: list[dict]) -> dict | None:
    first = next((r for r in rows if r.get("index") == 1), None)
    own = next((r for r in rows if r.get("quest_id") == qid), None)
    if first is None or first.get("quest_id") is None or own is None or own.get("index") is None:
        return None
    length = max(r["index"] for r in rows if r.get("index") is not None)
    return {"chain_id": first["quest_id"], "index": own["index"], "length": length}


def _items(entries) -> list[dict]:
    return [{"item_id": e["item_id"], "count": e["count"]} for e in entries or []]


def _merge_one(qid: int, o: dict, z: dict | None, rec: dict | None,
               npcs: dict[int, str | None], fill: "_Fill | None" = None,
               names: Names | None = None) -> tuple[dict, dict]:
    """(merged quest, info for exclusion and report) for one outof.games quest. names: the QuestieDB
    names the objectives are built with (``Names.from_questiedb``; empty without QuestieDB)."""
    prov: dict[str, str] = {}
    info = {"race_unclear": False, "class_unclear": False, "faction_from_questie": False,
            "faction_from_giver": False, "faction_conflict": False, "giver_faction_unknown": False,
            "unknown_race": [], "unknown_class": []}
    zq = z or {}
    requirements = o.get("requirements") or {}
    tags = o.get("tags") or []

    def src(field, value, source):
        if value is not None:
            prov[field] = source
        return value

    # giver: recorder sighting > outof.games
    rec_giver = (rec or {}).get("giver")
    if rec_giver:
        giver = src("giver", {"kind": "npc", "id": rec_giver.get("npc"), "map_id": rec_giver.get("map_id"),
                              "x": rec_giver.get("x"), "y": rec_giver.get("y")}, "recorder")
    else:
        giver = src("giver", _place(o.get("giver")), "outofgames")

    changes = _changes(o, z, giver)
    changed = bool(changes)

    # race / class: explicit oog Requirements row > Questie mask (0 == None == any). Race masks keep
    # their Forever (Skyborne) bits; only a whole-faction mask becomes "no race mask" (see _race).
    masks = {}
    for field, labels, table, key in (("race_mask", ("Race", "Races"), RACE_BITS, "race"),
                                      ("class_mask", ("Class", "Classes"), CLASS_BITS, "class")):
        text = _row(requirements, *labels)
        if text is not None:
            mask, unknown = _parse_names(text, table)
            info[f"unknown_{key}"] = unknown
            info[f"{key}_unclear"] = mask is None
            if field == "race_mask":
                # the faction the race restriction implies (before a whole-faction mask is dropped)
                mask, mask_faction = _race(mask, era_whole_faction=False)
            masks[field] = src(field, mask, "outofgames")
        elif field == "race_mask":
            mask, mask_faction = _questie_race(zq)
            masks[field] = src(field, mask, "questie")
        else:
            masks[field] = src(field, zq.get(field) or None, "questie")
    if masks["class_mask"] is None and _row(requirements, "Class", "Classes") is None:
        tag_mask = 0
        for t in tags:
            tag_mask |= CLASS_BITS.get(_norm_tag(t), 0)
        masks["class_mask"] = src("class_mask", tag_mask or None, "tag")

    # faction: oog > Questie race mask; then narrowed or contradicted by a one-faction NPC giver
    faction = src("faction", o.get("faction"), "outofgames")
    if faction is None and _row(requirements, "Race", "Races") is not None and mask_faction in SINGLE_FACTIONS:
        faction = src("faction", mask_faction, "outofgames")   # the oog Race row names one faction's races
    if faction is None:
        faction = src("faction", _questie_race(zq)[1], "questie")
        info["faction_from_questie"] = faction is not None

    # giver without coordinates: QuestieDB Forever may supply one (fill only; see _questiedb_giver),
    # never for a quest QuestieDB disagrees on (changed in Forever)
    info["giver_fill"] = info["giver_fill_why"] = None
    if fill is not None and not rec_giver and not _has_coords(giver):
        if changed:
            info["giver_fill"] = "skipped-changed"
        else:
            filled, info["giver_fill"], info["giver_fill_why"] = _questiedb_giver(o.get("giver"), z, faction, fill)
            if filled is not None:
                giver = src("giver", filled, "questiedb")
    npc_giver = bool(giver) and giver.get("kind") == "npc"
    giver_faction = npcs.get(giver["id"]) if npc_giver else None
    giver_conflict = False
    if giver_faction == CONFLICT:
        giver_conflict = True
    elif giver_faction in SINGLE_FACTIONS:
        if faction == "Both":
            faction = src("faction", giver_faction, "giver")
            info["faction_from_giver"] = True
        elif faction in SINGLE_FACTIONS and faction != giver_faction:
            giver_conflict = True
    mask_conflict = faction is not None and mask_faction in SINGLE_FACTIONS and faction != mask_faction
    info["faction_conflict"] = giver_conflict or mask_conflict
    # a "Both" quest from an NPC of unknown faction may really be one-faction only
    info["giver_faction_unknown"] = faction == "Both" and npc_giver and giver_faction is None

    # levels: recorder > oog game > Questie (unchanged quests, > 0) > oog estimate
    questie_level = zq.get("quest_level")
    if rec and rec.get("level") is not None:
        quest_level, level_source = src("quest_level", rec["level"], "recorder"), "recorder"
    elif o.get("quest_level") is not None:
        quest_level, level_source = src("quest_level", o["quest_level"], "outofgames"), "game"
    elif not changed and questie_level is not None and questie_level > 0:
        quest_level, level_source = src("quest_level", questie_level, "questie"), "game"
    elif o.get("reward_level_estimate") is not None:
        quest_level, level_source = src("quest_level", o["reward_level_estimate"], "outofgames"), "estimate"
    else:
        quest_level, level_source = None, None
    if o.get("required_level") is not None:
        required_level = src("required_level", o["required_level"], "outofgames")
    elif not changed:
        required_level = src("required_level", zq.get("required_level"), "questie")
    else:
        required_level = None   # Questie's value is not trusted for a changed quest -> no-data

    # prerequisites: oog when it lists any, else Questie's
    if o.get("prereq_ids") or o.get("prereq_any_ids"):
        prereq = {"all": _ids(o.get("prereq_ids")), "any": _ids(o.get("prereq_any_ids"))}
        prov["prereq"] = "outofgames"
    else:
        prereq = {"all": _ids(zq.get("pre_all")), "any": _ids(zq.get("pre_any"))}
        if prereq["all"] or prereq["any"]:
            prov["prereq"] = "questie"

    # QuestieDB availability gates (see the module docstring): never dropped, only narrowing
    start = zq.get("available_starting_with")
    if start and abs(start) not in prereq["all"]:
        prereq["all"].append(abs(start))
        prov["prereq_gate"] = "questie"
    exclusive_to = list(zq["exclusive_to"]) if zq.get("exclusive_to") else None
    after = [abs(v) for v in (zq.get("available_until_completed"), zq.get("disabled_by_quest")) if v]
    if after:
        prov["unavailable_after"] = "questie"
    oog_after = [i for i in o.get("not_available_after_ids") or [] if i not in (exclusive_to or [])]
    if oog_after:
        prov["unavailable_after"] = "outofgames" if not after else "outofgames+questie"
    unavailable_after = [i for i in dict.fromkeys(after + oog_after) if i != qid] or None

    # objectives (field 26) and the objective index of each point (field 13): QuestieDB rows, else
    # the outof.games point names; see pipeline.objectives
    raw_points = o.get("objective_points") or []
    rows = zq.get("objectives")
    rows = rows_from_ids(zq) if rows is None else rows
    turn_in = _place(o.get("turn_in"))
    maps = {p.get("map_id") for p in [*raw_points, giver or {}, turn_in or {}] if p.get("map_id") is not None}
    objectives, indices = build_objectives(rows, raw_points, o.get("objective_text"), names or Names(), maps)
    if objectives:
        prov["objectives"] = "questiedb" if rows else "outofgames"
    points = [{"map_id": p.get("map_id"), "x": p.get("x"), "y": p.get("y"), "objective": index}
              for p, index in zip(raw_points, indices)]
    if points:
        prov["objective_points"] = "outofgames"

    # items: Questie only; a required item's count is its item objective's (None when the text does not say)
    item_counts: dict = {}
    for ob in objectives:
        if ob["kind"] == "item" and ob["id"] is not None:
            item_counts.setdefault(ob["id"], ob["count"])
    items = {"provided": [zq["source_item_id"]] if zq.get("source_item_id") else [],
             "required": [{"item_id": i, "count": item_counts.get(i)} for i in zq.get("objective_item_ids") or []]}
    if items["provided"] or items["required"]:
        prov["items"] = "questie"

    # XP: outof.games > QuestieDB (only when the agreement check passed and the levels match)
    xp, xp_source, xp_provenance = o.get("xp"), "game", "outofgames"
    info["xp_level_mismatch"] = False
    if xp is None:
        xp_source = None
        questie_xp = fill.xp.get(qid) if fill is not None and fill.use_xp else None
        if questie_xp is not None:
            if questie_xp[0] == quest_level:
                xp, xp_source, xp_provenance = questie_xp[1], "questiedb", "questiedb"
            else:
                info["xp_level_mismatch"] = True

    rw = o.get("rewards") or {}
    other = rw.get("other") or []
    rewards = {"choice": _items(rw.get("choice")), "fixed": _items(rw.get("fixed")) + _items(other),
               "money": o.get("money_copper"), "rep": [dict(r) for r in rw.get("rep") or []],
               "spell_id": None}
    if rewards["choice"] or rewards["fixed"] or rewards["money"] or rewards["rep"]:
        prov["rewards"] = "outofgames"
    info["rewards_other"] = len(other)

    # flags
    oog_repeatable, questie_repeatable = bool(o.get("repeatable")), bool(zq.get("repeatable"))
    prov["repeatable"] = "questie" if questie_repeatable and not oog_repeatable else "outofgames"
    dungeon = "dungeon" in _tag_keys(tags)
    prov["elite"] = prov["dungeon_quest"] = "outofgames"
    group_size = src("group_size", 5 if dungeon else None, "outofgames")

    class_mask = masks["class_mask"]
    # new in Forever: absent from QuestieDB, or created there by a Forever layer (not Era data)
    new = z is None or bool(z.get("new_in_forever"))
    chain = _chain(qid, o.get("chain") or [])
    merged = {
        "id": qid,
        "name": src("name", o.get("name"), "outofgames"),
        "faction": faction,
        "race_mask": masks["race_mask"],
        "class_mask": class_mask,
        "required_level": required_level,
        "quest_level": quest_level,
        "level_source": level_source,
        "zone_map_id": giver.get("map_id") if giver else None,
        "elite": bool(o.get("elite")),
        "class_quest": _class_quest(class_mask),
        "new_in_forever": new,
        "unverified": new and rec is None,
        "repeatable": oog_repeatable or questie_repeatable,
        "dungeon_quest": dungeon,
        "group_size": group_size,
        "giver": giver,
        "turn_in": src("turn_in", turn_in, "outofgames"),
        "objective_points": points,
        "objective_text": src("objective_text", o.get("objective_text"), "outofgames"),
        "items": items,
        "rewards": rewards,
        "xp": src("xp", xp, xp_provenance),
        "xp_source": xp_source,
        "prereq": prereq,
        "exclusive_to": src("exclusive_to", exclusive_to, "questie"),
        "unavailable_after": unavailable_after,
        "objectives": objectives,
        "breadcrumb_of": src("breadcrumb_of", zq.get("breadcrumb_of"), "questie"),
        "chain": src("chain", chain, "outofgames"),
        "dungeon_key": None,
        "changed_in_forever": changed,
        "required_max_level": src("required_max_level", zq.get("required_max_level"), "questie"),
        "recorded_xp": src("recorded_xp", dict(rec["xp"]) if rec and rec.get("xp") else None, "recorder"),
        "source_url": o.get("source_url"),
        "provenance": prov,
    }
    info["changes"] = changes
    info["unknown_tags"] = _unknown_tags(tags)
    info["unknown_requirements"] = _unknown_requirements(requirements)
    return merged, info


def _exclusion(o: dict, zs: list, m: dict, info: dict, live_maps, hidden_ids=frozenset(),
               problems=None) -> str | None:
    """First exclusion reason for a merged quest, or None. zs: the QuestieDB quest as stored and, for a
    quest of one faction with Dynamic Corrections, as that faction sees it; a gate in either excludes."""
    tags = _tag_keys(o.get("tags") or [])
    requirements = o.get("requirements") or {}
    problem = (problems or {}).get(m["id"])

    def has(field):
        return any((z or {}).get(field) for z in zs)

    checks = {
        "test-name": lambda: bool(m["name"]) and TEST_NAME_RE.search(m["name"]) is not None,
        "questie-hidden": lambda: has("hidden") or m["id"] in hidden_ids,
        "correction-skipped": lambda: problem == "correction-skipped",
        "correction-unclear": lambda: problem == "correction-unclear",
        "questie-giver-ambiguous": lambda: info["giver_fill"] == "ambiguous",
        "no-giver-coords": lambda: not _has_coords(m["giver"]),
        "no-faction": lambda: m["faction"] is None,
        "faction-conflict": lambda: info["faction_conflict"],
        "giver-faction-unknown": lambda: info["giver_faction_unknown"],
        "faction-fix-unclear": lambda: info.get("faction_fix_unclear", False),
        "no-data": lambda: m["quest_level"] is None or m["required_level"] is None,
        "prereq-unclear": lambda: "prereq-count-mismatch" in (o.get("warnings") or []),
        "race-unclear": lambda: info["race_unclear"],
        "class-unclear": lambda: info["class_unclear"],
        "exclusive-unclear": lambda: NOT_AVAILABLE_AFTER in requirements and not o.get("not_available_after_ids"),
        "gate-unclear": lambda: m["changed_in_forever"] and any(has(g) for g in GATE_FIELDS),
        "parent-quest": lambda: has("parent_quest"),
        "needs-skill": lambda: has("required_skill") or has("required_specialization") or bool(tags & PROFESSION_KEYS),
        "needs-rep": lambda: has("required_min_rep") or has("required_max_rep") or "Reputation" in requirements,
        "needs-spell": lambda: has("required_spell"),
        "needs-rank": lambda: has("required_ranks"),
        "raid": lambda: bool(tags & RAID_KEYS),
        "pvp": lambda: "pvp" in tags,
        "seasonal": lambda: any(_is_seasonal(t) for t in tags),
        "event": lambda: bool(tags & EVENT_KEYS),
        "zone-not-live": lambda: live_maps is not None and m["giver"]["map_id"] not in live_maps,
    }
    return next((reason for reason in EXCLUSION_ORDER if checks[reason]()), None)


# Exclusion reasons whose quest has no faction the sources agree on: its stub's faction is None
# (unclear), so the addon never blocks a chain on a faction that may be wrong (R6).
UNCLEAR_FACTION_REASONS = frozenset({"faction-conflict", "faction-fix-unclear"})


def _stubs(quests: dict, excluded_merged: dict, excluded: dict) -> dict[int, dict]:
    """Stubs for excluded quests that kept quests need as prerequisites, transitively.

    Walk prereq.all and prereq.any of every kept quest; an id that is an excluded quest with a merged
    record becomes a stub and its own prerequisites are walked too. Kept ids stop the walk (they are
    in ``quests``); ids with no merged record get no stub. A stub carries the merged name, levels,
    masks, prereq and giver place (the addon's "how it starts"), the exclusion reason, and a faction
    that is None when the sources leave it unclear (UNCLEAR_FACTION_REASONS) or it is missing.
    """
    stubs: dict[int, dict] = {}
    todo = [pid for q in quests.values() for pid in _prereq_ids(q)]
    while todo:
        pid = todo.pop()
        if pid in stubs or pid in quests or pid not in excluded_merged:
            continue
        m, reason = excluded_merged[pid], excluded[pid]
        stubs[pid] = {
            "name": m.get("name"), "level": m.get("quest_level"), "required_level": m.get("required_level"),
            "faction": None if reason in UNCLEAR_FACTION_REASONS else m.get("faction"),
            "race_mask": m.get("race_mask"), "class_mask": m.get("class_mask"),
            "prereq": m.get("prereq"), "giver": m.get("giver"), "start_name": None, "reason": reason,
        }
        todo.extend(_prereq_ids(m))
    return dict(sorted(stubs.items()))


def _prereq_ids(q: dict) -> list[int]:
    pre = q.get("prereq") or {}
    return [*(pre.get("all") or []), *(pre.get("any") or [])]


def _objective_counts(quests: dict) -> dict:
    """Over the kept quests: quests with objectives, objectives, objectives with a count, objective
    points, points with an objective index, required items and required items with a count."""
    obs = [ob for q in quests.values() for ob in q.get("objectives") or []]
    pts = [p for q in quests.values() for p in q.get("objective_points") or []]
    req = [r for q in quests.values() for r in (q.get("items") or {}).get("required") or []]
    return {"quests": sum(1 for q in quests.values() if q.get("objectives")), "objectives": len(obs),
            "counts": sum(1 for ob in obs if ob["count"] is not None), "points": len(pts),
            "points_indexed": sum(1 for p in pts if p.get("objective") is not None),
            "required_items": len(req), "required_counts": sum(1 for r in req if r.get("count") is not None)}


def merge(oog: dict[int, dict], questie: dict[int, dict], live_maps: set[int] | None,
          recorder: dict[int, dict] | None = None, without: set[str] = frozenset(),
          npcs: dict[int, str | None] | None = None, questiedb=None,
          trusted_maps=None) -> tuple[dict[int, dict], dict]:
    """Merge the sources; return (kept quests by id, report).

    live_maps: uiMapIDs of live zones, or None for provisional mode (zone filter off).
    without: sources to build without ("questie", "recorder"; "openmap" is accepted and does not
             affect quests).
    npcs: {npc_id: faction} from giver_factions(), for the giver-faction check. An NPC absent
          from it (or None) has an unknown faction, so None excludes every "Both" quest
          with an NPC giver: always pass the map.
    questiedb: pipeline.questiedb.QuestieDBData (its NPCs, spawns and XP) for the giver and XP
          fill, plus its ``hidden_ids`` and ``quest_problems`` for the exclusions; trusted_maps: the
          uiMapIDs spawn_check() trusts (no others are used). Both are ignored when building without
          questie.
    report = {"conflicts": {id: [reasons]}, "excluded": {id: reason}, "counts": {...},
              "live_filter": "on" | "off", "unknown_names": {"race": {...}, "class": {...}},
              "unknown_tags": {tag: n}, "unknown_requirements": {label: n}, "warnings": [...]},
    "next_quest_in_chain": {...} (reported only), plus "questiedb": {"giver_fill": {...},
    "xp_check": xp_check(), "xp_filled": n, "xp_level_mismatch": n} when questiedb is used, and
    "stubs": {id: stub} (see _stubs; the build pops it before writing report.json).
    Conflicts cover every changed quest, excluded or not.
    """
    unknown_sources = set(without) - REMOVABLE_SOURCES
    if unknown_sources:
        raise ValueError(f"cannot build without {sorted(unknown_sources)}; "
                         f"removable sources: {sorted(REMOVABLE_SOURCES)}")
    warnings = []
    if "questie" in without:
        questie = {}
        warnings.append(QUESTIE_DISABLED_WARNING)
    questie = questie or {}
    recorder = {} if "recorder" in without else (recorder or {})
    npcs = npcs or {}
    fill = xp_report = None
    hidden_ids, problems = frozenset(), {}
    names = Names()
    if questiedb is not None and "questie" not in without:
        names = Names.from_questiedb(questiedb)
        xp_report = xp_check(oog, questiedb.xp or {})
        fill = _Fill(questiedb, trusted_maps, xp_report["fill"])
        hidden_ids = frozenset(getattr(questiedb, "hidden_ids", None) or ())
        problems = dict(getattr(questiedb, "quest_problems", None) or {})
    stale = sum(1 for o in oog.values()
                if NOT_AVAILABLE_AFTER in (o.get("requirements") or {}) and "not_available_after_ids" not in o)
    if stale:
        warnings.append(f"outof.games: {stale} quest JSON file(s) with a 'Not available after' row predate its quest "
                        "links and count as exclusive-unclear (re-parse with `crawl --reparse`)")
    fill_status: Counter = Counter()
    ambiguous_why: Counter = Counter()
    no_usable_why: Counter = Counter()
    faction_fixes_applied = 0

    quests, conflicts, excluded = {}, {}, {}
    excluded_merged: dict[int, dict] = {}
    by_reason: Counter = Counter()
    unknown_names = {"race": Counter(), "class": Counter()}
    unknown_tags, unknown_requirements = Counter(), Counter()
    totals, kept = Counter(), Counter()
    for qid in sorted(oog):
        o, z = oog[qid], questie.get(qid)
        m, info = _merge_one(qid, o, z, recorder.get(qid), npcs, fill, names)
        views = [z]
        fixes = (z or {}).get("faction_fixes")
        if fixes:
            # Dynamic Corrections that differ by faction: use the quest's own faction's values
            faction = m["faction"]
            if faction in SINGLE_FACTIONS and fixes.get(faction) is not None:
                views.append({**z, **fixes[faction]})
                m, info = _merge_one(qid, o, views[-1], recorder.get(qid), npcs, fill, names)
                info["faction_fix_unclear"] = m["faction"] != faction
                faction_fixes_applied += m["faction"] == faction
            else:
                info["faction_fix_unclear"] = True
        fill_status[info["giver_fill"]] += 1
        if info["giver_fill_why"]:
            (ambiguous_why if info["giver_fill"] == "ambiguous" else no_usable_why)[info["giver_fill_why"]] += 1
        fill_status["xp-level-mismatch"] += info["xp_level_mismatch"]
        if info["changes"]:
            conflicts[qid] = info["changes"]
        unknown_names["race"].update(info["unknown_race"])
        unknown_names["class"].update(info["unknown_class"])
        unknown_tags.update(info["unknown_tags"])
        unknown_requirements.update(info["unknown_requirements"])
        tally = {"changed_in_forever": int(m["changed_in_forever"]), "new_in_forever": int(m["new_in_forever"]),
                 "unverified": int(m["unverified"]), "rewards_other": info["rewards_other"],
                 "faction_from_questie": int(info["faction_from_questie"]),
                 "faction_from_giver": int(info["faction_from_giver"]),
                 "giver_from_questiedb": int(m["provenance"].get("giver") == "questiedb"),
                 "xp_from_questiedb": int(m["xp_source"] == "questiedb"),
                 "skyborne_race_mask": int(bool((m["race_mask"] or 0) & SKYBORNE_BITS))}
        totals.update(tally)
        reason = _exclusion(o, views, m, info, live_maps, hidden_ids, problems)
        if reason is not None:
            excluded[qid] = reason
            excluded_merged[qid] = m
            by_reason[reason] += 1
            continue
        kept.update(tally)
        quests[qid] = m

    # one length per chain: the longest any kept member's page reports
    lengths: dict[int, int] = {}
    for q in quests.values():
        if q["chain"]:
            cid = q["chain"]["chain_id"]
            lengths[cid] = max(lengths.get(cid, 0), q["chain"]["length"])
    for q in quests.values():
        if q["chain"]:
            q["chain"]["length"] = lengths[q["chain"]["chain_id"]]

    # a breadcrumb whose target requires it (prereq.all) is a real prerequisite, not a lead-in
    breadcrumb_dropped, kept_any = [], 0
    for qid in sorted(quests):
        t = quests[qid].get("breadcrumb_of")
        target = quests.get(t) if t else None
        if target is not None:
            pre = target.get("prereq") or {}
            if qid in (pre.get("all") or []):
                quests[qid]["breadcrumb_of"] = None
                quests[qid].get("provenance", {}).pop("breadcrumb_of", None)
                breadcrumb_dropped.append({"quest": qid, "target": t})
            elif qid in (pre.get("any") or []):
                kept_any += 1

    # QuestieDB nextQuestInChain (not used): kept quests whose successor nothing in our data ties to them
    next_report = {"kept_with_next": 0, "next_not_kept": 0, "next_kept_without_prereq": 0, "examples": []}
    for qid in sorted(quests):
        nxt = abs((questie.get(qid) or {}).get("next_quest_in_chain") or 0)
        if not nxt:
            continue
        next_report["kept_with_next"] += 1
        target = quests.get(nxt)
        pre = (target or {}).get("prereq") or {}
        why = ("next_not_kept" if target is None else
               None if qid in (pre.get("all") or []) or qid in (pre.get("any") or []) else "next_kept_without_prereq")
        if why:
            next_report[why] += 1
            if len(next_report["examples"]) < 20:
                next_report["examples"].append({"quest": qid, "next": nxt, "why": why})

    counts = {
        "breadcrumb_dropped_required": len(breadcrumb_dropped),
        "gates": {"prereq_added": sum(1 for q in quests.values() if "prereq_gate" in q["provenance"]),
                  "unavailable_after": sum(1 for q in quests.values() if q.get("unavailable_after"))},
        "breadcrumb_kept_any": kept_any,
        "oog_quests": len(oog),
        "questie_quests": len(questie),
        "questie_only": sum(1 for qid in questie if qid not in oog),
        "faction_fixes_applied": faction_fixes_applied,
        "recorder_quests": len(recorder),
        "kept": len(quests),
        "excluded": len(excluded),
        "excluded_by_reason": {r: by_reason[r] for r in EXCLUSION_ORDER if by_reason[r]},
        **{k: totals[k] for k in _FLAG_KEYS},
        "among_kept": {k: kept[k] for k in _FLAG_KEYS},
        "objectives": _objective_counts(quests),
    }
    report = {
        "conflicts": conflicts,
        "excluded": excluded,
        "counts": counts,
        "breadcrumb_dropped_required": breadcrumb_dropped,
        "next_quest_in_chain": next_report,
        "live_filter": "off" if live_maps is None else "on",
        "unknown_names": {k: dict(v) for k, v in unknown_names.items()},
        "unknown_tags": dict(unknown_tags.most_common()),
        "unknown_requirements": dict(unknown_requirements.most_common()),
        "warnings": warnings,
    }
    if fill is not None:
        report["questiedb"] = {
            "giver_fill": {"filled": totals["giver_from_questiedb"], "filled_kept": kept["giver_from_questiedb"],
                           "ambiguous": fill_status["ambiguous"], "ambiguous_why": dict(ambiguous_why.most_common()),
                           "no_usable": fill_status["no-usable"], "no_usable_why": dict(no_usable_why.most_common()),
                           "no_candidates": fill_status["no-candidates"],
                           "skipped_changed": fill_status["skipped-changed"],
                           "trusted_maps": len(fill.trusted)},
            "xp_check": xp_report,
            "xp_filled": totals["xp_from_questiedb"],
            "xp_level_mismatch": fill_status["xp-level-mismatch"],
        }
    report["stubs"] = _stubs(quests, excluded_merged, excluded)
    return quests, report
