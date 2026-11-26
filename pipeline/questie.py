"""Shared helpers for reading Questie-format Lua files offline through lupa.

The build's Questie source is QuestieDB's Forever flavor (pipeline/questiedb.py,
data/QUESTIE_SOURCE.md). The former Questie Classic Era (v11.38) loader was removed; this module
keeps what the QuestieDB loader reuses:

  * the lupa sandbox (``_new_sandbox``): stubbed client flags, forbidden globals that raise, a
    proxy for any other global, stubbed QuestieLoader modules, ``_eval_table`` for data strings in
    an empty environment;
  * the readers: key tables, ``[[return {...}]]`` data strings, ``name = { ... }`` table literals;
  * the conversion of one Questie field to the quest dict fields (``_fix_fields``, ``_blank``), the
    startedBy/finishedBy faction union, the quest blacklist runner and friendlyToFaction normalising.

No Questie or QuestieDB code or tool is ever executed; only data, correction, enum and support files
are evaluated in these sandboxes.
"""
import re
from pathlib import Path

import lupa

_KEY_RE = re.compile(r"\[\s*'(\w+)'\s*\]\s*=\s*(\d+)")


def _read_keys(path: Path, table: str) -> dict[str, int]:
    """Parse a `QuestieDB.<table> = { ['name'] = n, ... }` key table into {name: index}."""
    src = Path(path).read_text(encoding="utf-8")
    m = re.search(table + r"\s*=\s*\{(.*?)^\}", src, re.S | re.M)
    if not m:
        raise ValueError(f"no {table} table in {path}")
    keys = {}
    for line in m.group(1).splitlines():
        line = line.split("--", 1)[0]  # drop comments (incl. commented sub-keys)
        km = _KEY_RE.search(line)
        if km:
            keys[km.group(1)] = int(km.group(2))
    return keys


def _extract_data_string(data_lua: Path, field: str = "questData") -> str:
    src = Path(data_lua).read_text(encoding="utf-8")
    m = re.search(field + r"\s*=\s*\[(=*)\[", src)
    if not m:
        raise ValueError(f"no {field} long string in {data_lua}")
    end = src.find("]" + m.group(1) + "]", m.end())
    if end < 0:
        raise ValueError(f"unterminated {field} long string")
    return src[m.end():end]


_SANDBOX_LUA = r"""
return function(cfg)
local proxies = setmetatable({}, {__mode = "k"})
local pmt = {}
local function newproxy() local p = setmetatable({}, pmt); proxies[p] = true; return p end
pmt.__index = function() return newproxy() end
pmt.__call = function() return newproxy() end
for _, e in ipairs({"__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__concat", "__idiv"}) do
    pmt[e] = function() return newproxy() end
end
pmt.__lt = function() return false end
pmt.__le = function() return false end
pmt.__len = function() return 0 end
pmt.__tostring = function() return "<unresolved>" end

-- A forbidden global (os, io, require, load, ...) is an error, not a harmless proxy.
local forbidden = {}
for _, name in ipairs(cfg.forbidden or {}) do forbidden[name] = true end
local env = {}
setmetatable(env, {__index = function(t, k)
    if forbidden[k] then error("sandbox: forbidden global '" .. tostring(k) .. "'", 2) end
    local p = newproxy(); rawset(t, k, p); return p
end})
for _, name in ipairs({"pairs", "ipairs", "type", "tostring", "tonumber", "select", "next", "unpack",
                       "math", "string", "table", "setmetatable", "getmetatable", "rawget", "rawset", "pcall", "error", "assert"}) do
    env[name] = _G[name]
end
env.unpack = env.unpack or table.unpack
for k, v in pairs(cfg.globals or {}) do env[k] = v end

-- The client flags: the given Is* flags, every other Is* flag false.
local flags = {}
for k, v in pairs(cfg.flags or {}) do flags[k] = v end
local Questie = setmetatable(flags, {__index = function(t, k)
    if type(k) == "string" and k:sub(1, 2) == "Is" then return false end
    local p = newproxy(); rawset(t, k, p); return p
end})
env.Questie = Questie
local Expansions = {Era = 1, Tbc = 2, Wotlk = 3, Cata = 4, MoP = 5, Current = 1}
local modules = {Expansions = Expansions}
modules.QuestieDB = {}
modules.ZoneDB = {}
modules.QuestieProfessions = {}
modules.QuestieCorrections = {itemObjectiveFirst = {}, objectObjectiveFirst = {}, killCreditObjectiveFirst = {},
                              eventObjectiveFirst = {}, spellObjectiveFirst = {}}
local created = {}
env.QuestieLoader = {
    ImportModule = function(_, name) return modules[name] or newproxy() end,
    CreateModule = function(_, name) local m = {}; created[name] = m; return m end,
}
env.QuestieDB, env.ZoneDB = modules.QuestieDB, modules.ZoneDB
env.QuestieProfessions, env.QuestieCorrections = modules.QuestieProfessions, modules.QuestieCorrections
env.Expansions = Expansions
local faction = "Alliance"
env.UnitFactionGroup = function() return faction end

local function chunk(src, name)
    local f, err = load(src, name, "t", env)
    if not f then error(err) end
    return f
end
return {
    env = env,
    modules = modules,
    isproxy = function(t) return proxies[t] == true end,
    eval = function(src, name) return chunk(src, name)() end,
    run = function(src, name) chunk(src, name)() end,
    call = function(src, name, ...) return chunk(src, name)(...) end,
    module = function(name) return created[name] end,
    setfaction = function(f) faction = f end,
}
end
"""


def _new_sandbox(flags: dict, forbidden=(), globals_: dict | None = None):
    """(runtime, sandbox) for evaluating Questie/QuestieDB files.

    flags: the Questie.Is* flags that are true (every other Is* flag reads false). forbidden:
    global names whose use raises instead of yielding a proxy. globals_: extra plain globals.
    """
    lua = lupa.LuaRuntime(register_eval=False, register_builtins=False, unpack_returned_tuples=True)
    cfg = lua.table_from({
        "flags": lua.table_from(flags),
        "forbidden": lua.table_from(list(forbidden)),
        "globals": lua.table_from(globals_ or {}),
    })
    return lua, lua.execute(_SANDBOX_LUA)(cfg)


def _balanced_table(src: str, start: int) -> str:
    """Text of the {...} table whose '{' is at src[start]; skips strings and comments."""
    depth, i, n = 0, start, len(src)
    while i < n:
        c = src[i]
        if src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                end = src.find("]" + m.group(1) + "]", i)
                i = n if end < 0 else end + len(m.group(1)) + 2
            else:
                nl = src.find("\n", i)
                i = n if nl < 0 else nl
            continue
        if c in "\"'":
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == "\\" else 1
            i = j + 1
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return src[start:i + 1]
        i += 1
    raise ValueError("unbalanced table")


def _extract_table(path: Path, field: str) -> str:
    src = Path(path).read_text(encoding="utf-8")
    m = re.search(r"\b" + re.escape(field) + r"\s*=\s*\{", src)
    if not m:
        raise ValueError(f"no {field} table in {path}")
    return _balanced_table(src, m.end() - 1)


_PROXY = object()


def _flat_ids(lst):
    """List of ids (nil holes dropped) -> (ids or None, unresolved flag)."""
    if lst is None:
        return None, False
    if lst is _PROXY:
        return None, True
    bad = any(i is _PROXY for i in lst)
    ids = [i for i in lst if isinstance(i, int) and not isinstance(i, bool)]
    return (ids or None), bad


def _entry_ids(lst):
    """`{{id, text?}, ...}` -> first elements."""
    if lst is None:
        return None, False
    if lst is _PROXY:
        return None, True
    bad, out = False, []
    for e in lst:
        if e is _PROXY:
            bad = True
        elif isinstance(e, list) and e:
            if e[0] is _PROXY:
                bad = True
            elif e[0] is not None:
                out.append(e[0])
    return (out or None), bad


def _scalar(v):
    if v is _PROXY:
        return None, True
    return (int(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else None), False


def _pair(v):
    """[id, value] -> [int, int]; anything else (incl. unresolved) -> None."""
    if isinstance(v, list) and len(v) >= 2 and all(
            isinstance(x, int) and not isinstance(x, bool) for x in v[:2]):
        return [v[0], v[1]]
    return None


# QuestieDB availability gates and the chain successor (scalar quest/spell ids) -> output field.
_GATES = {"parentQuest": "parent_quest", "requiredSpell": "required_spell",
          "availableUntilCompleted": "available_until_completed",
          "availableStartingWith": "available_starting_with", "disabledByQuest": "disabled_by_quest",
          "nextQuestInChain": "next_quest_in_chain"}


def _fix_fields(name, value, repeatable_bit=1):
    """One Questie fix (key name, python value) -> ({field: value}, unresolved flag)."""
    if name in ("requiredLevel", "questLevel", "requiredRaces", "requiredClasses", "sourceItemId"):
        field = {"requiredLevel": "required_level", "questLevel": "quest_level",
                 "requiredRaces": "race_mask", "requiredClasses": "class_mask",
                 "sourceItemId": "source_item_id"}[name]
        v, bad = _scalar(value)
        return {field: v}, bad
    if name == "name":
        return {"name": value if isinstance(value, str) else None}, not isinstance(value, str)
    if name in ("requiredMaxLevel", "requiredSpecialization"):
        v, bad = _scalar(value)
        return {{"requiredMaxLevel": "required_max_level",
                 "requiredSpecialization": "required_specialization"}[name]: v}, bad
    if name in ("requiredSkill", "requiredMinRep", "requiredMaxRep"):
        field = {"requiredSkill": "required_skill", "requiredMinRep": "required_min_rep",
                 "requiredMaxRep": "required_max_rep"}[name]
        return {field: _pair(value)}, value is _PROXY or (
            isinstance(value, list) and any(x is _PROXY for x in value))
    if name == "specialFlags":
        v, bad = _scalar(value)
        return {"repeatable": bool((v or 0) & repeatable_bit)}, bad
    if name == "breadcrumbForQuestId":
        v, bad = _scalar(value)
        return {"breadcrumb_of": v or None}, bad
    if name in _GATES:
        v, bad = _scalar(value)
        return {_GATES[name]: v or None}, bad      # 0 reads as "no gate"
    if name == "requiredRanks":
        if value is _PROXY:
            return {}, True
        rows = value if isinstance(value, list) else []
        pairs = [_pair(p) for p in rows]
        bad = any(p is None for p in pairs)
        # a malformed row still means "ranks are required": keep it as given (the merge only tests presence)
        return {"required_ranks": (list(rows) if bad else pairs) or None}, bad
    if name in ("preQuestGroup", "preQuestSingle", "exclusiveTo"):
        field = {"preQuestGroup": "pre_all", "preQuestSingle": "pre_any", "exclusiveTo": "exclusive_to"}[name]
        v, bad = _flat_ids(value)
        return {field: v}, bad
    if name in ("startedBy", "finishedBy"):
        if value is _PROXY:
            return {}, True
        t = value if isinstance(value, list) else []
        t = t + [None] * (3 - len(t))
        parts = [_flat_ids(t[i]) for i in range(3)]
        bad = any(b for _, b in parts)
        if name == "startedBy":
            return {"starter_npcs": parts[0][0], "starter_objects": parts[1][0],
                    "starter_items": parts[2][0]}, bad
        return {"finisher_npcs": parts[0][0]}, bad
    if name == "objectives":
        if value is _PROXY:
            return {}, True
        t = value if isinstance(value, list) else []
        t = t + [None] * (3 - len(t))
        parts = [_entry_ids(t[i]) for i in range(3)]
        return {"objective_creature_ids": parts[0][0], "objective_object_ids": parts[1][0],
                "objective_item_ids": parts[2][0]}, any(b for _, b in parts)
    return None, False  # not an output field


def _eval_table(data: str, name: str = "questData"):
    lua = lupa.LuaRuntime(register_eval=False, register_builtins=False, unpack_returned_tuples=True)
    loader = lua.eval("load")
    res = loader(data, name, "t", lua.table())  # empty env
    if isinstance(res, tuple):  # load() returned (nil, errmsg)
        raise ValueError(f"{name} failed to compile: {res[1]}")
    return res()


_OUT_FIELDS = (
    "name", "required_level", "quest_level", "race_mask", "class_mask", "starter_npcs",
    "starter_objects", "starter_items", "finisher_npcs", "pre_all", "pre_any", "exclusive_to",
    "breadcrumb_of", "source_item_id", "objective_creature_ids", "objective_object_ids",
    "objective_item_ids", "required_skill", "required_min_rep", "required_max_rep",
    "required_max_level", "required_specialization", "parent_quest", "required_spell",
    "available_until_completed", "available_starting_with", "disabled_by_quest", "required_ranks",
    "next_quest_in_chain", "race_mask_origin")


def _blank(qid):
    q = {f: None for f in _OUT_FIELDS}
    q.update(id=int(qid), repeatable=False, hidden=False)
    return q


def _union_conflict(name, a, b):
    """Union of two faction values for list-of-lists fields, or None if not unionable."""
    if name not in ("startedBy", "finishedBy") or not isinstance(a, list) or not isinstance(b, list):
        return None
    out = []
    for i in range(max(len(a), len(b), 3)):
        parts = [x[i] if isinstance(x, list) and i < len(x) else None for x in (a, b)]
        if any(p is _PROXY or (p is not None and not isinstance(p, list)) for p in parts):
            return None
        ids = {v for p in parts if p for v in p if isinstance(v, int) and not isinstance(v, bool)}
        out.append(sorted(ids) or None)
    while out and out[-1] is None:
        out.pop()
    return out


def _apply_blacklist(sb, path: Path, out: dict, stats: dict) -> set[int]:
    """Run QuestieQuestBlacklist:Load() in the sandbox (its client flags pick the branch).

    `true` entries hide the quest (out[qid]["hidden"]); string entries (HIDE_ON_MAP) only count.
    Returns every hidden id, including ids absent from out (``stats["hidden_not_in_data"]``).
    """
    sb.run(Path(path).read_text(encoding="utf-8"), "QuestieQuestBlacklist")
    bl = sb.module("QuestieQuestBlacklist")
    hidden: set[int] = set()
    for qid, flag in bl.Load(bl).items():
        if flag is True:
            hidden.add(int(qid))
            if int(qid) in out:
                out[int(qid)]["hidden"] = True
        elif isinstance(flag, str) and int(qid) in out:
            stats["hide_on_map"] += 1
    stats["hidden"] = sum(1 for q in out.values() if q["hidden"])
    stats["hidden_not_in_data"] = len(hidden - set(out))
    return hidden


def _friendly(value) -> str | None:
    """Questie friendlyToFaction ("A", "H", "AH", "HA", nil) -> "A" | "H" | "AH" | None."""
    letters = set(value.upper()) & {"A", "H"} if isinstance(value, str) else set()
    return "AH" if letters == {"A", "H"} else (letters.pop() if letters else None)


