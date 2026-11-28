local _, ns = ...; ns.UI = ns.UI or {}; ns.UI.Guide = ns.UI.Guide or {}

-- The guide: keeps the game's user waypoint on the next step of the top
-- recommended zone's route. The route is the book's own (Advisor.plan +
-- UI.Model.route), so the book and the guide always agree.
--   * On each advisor result it sets the waypoint (MapPins.setWaypoint, quiet)
--     when the target changes; in combat it waits for PLAYER_REGEN_ENABLED.
--   * It never fights the player: when they remove its waypoint or another one
--     is set (their own, or Show on Map), it pauses until continue() and says so
--     once in chat. A waypoint the game clears because the player arrived at it
--     is not a removal.
--   * It also pauses when the player super-tracks a quest (the quest arrow),
--     but not for the game's own auto-tracking right after a quest is accepted,
--     turned in or removed, or after a loading screen (AUTO_TRACK_S).
--   * Off removes its own waypoint and gives the game's waypoint pin back
--     (MapPins.releaseOurs); a pause keeps the current waypoint as it is.
--   * While it runs it asks the advisor for a result (which the book only
--     computes while it is open) when the target's quest action is done, on a
--     level up, at login and on resume, so it moves on with the book closed.
--   * A waypoint the player reached (the game clears it on arrival) is not set
--     again for the same target, not even after a /reload.
-- On/off is the per-character setting "guide" (Core/Settings.lua keeps it in
-- LevelingAdvisorCharDB.settings). The pause, the guide's last waypoint and
-- the reached target live in LevelingAdvisorCharDB.guideState, made on the
-- first write.
-- Every client API is optional: a missing one never errors.
local Guide = ns.UI.Guide
local call, method = ns.Util.call, ns.Util.method

Guide.ARRIVAL_YARDS = 40 -- a waypoint cleared this close to the player was reached
Guide.MAX_ASKS = 2 -- results asked for one target, so a disagreement never loops
-- Seconds after these events in which SUPER_TRACKING_CHANGED is the game's own
-- auto-tracking, not the player's choice.
Guide.AUTO_TRACK_S = { QUEST_ACCEPTED = 2, QUEST_TURNED_IN = 2, QUEST_REMOVED = 2, PLAYER_ENTERING_WORLD = 5 }

local WHAT = { pickup = "pick up", objective = "objectives", turnin = "turn in" }

local listeners = {}
local lastKey -- the target set last (per session: a reload sets it again unless the player reached it)
local current -- the target of the last result (QUEST_LOG_UPDATE checks it)
local asked = 0 -- results asked for that target
local pending, pendingForce = false, false -- an update waiting for the end of combat
local failed = false -- the last set did not take (shown by /advisor debug)
local autoTrackUntil -- GetTime() up to which a super-tracked quest is the game's doing

local inCombat = ns.Util.inCombat

local function notify(reason)
  for i = 1, #listeners do
    local ok, err = pcall(listeners[i], reason)
    if not ok then geterrorhandler()(err) end
  end
end

-- fn(reason): reason is "enabled" (on or off), "paused" (paused or resumed) or
-- "target" (a new waypoint was set).
function Guide.onChange(fn)
  listeners[#listeners + 1] = fn
end

-- LevelingAdvisorCharDB.guideState = { paused, why, spot, reached }, or nil.
local function saved(create)
  local c = ns.chardb
  if type(c) ~= "table" then return nil end
  if type(c.guideState) ~= "table" then
    if not create then return nil end
    c.guideState = {}
  end
  return c.guideState
end

function Guide.enabled() return ns.Settings.get("guide") == true end

function Guide.paused()
  local s = saved(false)
  return s ~= nil and s.paused == true
end

local function active() return Guide.enabled() and not Guide.paused() end

-- The waypoint the guide set last ({ mapID, x, y }, 0-100), kept across reloads.
local function spot()
  local s = saved(false)
  return s and s.spot or nil
end

local function setSpot(p)
  local s = saved(p ~= nil)
  if s then s.spot = p and { mapID = p.mapID, x = p.x, y = p.y } or nil end
end

-- The key of the target whose waypoint the player reached, kept across reloads
-- until the target changes.
local function reached()
  local s = saved(false)
  return s and s.reached or nil
end

local function setReached(key)
  local s = saved(key ~= nil)
  if s then s.reached = key end
end

-- why: "removed", "replaced" or "tracking" (a quest). A new pause says so in chat once (a pause kept
-- from an earlier session does not).
local function setPaused(on, why)
  local s = saved(on)
  if not s or (s.paused == true) == on then return end
  s.paused = on or nil
  s.why = on and why or nil
  if on then
    pending, pendingForce = false, false
    setSpot(nil)
    ns.Util.say("guide paused — click Resume guide to continue.")
  end
  notify("paused")
end

---------------------------------------------------------------------------
-- The target.
---------------------------------------------------------------------------
local function hasPoint(p)
  return type(p) == "table" and p.mapID ~= nil and type(p.x) == "number" and type(p.y) == "number"
end

-- The first action of a plan step that is neither done nor ruled out.
local function firstOpen(step, state, db)
  local A = ns.Advisor
  local actions = type(step) == "table" and step.actions or {}
  for _, a in ipairs(actions) do
    if not A.actionDone(a[1], a[2], state) and not A.questDropped(db, a[1], state) then
      return a[1], a[2]
    end
  end
  if actions[1] then return actions[1][1], actions[1][2] end
end

local function findTarget()
  local A = ns.Advisor
  local last = A and A.last
  local zones = last and type(last.rec) == "table" and last.rec.zones
  local top = type(zones) == "table" and zones[1]
  if not (type(top) == "table" and top.mapID ~= nil) then return nil end
  local plan = A.plan(top.mapID)
  local route = ns.UI.Model.route(plan, last.state, A.db)
  local i = route and route.current
  local step = i and route.steps[i]
  if not (step and hasPoint(step.place)) then return nil end
  local questID, kind = firstOpen(plan.steps[i], last.state, A.db)
  local label
  for _, q in ipairs(step.quests or {}) do
    if q.questID == questID then label = q.name end
  end
  return { mapID = step.place.mapID, x = step.place.x, y = step.place.y,
    questID = questID, kind = kind, label = label or step.title }
end

-- The next step of the top zone's route: { mapID, x, y, questID, kind, label }
-- (kind "pickup" | "objective" | "turnin"), or nil when there is none.
function Guide.target()
  local ok, t = pcall(findTarget)
  if not ok then
    geterrorhandler()(t)
    return nil
  end
  return t
end

local function keyOf(t)
  if not t then return nil end
  return string.format("%s|%.1f|%.1f|%s|%s", tostring(t.mapID), t.x, t.y, tostring(t.questID), tostring(t.kind))
end

---------------------------------------------------------------------------
-- The waypoint.
---------------------------------------------------------------------------
-- Whose the user waypoint is: "guide", "other" (the player's, or a Show on Map
-- one), "none", or nil when the client cannot tell.
local function owner()
  local has = ns.MapPins.hasUserWaypoint()
  if has == nil then return nil end
  if not has then return "none" end
  return ns.MapPins.isWaypointAt(spot()) and "guide" or "other"
end

-- Whether the player stands within ARRIVAL_YARDS of p (a cleared waypoint was reached).
local function arrived(p)
  local db = ns.Advisor and ns.Advisor.db
  if not db or type(C_Map) ~= "table" then return false end
  local px, py = method(call(C_Map.GetPlayerMapPosition, p.mapID, "player"), "GetXY")
  if type(px) ~= "number" or type(py) ~= "number" then return false end
  local yards = call(ns.Geo.distance, db, { mapID = p.mapID, x = px * 100, y = py * 100 }, p)
  return type(yards) == "number" and yards <= Guide.ARRIVAL_YARDS
end

-- The client took the waypoint: it reads back at t (taken on trust when the
-- client cannot read it). A set it silently ignored would pause the guide later.
local function taken(t)
  if ns.MapPins.hasUserWaypoint() == nil then return true end
  return ns.MapPins.isWaypointAt(t)
end

local placing = false -- inside place(): its own super-tracking is no player choice

local function place(t)
  local previous = spot()
  -- before the call: the client may report the new waypoint from inside it
  setSpot(t)
  local entry = { mapID = t.mapID, x = t.x, y = t.y, quests = { { id = t.questID, name = t.label } } }
  placing = true
  local ok, set = pcall(ns.MapPins.setWaypoint, entry, { quiet = true })
  placing = false
  if not ok then error(set, 0) end
  if set and taken(t) then
    lastKey, failed = keyOf(t), false
    setReached(nil)
    notify("target")
    return true
  end
  setSpot(previous)
  failed = true
  return false
end

-- Returns a status ("set", "same", "none", "paused", "combat", "off", "failed")
-- and the target. force (continue, turning it on): set even for the same target
-- and over another waypoint.
local function update(force)
  if not Guide.enabled() then return "off" end
  if Guide.paused() and not force then return "paused" end
  if inCombat() then
    pending = true
    pendingForce = pendingForce or force == true
    return "combat"
  end
  local t = Guide.target()
  local key = keyOf(t)
  if key ~= keyOf(current) then asked = 0 end
  current = t
  if not t then return "none" end
  if not force then
    if key == lastKey then return "same", t end
    if key == reached() then return "same", t end
    setReached(nil) -- the target moved on from the reached one
    -- never replaces a waypoint the player placed (a missed USER_WAYPOINT_UPDATED)
    if owner() == "other" then
      setPaused(true, "replaced")
      return "paused", t
    end
  end
  return place(t) and "set" or "failed", t
end

-- A result even while the book is closed (the scheduler's "open" request).
-- Returns true when this ask armed the scheduler (or, in combat, queued the
-- compute for the end of the fight); false when a compute was already on its
-- way or queued (this ask joins it) or there is no scheduler.
local function askResult()
  local s = ns.Advisor and ns.Advisor.scheduler
  if not s then return false end
  local joined = s.armed == true or (s.pending == true and inCombat())
  pcall(s.request, s, "open")
  return not joined
end

-- Sets the current target at once, and asks for a fresh result: the last one
-- may be older than the quest log (the book computes only while it is open),
-- and the new result moves the waypoint on from a step done since.
local function resume()
  setPaused(false)
  lastKey = nil
  local status, t = update(true)
  askResult()
  return status, t
end

-- "Resume guide": clears the pause and sets the current target at
-- once (after the fight in combat), even over the player's own waypoint.
-- Returns the status ("set", "combat", "none", "off", "failed") and the target.
function Guide.continue()
  if not Guide.enabled() then return "off" end
  return resume()
end

-- Off stops the guide and removes its own waypoint (another one stays); on
-- resumes it. The settings checkbox, the slash command, the minimap menu and
-- the book all end up here or in the Settings.onChange listener below.
function Guide.setEnabled(on)
  ns.Settings.set("guide", on and true or false)
end

-- "Guide: On", "Guide: Paused" or "Guide: Off" (the book's toggle and the minimap menu).
function Guide.label()
  if not Guide.enabled() then return "Guide: Off" end
  return Guide.paused() and "Guide: Paused" or "Guide: On"
end

---------------------------------------------------------------------------
-- Text for /advisor guide and /advisor debug.
---------------------------------------------------------------------------
function Guide.describe()
  if not Guide.enabled() then return "Guide: off. Type /advisor guide on to turn it on." end
  if Guide.paused() then
    local s = saved(false) or {}
    local why = { removed = "you removed its waypoint", tracking = "you are tracking a quest" }
    return "Guide: paused — " .. (why[s.why] or "another waypoint was set")
      .. ". Type /advisor guide resume to continue."
  end
  local t = Guide.target()
  if not t then return "Guide: on — no next step right now." end
  local zone = ns.UI.QuestInfo.zoneName(ns.Advisor.db, t.mapID) or ("map " .. tostring(t.mapID))
  return string.format("Guide: on — next: %s (%s), %s %s.", tostring(t.label),
    WHAT[t.kind] or tostring(t.kind), zone, ns.UI.Style.coords(t.x, t.y))
end

function Guide.debugLine()
  local s = saved(false) or {}
  local t = Guide.target()
  local where = t and string.format("%s %s %s %.1f,%.1f", tostring(t.questID), tostring(t.kind),
    tostring(t.mapID), t.x, t.y) or "none"
  return string.format("guide: %s, %s, target %s, waypoint %s%s%s",
    Guide.enabled() and "on" or "off",
    s.paused and ("paused (" .. (s.why == "tracking" and "you are tracking a quest" or tostring(s.why)) .. ")") or "not paused",
    where, owner() or "unknown",
    pending and ", waiting for the end of combat" or "",
    failed and ", the last waypoint did not take" or "")
end

---------------------------------------------------------------------------
-- Wiring.
---------------------------------------------------------------------------
-- The player removed the guide's waypoint or placed another one: pause. Only
-- once the guide set a waypoint this session: the login-time update (the game
-- restoring its waypoint, or not) is no removal.
local function onWaypointUpdated()
  if not active() or lastKey == nil then return end
  local p = spot()
  if not p then return end -- the guide has set none
  local who = owner()
  if who == nil or who == "guide" then return end
  if who == "none" and arrived(p) then
    setSpot(nil)
    setReached(lastKey)
    return
  end
  setPaused(true, who == "none" and "removed" or "replaced")
end

local function now()
  local t = call(GetTime)
  return type(t) == "number" and t or nil
end

-- One of the AUTO_TRACK_S events: the game may super-track a quest by itself
-- for that many seconds. A later window never shortens an earlier, longer one.
local function autoTracking(seconds)
  local t = now()
  if t and (autoTrackUntil == nil or t + seconds > autoTrackUntil) then autoTrackUntil = t + seconds end
end

-- The player super-tracks a quest (the game's quest arrow, or Show on Map for
-- a quest in progress): the arrow is theirs now, so the guide pauses. Our own
-- waypoint fires the same event but super-tracks the waypoint (quest ID 0), and
-- `placing` covers the calls inside place() anyway. Inside an auto-track window
-- the game did it, not the player. Without GetTime there is no window.
local function onSuperTracking()
  if placing or not active() then return end
  local t = autoTrackUntil and now()
  if t and t <= autoTrackUntil then return end
  local ST = type(C_SuperTrack) == "table" and C_SuperTrack or nil
  if not ST or type(ST.GetSuperTrackedQuestID) ~= "function" then return end
  local ok, id = pcall(ST.GetSuperTrackedQuestID)
  if ok and type(id) == "number" and id > 0 then setPaused(true, "tracking") end
end

-- Off: clears the user waypoint while it is still the one the guide set (a
-- paused guide has none: its spot is cleared on pause), then releases
-- MapPins' claim, so a waypoint left behind shows the game's pin again and the
-- player can remove it. Fail-soft without C_Map.ClearUserWaypoint.
local function stop()
  pending, pendingForce = false, false
  lastKey, failed, current, asked = nil, false, nil, 0
  local p = spot()
  if p and ns.MapPins.isWaypointAt(p) and type(C_Map) == "table"
      and type(C_Map.ClearUserWaypoint) == "function" and pcall(C_Map.ClearUserWaypoint) then
    setSpot(nil)
  end
  ns.MapPins.releaseOurs()
end

-- Whether the target's quest action looks done in the live quest log.
local function liveDone(t)
  local Q = C_QuestLog
  if type(Q) ~= "table" or t.questID == nil then return false end
  if call(Q.IsQuestFlaggedCompleted, t.questID) then return true end
  if t.kind == "pickup" then
    local i = call(Q.GetLogIndexForQuestID, t.questID)
    return type(i) == "number" and i > 0
  end
  if t.kind == "objective" then return call(Q.IsComplete, t.questID) == true end
  return false
end

-- An ask counts towards MAX_ASKS only when it armed the scheduler (or queued the
-- compute in combat): a burst of QUEST_LOG_UPDATE in one debounce window, or in
-- one fight, is one compute, so one ask.
local function onQuestLog()
  if not (active() and current) or asked >= Guide.MAX_ASKS then return end
  if liveDone(current) and askResult() then asked = asked + 1 end
end

ns.Advisor.onUpdate(function() update(false) end)

ns.Settings.onChange(function(key, value)
  if key ~= "guide" then return end
  if value then
    resume()
  else
    stop()
  end
  notify("enabled")
end)

ns.Events.on("USER_WAYPOINT_UPDATED", onWaypointUpdated)
ns.Events.on("SUPER_TRACKING_CHANGED", onSuperTracking)
for event, seconds in pairs(Guide.AUTO_TRACK_S) do
  ns.Events.on(event, function() autoTracking(seconds) end)
end
ns.Events.on("QUEST_LOG_UPDATE", onQuestLog)
ns.Events.on("PLAYER_LEVEL_UP", function()
  if active() then askResult() end
end)
ns.Events.on("PLAYER_REGEN_ENABLED", function()
  if not pending then return end
  local force = pendingForce
  pending, pendingForce = false, false
  update(force)
end)

ns.Init.onReady(function()
  if active() then askResult() end
end)
