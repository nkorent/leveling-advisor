local _, ns = ...

-- The unlock path of a quest: the quests that must be done before it, earliest first, each
-- with its state for this character. Pure Lua, no WoW globals.
-- Walk: prereq.all, transitively, through shipped quests and quest stubs alike. An any-list
-- with no completed option becomes one "one of" group of its options (their own
-- prerequisites are not walked); a satisfied any-list adds nothing.
-- A done or in-log step (or the quest itself) was let through by the server, so every
-- ancestor of it counts as done ("implied"), and its any-list adds no group.
-- Blocked: a unit whose steps are all blocked, or the quest itself blocked for this character
-- (when not done or in the log); a blocked path has no `first` step to start with.
-- Order: depth = 1 + the deepest of a step's prerequisites in the path (roots are 1). Ties
-- keep the first-visit order of a DFS over prereq.all in list order, starting from the quest;
-- in a layer the required steps come before any-groups, so a "needs all" group stays together.
-- Position (Unlock.position): the quest's place in its chain, the one "Chain n/m" shows.
local Unlock = {}
ns.Unlock = Unlock

-- A path holds at most this many steps. The walk collects ancestors nearest the quest first,
-- so on a longer path the ancestors farthest from the quest (the deepest) are dropped first.
local MAX_STEPS = 64

-- Step status of a DB quest that Eligibility rejects, by reason. "ignored" is left out on
-- purpose: path() checks steps without the ignore list, and should it ever get here it
-- falls to "unknown", like any reason not listed, never to "start".
local STATUS_BY_REASON = {
  grey = "start",
  prereq = "locked", level = "locked", ["too-high"] = "locked",
  faction = "blocked", race = "blocked", class = "blocked", exclusive = "blocked",
  unavailable = "blocked", ["max-level"] = "blocked", breadcrumb = "blocked",
  ["no-data"] = "unknown",
}

-- The reason a stub's known faction, race or class rules the player out, or nil.
local function stubBlock(stub, state)
  local E = ns.Eligibility
  local f = stub.faction
  if f ~= nil and f ~= 3 and f ~= E.FACTION_ID[state.faction] then return "faction" end
  if not E.maskAllows(stub.raceMask, state.raceMask) then return "race" end
  if not E.maskAllows(stub.classMask, state.classMask) then return "class" end
  return nil
end

local function record(db, id)
  return db:quest(id) or db:stub(id)
end

local function anyCompleted(options, completed)
  for _, o in ipairs(options) do
    if completed[o] then return true end
  end
  return false
end

-- An any-list's options without duplicates or the quest itself, and a key for the set.
local function optionSet(options, questID)
  local ids, seen, sorted = {}, {}, {}
  for _, o in ipairs(options) do
    if o ~= questID and not seen[o] then
      seen[o] = true
      ids[#ids + 1] = o
      sorted[#sorted + 1] = o
    end
  end
  table.sort(sorted)
  return ids, table.concat(sorted, ",")
end

-- Status of a DB quest step from Eligibility. The data lists some quests that exclude each
-- other as prerequisites of one path; a step excluded only by quests of the path itself (or
-- the path's own quest) is a data conflict, "unknown", not "not available".
local function questStatus(db, q, ctx)
  local s, why = ns.Eligibility.check(db, q, ctx.stepState)
  if s == "eligible" then return "start", nil end
  if s == "soon" then return "locked", "level" end
  if why == "exclusive" then
    for _, other in ipairs(q.exclusiveTo) do
      if ctx.taken(other) and not ctx.inPath[other] then return "blocked", why end
    end
    return "unknown", "conflict"
  end
  return STATUS_BY_REASON[why] or "unknown", why
end

local function makeStep(db, id, ctx)
  local state = ctx.state
  local q = db:quest(id)
  local stub = not q and db:stub(id) or nil
  local rec = q or stub
  local step = { questID = id, name = rec and rec.name, level = rec and rec.level,
    giver = q and q.giver or nil, stub = stub }
  local status, reason
  if state.completed and state.completed[id] then
    status, reason = "done", "completed"
  elseif ctx.implied[id] then
    status, reason = "done", "implied"
  elseif ns.Eligibility.logState(state, id) then
    status, reason = "progress", "in-log"
  elseif q then
    status, reason = questStatus(db, q, ctx)
  elseif stub then
    reason = stubBlock(stub, state)
    status = reason and "blocked" or "unknown"
    reason = reason or "stub"
  else
    status, reason = "unknown", "missing"
  end
  step.status, step.reason = status, reason
  return step
end

-- The required ancestors (prereq.all, transitively), nearest the quest first: one unit
-- { ids = { id }, deps = {} } each, at most MAX_STEPS.
local function ancestors(db, questID)
  local unitOf, queue, head, n = {}, { questID }, 1, 0
  while queue[head] do
    local r = record(db, queue[head])
    head = head + 1
    for _, p in ipairs(r and r.prereq.all or {}) do
      if p ~= questID and not unitOf[p] then
        if n == MAX_STEPS then return unitOf, n end
        unitOf[p] = { ids = { p }, deps = {} }
        n = n + 1
        queue[#queue + 1] = p
      end
    end
  end
  return unitOf, n
end

local function depthOf(u)
  if u.depth then return u.depth end
  if u.busy then return 0 end -- a cycle: the edge back to a step being measured adds nothing
  u.busy = true
  local d = 0
  for _, p in ipairs(u.deps) do d = math.max(d, depthOf(p)) end
  u.busy = nil
  u.depth = d + 1
  return u.depth
end

local function byLayer(a, b)
  if a.depth ~= b.depth then return a.depth < b.depth end
  if (a.any or false) ~= (b.any or false) then return not a.any end
  return a.order < b.order
end

-- Returns nil when the quest (or stub) is unknown or nothing has to be done before it.
function Unlock.path(db, questID, state)
  if not record(db, questID) then return nil end
  local completed = state.completed or {}
  -- the player's ignore list does not apply to chain steps; every other Eligibility gate does
  local stepState = {}
  for k, v in pairs(state) do stepState[k] = v end
  stepState.ignored = nil
  -- done or in the log, the test Eligibility uses for exclusiveTo
  local function taken(id)
    return completed[id] or ns.Eligibility.logState(state, id) ~= nil
  end

  local unitOf, size = ancestors(db, questID) -- required steps only
  local units, order, groupBySet = {}, 0, {}
  local top = { deps = {} } -- the quest itself: not a step

  -- Every ancestor of a done or in-log step, or of the quest itself when it is done or in
  -- the log, is met in practice: it shows as done ("implied").
  local implied = {}
  local function imply(id)
    local r = record(db, id)
    for _, p in ipairs(r and r.prereq.all or {}) do
      if unitOf[p] and not implied[p] then
        implied[p] = true
        imply(p)
      end
    end
  end
  if taken(questID) then imply(questID) end
  for id in pairs(unitOf) do
    if taken(id) then imply(id) end
  end

  -- The unit an unsatisfied any-list waits on: an option that is a required step (the path
  -- satisfies the list), the group made for the same set of options, else a new group.
  local function anyUnit(options, owner)
    for _, o in ipairs(options) do
      if unitOf[o] then return unitOf[o] end
    end
    local ids, key = optionSet(options, questID)
    if groupBySet[key] then return groupBySet[key] end
    local deps = {}
    for i, d in ipairs(owner.deps) do deps[i] = d end
    local g = { ids = {}, deps = deps, any = true }
    for _, o in ipairs(ids) do
      if size < MAX_STEPS then
        g.ids[#g.ids + 1] = o
        size = size + 1
      end
    end
    if #g.ids == 0 then return nil end
    order = order + 1
    g.order = order
    groupBySet[key] = g
    units[#units + 1] = g
    return g
  end

  local function visit(id, u)
    local r = record(db, id)
    if not r then return end
    for _, p in ipairs(r.prereq.all) do
      local pu = unitOf[p]
      if pu then
        u.deps[#u.deps + 1] = pu
        if not pu.order then
          order = order + 1
          pu.order = order
          units[#units + 1] = pu
          visit(p, pu)
        end
      end
    end
    local any = r.prereq.any
    if #any > 0 and not taken(id) and not implied[id] and not anyCompleted(any, completed) then
      local g = anyUnit(any, u)
      if g then u.deps[#u.deps + 1] = g end
    end
  end
  visit(questID, top)
  if #units == 0 then return nil end

  local inPath = { [questID] = true }
  for _, u in ipairs(units) do
    depthOf(u)
    for _, id in ipairs(u.ids) do inPath[id] = true end
  end
  table.sort(units, byLayer)
  local perLayer = {}
  for _, u in ipairs(units) do
    if not u.any then perLayer[u.depth] = (perLayer[u.depth] or 0) + 1 end
  end

  local ctx = { state = state, stepState = stepState, implied = implied, inPath = inPath, taken = taken }
  local result = { questID = questID, steps = {}, total = #units, done = 0, xp = 0, blocked = false }
  local steps, allGroups, anyGroups = result.steps, {}, 0
  for number, u in ipairs(units) do
    local group
    if u.any then
      anyGroups = anyGroups + 1
      group = { kind = "any", id = anyGroups, size = #u.ids }
    elseif perLayer[u.depth] >= 2 then
      group = allGroups[u.depth] or { kind = "all", id = u.depth, size = perLayer[u.depth] }
      allGroups[u.depth] = group
    end
    -- a unit is done when a step of it is, blocked when all of its steps are
    local done, blocked, open = false, true, nil
    for _, id in ipairs(u.ids) do
      local step = makeStep(db, id, ctx)
      step.group, step.number = group, number
      steps[#steps + 1] = step
      if step.status == "done" then done = true end
      if step.status ~= "blocked" then
        blocked = false
        open = open or step
      end
      if step.status == "start" and not result.first then result.first = #steps end
    end
    if done then result.done = result.done + 1 end
    if blocked then result.blocked = true end
    -- XP: a required step's own; an any-group's first non-blocked option only
    local xpStep = steps[#steps]
    if u.any then xpStep = open end
    local q = xpStep and xpStep.status ~= "done" and db:quest(xpStep.questID)
    if q then result.xp = result.xp + ns.XP.estimate(q, state.level, state.recordedXP) end
  end
  result.remaining = result.total - result.done
  -- The quest itself, when not done or in the log: a chain that ends in a quest this
  -- character can never take is blocked too.
  local q = db:quest(questID)
  if q and not taken(questID) and questStatus(db, q, ctx) == "blocked" then result.blocked = true end
  -- the anti-goal: no place to start on a chain that cannot be completed
  if result.blocked then result.first = nil end
  return result
end

-- db -> { followers = { [id] = { id, ... } }, after = { [id] = n } }: the quests (shipped
-- quests and stubs, as the path walks both) that list an id in prereq.all or prereq.any, and
-- the memoised longest chain after each id. Built once per db; it does not depend on the player.
local forwardByDB = setmetatable({}, { __mode = "k" })

local function forward(db)
  local f = forwardByDB[db]
  if f then return f end
  local followers = {}
  local function add(id, r)
    local seen = {}
    for _, list in ipairs({ r.prereq.all, r.prereq.any }) do
      for _, p in ipairs(list) do
        if p ~= id and not seen[p] then
          seen[p] = true
          local of = followers[p]
          if not of then of = {}; followers[p] = of end
          of[#of + 1] = id
        end
      end
    end
  end
  for _, id in ipairs(db:questIDs()) do add(id, db:quest(id)) end
  if db.stubIDs then
    for _, id in ipairs(db:stubIDs()) do add(id, db:stub(id)) end
  end
  f = { followers = followers, after = {}, busy = {} }
  forwardByDB[db] = f
  return f
end

-- Steps on the longest chain of followers after `id`, at most MAX_STEPS. A follower still
-- being measured (a cycle) adds nothing. A value measured inside a cycle is cached like any
-- other, so in a prerequisite cycle (rare in the data) the length can depend on which of its
-- quests was measured first.
local function stepsAfter(f, id)
  local n = f.after[id]
  if n then return n end
  f.busy[id] = true
  n = 0
  for _, follower in ipairs(f.followers[id] or {}) do
    if not f.busy[follower] then n = math.max(n, 1 + stepsAfter(f, follower)) end
  end
  f.busy[id] = nil
  n = math.min(n, MAX_STEPS)
  f.after[id] = n
  return n
end

-- { index, length }: index = 1 + the quests the Unlock Path counts before this one (its
-- total, an any-group once), length = index + the longest chain of quests that need this one.
-- nil when the quest (or stub) is unknown or neither comes before nor after another quest.
function Unlock.position(db, questID, state)
  if not record(db, questID) then return nil end
  local path = Unlock.path(db, questID, state)
  local before = path and path.total or 0
  local after = stepsAfter(forward(db), questID)
  if before == 0 and after == 0 then return nil end
  return { index = before + 1, length = before + 1 + after }
end
