"""QuestieDB Forever import (Questie's data repository), read offline through lupa.

QuestieDB (https://github.com/Questie/QuestieDB; licensing in data/QUESTIE_SOURCE.md) holds
Questie's entity data since Questie v12. Its Forever flavor is read here: the raw entity data
(Era data with coordinates converted to Forever map frames), then the Static Correction layers in
the order docs/forever.md gives (a later layer overrides an earlier one):

  legacy           src/corrections/Forever/legacy/classic{Quest,NPC,Object,Item}Fixes.lua   Load()
  generated        src/corrections/Forever/generated/foreverBase{Quest,Npc,Object,Item}.lua
  traces           src/corrections/Forever/traces/forever{Quest,Npc,Object,Item}Traces.lua
  relation-traces  src/corrections/Forever/traces/foreverQuestRelationTraces.lua
  authored         src/corrections/Forever/forever{Quest,NPC,Object,Item}Fixes.lua         Load()

then the Dynamic Corrections (legacy LoadFactionFixes, then LoadDynamic) evaluated once for
Alliance and once for Horde, the Questie master quest blacklist evaluated for a Forever client,
areaId -> uiMapID for NPC and object spawns, and the quest XP support tables. Items are read for
their name and drop sources only (npcDrops, objectDrops: the "where it drops" of an item objective,
Contract A field 26). The quest reputation and item-start providers are not read (not output fields).
A data file's key table may lack only trailing keys of its meta (the item data predates teachesSpell).

Only data, correction, enum and support files are evaluated, never QuestieDB's or Questie's code
or tools. Raw data strings run in an empty Lua environment; everything else runs in the sandbox of
``pipeline.questie`` (register_eval off; no os, io, require, load, loadstring or dofile: using one
raises; stubbed QuestieLoader, QuestieDB, ZoneDB and Questie; a proxy for any other global). A value
that still contains a proxy is unresolved: skipped and listed. The table operations of ADR 0016
(``<field>_add`` = index + 1000, ``<field>_remove`` = index - 1000) are reimplemented here.

Rules beyond QuestieDB's own:
  * a correction row for an id that does not exist yet creates it only when it carries a name
    (``stats["created"]``); other such rows are skipped (``stats["skipped"]``);
  * Dynamic Corrections: a field both factions compose to the same value is applied; where they
    disagree on startedBy / finishedBy the per-group union is stored (``stats["faction_conflicts"]``).
    A disagreement on any other quest field the merge gates on (levels, race/class masks,
    prerequisites, exclusiveTo, breadcrumb, skill/reputation/max-level/specialization, special
    flags) keeps the static value in the quest and both factions' values in its ``faction_fixes``
    (``stats["faction_dependent"]``): the merge applies the one of the quest's faction, or excludes
    a quest of both factions. Other disagreements (quest name, objectives, source item; NPC and
    object spawns) leave the static value (``stats["dynamic_not_applied"]``);
  * an NPC a Forever layer created without ever stating friendlyToFaction has an unknown faction
    (``faction_known`` False), not "hostile to both" as nil means in the Era data;
  * a quest created by a Forever layer (not the Era data or the legacy layer) is ``new_in_forever``;
  * an operation QuestieDB would reject (malformed operand, replacement plus operation on one field,
    the same value added and removed, an atomic add over a different value) is skipped and listed in
    ``stats["rejected"]``;
  * the layer that last set each field is kept; a quest's ``race_mask_origin`` is "era" when its race
    mask comes from the Era raw data or the legacy (Classic) fixes and "forever" otherwise (the merge
    reads 77/178/255 as "the whole faction" only for "era");
  * quests whose corrections could not all be applied are listed in ``quest_problems`` (see
    QuestieDBData), and every id the blacklist hides in ``hidden_ids``, so the merge can exclude them.
"""
from __future__ import annotations

import copy
import re
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

import lupa

from pipeline.questie import (_PROXY, _apply_blacklist, _blank, _eval_table, _extract_data_string,
                              _extract_table, _fix_fields, _friendly, _new_sandbox, _read_keys,
                              _union_conflict)

DATATYPES = ("Quest", "Npc", "Object", "Item")
# datatype: (raw data file, its key table, its data string)
DATA_FILES = {
    "Quest": ("data/Forever/foreverQuestDB.lua", "questKeys", "questData"),
    "Npc": ("data/Forever/foreverNpcDB.lua", "npcKeys", "npcData"),
    "Object": ("data/Forever/foreverObjectDB.lua", "objectKeys", "objectData"),
    "Item": ("data/Forever/foreverItemDB.lua", "itemKeys", "itemData"),
}
META_FILES = {"Quest": "src/meta/questMeta.lua", "Npc": "src/meta/npcMeta.lua", "Object": "src/meta/objectMeta.lua",
              "Item": "src/meta/itemMeta.lua"}
_F = "src/corrections/Forever"
# Static Correction layers in application order: (layer, {datatype: (file, module)}).
STATIC_LAYERS = (
    ("legacy", {"Quest": (f"{_F}/legacy/classicQuestFixes.lua", "QuestieQuestFixes"),
                "Npc": (f"{_F}/legacy/classicNPCFixes.lua", "QuestieNPCFixes"),
                "Object": (f"{_F}/legacy/classicObjectFixes.lua", "QuestieObjectFixes"),
                "Item": (f"{_F}/legacy/classicItemFixes.lua", "QuestieItemFixes")}),
    ("generated", {"Quest": (f"{_F}/generated/foreverBaseQuest.lua", "ForeverBaseQuest"),
                   "Npc": (f"{_F}/generated/foreverBaseNpc.lua", "ForeverBaseNpc"),
                   "Object": (f"{_F}/generated/foreverBaseObject.lua", "ForeverBaseObject"),
                   "Item": (f"{_F}/generated/foreverBaseItem.lua", "ForeverBaseItem")}),
    ("traces", {"Quest": (f"{_F}/traces/foreverQuestTraces.lua", "ForeverQuestTraces"),
                "Npc": (f"{_F}/traces/foreverNpcTraces.lua", "ForeverNpcTraces"),
                "Object": (f"{_F}/traces/foreverObjectTraces.lua", "ForeverObjectTraces"),
                "Item": (f"{_F}/traces/foreverItemTraces.lua", "ForeverItemTraces")}),
    ("relation-traces", {"Quest": (f"{_F}/traces/foreverQuestRelationTraces.lua", "ForeverQuestRelationTraces")}),
    ("authored", {"Quest": (f"{_F}/foreverQuestFixes.lua", "ForeverQuestFixes"),
                  "Npc": (f"{_F}/foreverNPCFixes.lua", "ForeverNpcFixes"),
                  "Object": (f"{_F}/foreverObjectFixes.lua", "ForeverObjectFixes"),
                  "Item": (f"{_F}/foreverItemFixes.lua", "ForeverItemFixes")}),
)
FOREVER_LAYERS = frozenset({"generated", "traces", "relation-traces", "authored"})
# Dynamic providers in application order: (static layer whose module defines it, function).
DYNAMIC_PROVIDERS = (("legacy", "LoadFactionFixes"), ("authored", "LoadDynamic"))
ENUM_DIR = "src/corrections/enum"
ZONES_FILE = "support/Forever/Zones/areaIdToUiMapId.lua"
XP_FILES = ("support/Forever/QuestXP/xpDB-classic.lua", "support/Forever/QuestXP/xpDB-traces.lua")
FOREVER_FLAGS = {"IsForever": True}     # every other Questie.Is* flag reads false
FORBIDDEN_GLOBALS = ("os", "io", "require", "load", "loadstring", "dofile", "loadfile", "debug", "package",
                     "collectgarbage")
# Fields read per datatype; corrections to other fields are ignored.
FIELDS = {
    "Quest": ("name", "startedBy", "finishedBy", "requiredLevel", "questLevel", "requiredRaces",
              "requiredClasses", "objectives", "sourceItemId", "preQuestGroup", "preQuestSingle", "exclusiveTo",
              "requiredSkill", "requiredMinRep", "requiredMaxRep", "specialFlags", "breadcrumbForQuestId",
              "requiredMaxLevel", "requiredSpecialization",
              # availability gates (C1): read through every layer like the fields above
              "parentQuest", "requiredSpell", "availableUntilCompleted", "availableStartingWith", "requiredRanks",
              "disabledByQuest",
              # reported only (merge report "next_quest_in_chain"), never gating
              "nextQuestInChain"),
    "Npc": ("name", "minLevel", "spawns", "friendlyToFaction"),
    "Object": ("name", "spawns"),
    "Item": ("name", "npcDrops", "objectDrops"),     # Task 8: an item objective's name and sources
}
UNIONABLE = ("startedBy", "finishedBy")
# Quest fields the merge does not gate on: a faction disagreement there just keeps the static value.
NOT_GATING = frozenset({"name", "objectives", "sourceItemId", "nextQuestInChain"})
# Where a field value came from: the Era raw data and the legacy (Classic) fixes are Era-origin; every
# Forever layer is not. Only an Era-origin race mask 77/178/255 means "the whole faction" (merge._race).
ERA_ORIGINS = frozenset({"raw", "legacy", "dynamic-legacy"})
OP_OFFSET = 1000
# QuestieDB constants the correction files read: (module, field, Enum name); see _pick().
_QUESTIEDB_CONSTANTS = ("raceKeys", "classKeys", "sortKeys", "specialFlags", "factionIDs", "questFlags",
                        "npcFlags", "npcRanks", "itemClasses", "waypointPresets")
_FLAVOR_CONSTANTS = frozenset({"classKeys", "npcFlags"})   # never read from the shared Enum


@dataclass
class QuestieDBData:
    """Result of load_questiedb().

    quests: {id: dict} with pipeline.questie._blank's fields (race_mask keeps Forever bits),
    plus "new_in_forever": created by a Forever layer (generated, traces, authored), not Era data,
    and "faction_fixes": None, or {"Alliance": {field: value}, "Horde": {field: value}} for the
    gating fields whose Dynamic Corrections differ by faction (output field names).
    npcs: {id: {"name", "friendly": "A" | "H" | "AH" | None, "level": minLevel, "faction_known"}};
    friendly None is "hostile to both" when faction_known (Era data, or a layer set it) and
    "unknown" otherwise (an NPC a Forever layer created without friendlyToFaction).
    objects: {id: {"name"}}. items: {id: {"name", "npc_drops": [npc id, ...], "object_drops": [object
    id, ...]}} (empty lists when none). Each quest also has "objectives": its objective rows in group
    order, [{"group": 1 creature | 2 object | 3 item | 4 reputation | 5 kill credit | 6 spell, "id",
    "text": its own objective text or None}, ...] (group 5 adds "ids": every NPC that gives the credit,
    "id" is the base NPC; group 4's id is the faction). npc_spawns / object_spawns: {id: [{"map_id", "x", "y"}, ...]}
    (uiMapIDs, 0-100 Forever map coordinates; entities without a usable spawn are absent).
    xp: {quest id: (level, xp)}. stats: counts per layer and the lists described in the module doc.
    hidden_ids: every quest id the blacklist hides for a Forever client, including ids QuestieDB does
    not have (the merge excludes an outof.games quest with such an id as questie-hidden).
    quest_problems: {quest id: "correction-skipped" | "correction-unclear"} for quests a correction
    could not be applied to: a nameless row for an id that does not exist (skipped), or an
    unresolved or rejected value on a quest field the merge gates on, or a quest a Dynamic
    Correction creates for one faction only (unclear). The merge excludes those quests.
    """
    quests: dict = field(default_factory=dict)
    npcs: dict = field(default_factory=dict)
    objects: dict = field(default_factory=dict)
    items: dict = field(default_factory=dict)
    npc_spawns: dict = field(default_factory=dict)
    object_spawns: dict = field(default_factory=dict)
    xp: dict = field(default_factory=dict)
    stats: dict = field(default_factory=dict)
    hidden_ids: frozenset = frozenset()
    quest_problems: dict = field(default_factory=dict)


class _Bad(Exception):
    """A correction value or operation that QuestieDB would reject."""


# ---------------------------------------------------------------- Lua values -> Python trees

def _tree(v, isproxy=None):
    """Lua value -> Python: tables become dicts (keys kept), integral floats ints, proxies _PROXY."""
    if v is None or isinstance(v, (str, bool)):
        return v
    if isinstance(v, float):
        return int(v) if v.is_integer() else v
    if isinstance(v, int):
        return v
    if lupa.lua_type(v) != "table" or (isproxy is not None and isproxy(v)):
        return _PROXY
    out = {}
    for k, x in v.items():
        if isinstance(k, float) and k.is_integer():
            k = int(k)
        out[k] = _tree(x, isproxy)
    return out


def _has_proxy(t) -> bool:
    if t is _PROXY:
        return True
    return isinstance(t, dict) and any(_has_proxy(x) for x in t.values())


# ---------------------------------------------------------------- canonical shapes

def _num(v) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def _freeze(t):
    """Positional table -> tuple (nil holes as None), recursively."""
    if not isinstance(t, dict):
        return t
    if any(not isinstance(k, int) or isinstance(k, bool) or k < 1 for k in t):
        raise _Bad("expected a positional table")
    return tuple(_freeze(t.get(i)) for i in range(1, max(t, default=0) + 1))


def _items(t, strict: bool) -> list:
    """Lua list -> Python list in key order (strict: it must be dense, as operands must)."""
    if not isinstance(t, dict):
        raise _Bad("expected a list")
    keys = sorted(t, key=lambda k: (not isinstance(k, int), k if isinstance(k, int) else 0))
    if any(not isinstance(k, int) or isinstance(k, bool) or k < 1 for k in keys):
        raise _Bad("expected a list")
    if strict and keys != list(range(1, len(keys) + 1)):
        raise _Bad("list with holes")
    return [t[k] for k in keys]


def _id_list(t, strict: bool) -> list[int]:
    ids = _items(t, strict)
    if any(not isinstance(i, int) or isinstance(i, bool) for i in ids):
        raise _Bad("non-integer id")
    return ids


def _coordinate(row) -> tuple:
    """Spawn tuple as QuestieDB reads it: phase 0 (or none) omitted, (-1, -1) kept as is."""
    tup = _freeze(row) if isinstance(row, dict) else None
    if not tup or len(tup) < 2 or len(tup) > 3 or not _num(tup[0]) or not _num(tup[1]):
        raise _Bad("malformed coordinate")
    if len(tup) == 3 and tup[2] not in (None, 0):
        return tup[0], tup[1], tup[2]
    return tup[0], tup[1]


_OBJECTIVE_NUMERIC_SLOT = {1: 3, 2: 3, 3: 3, 5: 4, 6: 3}   # absent icon / item slot reads as 0


def _objective_row(row, slot: int) -> tuple:
    if not isinstance(row, dict):
        raise _Bad("malformed objective row")
    values = list(_freeze(row))
    values += [None] * (slot - len(values))
    if values[slot - 1] is None:
        values[slot - 1] = 0
    return tuple(values)


def _groups(t, allowed) -> dict:
    if not isinstance(t, dict) or any(k not in allowed for k in t):
        raise _Bad("unknown group")
    return t


def _shape(shape: str | None, t, strict: bool):
    """Tree -> internal value of a canonical table shape; None when it reads back as nil."""
    if shape == "idarray":
        return _id_list(t, strict) or None
    if shape == "pair":
        tup = _freeze(t) if isinstance(t, dict) else None
        if tup is None or len(tup) > 2 or any(v is not None and not _num(v) for v in tup):
            raise _Bad("malformed pair")
        return None if tup in ((), (0, 0)) else tup      # {0, 0} reads back as nil
    if shape == "questgivers":
        out = {}
        for g, sub in _groups(t, (1, 2, 3)).items():
            ids = _id_list(sub, strict)
            if ids:
                out[g] = ids
        return out or None
    if shape == "objectives":
        out = {}
        for g, sub in _groups(t, (1, 2, 3, 4, 5, 6)).items():
            if g == 4:
                pair = _freeze(sub) if isinstance(sub, dict) else None
                if pair is None:
                    raise _Bad("malformed reputation objective")
                if pair:
                    out[4] = pair
            else:
                rows = [_objective_row(r, _OBJECTIVE_NUMERIC_SLOT[g]) for r in _items(sub, strict)]
                if rows:
                    out[g] = rows
        return out or None
    if shape == "pairs":       # {{a, b}, ...} (requiredRanks): a list of numeric pairs
        out = []
        for row in _items(t, strict):
            pair = _freeze(row) if isinstance(row, dict) else None
            if pair is None or len(pair) != 2 or not all(_num(v) for v in pair):
                raise _Bad("malformed pair in a pair list")
            out.append(pair)
        return out or None
    if shape == "spawnlist":
        if not isinstance(t, dict):
            raise _Bad("malformed spawn list")
        out = {}
        for zone, rows in t.items():
            if not isinstance(zone, int) or isinstance(zone, bool):
                raise _Bad("non-integer zone")
            coords = [_coordinate(r) for r in _items(rows, strict)]
            if coords:
                out[zone] = coords
        return out or None
    raise _Bad(f"unsupported table shape {shape}")


def _replacement(ftype: str, shape: str | None, t):
    """`[key] = value`: the new field value ({} clears the field)."""
    if isinstance(t, dict) and not t:
        return None
    if ftype == "table":
        if not isinstance(t, dict):
            raise _Bad("a table field needs a table")
        return _shape(shape, t, strict=False)
    if isinstance(t, dict):
        raise _Bad("a non-empty table on a scalar field")
    if (ftype == "number" and not _num(t)) or (ftype == "string" and not isinstance(t, str)):
        raise _Bad(f"expected a {ftype}")
    return t


def _operand(ftype: str, shape: str | None, t):
    """An `_add` / `_remove` operand (None: absent or empty, which does nothing)."""
    if t is None:
        return None
    if ftype != "table" or shape is None:
        raise _Bad("operation on a scalar field")
    if not isinstance(t, dict):
        raise _Bad("operand is not a table")
    return _shape(shape, t, strict=True) if t else None


_GROUPED = frozenset({"questgivers", "objectives", "spawnlist", "waypointlist"})
_ATOMIC = frozenset({"pair", "trigger"})


def _operate(shape: str, existing, add, remove):
    """ADR 0016 `_add` / `_remove` on one field value; returns the new value (None reads as nil).

    Lists: removals drop every exact match, additions append absent values in operand order.
    Grouped values (starter/finisher groups, objective groups, spawn zones): the list rule within
    each supplied group, other groups kept. Atomic records (pairs, objective group 4): add when
    absent or equal, remove only an exact match.
    """
    grouped = shape in _GROUPED
    adds = (add or {}) if grouped else ({0: add} if add is not None else {})
    removes = (remove or {}) if grouped else ({0: remove} if remove is not None else {})

    def atomic(g):
        return shape in _ATOMIC or (shape == "objectives" and g == 4)

    if shape in _ATOMIC and adds and removes:
        raise _Bad("atomic records cannot add and remove in one row; use replacement")
    for g, values in adds.items():
        other = removes.get(g)
        if other and (values == other if atomic(g) else any(v in other for v in values)):
            raise _Bad("same value requested for add and remove")
    if not adds and not removes:
        return existing
    targets = (dict(existing) if existing else {}) if grouped else {0: existing}
    for g in [*adds, *(g for g in removes if g not in adds)]:
        current, a, r = targets.get(g), adds.get(g), removes.get(g)
        if atomic(g):
            if r is not None and current == r:
                current = None
            if a is not None:
                if current is not None and current != a:
                    raise _Bad("a different atomic value already exists; use replacement")
                current = a
        else:
            kept = [v for v in current or [] if not (r and v in r)]
            for v in a or []:
                if v not in kept:
                    kept.append(v)
            current = kept or None
        if current is None:
            targets.pop(g, None)
        else:
            targets[g] = current
    return (targets or None) if grouped else targets.get(0)


def _parts(groups) -> list:
    """Grouped value -> [group 1, group 2, group 3] (the list form pipeline.questie uses)."""
    return [list((groups or {}).get(g) or []) or None for g in (1, 2, 3)]


def _as_lists(v):
    """Internal value -> the plain-list form of pipeline.questie._to_py (tuples as lists)."""
    if isinstance(v, dict):
        n = max(v, default=0)
        return [_as_lists(v.get(i)) for i in range(1, n + 1)]
    if isinstance(v, (list, tuple)):
        return [_as_lists(x) for x in v]
    return v


# ---------------------------------------------------------------- the loader

@dataclass
class _Meta:
    keys: dict
    names: dict
    types: dict
    structures: dict
    field_count: int

    def decode(self, key):
        """Correction key -> (field, "set" | "add" | "remove"), or (None, None) if unknown."""
        if isinstance(key, float) and key.is_integer():
            key = int(key)
        if not isinstance(key, int) or isinstance(key, bool):
            return None, None
        if 1 <= key <= self.field_count and key in self.names:
            return self.names[key], "set"
        if key >= OP_OFFSET and key - OP_OFFSET in self.names:
            return self.names[key - OP_OFFSET], "add"
        if key <= 0 and key + OP_OFFSET in self.names:
            return self.names[key + OP_OFFSET], "remove"
        return None, None


def _lua_dict(text: str, name: str) -> dict:
    return _tree(_eval_table("return " + text, name))


def _read_meta(root: Path, dt: str) -> _Meta:
    path = root / META_FILES[dt]
    m = re.search(r"\bfieldCount\s*=\s*(\d+)", path.read_text(encoding="utf-8"))
    if not m:
        raise ValueError(f"no fieldCount in {path}")
    keys = _lua_dict(_extract_table(path, "keys"), "keys")
    types = _lua_dict(_extract_table(path, "types"), "types")
    structures = _lua_dict(_extract_table(path, "structures"), "structures")
    meta = _Meta(keys=keys, names={i: n for n, i in keys.items()}, types=types, structures=structures,
                 field_count=int(m.group(1)))
    bad = [n for n, i in keys.items() if not (isinstance(i, int) and 1 <= i <= meta.field_count)
           or types.get(i) not in ("number", "string", "table")]
    bad += [n for n in FIELDS[dt] if types.get(keys.get(n)) == "table" and keys.get(n) not in structures]
    if bad or len(meta.names) != len(keys):
        raise ValueError(f"{META_FILES[dt]}: keys outside fieldCount, without a type or table shape, "
                         f"or duplicated: {sorted(bad)}")
    return meta


def _required_files(root: Path, blacklist: Path) -> list[Path]:
    paths = [root / DATA_FILES[dt][0] for dt in DATATYPES] + [root / META_FILES[dt] for dt in DATATYPES]
    for _layer, files in STATIC_LAYERS:
        paths += [root / f for f, _module in files.values()]
    paths += [root / ENUM_DIR / "constants.lua", root / ZONES_FILE] + [root / f for f in XP_FILES]
    return paths + [Path(blacklist)]


class _Loader:
    def __init__(self, root: Path, blacklist: Path):
        self.root, self.blacklist = Path(root), Path(blacklist)
        self.meta: dict[str, _Meta] = {}
        self.ents: dict[str, dict[int, dict]] = {dt: {} for dt in DATATYPES}
        self.forever_created: set[int] = set()     # quests created by a Forever layer
        self.faction_stated: set[int] = set()      # NPCs whose friendlyToFaction the Era data or a layer states
        self.faction_fixes: dict[int, dict] = {}   # quest id -> {faction: {Questie field: internal value}}
        # datatype -> id -> {field: layer that last set it}; faction_fix_origins: id -> {faction: {field: layer}}
        self.origins: dict[str, dict[int, dict]] = {dt: {} for dt in DATATYPES}
        self.fix_origins: dict[int, dict] = {}
        self.stats = {
            "raw": {}, "layers": {dt: {} for dt in DATATYPES},
            "dynamic": {dt: {"rows": {"Alliance": 0, "Horde": 0}, "applied": 0, "unioned": 0, "faction_dependent": 0,
                             "not_applied": 0}
                        for dt in DATATYPES},
            "created": [], "skipped": [], "unresolved": [], "rejected": [],
            "faction_conflicts": [], "faction_dependent": [], "dynamic_not_applied": [],
            "hidden": 0, "hide_on_map": 0, "spawns": {}, "xp": {}, "final": {},
        }

    # -- inputs
    def _keys(self, dt: str) -> dict:
        rel, key_table, _data = DATA_FILES[dt]
        keys = _read_keys(self.root / rel, key_table)
        meta = self.meta[dt] = _read_meta(self.root, dt)
        # the data's key table may lack only trailing meta keys (fields added after the data was written)
        top = max(keys.values(), default=0)
        missing = {n: i for n, i in meta.keys.items() if n not in keys}
        if not keys.items() <= meta.keys.items() or any(i <= top for i in missing.values()):
            diff = sorted(set(keys.items()) ^ set(meta.keys.items()))
            raise ValueError(f"{rel}: {key_table} differ from {META_FILES[dt]}: {diff}")
        return keys

    def _raw(self, dt: str) -> None:
        rel, _keys, data_field = DATA_FILES[dt]
        keys, meta = self._keys(dt), self.meta[dt]
        data = _eval_table(_extract_data_string(self.root / rel, data_field), data_field)
        ents = self.ents[dt]
        for eid, row in data.items():
            if not isinstance(eid, (int, float)) or lupa.lua_type(row) != "table":
                continue
            ent = ents[int(eid)] = {}
            for name in FIELDS[dt]:
                tree = _tree(row[keys[name]])
                if tree is None:
                    continue
                idx = keys[name]
                try:
                    value = _replacement(meta.types[idx], meta.structures.get(idx), tree)
                except _Bad as e:
                    self.stats["rejected"].append((dt, int(eid), name, "raw", str(e)))
                    continue
                if value is not None:
                    ent[name] = value
                    self.origins[dt].setdefault(int(eid), {})[name] = "raw"
        self.stats["raw"][dt] = len(ents)
        if dt == "Npc":
            self.faction_stated |= set(ents)

    def _sandbox(self) -> None:
        self.lua, self.sb = _new_sandbox(flags=FOREVER_FLAGS, forbidden=FORBIDDEN_GLOBALS, globals_={})
        lua, sb = self.lua, self.sb
        ns = lua.table_from({"Enum": lua.table()})
        enum_dir = self.root / ENUM_DIR
        files = sorted(enum_dir.glob("*.lua"), key=lambda p: (p.name != "constants.lua", p.name))
        for path in files:   # constants.lua creates LibQuestieDB.Enum; the others fill it
            sb.call(path.read_text(encoding="utf-8"), f"{ENUM_DIR}/{path.name}", "QuestieDB", ns)
        enum = self.enum = ns["Enum"]

        def alias_keys(dt):
            out = {}
            for name, idx in self.meta[dt].keys.items():
                out[name] = idx
                out[name + "_add"] = idx + OP_OFFSET
                out[name + "_remove"] = idx - OP_OFFSET
            return lua.table_from(out)

        qdb = sb.modules["QuestieDB"]
        for dt in DATATYPES:
            qdb[DATA_FILES[dt][1]] = alias_keys(dt)          # questKeys, npcKeys, objectKeys, itemKeys
        for name in _QUESTIEDB_CONSTANTS:
            qdb[name] = _pick(enum, name)
        sb.modules["ZoneDB"]["zoneIDs"] = enum["zoneIDs"]
        professions = sb.modules["QuestieProfessions"]
        for name in ("professionKeys", "specializationKeys", "rankNames"):
            professions[name] = enum[name]
        sb.modules["Phasing"] = lua.table_from({"phases": enum["phases"]})
        sb.modules["l10n"] = sb.eval("return setmetatable({}, {__call = function(_, text) return text end})", "l10n")
        questie = sb.env["Questie"]
        for name, value in (enum["iconTypes"] or lua.table()).items():
            questie[name] = value

    def _module(self, rel: str, module: str):
        self.sb.run((self.root / rel).read_text(encoding="utf-8"), rel)
        mod = self.sb.module(module)
        if mod is None:
            raise ValueError(f"{rel} did not create module {module}")
        return mod

    # -- rows
    def _rows(self, dt: str, table, layer: str) -> dict:
        """{id: {field: {"set" | "add" | "remove": tree}}} for the read fields of one provider result."""
        meta, wanted, out = self.meta[dt], FIELDS[dt], {}
        if table is None:
            return out
        if lupa.lua_type(table) != "table":
            raise ValueError(f"{dt} {layer}: provider did not return a table")
        for eid, row in table.items():
            if not isinstance(eid, (int, float)) or isinstance(eid, bool) or lupa.lua_type(row) != "table":
                continue
            ops = out[int(eid)] = {}
            for key, value in row.items():
                name, op = meta.decode(key)
                if name is None:
                    self.stats["rejected"].append((dt, int(eid), str(key), layer, "unknown field key"))
                elif name in wanted:
                    ops.setdefault(name, {})[op] = _tree(value, self.sb.isproxy)
        return out

    def _apply(self, ents: dict, dt: str, eid: int, ops: dict, layer: str, counts: dict | None,
               origins: dict | None = None) -> None:
        """Apply one row's operations to ents[eid]; origins (id -> {field: layer}, default the static
        origins) records the layer of every field the row sets or clears."""
        origins = self.origins[dt] if origins is None else origins

        def count(key):
            if counts is not None:
                counts[key] += 1

        meta, ent = self.meta[dt], ents.get(eid)
        if ent is None:
            name = (ops.get("name") or {}).get("set")
            if not isinstance(name, str):
                count("skipped")
                self.stats["skipped"].append((dt, eid, layer))
                return
            ent = ents[eid] = {}
            count("created")
            self.stats["created"].append((dt, eid, layer))
            if dt == "Quest" and counts is not None and layer in FOREVER_LAYERS:
                self.forever_created.add(eid)
        for name, parts in ops.items():
            idx = meta.keys[name]
            if _has_proxy(parts):
                count("unresolved")
                self.stats["unresolved"].append((dt, eid, name, layer))
                continue
            ftype, shape = meta.types[idx], meta.structures.get(idx)
            try:
                if "set" in parts:
                    if len(parts) > 1:
                        raise _Bad("replacement and operation share a field")
                    value = _replacement(ftype, shape, parts["set"])
                else:
                    value = _operate(shape, ent.get(name), _operand(ftype, shape, parts.get("add")),
                                     _operand(ftype, shape, parts.get("remove")))
            except _Bad as e:
                count("rejected")
                self.stats["rejected"].append((dt, eid, name, layer, str(e)))
                continue
            if value is None:
                ent.pop(name, None)
                origins.get(eid, {}).pop(name, None)
            else:
                ent[name] = value
                origins.setdefault(eid, {})[name] = layer.split(":", 1)[0]
            count("fields")
            if name == "friendlyToFaction" and counts is not None:
                self.faction_stated.add(eid)

    def _static(self) -> dict:
        modules = {}
        for layer, files in STATIC_LAYERS:
            for dt in DATATYPES:
                if dt not in files:
                    continue
                rel, module = files[dt]
                mod = modules[(layer, dt)] = (self._module(rel, module), rel)
                counts = self.stats["layers"][dt][layer] = {
                    "rows": 0, "fields": 0, "created": 0, "skipped": 0, "unresolved": 0, "rejected": 0}
                rows = self._rows(dt, mod[0].Load(mod[0]), layer)
                counts["rows"] = len(rows)
                for eid in sorted(rows):
                    self._apply(self.ents[dt], dt, eid, rows[eid], layer, counts)
        return modules

    def _dynamic(self, modules: dict) -> None:
        for dt in DATATYPES:
            providers = [(layer, *modules[(layer, dt)], fn) for layer, fn in DYNAMIC_PROVIDERS
                         if (layer, dt) in modules and modules[(layer, dt)][0][fn] is not None]
            if not providers:
                continue
            static, dyn = self.ents[dt], self.stats["dynamic"][dt]
            per, per_origins = {}, {}
            for faction in ("Alliance", "Horde"):
                self.sb.setfaction(faction)
                ents, origins = per[faction], per_origins[faction] = {}, {}
                for layer, mod, _rel, fn in providers:
                    rows = self._rows(dt, mod[fn](mod), f"dynamic-{layer}")
                    dyn["rows"][faction] += len(rows)
                    for eid in sorted(rows):
                        if eid not in ents and eid in static:
                            ents[eid] = copy.deepcopy(static[eid])
                            origins[eid] = dict(self.origins[dt].get(eid, {}))
                        self._apply(ents, dt, eid, rows[eid], f"dynamic-{layer}:{faction}", None, origins)
            self.sb.setfaction("Alliance")
            self._compose(dt, per, static, dyn, per_origins)

    def _compose(self, dt: str, per: dict, static: dict, dyn: dict, per_origins: dict) -> None:
        def origin(faction, eid, name):
            source = per_origins[faction] if eid in per[faction] else self.origins[dt]
            return source.get(eid, {}).get(name)

        for eid in sorted(per["Alliance"].keys() | per["Horde"].keys()):
            a, h = per["Alliance"].get(eid, static.get(eid)), per["Horde"].get(eid, static.get(eid))
            if a is None or h is None:      # created for one faction only
                dyn["not_applied"] += 1
                self.stats["dynamic_not_applied"].append((dt, eid, "entity"))
                continue
            if eid not in static:
                self.stats["created"].append((dt, eid, "dynamic"))
            base = static.setdefault(eid, {})
            for name in sorted(a.keys() | h.keys() | base.keys()):
                va, vh = a.get(name), h.get(name)
                if va == vh:
                    if name == "friendlyToFaction" and dt == "Npc":
                        self.faction_stated.add(eid)
                    if base.get(name) != va:
                        dyn["applied"] += 1
                        if va is None:
                            base.pop(name, None)
                            self.origins[dt].get(eid, {}).pop(name, None)
                        else:
                            base[name] = copy.deepcopy(va)
                            oa, oh = origin("Alliance", eid, name), origin("Horde", eid, name)
                            self.origins[dt].setdefault(eid, {})[name] = oa if oa == oh else "dynamic-mixed"
                    continue
                if dt == "Quest" and name not in UNIONABLE and name not in NOT_GATING:
                    fixes = self.faction_fixes.setdefault(eid, {"Alliance": {}, "Horde": {}})
                    fixes["Alliance"][name], fixes["Horde"][name] = copy.deepcopy(va), copy.deepcopy(vh)
                    fix_origins = self.fix_origins.setdefault(eid, {"Alliance": {}, "Horde": {}})
                    for faction in ("Alliance", "Horde"):
                        fix_origins[faction][name] = origin(faction, eid, name)
                    dyn["faction_dependent"] += 1
                    self.stats["faction_dependent"].append((dt, eid, name))
                    continue
                union = _union_conflict(name, _parts(va), _parts(vh)) if name in UNIONABLE else None
                if union is None:
                    dyn["not_applied"] += 1
                    self.stats["dynamic_not_applied"].append((dt, eid, name))
                    continue
                dyn["unioned"] += 1
                self.stats["faction_conflicts"].append((dt, eid, name))
                groups = {g: ids for g, ids in enumerate(union, start=1) if ids}
                if groups:
                    base[name] = groups
                else:
                    base.pop(name, None)

    # -- support data
    def _zones(self) -> tuple[dict, dict]:
        path = self.root / ZONES_FILE
        override = _tree(_eval_table(_extract_data_string(path, "areaIdToUiMapIdOverride"), "override"))
        base = _tree(_eval_table(_extract_data_string(path, "areaIdToUiMapId"), "areaIdToUiMapId"))
        return override, base

    def _spawns(self, dt: str, override: dict, base: dict) -> dict:
        counts = self.stats["spawns"][dt] = {"kept": 0, "unmapped": 0, "bad_coords": 0}
        out = {}
        for eid in sorted(self.ents[dt]):
            points = []
            for zone, rows in sorted((self.ents[dt][eid].get("spawns") or {}).items()):
                ui = override[zone] if zone in override else base.get(zone)
                if not isinstance(ui, int) or ui <= 0:
                    counts["unmapped"] += len(rows)
                    continue
                for row in rows:
                    x, y = row[0], row[1]
                    if not (0 <= x <= 100 and 0 <= y <= 100):    # also the (-1, -1) placeholders
                        counts["bad_coords"] += 1
                        continue
                    points.append({"map_id": ui, "x": float(x), "y": float(y)})
                    counts["kept"] += 1
            if points:
                out[eid] = points
        return out

    def _xp(self) -> dict:
        self.sb.modules["QuestXP"] = self.lua.table()
        for rel in XP_FILES:
            self.sb.run((self.root / rel).read_text(encoding="utf-8"), rel)
        out, bad = {}, 0
        for qid, row in (_tree(self.sb.modules["QuestXP"]["db"], self.sb.isproxy) or {}).items():
            pair = tuple(row.get(i) for i in (1, 2)) if isinstance(row, dict) and len(row) == 2 else None
            if (isinstance(qid, int) and pair is not None
                    and all(isinstance(v, int) and not isinstance(v, bool) for v in pair)):
                out[qid] = pair                                 # (level, xp)
            else:
                bad += 1
        self.stats["xp"] = {"quests": len(out), "malformed": bad}
        return out

    # -- output
    def _quests(self) -> dict:
        flags = self.enum["specialFlags"]
        bit = int((flags and flags["REPEATABLE"]) or 1)
        out = {}
        for qid in sorted(self.ents["Quest"]):
            q = _blank(qid)
            for name, value in self.ents["Quest"][qid].items():
                fields, _unresolved = _fix_fields(name, _as_lists(value), bit)
                q.update(fields or {})
            q["race_mask_origin"] = _origin(q["race_mask"], self.origins["Quest"].get(qid, {}).get("requiredRaces"))
            q["objectives"] = _objective_rows(self.ents["Quest"][qid].get("objectives"))
            q["new_in_forever"] = qid in self.forever_created
            q["faction_fixes"] = None
            if qid in self.faction_fixes:
                q["faction_fixes"] = {}
                for faction, values in self.faction_fixes[qid].items():
                    out_fields = q["faction_fixes"][faction] = {}
                    for name, value in values.items():
                        out_fields.update(_fix_fields(name, _as_lists(value), bit)[0] or {})
                    if "requiredRaces" in values:
                        out_fields["race_mask_origin"] = _origin(
                            out_fields.get("race_mask"), self.fix_origins[qid][faction].get("requiredRaces"))
            out[qid] = q
        return out

    def _quest_problems(self) -> dict:
        """{quest id: reason} for the quests a correction could not be applied to (see QuestieDBData)."""
        gating = set(FIELDS["Quest"]) - NOT_GATING
        out = {}
        for dt, eid, *rest in self.stats["unresolved"] + self.stats["rejected"]:
            if dt == "Quest" and (rest[0] in gating or rest[0] not in self.meta["Quest"].keys):
                out[eid] = "correction-unclear"
        for dt, eid, what in self.stats["dynamic_not_applied"]:
            if dt == "Quest" and what == "entity":
                out[eid] = "correction-unclear"
        for dt, eid, _layer in self.stats["skipped"]:
            if dt == "Quest":
                out[eid] = "correction-skipped"
        return dict(sorted(out.items()))

    def run(self) -> QuestieDBData:
        missing = [str(p) for p in _required_files(self.root, self.blacklist) if not p.is_file()]
        if missing:
            raise FileNotFoundError(f"QuestieDB files not found: {', '.join(missing)}")
        try:
            for dt in DATATYPES:
                self._raw(dt)
            self._sandbox()
            self._dynamic(self._static())
            quests = self._quests()
            hidden_ids = _apply_blacklist(self.sb, self.blacklist, quests, self.stats)
            override, base = self._zones()
            npc_spawns, object_spawns = self._spawns("Npc", override, base), self._spawns("Object", override, base)
            xp = self._xp()
        except lupa.LuaError as e:
            raise ValueError(f"QuestieDB evaluation failed: {e}") from e
        npcs = {nid: {"name": e.get("name") if isinstance(e.get("name"), str) else None,
                      "friendly": _friendly(e.get("friendlyToFaction")),
                      "level": int(e["minLevel"]) if _num(e.get("minLevel")) else None,
                      "faction_known": nid in self.faction_stated}
                for nid, e in sorted(self.ents["Npc"].items())}
        objects = {oid: {"name": e.get("name") if isinstance(e.get("name"), str) else None}
                   for oid, e in sorted(self.ents["Object"].items())}
        items = {iid: {"name": e.get("name") if isinstance(e.get("name"), str) else None,
                       "npc_drops": list(e.get("npcDrops") or []), "object_drops": list(e.get("objectDrops") or [])}
                 for iid, e in sorted(self.ents["Item"].items())}
        self.stats["final"] = {"Quest": len(quests), "Npc": len(npcs), "Object": len(objects), "Item": len(items)}
        problems = self._quest_problems()
        self.stats["quest_problems"] = dict(sorted(Counter(problems.values()).items()))
        return QuestieDBData(quests=quests, npcs=npcs, objects=objects, items=items, npc_spawns=npc_spawns,
                             object_spawns=object_spawns, xp=xp, stats=self.stats,
                             hidden_ids=frozenset(hidden_ids), quest_problems=problems)


def _objective_rows(groups) -> list[dict]:
    """Internal objectives value ({group: rows}) -> [{"group", "id", "text"(, "ids")}, ...] in group order.

    Rows: creature / object / item (id, text, icon), kill credit ({ids}, base id, text, icon), spell
    (spell id, text, item); reputation is one (faction, value) pair. An empty text reads as None."""
    out = []
    for g in sorted(groups or {}):
        value = groups[g]
        if g == 4:
            if value and _num(value[0]):
                out.append({"group": 4, "id": int(value[0]), "text": None})
            continue
        for row in value:
            text = row[2] if g == 5 and len(row) > 2 else row[1] if g != 5 and len(row) > 1 else None
            text = text if isinstance(text, str) and text.strip() else None
            if g == 5:
                ids = [i for i in (row[0] or ()) if _num(i)] if isinstance(row[0], tuple) else []
                base = row[1] if len(row) > 1 and _num(row[1]) else (ids[0] if ids else None)
                if base is not None:
                    out.append({"group": 5, "id": int(base), "ids": [int(i) for i in ids], "text": text})
            elif row and _num(row[0]):
                out.append({"group": g, "id": int(row[0]), "text": text})
    return out


def _origin(mask, layer: str | None) -> str | None:
    """Origin of a quest's race mask: "era" (Era raw data or the legacy Classic fixes), "forever"
    (any Forever layer, or Alliance and Horde Dynamic Corrections of different origins), or None
    (no mask)."""
    if not mask:
        return None
    return "era" if layer in ERA_ORIGINS else "forever"


def _pick(enum, name: str):
    """A QuestieDB constant as QuestieDB's correction compat selects it for Forever: the shared Enum
    table (except classKeys and npcFlags), else Forever's own table, else Classic's (Forever's rules)."""
    if name not in _FLAVOR_CONSTANTS and enum[name] is not None:
        return enum[name]
    by_expansion = enum["byExpansion"]
    for expansion in ("Forever", "Classic"):
        table = by_expansion[expansion] if by_expansion is not None else None
        if table is not None and table[name] is not None:
            return table[name]
    return None


def load_questiedb(root: Path, blacklist_path: Path) -> QuestieDBData:
    """QuestieDB's Forever flavor (a QuestieDB checkout at root) with every layer described in the
    module docstring applied, plus Questie master's quest blacklist at blacklist_path.

    Raises FileNotFoundError when an input file is missing and ValueError when a file fails to
    evaluate, touches a forbidden global, or the data's key tables differ from src/meta.
    """
    return _Loader(root, blacklist_path).run()
