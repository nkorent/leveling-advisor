local _, ns = ...

-- Travel costs between zones: Dijkstra over the zone-link graph.
-- Costs are in XP (yards * TRAVEL_XP_PER_YD + LINK_XP[kind]).
local Travel = {}
ns.Travel = Travel

local FACTION_ID = { Alliance = 1, Horde = 2 }

-- Zone faction is a questing affinity, not a wall: only the other faction's
-- capital (a city) is closed to a traveller.
local function enterable(z, factionID)
  if z == nil or not z.live then return false end
  local enemyCapital = z.kind == "city" and (z.faction == 1 or z.faction == 2) and z.faction ~= factionID
  return not enemyCapital
end

-- The point where a traveller lands in `to` after taking a `kind` link from `from`.
local function arrivalPoint(db, to, from, kind)
  local z = db:zone(to)
  for _, l in ipairs(z and z.links or {}) do
    if l.to == from and l.kind == kind then return { to, l.x or 50, l.y or 50 } end
  end
  return { to, 50, 50 }
end

function Travel.fromPlayer(db, state)
  local reach = {}
  if not (state and state.mapID) then return reach end
  local T = ns.Tuning
  local factionID = FACTION_ID[state.faction]

  local ids = db:zoneIDs()
  table.sort(ids)

  reach[state.mapID] = {
    xp = 0, hops = {},
    arrive = (state.x and state.y) and { state.mapID, state.x, state.y } or { state.mapID, 50, 50 },
  }

  local done = {}
  while true do
    local cur, curXP
    for _, id in ipairs(ids) do
      local r = reach[id]
      if r and not done[id] and (curXP == nil or r.xp < curXP) then cur, curXP = id, r.xp end
    end
    -- the start zone may be missing from zoneIDs; handle it explicitly
    if reach[state.mapID] and not done[state.mapID] and (curXP == nil or reach[state.mapID].xp < curXP) then
      cur, curXP = state.mapID, reach[state.mapID].xp
    end
    if not cur then break end
    done[cur] = true

    local node = reach[cur]
    local z = db:zone(cur)
    for _, l in ipairs(z and z.links or {}) do
      local target = db:zone(l.to)
      if not done[l.to]
        and (l.faction == nil or l.faction == factionID)
        and enterable(target, factionID) then
        local yards = ns.Geo.distance(db, node.arrive, { cur, l.x, l.y })
        local cost = node.xp + (yards or 0) * T.TRAVEL_XP_PER_YD + (T.LINK_XP[l.kind] or 0)
        local existing = reach[l.to]
        if existing == nil or cost < existing.xp then
          local hops = {}
          for i, h in ipairs(node.hops) do hops[i] = h end
          hops[#hops + 1] = l.label
          reach[l.to] = {
            xp = cost, hops = hops,
            arrive = arrivalPoint(db, l.to, cur, l.kind),
            approx = (node.approx or yards == nil) or nil,
          }
        end
      end
    end
  end
  return reach
end

function Travel.costTo(db, reach, state, point)
  local T = ns.Tuning
  local mapID = ns.Geo.unpackPoint(point)
  local r = mapID and reach[mapID]
  if r then
    local yards = ns.Geo.distance(db, r.arrive, point)
    return r.xp + (yards or 0) * T.TRAVEL_XP_PER_YD
  end
  local from = { state.mapID, state.x or 50, state.y or 50 }
  local yards = state.mapID and ns.Geo.distance(db, from, point)
  if yards then return yards * T.TRAVEL_XP_PER_YD end
  return T.CONTINENT_CHANGE_XP
end
