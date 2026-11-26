local _, ns = ...; ns.UI = ns.UI or {}; ns.UI.Nav = ns.UI.Nav or {}

-- Show on Map: waypoint plus a focus pin for a quest or a place, then open the
-- world map there. In combat the map waits for PLAYER_REGEN_ENABLED.
local Nav = ns.UI.Nav
local call, method = ns.Util.call, ns.Util.method

local pending -- map to open after combat (the latest request wins)

local function hasPoint(p)
  return type(p) == "table" and p.mapID ~= nil and type(p.x) == "number" and type(p.y) == "number"
end

-- Pure. Returns place { mapID, x, y, label } and kind "giver" | "turnin" |
-- "objective", or nil when the quest or its coordinates are unknown.
function Nav.placeFor(db, questID, state)
  local q = method(db, "quest", questID)
  if type(q) ~= "table" then return nil end
  local entry = type(state) == "table" and type(state.log) == "table" and state.log[questID]
  local chosen, kind
  if not entry then
    chosen, kind = q.giver, "giver"
  elseif entry.complete then
    if q.turnIn then chosen, kind = q.turnIn, "turnin" else chosen, kind = q.giver, "giver" end
  elseif q.points and q.points[1] then
    chosen, kind = q.points[1], "objective"
  elseif q.turnIn then
    chosen, kind = q.turnIn, "turnin"
  else
    chosen, kind = q.giver, "giver"
  end
  if not hasPoint(chosen) then return nil end
  return { mapID = chosen.mapID, x = chosen.x, y = chosen.y, label = q.name }, kind
end

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function doOpen(mapID)
  if type(OpenWorldMap) == "function" then
    call(OpenWorldMap, mapID)
    return
  end
  if type(WorldMapFrame) ~= "table" then return end
  if type(ShowUIPanel) == "function" then
    call(ShowUIPanel, WorldMapFrame)
  else
    method(WorldMapFrame, "Show")
  end
  method(WorldMapFrame, "SetMapID", mapID)
end

function Nav.openMap(mapID)
  if inCombat() then
    if pending == nil then ns.Util.say("The map opens after the fight.") end
    pending = mapID
    return
  end
  doOpen(mapID)
end

ns.Events.on("PLAYER_REGEN_ENABLED", function()
  local id = pending
  pending = nil
  if id ~= nil then Nav.openMap(id) end
end)

local function closeBook()
  if ns.UI.close then ns.UI.close() end
end

-- quest: optional { id, name, level, xp } for the pin's tooltip.
local function pinTo(place, kind, quest)
  local entry = { mapID = place.mapID, x = place.x, y = place.y,
    quests = { quest or { name = place.label } } }
  ns.MapPins.setWaypoint(entry)
  entry.kind = kind == "turnin" and "turnin" or "pickup"
  ns.MapPins.setFocus(entry)
end

function Nav.showPlace(place, label, kind)
  if not hasPoint(place) then return false end
  local p = { mapID = place.mapID, x = place.x, y = place.y, label = label or place.label }
  pinTo(p, kind)
  closeBook()
  Nav.openMap(p.mapID)
  return true
end

function Nav.showQuest(questID)
  local A = ns.Advisor
  local db, last = A and A.db, A and A.last
  local place, kind = Nav.placeFor(db, questID, last and last.state)
  local q = method(db, "quest", questID)
  local name = type(q) == "table" and q.name or ("quest " .. tostring(questID))
  if not place then
    ns.Util.say("No map position known for " .. name .. ".")
    return false
  end
  local tracked = false
  if kind == "objective" and type(C_SuperTrack) == "table" then
    local ok = type(C_SuperTrack.SetSuperTrackedQuestID) == "function"
      and pcall(C_SuperTrack.SetSuperTrackedQuestID, questID)
    if ok then
      ns.Util.say("Tracking " .. name .. " on the map.")
      tracked = true
    end
  end
  if not tracked then
    local quest = { id = questID, name = name, level = q.level, xp = q.xp }
    if kind == "objective" then
      -- no focus pin: a pickup pin for a quest already in the log would be stale
      ns.MapPins.setWaypoint({ mapID = place.mapID, x = place.x, y = place.y, quests = { quest } })
    else
      pinTo(place, kind, quest)
    end
  end
  closeBook()
  Nav.openMap(place.mapID)
  return true
end
