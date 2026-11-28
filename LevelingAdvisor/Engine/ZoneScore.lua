local _, ns = ...

-- Ranks up to MAX_ZONES zones by XP value minus travel cost. Only quests the
-- engine recommends count (Candidates.recommendable: yellow and green quests,
-- plus turn-ins), each weighted by its colour (Tuning.FIT_WEIGHT).
local ZoneScore = {}
ns.ZoneScore = ZoneScore

local function countable(c)
  return ns.Candidates.recommendable(c) and not c.quest.dungeonQuest
end

local function usableZone(z, factionID)
  if not (z and z.live) then return false end
  if z.kind ~= nil then return false end    -- cities and battlegrounds are not leveling zones
  return not ns.Eligibility.otherFaction(z.faction, factionID)
end

-- green: how many of the zone's counted quests are eligible green ones (not logged); total: all of them.
local function reasonFor(db, state, zone, isHere, green, total)
  if isHere then return "You are here — finish before you leave" end
  if green * 2 > total then
    return "Catch up — " .. green .. (green == 1 and " quest" or " quests") .. " you skipped at your level"
  end
  local here = state.mapID and db:zone(state.mapID)
  local factionID = ns.Eligibility.FACTION_ID[state.faction]
  for _, l in ipairs(here and here.links or {}) do
    -- never name the other faction's transport (spec 5.4)
    local usable = not ns.Eligibility.otherFaction(l.faction, factionID)
    if l.to == zone and usable then
      if l.kind == "walk" then return "Next zone — " .. l.label end
      return "Alternative — " .. l.label
    end
  end
  return "Most XP for your level"
end

function ZoneScore.rank(db, state, candidates, reach)
  local T = ns.Tuning
  local factionID = ns.Eligibility.FACTION_ID[state.faction]
  reach = reach or ns.Travel.fromPlayer(db, state)

  -- group counted candidates by zone, in ascending quest ID order
  local byZone, zoneOrder = {}, {}
  local sorted = {}
  for _, c in ipairs(candidates) do
    if countable(c) then sorted[#sorted + 1] = c end
  end
  table.sort(sorted, function(a, b) return a.quest.id < b.quest.id end)
  for _, c in ipairs(sorted) do
    local m = c.quest.zone
    if m and usableZone(db:zone(m), factionID) then
      if not byZone[m] then byZone[m] = {}; zoneOrder[#zoneOrder + 1] = m end
      local list = byZone[m]
      list[#list + 1] = c
    end
  end

  local zones = {}
  for _, mapID in ipairs(zoneOrder) do
    local list = byZone[mapID]
    local points = {}
    for i, c in ipairs(list) do
      local g = c.quest.giver or {}
      points[i] = { g.mapID or mapID, g.x or 50, g.y or 50, c.quest.id }
    end
    local sharing = {}
    for _, hub in ipairs(ns.Hubs.cluster(db, points, T.HUB_RADIUS_YD)) do
      for _, id in ipairs(hub.members) do sharing[id] = #hub.members end
    end

    local score, xp, chainSet, chains, green = 0, 0, {}, 0, 0
    for _, c in ipairs(list) do
      local q = c.quest
      local hubFactor = 1 + math.min(T.HUB_BONUS * ((sharing[q.id] or 1) - 1), T.HUB_BONUS_CAP)
      local solo = ns.Candidates.isGroupQuest(q) and T.ELITE_SOLO_FACTOR or 1
      -- a turn-in is worth its full XP whatever its colour: the trip is made anyway
      local weight = c.status == "complete" and T.FIT_WEIGHT.yellow or (T.FIT_WEIGHT[c.fit] or 1)
      score = score + c.xp * solo * hubFactor * weight
      xp = xp + c.xp
      if c.status == "eligible" and c.fit == "green" then green = green + 1 end
      if q.chain and q.chain.id and not chainSet[q.chain.id] then
        chainSet[q.chain.id] = true
        chains = chains + 1
      end
    end

    local isHere = (mapID == state.mapID)
    if not isHere then
      score = score - ns.Travel.costTo(db, reach, state, { mapID, 50, 50 })
    end
    local z = db:zone(mapID)
    zones[#zones + 1] = {
      mapID = mapID, name = z.name, minLevel = z.minLevel, maxLevel = z.maxLevel,
      questCount = #list, xp = xp, chains = chains, isHere = isHere, score = score,
      reason = reasonFor(db, state, mapID, isHere, green, #list),
    }
  end

  -- the player's zone comes first only with enough quests that fit their level
  local function pinned(z) return z.isHere and z.questCount >= T.HERE_MIN_QUESTS end
  table.sort(zones, function(a, b)
    local pa, pb = pinned(a), pinned(b)
    if pa ~= pb then return pa end
    if a.score ~= b.score then return a.score > b.score end
    return a.mapID < b.mapID
  end)
  for i = #zones, T.MAX_ZONES + 1, -1 do zones[i] = nil end
  return zones
end
