local _, ns = ...

-- Picks the one dungeon worth running now: the best by XP minus travel.
local Dungeons = {}
ns.Dungeons = Dungeons

local WORDS = { [2] = "two", [3] = "three", [4] = "four" }

-- The reason line: the best level, and how many of the quests start on the way.
local function reasonFor(bestLevel, onWay)
  local text = "Best at " .. bestLevel
  if onWay <= 0 then return text end
  if onWay == 1 then return text .. " — one of its quests starts on your way" end
  return text .. " — " .. (WORDS[onWay] or tostring(onWay)) .. " of its quests start on your way"
end
Dungeons.reasonFor = reasonFor

local function dist(db, from, p)
  if not (from and from[1] and from[2] and from[3] and p and p.mapID and p.x and p.y) then return nil end
  return (ns.Geo.distance(db, from, { p.mapID, p.x, p.y }))
end

-- Greedy nearest-next from the player; nil distances go last by quest ID.
local function orderPickups(db, state, list)
  table.sort(list, function(a, b) return a.questID < b.questID end)
  local out = {}
  local cur = { state.mapID, state.x, state.y }
  while #list > 0 do
    local bi, bd
    for i, p in ipairs(list) do
      local d = dist(db, cur, p)
      if d and (bd == nil or d < bd) then bi, bd = i, d end
    end
    if not bi then
      for _, p in ipairs(list) do out[#out + 1] = p end
      break
    end
    local p = table.remove(list, bi)
    out[#out + 1] = p
    cur = { p.mapID, p.x, p.y }
  end
  return out
end

-- The lowest level at which two of the quests are good (`goods` sorted
-- ascending: each quest's goodAt), kept within the dungeon's range. With fewer
-- than two quests, or when the level is above the range, "minLevel - 1".
function Dungeons.bestLevel(goods, d)
  local level = goods[2]
  if not level or level > d.maxLevel then return d.minLevel - 1 end
  return math.max(level, d.minLevel)
end

function Dungeons.recommend(db, state, candidates, zones, reach)
  if state.settings and state.settings.dungeons == false then return nil end
  local T = ns.Tuning
  local level = state.level
  local factionID = ns.Eligibility.FACTION_ID[state.faction]
  reach = reach or ns.Travel.fromPlayer(db, state)

  local byID
  local function candidateOf(id)
    if not byID then
      byID = {}
      for _, c in ipairs(candidates) do
        if c.quest.dungeonQuest then byID[c.quest.id] = c end
      end
    end
    return byID[id]
  end

  local nextZone
  for _, z in ipairs(zones or {}) do
    if z.mapID ~= state.mapID then nextZone = z.mapID; break end
  end

  local best, bestScore, bestKey
  for _, key in ipairs(db:dungeonKeys()) do
    local d = db:dungeon(key)
    if d.live and not ns.Eligibility.otherFaction(d.faction, factionID) and d.minLevel and d.maxLevel
        and level >= d.minLevel - T.DUNGEON_LEVEL_WINDOW and level <= d.maxLevel then
      local list = {}
      for _, id in ipairs(d.quests or {}) do
        local c = candidateOf(id)
        -- only quests the engine recommends qualify a dungeon: not a later quest (orange, soon, or
        -- orange or red in the log), nor a grey one in the log; a complete one still does
        if c and ns.Candidates.recommendable(c) then
          list[#list + 1] = c
        end
      end
      if #list >= 2 then
        local atLevel = math.max(level, d.minLevel)
        local xp = 0
        for _, c in ipairs(list) do
          xp = xp + (ns.XP.estimate(c.quest, atLevel, state.recordedXP) or 0)
        end
        local em, ex, ey = ns.Geo.unpackPoint(d.entrance or {})
        local score = xp + T.DUNGEON_RUN_XP - ns.Travel.costTo(db, reach, state, { em, ex, ey })
        -- ties keep the first key (dungeonKeys is sorted)
        if bestScore == nil or score > bestScore then
          bestScore, bestKey = score, key
          best = { d = d, list = list, xp = xp }
        end
      end
    end
  end
  if not best then return nil end

  local d = best.d
  local pickups = {}
  for _, c in ipairs(best.list) do
    local g = c.quest.giver or {}
    pickups[#pickups + 1] = {
      questID = c.quest.id, mapID = g.mapID, x = g.x, y = g.y,
      inLog = (c.status == "progress" or c.status == "complete"),
    }
  end
  pickups = orderPickups(db, state, pickups)

  local onWay = 0
  for _, p in ipairs(pickups) do
    if not p.inLog and p.mapID and (p.mapID == state.mapID or p.mapID == nextZone) then onWay = onWay + 1 end
  end
  -- the lowest level at which two of its quests are yellow or green (quest level - L <= 2)
  local levels = {}
  for _, c in ipairs(best.list) do
    if c.quest.level then levels[#levels + 1] = ns.Difficulty.goodAt(c.quest) end
  end
  table.sort(levels)
  -- within the dungeon's range; above it (all quests too high) or fewer than two quests: the old text
  local bestLevel = Dungeons.bestLevel(levels, d)
  local em, ex, ey = ns.Geo.unpackPoint(d.entrance or {})
  return {
    key = bestKey, name = d.name, minLevel = d.minLevel, maxLevel = d.maxLevel,
    groupSize = d.groupSize, questCount = #best.list, xp = best.xp,
    bestLevel = bestLevel, reason = reasonFor(bestLevel, onWay),
    entrance = { mapID = em, x = ex, y = ey },
    pickups = pickups,
  }
end
