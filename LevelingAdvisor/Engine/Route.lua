local _, ns = ...

-- Greedy zone route: an ordered list of hub stops (steps). Pure Lua.
-- The result is then improved by RouteImprove unless opts.improve == false.
-- It visits only quests the engine recommends (Candidates.recommendable:
-- yellow and green quests, plus turn-ins at any colour); chain follow-ups it
-- adds must fit the player's level too.
local Route = {}
ns.Route = Route

local function copyState(state, completed)
  local out = {}
  for k, v in pairs(state) do out[k] = v end
  out.completed = completed
  return out
end

local function onMap(p, mapID)
  if p and p.mapID == mapID and p.x and p.y then return p end
  return nil
end

-- Route entry for one quest, or nil when it has nothing to do on this map.
-- Fields: quest, status, pickup (point), objectives (on-map points),
-- turnin (point), deps (chain-extended only).
local function makeEntry(q, status, mapID, dungeonKey)
  local e = { quest = q, status = status, objectives = {} }
  if q.dungeonQuest then
    if status ~= "eligible" or dungeonKey == nil or q.dungeonKey ~= dungeonKey then
      return nil
    end
    e.pickup = onMap(q.giver, mapID)
    return e.pickup and e or nil
  end
  if status == "eligible" then
    -- a quest we cannot pick up on this map cannot be worked on from here
    e.pickup = onMap(q.giver, mapID)
    if not e.pickup then return nil end
  end
  local points = q.points or {}
  local offMap = false
  for _, p in ipairs(points) do
    local mp = onMap(p, mapID)
    if mp then e.objectives[#e.objectives + 1] = mp else offMap = true end
  end
  if status == "complete" then
    e.turnin = onMap(q.turnIn or q.giver, mapID)
  elseif not offMap and (#points > 0 or status == "eligible") then
    -- all objectives are on this map, or an eligible delivery quest
    e.turnin = onMap(q.turnIn or q.giver, mapID)
  end
  return e
end

local function hasTurnin(entries, id)
  local e = entries[id]
  return e ~= nil and e.turnin ~= nil
end

local function depsMet(entries, deps)
  for _, p in ipairs(deps.all) do
    if not hasTurnin(entries, p) then return false end
  end
  if deps.any then
    for _, p in ipairs(deps.any) do
      if hasTurnin(entries, p) then return true end
    end
    return false
  end
  return true
end

-- Quests of this zone that fail eligibility only with `prereq` and would pass
-- once their missing prerequisites are done, and that fit the player's level
-- (an orange follow-up waits in Later). Independent of the route.
local function chainCandidates(db, state, mapID, entries)
  local out = {}
  local completed = state.completed or {}
  local eliteOff = state.settings and state.settings.elite == false
  local ids = db:questsInZone(mapID)
  for _, id in ipairs(ids) do
    local q = not entries[id] and db:quest(id) or nil
    if q and not q.dungeonQuest and q.giver and q.giver.mapID == mapID
        and not (eliteOff and ns.Candidates.isGroupQuest(q)) then
      local status, reason = ns.Eligibility.check(db, q, state)
      if status == nil and reason == "prereq" then
        local all, any = {}, nil
        local prereq = q.prereq or {}
        local overlay = {}
        for _, p in ipairs(prereq.all or {}) do
          if not completed[p] then all[#all + 1] = p; overlay[p] = true end
        end
        local list = prereq.any or {}
        if #list > 0 then
          local ok = false
          for _, p in ipairs(list) do
            if completed[p] then ok = true; break end
          end
          if not ok then any = list; overlay[list[1]] = true end
        end
        setmetatable(overlay, { __index = completed })
        if ns.Eligibility.check(db, q, copyState(state, overlay)) == "eligible"
            and ns.Candidates.fits(ns.Candidates.fitOf(q, state)) then
          out[#out + 1] = { quest = q, all = all, any = any }
        end
      end
    end
  end
  return out
end

local function xpOf(state, entry)
  return ns.XP.estimate(entry.quest, state.level, state.recordedXP) or 0
end

-- True when quest t lists id in prereq.all or prereq.any (id is a real prerequisite).
local function targetRequires(db, t, id)
  local tq = db and db:quest(t)
  local pre = tq and tq.prereq
  if not pre then return false end
  for _, p in ipairs(pre.all or {}) do if p == id then return true end end
  for _, p in ipairs(pre.any or {}) do if p == id then return true end end
  return false
end

-- Drops breadcrumbs of route quests (unless their target requires them) and the
-- weaker of mutually exclusive quests. Returns the dropped quest IDs.
local function prune(db, state, entries)
  local ids = {}
  for id in pairs(entries) do ids[#ids + 1] = id end
  table.sort(ids)
  local dropped = {}
  for _, id in ipairs(ids) do
    local e = entries[id]
    if e then
      local t = e.quest.breadcrumbOf
      if t and entries[t] and not targetRequires(db, t, id) then
        entries[id] = nil; dropped[#dropped + 1] = id
      else
        for _, other in ipairs(e.quest.exclusiveTo or {}) do
          local o = entries[other]
          if o and entries[id] then
            local xa, xb = xpOf(state, e), xpOf(state, o)
            local loser = id
            if xa > xb or (xa == xb and id < other) then loser = other end
            entries[loser] = nil; dropped[#dropped + 1] = loser
          end
        end
      end
    end
  end
  return dropped
end

-- Returns entries keyed by quest ID.
local function routeQuests(db, state, mapID, candidates, opts)
  local entries = {}
  for _, c in ipairs(candidates or {}) do
    local q = c.quest
    if ns.Candidates.recommendable(c) and not entries[q.id] then
      entries[q.id] = makeEntry(q, c.status, mapID, opts.dungeonKey)
    end
  end

  local pending = chainCandidates(db, state, mapID, entries)
  local banned = {}
  while true do
    -- chain extension to a fixed point; drop followers whose deps vanished
    local changed = true
    while changed do
      changed = false
      for _, c in ipairs(pending) do
        local id = c.quest.id
        local deps = { all = c.all, any = c.any }
        local met = depsMet(entries, deps)
        if not entries[id] and not banned[id] and met then
          local e = makeEntry(c.quest, "eligible", mapID, opts.dungeonKey)
          if e then
            e.deps = deps
            entries[id] = e
            changed = true
          end
        elseif entries[id] and entries[id].deps and not met then
          entries[id] = nil
          changed = true
        end
      end
    end
    local dropped = prune(db, state, entries)
    if #dropped == 0 then break end
    for _, id in ipairs(dropped) do banned[id] = true end
  end
  return entries
end

-- All actions of the route, in deterministic order (questID, then kind).
local function buildActions(entries)
  local qids = {}
  for id in pairs(entries) do qids[#qids + 1] = id end
  table.sort(qids)
  local actions = {}
  local function add(e, kind, p)
    actions[#actions + 1] = {
      questID = e.quest.id, kind = kind, mapID = p.mapID, x = p.x, y = p.y,
      entry = e,
    }
  end
  for _, id in ipairs(qids) do
    local e = entries[id]
    if e.pickup then add(e, "pickup", e.pickup) end
    for _, p in ipairs(e.objectives) do add(e, "objective", p) end
    if e.turnin then add(e, "turnin", e.turnin) end
  end
  return actions
end

function Route.forZone(db, state, mapID, candidates, opts)
  opts = opts or {}
  local entries = routeQuests(db, state, mapID, candidates, opts)
  local actions = buildActions(entries)
  if #actions == 0 then return {} end

  -- Cluster every action point once, in a deterministic order.
  local points = {}
  for i, a in ipairs(actions) do points[i] = { a.mapID, a.x, a.y, a } end
  local hubs = ns.Hubs.cluster(db, points, ns.Tuning.HUB_RADIUS_YD)

  local turnedIn, pickedUp, objectivesLeft = {}, {}, {}
  for _, a in ipairs(actions) do
    local e = a.entry
    if a.kind == "objective" then
      objectivesLeft[a.questID] = (objectivesLeft[a.questID] or 0) + 1
    end
    if e.status ~= "eligible" then pickedUp[a.questID] = true end
  end

  local function ready(a)
    if a.done then return false end
    local e = a.entry
    if a.kind == "pickup" then
      local deps = e.deps
      if not deps then return true end
      for _, p in ipairs(deps.all) do
        if not turnedIn[p] then return false end
      end
      if deps.any then
        local ok = false
        for _, p in ipairs(deps.any) do
          if turnedIn[p] then ok = true; break end
        end
        if not ok then return false end
      end
      return true
    elseif a.kind == "objective" then
      return pickedUp[a.questID] == true
    end
    return pickedUp[a.questID] == true and (objectivesLeft[a.questID] or 0) == 0
  end

  local function perform(a)
    a.done = true
    if a.kind == "pickup" then pickedUp[a.questID] = true
    elseif a.kind == "objective" then
      objectivesLeft[a.questID] = objectivesLeft[a.questID] - 1
    else turnedIn[a.questID] = true end
  end

  -- Starting position.
  local pos
  if state.mapID == mapID and state.x and state.y then
    pos = { mapID, state.x, state.y }
  else
    local best, bestN = hubs[1], -1
    for _, hub in ipairs(hubs) do
      local n = 0
      for _, a in ipairs(hub.members) do
        if a.kind == "pickup" then n = n + 1 end
      end
      if n > bestN then best, bestN = hub, n end
    end
    pos = { best.mapID, best.x, best.y }
  end

  local steps = {}
  local live = {}
  for i, hub in ipairs(hubs) do live[i] = hub end
  while true do
    local target, targetD
    local posMap, posX, posY = pos[1], pos[2], pos[3]
    local posW, posH = ns.Geo.zoneYards(db, posMap)
    -- drop hubs whose members are all done; they can never be ready again
    local kept = 0
    for i = 1, #live do
      local hub = live[i]
      local open, hasReady = false, false
      local members = hub.members
      for j = 1, #members do
        local a = members[j]
        if not a.done then
          open = true
          if ready(a) then hasReady = true; break end
        end
      end
      if open then
        kept = kept + 1
        live[kept] = hub
        if hasReady then
          local d
          if hub.mapID == posMap then
            -- same-map distance, as Geo.distance computes it
            local dx, dy = (hub.x - posX) / 100 * posW, (hub.y - posY) / 100 * posH
            d = math.sqrt(dx * dx + dy * dy)
          else
            d = ns.Geo.distance(db, pos, hub) or math.huge
          end
          if not target or d < targetD then target, targetD = hub, d end
        end
      end
    end
    for i = #live, kept + 1, -1 do live[i] = nil end
    if not target then break end

    local step = {
      mapID = target.mapID, x = target.x, y = target.y, actions = {},
      counts = { pickup = 0, objective = 0, turnin = 0 }, xp = 0,
    }
    local progressed = true
    while progressed do
      progressed = false
      for _, a in ipairs(target.members) do
        if ready(a) then
          perform(a)
          step.actions[#step.actions + 1] = { a.questID, a.kind }
          step.counts[a.kind] = step.counts[a.kind] + 1
          if a.kind == "turnin" then
            step.xp = step.xp + (ns.XP.estimate(a.entry.quest, state.level, state.recordedXP) or 0)
          end
          progressed = true
        end
      end
    end
    steps[#steps + 1] = step
    pos = { target.mapID, target.x, target.y }
  end
  if opts.improve == false then return steps end
  local start
  if state.mapID == mapID and state.x and state.y then
    start = { mapID, state.x, state.y }
  end
  -- Dependency data the greedy used, so the improver's rule matches it.
  local deps = {}
  for id, e in pairs(entries) do
    if e.deps then deps[id] = { all = e.deps.all or {}, any = e.deps.any or {} } end
  end
  local better = ns.RouteImprove.improve(db, steps, start, { clock = opts.clock, deps = deps })
  return better
end
