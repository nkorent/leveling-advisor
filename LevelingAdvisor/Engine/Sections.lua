local _, ns = ...

-- Builds the quest sections for the right-hand page. Each quest appears in at
-- most one section (priority: turnin > class > here > chains > next).
local Sections = {}
ns.Sections = Sections

local TITLES = {
  turnin = "Ready to Turn In",
  here = "Right Here",
  class = "Class Quests",
  chains = "Continue Your Chains",
  next = "For Your Next Zone",
}
local DISPLAY_ORDER = { "turnin", "here", "class", "chains", "next" }

local function playerPoint(state)
  return { state.mapID, state.x, state.y }
end

local function dist(db, state, point)
  if not (state.mapID and state.x and state.y and point) then return nil end
  return (ns.Geo.distance(db, playerPoint(state), point))
end

local function minDist(db, state, points)
  local best
  for _, p in ipairs(points) do
    local d = dist(db, state, p)
    if d and (not best or d < best) then best = d end
  end
  return best
end

-- Yards used for the row: turn-in for complete, nearest point (else turn-in)
-- for progress, giver otherwise.
local function rowYards(db, state, c)
  local q = c.quest
  if c.status == "complete" then return dist(db, state, q.turnIn) end
  if c.status == "progress" then
    local pts = q.points
    if pts and #pts > 0 then return minDist(db, state, pts) end
    return dist(db, state, q.turnIn)
  end
  return dist(db, state, q.giver)
end

local function makeRow(db, state, c)
  local q = c.quest
  local g = q.giver or {}
  local st = (c.status == "progress" and "progress")
    or (c.status == "complete" and "complete") or "available"
  return {
    questID = q.id,
    name = q.name,
    level = q.level,
    color = ns.Difficulty.color(q.level, state.level, state.greyAtOrBelow),
    state = st,
    soon = c.status == "soon",
    xp = c.xp,
    giver = { mapID = g.mapID, x = g.x, y = g.y, kind = g.kind, id = g.id },
    yards = rowYards(db, state, c),
    tags = {
      chain = q.chain and { index = q.chain.index, length = q.chain.length } or nil,
      class = q.classQuest and state.classFile or nil,
      elite = q.elite and true or false,
      group = (q.groupSize and q.groupSize >= 2) and q.groupSize or nil,
      unverified = q.unverified and true or false,
    },
  }
end

-- nil yards sorts last
local function byYards(a, b)
  local ya, yb = a.yards, b.yards
  if ya and yb and ya ~= yb then return ya < yb end
  if (ya == nil) ~= (yb == nil) then return yb == nil end
  return a.questID < b.questID
end

local function byYardsThenLevel(a, b)
  local ya, yb = a.yards, b.yards
  if ya and yb and ya ~= yb then return ya < yb end
  if (ya == nil) ~= (yb == nil) then return yb == nil end
  if a.level ~= b.level then return (a.level or 0) < (b.level or 0) end
  return a.questID < b.questID
end

local function byXp(a, b)
  if (a.xp or 0) ~= (b.xp or 0) then return (a.xp or 0) > (b.xp or 0) end
  return a.questID < b.questID
end

local function limited(rows, n)
  local out = {}
  for i = 1, math.min(n, #rows) do out[i] = rows[i] end
  return out
end

function Sections.build(db, state, candidates, zones)
  local T = ns.Tuning
  local used = {}
  local result = {}

  local nextZone
  for _, z in ipairs(zones or {}) do
    if z.mapID ~= state.mapID then nextZone = z.mapID; break end
  end

  -- Takes candidates matching pred in order; rows are marked used only if kept.
  local function take(pred, sorter, limit)
    local rows = {}
    for _, c in ipairs(candidates) do
      if not used[c.quest.id] and pred(c) then
        rows[#rows + 1] = makeRow(db, state, c)
      end
    end
    table.sort(rows, sorter)
    if limit then rows = limited(rows, limit) end
    for _, r in ipairs(rows) do used[r.questID] = true end
    return rows
  end

  local function near(yards)
    return yards ~= nil and yards <= T.RIGHT_HERE_YD
  end

  result.turnin = take(function(c) return c.status == "complete" end, byYards)

  result.class = take(function(c)
    return (c.status == "eligible" or c.status == "soon") and c.quest.classQuest
  end, byYardsThenLevel)

  result.here = take(function(c)
    local q = c.quest
    if q.dungeonQuest then return false end
    if c.status == "eligible" then
      return near(dist(db, state, q.giver))
    elseif c.status == "progress" then
      local pts = {}
      for _, p in ipairs(q.points or {}) do pts[#pts + 1] = p end
      if q.turnIn then pts[#pts + 1] = q.turnIn end
      return near(minDist(db, state, pts))
    end
    return false
  end, byYards, T.SECTION_LIMITS.here)

  result.chains = take(function(c)
    local q = c.quest
    return c.status == "eligible" and q.chain and q.chain.index > 1 and not q.dungeonQuest
  end, byXp, T.SECTION_LIMITS.chains)

  result.next = take(function(c)
    local q = c.quest
    return nextZone ~= nil and c.status == "eligible" and q.zone == nextZone
      and not q.dungeonQuest
  end, byXp, T.SECTION_LIMITS.next)

  local out = {}
  for _, key in ipairs(DISPLAY_ORDER) do
    if #result[key] > 0 then
      out[#out + 1] = { key = key, title = TITLES[key], rows = result[key] }
    end
  end
  return out
end
