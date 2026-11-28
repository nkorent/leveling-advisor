"""QuestieDB Forever loader (Task 8c): layers, table operations, dynamic factions, blacklist,
spawns, quest XP and the sandbox. Fixtures in fixtures/questiedb/ are hand-written in the shapes
of QuestieDB's files; they are not copies."""
import json
import shutil
from pathlib import Path

import pytest

from pipeline.questiedb import QuestieDBData, load_questiedb

FX = Path(__file__).parent / "fixtures" / "questiedb"
ROOT = FX / "root"
BLACKLIST = FX / "QuestieQuestBlacklist.lua"
REPO = Path(__file__).resolve().parents[2]
REAL_ROOT = REPO / "data" / "vendor" / "QuestieDB"
REAL_BLACKLIST = REPO / "data" / "vendor" / "Questie-master" / "Database" / "Corrections" / "QuestieQuestBlacklist.lua"
REAL_OOG_NPCS = REPO / "data" / "build" / "outofgames" / "npcs"
SKYBORNE_ALLIANCE = 2 ** 32


@pytest.fixture(scope="module")
def qdb() -> QuestieDBData:
    return load_questiedb(ROOT, BLACKLIST)


def tmp_root(tmp_path):
    """A writable copy of the fixture root."""
    dst = tmp_path / "root"
    shutil.copytree(ROOT, dst)
    return dst


# ---------------------------------------------------------------- layers

def test_layers_apply_in_order(qdb):
    """Each layer appends its own id to preQuestSingle, so the list shows the order:
    raw 1, legacy 2, generated 3, traces 4, relation traces 5, authored 6."""
    q = qdb.quests[100]
    assert q["pre_any"] == [1, 2, 3, 4, 5, 6]
    assert q["quest_level"] == 13          # each layer replaced the previous one; authored is last
    assert list(qdb.stats["layers"]["Quest"]) == ["legacy", "generated", "traces", "relation-traces", "authored"]
    assert list(qdb.stats["layers"]["Npc"]) == ["legacy", "generated", "traces", "authored"]
    assert qdb.stats["layers"]["Quest"]["traces"]["rows"] == 3
    assert qdb.stats["raw"] == {"Quest": 19, "Npc": 7, "Object": 1, "Item": 3}
    assert qdb.stats["final"] == {"Quest": 20, "Npc": 9, "Object": 2, "Item": 4}


def test_add_remove_operations(qdb):
    q = qdb.quests[200]
    # {nil, {424005}} adds to the object starter group only; the NPC group then loses 11
    assert q["starter_npcs"] == [10] and q["starter_objects"] == [424005] and q["starter_items"] is None
    assert q["finisher_npcs"] == [10]               # finishedBy_add {nil, {630696}} leaves group 1 alone
    assert q["exclusive_to"] == [300, 301]          # {299, 300} - {299} + {301}
    assert q["required_min_rep"] == [72, 3000]      # atomic add onto an absent pair
    assert q["objective_creature_ids"] == [1001] and q["objective_item_ids"] == [2001]
    assert q["repeatable"] is True
    npc10 = qdb.npc_spawns[10]                      # replaced, then {52, 52} added, then {51, 51} removed
    assert npc10 == [{"map_id": 1453, "x": 52.0, "y": 52.0}]
    assert qdb.object_spawns[5000] == [{"map_id": 1429, "x": 40.0, "y": 60.0},
                                       {"map_id": 1429, "x": 40.5, "y": 60.5}]


def test_add_of_a_present_value_keeps_one_copy(tmp_path):
    """`_add` appends only absent values: 3 is already there (generated layer), 4 comes twice."""
    root = tmp_root(tmp_path)
    traces = root / "src/corrections/Forever/traces/foreverQuestTraces.lua"
    text = traces.read_text(encoding="utf-8")
    assert "[questKeys.preQuestSingle_add] = {4}," in text
    traces.write_text(text.replace("[questKeys.preQuestSingle_add] = {4},",
                                   "[questKeys.preQuestSingle_add] = {3, 4, 4},"), encoding="utf-8")
    q = load_questiedb(root, BLACKLIST).quests[100]
    assert q["pre_any"] == [1, 2, 3, 4, 5, 6]


def test_operate_list_add_is_a_set_union_in_operand_order():
    from pipeline.questiedb import _operate
    assert _operate("idarray", [1, 2], [2, 3, 3, 1], None) == [1, 2, 3]
    assert _operate("idarray", None, [5, 5], None) == [5]
    # grouped lists (starter groups): the same rule inside each group, other groups kept
    assert _operate("questgivers", {1: [10], 2: [20]}, {1: [10, 11, 11]}, None) == {1: [10, 11], 2: [20]}


def test_invalid_operations_are_rejected_and_listed(qdb):
    q = qdb.quests[201]
    assert q["pre_all"] is None                     # replacement and operation on one field
    assert q["exclusive_to"] is None                # same value added and removed
    assert q["required_skill"] == [164, 50]         # a different atomic pair already exists
    assert q["required_level"] == 11                # the row's valid field still applies
    rejected = {(dt, i, f) for dt, i, f, _layer, _why in qdb.stats["rejected"]}
    assert {("Quest", 201, "preQuestGroup"), ("Quest", 201, "exclusiveTo"),
            ("Quest", 201, "requiredSkill")} <= rejected


def test_named_row_creates_and_nameless_row_is_skipped(qdb):
    q = qdb.quests[300]
    assert q["name"] == "New Forever Quest" and q["starter_npcs"] == [20] and q["quest_level"] == 7
    assert q["race_mask"] == 8 + SKYBORNE_ALLIANCE
    assert ("Quest", 300, "generated") in qdb.stats["created"]
    assert 301 not in qdb.quests and ("Quest", 301, "traces") in qdb.stats["skipped"]
    assert 21 not in qdb.npcs and ("Npc", 21, "generated") in qdb.stats["skipped"]
    assert qdb.npcs[20] == {"name": "Forever Giver", "friendly": "A", "level": 12, "faction_known": True}
    assert qdb.objects[424005] == {"name": "Forever Crate"}
    assert qdb.stats["layers"]["Quest"]["generated"]["created"] == 1


def test_unresolved_value_is_skipped_and_listed(qdb):
    q = qdb.quests[600]
    assert q["source_item_id"] == 5555 and q["required_level"] == 11
    assert ("Quest", 600, "sourceItemId", "legacy") in qdb.stats["unresolved"]


def test_dynamic_faction_union(qdb):
    q = qdb.quests[400]
    assert q["starter_npcs"] == [30, 31]            # Alliance {30}, Horde {31}: union, listed
    assert ("Quest", 400, "startedBy") in qdb.stats["faction_conflicts"]
    assert q["required_level"] == 12                # both factions agree: applied
    # Horde only: the base keeps the static value, the per-faction values go to the merge
    assert q["pre_any"] is None
    assert q["faction_fixes"] == {"Alliance": {"pre_any": None}, "Horde": {"pre_any": [401]}}
    assert ("Quest", 400, "preQuestSingle") in qdb.stats["faction_dependent"]
    assert ("Quest", 400, "preQuestSingle") not in qdb.stats["dynamic_not_applied"]
    assert qdb.quests[402]["faction_fixes"] is None
    assert qdb.quests[402]["starter_npcs"] == [42]  # LoadDynamic overrides the legacy faction fixes
    assert ("Quest", 402, "startedBy") not in qdb.stats["faction_conflicts"]
    assert 403 not in qdb.quests
    assert qdb.npc_spawns[13] == [{"map_id": 1429, "x": 40.0, "y": 40.0}]
    assert ("Npc", 13, "spawns") in qdb.stats["dynamic_not_applied"]
    assert qdb.objects[5000]["name"] == "Wanted Poster (both factions)"


def test_blacklist_forever_flags(qdb):
    hidden = {qid for qid in range(500, 506) if qdb.quests[qid]["hidden"]}
    assert hidden == {500, 503, 505}                # IsForever, true, Era-or-Wotlk (Current = Era)
    assert qdb.stats["hide_on_map"] == 1            # 502
    assert qdb.stats["hidden"] == 3


def test_spawn_area_to_uimap(qdb):
    # area 12 -> 1429; (-1, -1) and (120, 50) dropped; the phase of (30.5, 40.5, 2) dropped;
    # area 2257 is overridden to 0 and area 4242 has no mapping: both dropped
    assert qdb.npc_spawns[11] == [{"map_id": 1429, "x": 10.0, "y": 10.0},
                                  {"map_id": 1429, "x": 30.5, "y": 40.5}]
    assert qdb.npc_spawns[12] == [{"map_id": 9999, "x": 60.0, "y": 60.0}]   # override wins
    assert qdb.stats["spawns"]["Npc"] == {"kept": 9, "unmapped": 2, "bad_coords": 2}
    assert 99 not in qdb.npc_spawns


def test_npc_shapes(qdb):
    assert qdb.npcs[10] == {"name": "Starter Ten", "friendly": "A", "level": 20, "faction_known": True}
    assert qdb.npcs[12]["friendly"] == "AH"         # "HA" normalised
    # raw Era data: nil means hostile to both (a known faction)
    assert qdb.npcs[99] == {"name": "Hostile Ninety-Nine", "friendly": None, "level": 10, "faction_known": True}
    # created by a Forever layer that never states friendlyToFaction: unknown, not hostile
    assert qdb.npcs[22] == {"name": "Unknown Side", "friendly": None, "level": 8, "faction_known": False}
    assert len(qdb.npcs) == 9 and len(qdb.objects) == 2


def test_new_in_forever_marks_quests_created_by_forever_layers(qdb):
    assert qdb.quests[300]["new_in_forever"] is True        # created by the generated delta-base
    assert qdb.quests[100]["new_in_forever"] is False       # Era raw data
    assert all(q["new_in_forever"] is False for qid, q in qdb.quests.items() if qid != 300)


def test_item_start_and_repeatable_raw_fields(qdb):
    q = qdb.quests[700]
    assert q["starter_items"] == [9000] and q["starter_npcs"] is None and q["repeatable"] is True


def test_items_read_through_every_layer(qdb):
    """Task 8: Item name, npcDrops and objectDrops, through the same layers as the other types."""
    assert list(qdb.stats["layers"]["Item"]) == ["legacy", "generated", "traces", "authored"]
    # raw {99, 10}, legacy adds 11, traces remove 10
    assert qdb.items[2001] == {"name": "Gnoll Paw", "npc_drops": [99, 11], "object_drops": []}
    # created by the generated layer (it carries a name), renamed by the authored one
    assert qdb.items[2002] == {"name": "Forever Charm of Testing", "npc_drops": [12], "object_drops": [5000]}
    assert ("Item", 2002, "generated") in qdb.stats["created"]
    assert qdb.items[9000] == {"name": "Starting Letter", "npc_drops": [], "object_drops": []}   # {} clears
    assert 2003 not in qdb.items and ("Item", 2003, "authored") in qdb.stats["skipped"]
    # Alliance and Horde give Faction Spice different drops: the static value stays
    assert qdb.items[2004]["npc_drops"] == [13]
    assert ("Item", 2004, "npcDrops") in qdb.stats["dynamic_not_applied"]
    assert 2003 not in qdb.quest_problems                  # an item row never makes a quest problem


def test_quest_objective_rows(qdb):
    """Task 8: every objective row with its group, id and own text (field 26 is built from them)."""
    assert qdb.quests[200]["objectives"] == [{"group": 1, "id": 1001, "text": "Slay the thing"},
                                             {"group": 3, "id": 2001, "text": None}]
    assert qdb.quests[100]["objectives"] == []


def test_data_key_table_may_lack_only_trailing_meta_keys(tmp_path):
    """The real item data predates the meta's last key (teachesSpell): allowed. A key missing in the
    middle (or a different index) still fails."""
    root = tmp_root(tmp_path)
    data = root / "data/Forever/foreverItemDB.lua"
    text = data.read_text(encoding="utf-8")
    assert "['flags'] = 7" in text
    data.write_text(text.replace("    ['flags'] = 7, -- int or nil\n", ""), encoding="utf-8")
    with pytest.raises(ValueError, match="itemKeys"):
        load_questiedb(root, BLACKLIST)


def test_quest_xp_traces_override_classic(qdb):
    assert qdb.xp == {100: (8, 400), 200: (10, 520), 300: (12, 700)}


def test_availability_gates_are_read_through_every_layer(qdb):
    """C1: raw parentQuest / availableUntilCompleted, generated availableStartingWith, authored
    requiredRanks / disabledByQuest, legacy requiredSpell; nextQuestInChain is read for the report."""
    q = qdb.quests[800]
    assert (q["parent_quest"], q["available_until_completed"], q["available_starting_with"],
            q["disabled_by_quest"], q["required_ranks"], q["next_quest_in_chain"]) == (338, 1302, 92514, 420,
                                                                                       [[171, 225]], 801)
    assert q["required_spell"] is None
    assert qdb.quests[801]["required_spell"] == 12345
    assert all(qdb.quests[100][f] is None for f in ("parent_quest", "required_spell", "available_until_completed",
                                                    "available_starting_with", "disabled_by_quest", "required_ranks"))


def test_race_mask_origin_is_tracked_per_layer(qdb):
    """8c #3: a mask from the Era raw data or the legacy fixes is "era"; one a Forever layer wrote is
    "forever", even when it is the classic 77."""
    assert (qdb.quests[802]["race_mask"], qdb.quests[802]["race_mask_origin"]) == (77, "era")
    assert (qdb.quests[803]["race_mask"], qdb.quests[803]["race_mask_origin"]) == (77, "forever")
    assert qdb.quests[200]["race_mask_origin"] == "forever"            # raw 77, then the generated layer
    assert not qdb.quests[100]["race_mask"] and qdb.quests[100]["race_mask_origin"] is None   # raw 0: any race
    fixes = qdb.quests[804]["faction_fixes"]                            # authored LoadDynamic, per faction
    assert fixes == {"Alliance": {"race_mask": 77, "race_mask_origin": "forever"},
                     "Horde": {"race_mask": 178, "race_mask_origin": "forever"}}


def test_quest_problems_list_dropped_corrections(qdb):
    """T4 / M2: nameless rows for missing ids are skipped, rejected or unresolved gating values are
    unclear; an unresolved value on a field the merge does not gate on (600's sourceItemId) is not."""
    assert qdb.quest_problems == {201: "correction-unclear", 301: "correction-skipped", 403: "correction-skipped",
                                  805: "correction-unclear"}
    assert qdb.quests[805]["available_until_completed"] is None
    assert qdb.stats["quest_problems"] == {"correction-skipped": 2, "correction-unclear": 2}


def test_hidden_ids_include_blacklisted_ids_questiedb_lacks(qdb):
    """M1: the blacklist hides 99999, which QuestieDB does not have; the merge needs it anyway."""
    assert qdb.hidden_ids == frozenset({500, 503, 505, 99999})
    assert qdb.stats["hidden_not_in_data"] == 1


def test_stats_are_json_serialisable(qdb):
    stats = qdb.stats
    back = json.loads(json.dumps(stats))
    assert set(back) == set(stats)
    assert back["final"] == stats["final"] and back["layers"] == stats["layers"]
    assert back["created"] == [list(row) for row in stats["created"]]   # tuples come back as lists


# ---------------------------------------------------------------- inputs and sandbox

@pytest.mark.parametrize("payload", [
    'os.execute("touch pwned")', 'io.open("pwned", "w")', 'require("os")', 'load("return 1")()',
    'dofile("pwned.lua")', 'loadstring("return 1")'])
def test_questiedb_sandboxed(tmp_path, payload):
    root = tmp_root(tmp_path)
    fixes = root / "src/corrections/Forever/foreverQuestFixes.lua"
    fixes.write_text(payload + "\n" + fixes.read_text(encoding="utf-8"), encoding="utf-8")
    with pytest.raises(ValueError):
        load_questiedb(root, BLACKLIST)
    assert not (tmp_path / "pwned").exists() and not Path("pwned").exists()


def test_raw_data_is_sandboxed(tmp_path):
    root = tmp_root(tmp_path)
    data = root / "data/Forever/foreverQuestDB.lua"
    data.write_text(data.read_text(encoding="utf-8").replace('"Layered Quest"', 'os.execute("touch pwned")'),
                    encoding="utf-8")
    with pytest.raises(ValueError):
        load_questiedb(root, BLACKLIST)


def test_blacklist_is_sandboxed(tmp_path):
    bl = tmp_path / "bl.lua"
    bl.write_text('os.execute("touch pwned")\n' + BLACKLIST.read_text(encoding="utf-8"), encoding="utf-8")
    with pytest.raises(ValueError):
        load_questiedb(ROOT, bl)


def test_keys_checked_against_meta(tmp_path):
    root = tmp_root(tmp_path)
    meta = root / "src/meta/questMeta.lua"
    text = meta.read_text(encoding="utf-8")
    text = text.replace("['questLevel'] = 5", "@").replace("['requiredLevel'] = 4", "['requiredLevel'] = 5")
    meta.write_text(text.replace("@", "['questLevel'] = 4"), encoding="utf-8")     # swapped indices
    with pytest.raises(ValueError, match="questKeys"):
        load_questiedb(root, BLACKLIST)


def test_missing_input_file_raises(tmp_path):
    root = tmp_root(tmp_path)
    (root / "src/corrections/Forever/traces/foreverQuestTraces.lua").unlink()
    with pytest.raises(FileNotFoundError, match="foreverQuestTraces.lua"):
        load_questiedb(root, BLACKLIST)
    with pytest.raises(FileNotFoundError, match="nope.lua"):
        load_questiedb(ROOT, tmp_path / "nope.lua")


# ---------------------------------------------------------------- real data (skipped without the vendor copy)

@pytest.fixture(scope="module")
def real():
    if not REAL_ROOT.is_dir() or not REAL_BLACKLIST.is_file():
        pytest.skip("data/vendor/QuestieDB or the Questie master blacklist is absent")
    return load_questiedb(REAL_ROOT, REAL_BLACKLIST)


def test_real_questiedb_smoke(real):
    for dt, layers in (("Quest", ["legacy", "generated", "traces", "relation-traces", "authored"]),
                       ("Npc", ["legacy", "generated", "traces", "authored"]),
                       ("Object", ["legacy", "generated", "traces", "authored"]),
                       ("Item", ["legacy", "generated", "traces", "authored"])):
        assert list(real.stats["layers"][dt]) == layers
        assert all(real.stats["layers"][dt][layer]["rows"] > 0 for layer in layers), dt
    assert len(real.quests) >= 4000 and len(real.npcs) >= 8000
    assert real.quests[272]["race_mask"] == 8 + SKYBORNE_ALLIANCE     # Night Elf + Skyborne, before conversion
    assert real.stats["rejected"] == []
    assert real.xp and all(len(v) == 2 for v in real.xp.values())
    # Task 8: items with their drop sources (the authored layer removes four Forever wolves from 750)
    assert len(real.items) >= 10000
    assert real.items[750]["name"] == "Tough Wolf Meat" and real.items[750]["npc_drops"]
    assert not {238425, 238426, 238427, 247809} & set(real.items[750]["npc_drops"])
    assert real.items[3910]["name"] == "Snuff"
    assert real.quests[33]["objectives"] == [{"group": 3, "id": 750, "text": None}]
    assert real.quests[587]["objectives"] == [{"group": 3, "id": 3910, "text": None}]


@pytest.mark.skipif(not REAL_OOG_NPCS.is_dir(), reason="no outof.games NPC crawl output")
def test_real_spawn_check_overall_match(real):
    from pipeline.merge import spawn_check
    oog_npcs = {}
    for p in REAL_OOG_NPCS.glob("*.json"):
        n = json.loads(p.read_text(encoding="utf-8"))
        oog_npcs[int(n.get("id") or p.stem)] = n
    check = spawn_check(oog_npcs, real.npc_spawns)
    assert check["overall"]["comparable"] > 100
    assert check["overall"]["rate"] >= 0.8


@pytest.mark.parametrize("old,new", [("fieldCount = 36", "fieldCount = 30"),      # an index above fieldCount
                                     ("[36]='number'", "")])                       # an index without a type
def test_meta_field_count_and_types_checked(tmp_path, old, new):
    root = tmp_root(tmp_path)
    meta = root / "src/meta/questMeta.lua"
    text = meta.read_text(encoding="utf-8")
    assert old in text
    meta.write_text(text.replace(old, new), encoding="utf-8")
    with pytest.raises(ValueError, match="questMeta"):
        load_questiedb(root, BLACKLIST)


REAL_QUESTS_LUA = REPO / "LevelingAdvisor" / "Data" / "Quests.lua"


def _real_quests_lua() -> dict:
    """{id: {position: value}} from the committed Data/Quests.lua (lists as Python lists)."""
    import lupa
    lua = lupa.LuaRuntime(register_eval=False)
    ns = lua.table()
    lua.eval("function(src, ns) return assert(load(src, 'Quests.lua', 't', {}))(nil, ns) end")(
        REAL_QUESTS_LUA.read_text(encoding="utf-8"), ns)

    def py(v):
        if lupa.lua_type(v) == "table":
            return {k: py(x) for k, x in v.items()}
        return v
    return {int(k): py(r) for k, r in ns.Data.quests.items()}


@pytest.mark.skipif(not REAL_QUESTS_LUA.is_file(), reason="no committed Data/Quests.lua")
def test_real_kept_quests_encode_every_availability_gate(real):
    """Final review C1: no kept quest carries a QuestieDB availability gate the data does not encode
    (for its own faction's Dynamic Corrections too)."""
    faction_name = {1: "Alliance", 2: "Horde"}
    unencoded = []
    quests = _real_quests_lua()
    for qid, r in quests.items():
        z = real.quests.get(qid)
        if z is None:
            continue
        fixes = (z.get("faction_fixes") or {}).get(faction_name.get(r.get(2)))
        prereq_all = set(((r.get(19) or {}).get("all") or {}).values())
        ended_by = set((r.get(20) or {}).values()) | set((r.get(25) or {}).values())
        for view in [z] + ([{**z, **fixes}] if fixes else []):
            if view.get("parent_quest") or view.get("required_spell") or view.get("required_ranks"):
                unencoded.append((qid, "excluded gate kept"))
            start = view.get("available_starting_with")
            if start and abs(start) not in prereq_all:
                unencoded.append((qid, "availableStartingWith", start))
            for field in ("available_until_completed", "disabled_by_quest"):
                if view.get(field) and abs(view[field]) not in ended_by:
                    unencoded.append((qid, field, view[field]))
    assert unencoded == []
    assert 1302 in (quests[1282].get(25) or {}).values()       # They Call Him Smiling Jim, until 1302
