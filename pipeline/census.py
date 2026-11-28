"""Import the in-game census (dev/LevelingAdvisorDiag SavedVariables) into plain Python data.

The file is a WoW SavedVariables dump (`LevelingAdvisorDiagDB = { ... }`). It is run in a fresh
lupa runtime with an empty environment, so it can only assign globals; nothing else is reachable.
"""
from __future__ import annotations

import json
from pathlib import Path

import lupa

_RUN_LUA = """
function(src)
  local env, f, err = {}
  if setfenv then
    f, err = loadstring(src, "census")
    if f then setfenv(f, env) end
  else
    f, err = load(src, "census", "t", env)
  end
  if not f then error(err) end
  f()
  return env.LevelingAdvisorDiagDB
end
"""


def read_census_json(path: Path) -> dict:
    """data/census/maps.json (written by `python -m pipeline census`) ->
    {"maps": {uiMapID (int): map}, "areas": ..., "here": [...]}. ValueError when the file is
    missing, not JSON, or not shaped like a census export."""
    try:
        raw = json.loads(Path(path).read_text(encoding="utf-8"))
        maps = {int(k): v for k, v in (raw.get("maps") or {}).items()}
        return {"maps": maps, "areas": raw.get("areas") or {}, "here": list(raw.get("here") or [])}
    except (OSError, ValueError, AttributeError, TypeError) as e:
        raise ValueError(f"unreadable census {path}: {e}") from e


def _plain(v):
    """Lua value -> Python: tables become dict (or list for 1..n arrays), whole floats ints."""
    if lupa.lua_type(v) == "table":
        items = {_plain(k): _plain(x) for k, x in v.items()}
        n = len(items)
        if n and all(isinstance(k, int) for k in items) and set(items) == set(range(1, n + 1)):
            return [items[i] for i in range(1, n + 1)]
        return items
    if isinstance(v, float) and v.is_integer():
        return int(v)
    if isinstance(v, bytes):
        return v.decode("utf-8")
    return v


def _list(v):
    return list(v) if v else None


def load_census(saved_variables: Path) -> dict:
    """{"maps": {mapID: {name, mapType, parent, yards, continent, rect}}, "areas": {id: name}, "here": [...]}."""
    src = Path(saved_variables).read_text(encoding="utf-8")
    lua = lupa.LuaRuntime(register_eval=False, register_builtins=False)
    try:
        db = lua.eval(_RUN_LUA)(src)
    except lupa.LuaError as e:
        raise ValueError(f"cannot run {saved_variables}: {e}") from e
    if lupa.lua_type(db) != "table":
        raise ValueError(f"{saved_variables} does not define LevelingAdvisorDiagDB")
    db = _plain(db)
    raw_maps = (db.get("census") or {}).get("maps")
    if isinstance(raw_maps, list):   # a dense 1..n table, see areas below
        raw_maps = dict(enumerate(raw_maps, 1))
    if not isinstance(raw_maps, dict) or not raw_maps:
        raise ValueError(f"{saved_variables} has no census.maps (run the census in-game first)")
    maps = {}
    for map_id, m in raw_maps.items():
        maps[int(map_id)] = {
            "name": m.get("name"), "mapType": m.get("mapType"), "parent": m.get("parentMapID"),
            "yards": _list(m.get("yards")), "continent": m.get("continentID"), "rect": _list(m.get("rect")),
        }
    areas = db.get("areas") or {}
    if isinstance(areas, list):   # _plain turns a dense 1..n table into a list; restore the ids
        areas = dict(enumerate(areas, 1))
    areas = {int(k): v for k, v in areas.items()}
    here = db.get("here")
    here = list(here.values()) if isinstance(here, dict) else list(here or [])
    return {"maps": maps, "areas": areas, "here": here}
