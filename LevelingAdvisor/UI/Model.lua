local _, ns = ...; ns.UI = ns.UI or {}; ns.UI.Model = ns.UI.Model or {}
local Model = ns.UI.Model
local Style = ns.UI.Style

-- Pure view models for the book. No widgets, no client calls.

local function statsLine(questCount, xp, chains)
  local s = Style.plural(questCount or 0, "quest") .. " for you · ~" .. Style.number(xp or 0) .. " XP"
  if (chains or 0) > 0 then s = s .. " · " .. Style.plural(chains, "chain") end
  return s
end

-- The character line, up to three zone cards and the dungeon card of the main
-- page's left side. `info` is UI.playerInfo(): { name, race, className,
-- rested, zoneName }.
function Model.left(rec, state, db, info)
  rec, state, info = rec or {}, state or {}, info or {}
  local zone = db and db:zone(state.mapID)
  local zoneName = type(zone) == "table" and zone.name or info.zoneName

  local who = {}
  if info.name then who[#who + 1] = info.name end
  local kind = {}
  if info.race then kind[#kind + 1] = info.race end
  if info.className then kind[#kind + 1] = info.className end
  if #kind > 0 then who[#who + 1] = table.concat(kind, " ") end
  if zoneName then who[#who + 1] = zoneName end

  local xp, xpMax = tonumber(state.xp) or 0, tonumber(state.xpMax) or 0
  local right = "Level " .. tostring(state.level or "?")
  if xpMax > 0 then right = right .. " · " .. math.floor(xp / xpMax * 100) .. "%" end

  local left = {
    char = { left = table.concat(who, " · "), right = right, xp = xp, xpMax = xpMax, rested = tonumber(info.rested) or 0 },
    zones = {},
  }
  for i, z in ipairs(rec.zones or {}) do
    left.zones[i] = {
      mapID = z.mapID, name = z.name, levels = Style.levels(z.minLevel, z.maxLevel),
      stats = statsLine(z.questCount, z.xp, z.chains), reason = z.reason, isHere = z.isHere and true or false,
    }
  end
  local d = rec.dungeon
  if d then
    left.dungeon = {
      key = d.key, name = d.name, levels = Style.levels(d.minLevel, d.maxLevel),
      group = Style.number(d.groupSize or 5) .. " players",
      stats = statsLine(d.questCount, d.xp, 0), reason = d.reason,
      artMapID = d.entrance and d.entrance.mapID,
    }
  end
  return left
end

local EMPTY_TEXT = "Nothing to do right here. Pick one of the recommended zones."

-- The right page's list elements: a header per section, then its quest rows
-- unless the section is collapsed (`collapsed[key]`).
function Model.questList(rec, collapsed)
  collapsed = collapsed or {}
  local out = {}
  for _, s in ipairs(rec and rec.sections or {}) do
    local closed = collapsed[s.key] and true or false
    out[#out + 1] = { kind = "header", key = s.key, title = s.title, count = #s.rows,
      collapsed = closed, height = 26 }
    if not closed then
      for _, row in ipairs(s.rows) do
        out[#out + 1] = { kind = "quest", row = row, sectionKey = s.key, height = 44 }
      end
    end
  end
  if #out == 0 then out[1] = { kind = "text", text = EMPTY_TEXT, height = 40 } end
  return out
end

---------------------------------------------------------------------------
-- The zone route (page left of the zone view).
---------------------------------------------------------------------------
local WHAT = { pickup = "pick up", objective = "objectives", turnin = "turn in" }
local KIND_ORDER = { "pickup", "objective", "turnin" }
local SUB_PARTS = { { "pickup", "Pick up" }, { "objective", "Objectives" }, { "turnin", "Turn in" } }

local function actionDone(id, kind, state)
  local A = ns.Advisor
  return A and A.actionDone and A.actionDone(id, kind, state) or false
end

local function liveState(id, state)
  local log = type(state.log) == "table" and state.log[id] or nil
  if type(state.completed) == "table" and state.completed[id] then return "done" end
  if type(log) == "table" and log.complete then return "complete" end
  if log then return "progress" end
  return "available"
end

local function stepTitle(step, db, zoneName)
  local coords = Style.coords(step.x, step.y)
  local npcName
  for _, a in ipairs(step.actions or {}) do
    if not npcName and (a[2] == "pickup" or a[2] == "turnin") then
      local q = db and db:quest(a[1])
      local place = type(q) == "table" and (a[2] == "pickup" and q.giver or q.turnIn) or nil
      npcName = ns.UI.QuestInfo.npcName(db, place)
    end
  end
  if npcName then return npcName end
  if (step.counts and (step.counts.pickup or 0) + (step.counts.turnin or 0) or 0) == 0 then
    return "Objectives near " .. coords
  end
  return zoneName .. " " .. coords
end

local function stepSub(step)
  local parts = {}
  for _, p in ipairs(SUB_PARTS) do
    local n = step.counts and step.counts[p[1]] or 0
    if n > 0 then parts[#parts + 1] = p[2] .. " " .. n end
  end
  if (step.xp or 0) > 0 then parts[#parts + 1] = "~" .. Style.number(step.xp) .. " XP" end
  return table.concat(parts, " · ")
end

-- plan: Advisor.plan(mapID); nil for a nil plan.
function Model.route(plan, state, db, selectedID)
  if type(plan) ~= "table" then return nil end
  state = state or {}
  local zone = db and db:zone(plan.mapID)
  local zoneName = type(zone) == "table" and zone.name or "Zone"
  local out = { steps = {} }
  local leftQuests = {}
  local current
  for i, step in ipairs(plan.steps or {}) do
    local quests, byID = {}, {}
    local stepDone = true
    for _, a in ipairs(step.actions or {}) do
      local id, kind = a[1], a[2]
      local line = byID[id]
      if not line then
        local q = db and db:quest(id)
        line = { questID = id, name = type(q) == "table" and q.name or ("Quest " .. tostring(id)),
          kinds = {}, state = liveState(id, state), done = true, selected = id == selectedID }
        byID[id] = line
        quests[#quests + 1] = line
      end
      line.kinds[kind] = true
      if not actionDone(id, kind, state) then
        line.done = false
        stepDone = false
        leftQuests[id] = true
      end
    end
    for _, line in ipairs(quests) do
      local w = {}
      for _, k in ipairs(KIND_ORDER) do
        if line.kinds[k] then w[#w + 1] = WHAT[k] end
      end
      line.what = table.concat(w, ", ")
      line.kinds = nil
    end
    if not stepDone and not current then current = i end
    out.steps[i] = { index = i, title = stepTitle(step, db, zoneName), sub = stepSub(step),
      done = stepDone, current = false, quests = quests,
      place = { mapID = step.mapID, x = step.x, y = step.y } }
  end
  if current then out.steps[current].current = true end
  out.current = current
  local n = 0
  for _ in pairs(leftQuests) do n = n + 1 end
  local levels = type(zone) == "table" and zone.minLevel and zone.maxLevel
    and Style.levels(zone.minLevel, zone.maxLevel) or nil
  out.header = zoneName .. (levels and (" · " .. levels) or "") .. " · " .. Style.plural(n, "quest") .. " left"
  if #out.steps == 0 then
    out.progress = "Nothing to do here right now."
  elseif current then
    out.progress = "Your route · step " .. current .. " of " .. #out.steps
  else
    out.progress = "Your route is done."
  end
  return out
end

---------------------------------------------------------------------------
-- The dungeon page ("Before You Go" route).
---------------------------------------------------------------------------
-- d: rec.dungeon; nil without one. Quests come from the data's dungeon record.
function Model.dungeon(d, state, db)
  if type(d) ~= "table" then return nil end
  state = state or {}
  local QI = ns.UI.QuestInfo
  local steps, done = {}, 0
  local current
  for i, p in ipairs(d.pickups or {}) do
    local q = db and db:quest(p.questID)
    local name = type(q) == "table" and q.name or ("Quest " .. tostring(p.questID))
    local zone = QI.zoneName(db, p.mapID)
    local isDone = actionDone(p.questID, "pickup", state)
    local sub
    if isDone then
      sub = "In your quest log"
      done = done + 1
    else
      sub = type(q) == "table" and QI.npcName(db, q.giver) or "Not picked up yet"
    end
    if not isDone and not current then current = i end
    steps[i] = { index = i, title = zone and (zone .. " — " .. name) or name, sub = sub, done = isDone,
      current = false,
      quests = { { questID = p.questID, name = name, what = WHAT.pickup, state = liveState(p.questID, state),
        done = isDone } },
      place = { mapID = p.mapID, x = p.x, y = p.y } }
  end
  local e = d.entrance or {}
  local coords = Style.coords(e.x, e.y)
  local zoneName = QI.zoneName(db, e.mapID)
  local place = { mapID = e.mapID, x = e.x, y = e.y }
  local n = #steps + 1
  steps[n] = { index = n, title = "Dungeon entrance" .. (zoneName and (" — " .. zoneName) or ""),
    sub = coords, done = false, current = current == nil, entrance = true, quests = {}, place = place }
  if current then steps[current].current = true end

  local entry = db and db:dungeon(d.key)
  return {
    title = d.name,
    header = "Before You Go · pick these up first",
    progress = done .. " of " .. #(d.pickups or {}) .. " done",
    steps = steps,
    info = {
      meta = "Level " .. Style.levels(d.minLevel, d.maxLevel) .. " · " .. Style.plural(d.groupSize or 5, "player")
        .. " · " .. Style.plural(d.questCount or 0, "quest") .. " · ~" .. Style.number(d.xp or 0) .. " XP from quests",
      why = d.reason,
      entrance = (zoneName and (zoneName .. " ") or "") .. coords,
      place = place,
    },
    quests = type(entry) == "table" and entry.quests or {},
  }
end
