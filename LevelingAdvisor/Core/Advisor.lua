local _, ns = ...

-- Glue between the adapter, the scheduler and the pure engine.
local Advisor = {}
ns.Advisor = Advisor

local listeners = {}
local windowShown = false
local mapShown = false
local inited = false

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function now()
  if type(debugprofilestop) == "function" then return debugprofilestop() end
  return nil
end

function Advisor.onUpdate(fn)
  listeners[#listeners + 1] = fn
end

function Advisor.isShown() return windowShown end

-- Plan 4b's window calls this when it opens or closes.
function Advisor.setWindowShown(shown)
  windowShown = shown and true or false
  if windowShown and Advisor.scheduler then Advisor.scheduler:onShow() end
end

-- The world map counts like the window: computes are allowed while it is open
-- (UI/MapPins.lua calls this from the map's OnShow / OnHide).
function Advisor.setMapShown(shown)
  mapShown = shown and true or false
  if mapShown and Advisor.scheduler then Advisor.scheduler:onShow() end
end

local function computeAllowed() return windowShown or mapShown end

function Advisor.compute()
  if not Advisor.db then return nil, "no-data" end
  Advisor.computes = (Advisor.computes or 0) + 1
  local api = Advisor.api or ns.Adapter.realApi()
  local t0 = now()
  local state = ns.Adapter.snapshot(api, ns.db, ns.chardb)
  local rec = ns.Engine.compute(Advisor.db, state)
  local t1 = now()
  Advisor.last = { state = state, rec = rec, ms = (t0 and t1) and (t1 - t0) or nil }
  for i = 1, #listeners do
    local ok, err = pcall(listeners[i], rec, Advisor.last)
    if not ok then geterrorhandler()(err) end
  end
  return rec
end

function Advisor.route(mapID)
  if inCombat() then return nil end
  local last = Advisor.last
  if not (Advisor.db and last) then return nil end
  local clock = type(debugprofilestop) == "function" and debugprofilestop or nil
  return ns.Engine.route(Advisor.db, last.state, mapID, last.rec, clock)
end

-- Whether one route action is already done in `state` (pure; nil-safe).
function Advisor.actionDone(questID, kind, state)
  if type(state) ~= "table" then return false end
  local completed, log = state.completed, state.log
  if type(completed) == "table" and completed[questID] then return true end
  local entry = type(log) == "table" and log[questID] or nil
  if kind == "pickup" then return entry ~= nil end
  if kind == "objective" then return type(entry) == "table" and entry.complete and true or false end
  return false
end

-- One frozen route plan per zone, shared by the zone page and the map pins.
local plans = {}

local function planKey(last)
  local state, rec = last.state or {}, last.rec or {}
  local settings = state.settings or {}
  local ignored = 0
  for _ in pairs(state.ignored or {}) do ignored = ignored + 1 end
  return table.concat({ tostring(state.level), tostring(settings.elite), tostring(settings.dungeons),
    ignored, rec.dungeon and rec.dungeon.key or "-" }, "|")
end

local function allDone(plan, state)
  if #plan.steps == 0 then return false end
  for _, step in ipairs(plan.steps) do
    for _, a in ipairs(step.actions or {}) do
      if not Advisor.actionDone(a[1], a[2], state) then return false end
    end
  end
  return true
end

-- plan = { mapID, steps, key }. Kept while the key matches and some step is
-- open; replanned otherwise. In combat (or without a route) the stale plan
-- stays.
function Advisor.plan(mapID)
  local last = Advisor.last
  if not last then return nil end
  local plan = plans[mapID]
  if plan and plan.key == planKey(last) then
    -- an all-done plan is rebuilt once per advisor result, not on every call
    if not allDone(plan, last.state) or plan.last == last then return plan end
  end
  local steps = Advisor.route(mapID)
  if steps == nil then return plan end
  plan = { mapID = mapID, steps = steps, key = planKey(last), last = last }
  plans[mapID] = plan
  return plan
end

function Advisor.replan(mapID)
  if mapID == nil then plans = {} else plans[mapID] = nil end
end

-- deps (optional, for tests): api, after, inCombat
function Advisor.init(deps)
  if inited then return end
  inited = true
  deps = deps or {}
  Advisor.api = deps.api

  local data = ns.Data
  if type(data) == "table" and type(data.quests) == "table" and next(data.quests) ~= nil then
    local ok, res = pcall(ns.DB.new, data)
    if ok then
      Advisor.db = res
    else
      Advisor.loadError = tostring(res)
    end
  end

  local after = deps.after or function(...) return C_Timer.After(...) end
  Advisor.scheduler = ns.Scheduler.new({
    after = after,
    inCombat = deps.inCombat or inCombat,
    isShown = computeAllowed,
    run = Advisor.compute,
  })

  local function request(reason)
    return function() Advisor.scheduler:request(reason) end
  end
  for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED" }) do
    ns.Events.on(e, request("quest"))
  end
  ns.Events.on("PLAYER_LEVEL_UP", request("level"))
  ns.Events.on("ZONE_CHANGED_NEW_AREA", request("zone"))
  ns.Events.on("PLAYER_REGEN_ENABLED", function() Advisor.scheduler:onCombatEnd() end)
  ns.Settings.onChange(request("settings"))

  -- Local quest recorder (in addition to the scheduler wiring above).
  local rec = ns.Recorder.new(ns.db.recorder, deps.recorderApi or ns.Recorder.realApi())
  Advisor.recorder = rec
  ns.Events.on("QUEST_DETAIL", function() rec:onDetail() end)
  ns.Events.on("GOSSIP_SHOW", function() rec:onGossip() end)
  ns.Events.on("QUEST_GREETING", function() rec:onGreeting() end)
  ns.Events.on("QUEST_COMPLETE", function() rec:onComplete() end)
  ns.Events.on("QUEST_TURNED_IN", function(questID, xpReward) rec:onTurnedIn(questID, xpReward) end)
  ns.Events.on("QUEST_ACCEPTED", function(a, b) rec:onAccepted(a, b) end)
end

---------------------------------------------------------------------------
-- Chat summary (pure).
---------------------------------------------------------------------------
local function plural(n, word)
  return n .. " " .. word .. (n == 1 and "" or "s")
end

function Advisor.summaryLines(rec, db)
  local lines = {}
  if not rec then return lines end
  local zones = rec.zones or {}
  if #zones > 0 then
    lines[#lines + 1] = "Zones:"
    for i, z in ipairs(zones) do
      lines[#lines + 1] = string.format("  %d. %s (%d–%d) — %s, ~%d XP — %s",
        i, tostring(z.name), z.minLevel or 0, z.maxLevel or 0,
        plural(z.questCount or 0, "quest"), math.floor((z.xp or 0) + 0.5), tostring(z.reason))
    end
  end
  local d = rec.dungeon
  if d then
    lines[#lines + 1] = string.format("Dungeon: %s (%d–%d) — %s",
      tostring(d.name), d.minLevel or 0, d.maxLevel or 0, tostring(d.reason))
  end
  for _, s in ipairs(rec.sections or {}) do
    local rows = s.rows or {}
    lines[#lines + 1] = string.format("%s (%d):", tostring(s.title), #rows)
    for _, r in ipairs(rows) do
      local line = string.format("  [%s] %s", tostring(r.level), tostring(r.name))
      if r.yards then line = line .. " — " .. math.floor(r.yards + 0.5) .. " yd" end
      if r.soon then line = line .. " (soon)" end
      if r.state == "complete" then line = line .. " (ready)" end
      lines[#lines + 1] = line
    end
  end
  return lines
end
