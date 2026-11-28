local _, ns = ...

-- Bounded local search (2-opt, Or-opt) over a zone route, then a merge of
-- steps that ended up at the same point. Pure Lua; the clock is injected.
local RouteImprove = {}
ns.RouteImprove = RouteImprove

local function point(s) return { s.mapID, s.x, s.y } end

local function legLength(db, a, b)
  if a == nil or b == nil then return 0 end
  return ns.Geo.distance(db, a, b) or 0
end

-- Sum of distances between consecutive steps (plus start -> first step).
function RouteImprove.length(db, steps, start)
  local total, prev = 0, start
  for _, s in ipairs(steps) do
    local p = point(s)
    total = total + legLength(db, prev, p)
    prev = p
  end
  return total
end

-- Per-quest prerequisite IDs (all + any), derived from the DB. Conservative:
-- every listed prerequisite must come first.
local function dbDeps(db, questID)
  local q = db:quest(questID)
  local p = q and q.prereq
  local all = {}
  if p then
    for _, id in ipairs(p.all or {}) do all[#all + 1] = id end
    for _, id in ipairs(p.any or {}) do all[#all + 1] = id end
  end
  return { all = all, any = {} }
end

-- Constraint model over fixed nodes (original step indices).
local function buildModel(db, steps, depsOpt)
  local quests, nodeQuests = {}, {}
  local n = #steps
  for node = 1, n do
    nodeQuests[node] = {}
    for _, a in ipairs(steps[node].actions) do
      local q, kind = a[1], a[2]
      local c = quests[q]
      if not c then
        c = { id = q, objs = {}, all = {}, any = {} }
        quests[q] = c
      end
      if kind == "pickup" then c.pickup = node
      elseif kind == "turnin" then c.turnin = node
      else c.objs[#c.objs + 1] = node end
      local list = nodeQuests[node]
      if list[#list] ~= q then list[#list + 1] = q end
    end
  end
  for q, c in pairs(quests) do
    if c.pickup then
      local d = depsOpt and (depsOpt[q] or { all = {}, any = {} }) or dbDeps(db, q)
      for _, p in ipairs(d.all or {}) do
        local pc = quests[p]
        if pc and pc.turnin then
          c.all[#c.all + 1] = pc.turnin
        end
      end
      for _, p in ipairs(d.any or {}) do
        local pc = quests[p]
        if pc and pc.turnin then
          c.any[#c.any + 1] = pc.turnin
        end
      end
    end
  end
  return { quests = quests, nodeQuests = nodeQuests }
end

local function questOk(c, posOf)
  local pu, tu = c.pickup and posOf[c.pickup], c.turnin and posOf[c.turnin]
  if pu then
    if tu and pu > tu then return false end
    for _, o in ipairs(c.objs) do
      if pu > posOf[o] then return false end
    end
    for _, t in ipairs(c.all) do
      if posOf[t] > pu then return false end
    end
    if #c.any > 0 then
      local ok = false
      for _, t in ipairs(c.any) do
        if posOf[t] <= pu then ok = true; break end
      end
      if not ok then return false end
    end
  end
  if tu then
    for _, o in ipairs(c.objs) do
      if posOf[o] > tu then return false end
    end
  end
  return true
end

local function merge(db, steps)
  local out, fresh = {}, {}
  for _, s in ipairs(steps) do
    local last = out[#out]
    local d = last and ns.Geo.distance(db, point(last), point(s))
    if d and d < 1 then
      if not fresh[last] then
        local copy = {}
        for k, v in pairs(last) do copy[k] = v end
        copy.actions, copy.counts, copy.xp = {}, {}, last.xp or 0
        for _, a in ipairs(last.actions) do copy.actions[#copy.actions + 1] = a end
        for k, v in pairs(last.counts or {}) do copy.counts[k] = v end
        fresh[copy] = true
        last = copy
        out[#out] = copy
      end
      for _, a in ipairs(s.actions) do last.actions[#last.actions + 1] = a end
      for k, v in pairs(s.counts or {}) do last.counts[k] = (last.counts[k] or 0) + v end
      last.xp = last.xp + (s.xp or 0)
    else
      out[#out + 1] = s
    end
  end
  return out
end

function RouteImprove.improve(db, steps, start, opts)
  opts = opts or {}
  local T = ns.Tuning
  local n = #steps
  local before = RouteImprove.length(db, steps, start)
  local stats = { before = before, after = before, passes = 0, moves = 0 }
  if n == 0 then return {}, stats end

  local model = buildModel(db, steps, opts.deps)
  local ord, posOf = {}, {}
  for i = 1, n do ord[i] = i; posOf[i] = i end
  for _, c in pairs(model.quests) do
    if not questOk(c, posOf) then
      stats.invalidInput = true
      local copy = {}
      for i = 1, n do copy[i] = steps[i] end
      local result = merge(db, copy)
      stats.after = RouteImprove.length(db, result, start)
      return result, stats
    end
  end

  -- Distance cache over nodes 0 (start) .. n.
  local pts, dist = {}, {}
  for i = 1, n do pts[i] = point(steps[i]) end
  pts[0] = start
  local function D(a, b)
    if a == nil or b == nil then return 0 end
    local k = a * (n + 1) + b
    local v = dist[k]
    if v == nil then
      v = legLength(db, pts[a], pts[b])
      dist[k] = v; dist[b * (n + 1) + a] = v
    end
    return v
  end

  local startNode = start and 0 or nil
  local clock = opts.clock
  local t0 = clock and clock()
  local expired = false
  local candidates = 0
  local function overBudget()
    if not clock then return expired end
    if clock() - t0 > T.ROUTE_IMPROVE_MAX_MS then expired = true end
    return expired
  end
  -- Counts one candidate move. The candidate cap holds with or without a
  -- clock; the clock adds the time bound on top.
  local function tick()
    candidates = candidates + 1
    if candidates >= T.ROUTE_IMPROVE_MAX_CANDIDATES then expired = true end
    if candidates % 200 == 0 then return overBudget() end
    return expired
  end
  local minGain = T.ROUTE_IMPROVE_MIN_GAIN_YD

  local function nodeAt(t) if t == 0 then return startNode end return ord[t] end

  -- Rewrites ord[lo..hi] from buf and refreshes posOf.
  local function write(lo, hi, buf)
    for t = lo, hi do
      local node = buf[t - lo + 1]
      ord[t] = node; posOf[node] = t
    end
  end

  local stamp, seen = 0, {}
  -- Checks every constraint that a change inside positions lo..hi can affect.
  -- Quests that only depend on a moved turn-in need no recheck: their pickup
  -- lies outside the range, and a rewrite keeps each moved step inside it, so
  -- the order relative to anything outside is unchanged.
  local function rangeOk(lo, hi)
    stamp = stamp + 1
    for t = lo, hi do
      for _, q in ipairs(model.nodeQuests[ord[t]]) do
        if seen[q] ~= stamp then
          seen[q] = stamp
          if not questOk(model.quests[q], posOf) then return false end
        end
      end
    end
    return true
  end

  -- Applies the rewrite when valid; otherwise restores the old range.
  local old = {}
  local function tryWrite(lo, hi, buf)
    for t = lo, hi do old[t - lo + 1] = ord[t] end
    write(lo, hi, buf)
    if rangeOk(lo, hi) then return true end
    write(lo, hi, old)
    return false
  end

  local buf, rest = {}, {}
  local function sweep()
    local moved = false
    -- 2-opt: reverse i..j
    for i = 1, n - 1 do
      for j = i + 1, n do
        if tick() then return moved end
        local a, b = nodeAt(i - 1), ord[i]
        local c, d = ord[j], ord[j + 1]
        if D(a, b) + D(c, d) - D(a, c) - D(b, d) > minGain then
          for t = i, j do buf[t - i + 1] = ord[i + j - t] end
          if tryWrite(i, j, buf) then
            moved = true; stats.moves = stats.moves + 1
          end
        end
      end
    end
    -- Or-opt: move a run of 1-3 steps elsewhere
    for len = 1, 3 do
      local i = 1
      while i <= n - len + 1 do
        local k = i + len - 1
        local a, b = nodeAt(i - 1), ord[k + 1]
        local first, last = ord[i], ord[k]
        local removeGain = D(a, first) + D(last, b) - D(a, b)
        local applied = false
        if removeGain > minGain then
          local rn = 0
          for t = 1, n do
            if t < i or t > k then rn = rn + 1; rest[rn] = ord[t] end
          end
          rest[rn + 1] = nil  -- no stale tail from an earlier, longer fill
          for m = 0, rn do
            if m ~= i - 1 then
              if tick() then return moved end
              local p = (m == 0) and startNode or rest[m]
              local q = rest[m + 1]
              if removeGain - (D(p, first) + D(last, q) - D(p, q)) > minGain then
                local lo, hi, c = nil, nil, 0
                if m < i - 1 then
                  lo, hi = m + 1, k
                  for t = i, k do c = c + 1; buf[c] = ord[t] end
                  for t = m + 1, i - 1 do c = c + 1; buf[c] = ord[t] end
                else
                  lo, hi = i, m + len
                  for t = k + 1, m + len do c = c + 1; buf[c] = ord[t] end
                  for t = i, k do c = c + 1; buf[c] = ord[t] end
                end
                if tryWrite(lo, hi, buf) then
                  moved, applied = true, true
                  stats.moves = stats.moves + 1
                  break
                end
              end
            end
          end
        end
        -- after a move the run at i is new; look at it again
        if not applied then i = i + 1 end
      end
    end
    return moved
  end

  while stats.passes < T.ROUTE_IMPROVE_MAX_PASSES do
    if stats.passes > 0 and overBudget() then break end
    stats.passes = stats.passes + 1
    if not sweep() or expired then break end
  end

  stats.candidates = candidates
  local result = {}
  for i = 1, n do result[i] = steps[ord[i]] end
  if RouteImprove.length(db, result, start) > before + 1e-6 then
    -- safety net: never return a longer route
    stats.reverted = true
    for i = 1, n do result[i] = steps[i] end
  end
  result = merge(db, result)
  stats.after = RouteImprove.length(db, result, start)
  return result, stats
end
