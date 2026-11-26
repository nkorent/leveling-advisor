local _, ns = ...

-- Facade: the whole Recommendation (Contract C) in one call.
local Engine = {}
ns.Engine = Engine

-- The candidate scan covers every quest in the DB, so Engine.route reuses the
-- one compute did. Keyed by the recommendation compute returned (weakly, so it
-- goes when the recommendation does) and only honoured for the same db, the
-- same state table AND the same state fingerprint (level, position, the sizes
-- of completed/log/ignored and the number of complete log entries). An
-- in-place edit that changes the fingerprint therefore rebuilds the candidates
-- instead of routing on stale ones. The fingerprint is cheap, not exhaustive:
-- prefer passing a fresh state snapshot when anything changes.
local reusable = setmetatable({}, { __mode = "k" })

local function count(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

local function fingerprint(state)
  local done = 0
  for _, e in pairs(state.log or {}) do
    if type(e) == "table" and e.complete then done = done + 1 end
  end
  return table.concat({
    tostring(state.level), tostring(state.mapID), tostring(state.x), tostring(state.y),
    count(state.completed), count(state.log), count(state.ignored), done,
  }, "|")
end

function Engine.compute(db, state)
  local candidates = ns.Candidates.build(db, state)
  local reach = ns.Travel.fromPlayer(db, state)
  local zones = ns.ZoneScore.rank(db, state, candidates, reach)
  local sections = ns.Sections.build(db, state, candidates, zones)
  local dungeon = ns.Dungeons.recommend(db, state, candidates, zones, reach)
  local rec = { zones = zones, dungeon = dungeon, sections = sections }
  reusable[rec] = { db = db, state = state, candidates = candidates, print = fingerprint(state) }
  return rec
end

-- clock: optional function returning milliseconds
function Engine.route(db, state, mapID, rec, clock)
  local seen = rec and reusable[rec]
  local candidates
  if seen and seen.db == db and seen.state == state and seen.print == fingerprint(state) then
    candidates = seen.candidates
  else
    candidates = ns.Candidates.build(db, state)
  end
  return ns.Route.forZone(db, state, mapID, candidates, {
    dungeonKey = rec and rec.dungeon and rec.dungeon.key,
    clock = clock,
  })
end
