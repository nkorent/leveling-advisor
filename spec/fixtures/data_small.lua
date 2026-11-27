-- Synthetic Contract A fixture: real names, invented numbers.
local _, ns = ...
ns.Data = ns.Data or {}

local E, C, N, U, D = 1, 2, 4, 8, 32
local ALLIANCE, HORDE = 1, 2

-- Builds a positional Contract A record. o = optional fields:
-- raceMask, classMask, group, turnIn = {npc, x, y}, points = {{x, y}}, rewards,
-- prereq, exclusiveTo, breadcrumbOf, chain, dungeonKey, giverNpc, requiredMaxLevel.
local function Q(name, fac, req, lvl, zone, flags, gx, gy, xp, o)
  o = o or {}
  local giverNpc = o.giverNpc or (3000 + math.floor(gx * 10))
  local giver = { 1, giverNpc, zone, gx, gy }
  local turnIn
  if o.turnIn then
    turnIn = { 1, o.turnIn[1], zone, o.turnIn[2], o.turnIn[3] }
  else
    turnIn = { 1, giverNpc, zone, gx, gy } -- giver = turn-in
  end
  local points
  if o.points then
    points = {}
    for i, p in ipairs(o.points) do points[i] = { zone, p[1], p[2] } end
  end
  local r = {}
  r[1] = name; r[2] = fac; r[3] = o.raceMask; r[4] = o.classMask
  r[5] = req; r[6] = lvl; r[7] = 1; r[8] = zone; r[9] = flags
  r[10] = o.group; r[11] = giver; r[12] = turnIn; r[13] = points
  r[14] = "Objective of " .. name; r[16] = o.rewards
  r[17] = xp; r[18] = 1; r[19] = o.prereq; r[20] = o.exclusiveTo
  r[21] = o.breadcrumbOf; r[22] = o.chain; r[23] = o.dungeonKey
  r[24] = o.requiredMaxLevel
  return r
end

local dungeon = { group = 5, dungeonKey = "BFD" }
local function dq(name, req, lvl, zone, gx, gy, xp)
  return Q(name, ALLIANCE, req, lvl, zone, D, gx, gy, xp, dungeon)
end
local function filler(name, req, lvl, xp, o)
  return Q(name, ALLIANCE, req, lvl, 1439, 0, 40.0, 40.0, xp, o)
end

ns.Data.quests = {
  [965] = Q("The Tower of Althalaxx", ALLIANCE, 13, 18, 1439, 0, 39.1, 43.6, 675,
    { turnIn = { 3965, 55.0, 24.9 }, chain = { 965, 1, 6 } }),
  [966] = Q("The Tower of Althalaxx", ALLIANCE, 13, 18, 1439, 0, 55.0, 24.9, 1150,
    { points = { { 56.0, 26.0 } }, prereq = { all = { 965 } }, chain = { 965, 2, 6 }, giverNpc = 3965 }),
  [967] = Q("The Tower of Althalaxx", ALLIANCE, 13, 18, 1439, 0, 55.0, 24.9, 1200,
    { points = { { 57.0, 27.0 } }, prereq = { all = { 966 } }, chain = { 965, 3, 6 }, giverNpc = 3965 }),
  [4762] = Q("The Cliffspring River", ALLIANCE, 15, 16, 1439, 0, 37.4, 40.1, 1050,
    { points = { { 50.0, 35.0 } }, giverNpc = 3649 }),
  [4763] = Q("The Blackwood Corrupted", ALLIANCE, 15, 18, 1439, 0, 37.4, 40.1, 1700,
    { points = { { 52.5, 33.4 } }, prereq = { all = { 4762 } }, giverNpc = 3649,
      rewards = { choice = { { 15204, 1 }, { 15202, 1 }, { 15203, 1 } } } }),
  [4730] = Q("Beached Sea Creature", ALLIANCE, 10, 17, 1439, 0, 36.0, 45.0, 880,
    { turnIn = { 3371, 37.0, 44.0 } }),
  [5061] = Q("Aquatic Form", ALLIANCE, 16, 16, 1439, C, 36.5, 46.0, 1300, { classMask = 1024 }),
  [1000] = Q("The Lost Mine", ALLIANCE, 16, 19, 1439, E, 60.0, 20.0, 1500, { points = { { 61.0, 21.0 } } }),
  [1010] = Q("Bathran's Hair", ALLIANCE, 16, 19, 1440, 0, 36.0, 50.0, 1450, { points = { { 31.0, 22.0 } } }),
  [991] = Q("Raene's Cleansing", ALLIANCE, 18, 21, 1440, 0, 36.0, 50.0, 1050, { chain = { 991, 1, 7 } }),
  [1007] = Q("The Ancient Statuette", ALLIANCE, 17, 20, 1440, 0, 34.0, 48.0, 1350, { points = { { 20.0, 40.0 } } }),
  [1100] = Q("Riverglades Survey", ALLIANCE, 18, 20, 1440, N + U, 38.0, 52.0, 1200),
  [6382] = Q("The Ashenvale Hunt", HORDE, 20, 24, 1440, 0, 73.0, 61.0, 1100),
  [1081] = Q("Filthy Paws", ALLIANCE, 10, 15, 1432, 0, 35.0, 47.0, 900),
  [840] = Q("Conscript of the Horde", HORDE, 10, 12, 1411, 0, 54.0, 42.0, 400),
  [1275] = dq("Researching the Corruption", 18, 24, 1439, 38.5, 43.0, 2100),
  [1199] = dq("Twilight Falls", 20, 24, 1439, 38.0, 42.0, 2250),
  [6563] = dq("In Search of Thaelrid", 18, 24, 1440, 35.0, 45.0, 2000),
  [6922] = dq("Knowledge in the Deeps", 19, 23, 1432, 40.0, 40.0, 2050),
  -- A second dungeon's quest, eligible at S18 and S20, beside the player in Darkshore: routes,
  -- sections and dungeon picks must keep it apart from BFD (WC has one quest, never recommended).
  [1486] = Q("Deviate Hides", ALLIANCE, 17, 21, 1439, D, 38.2, 41.5, 1800, { group = 5, dungeonKey = "WC" }),
  [7001] = filler("Human Only", 10, 18, 500, { raceMask = 1 }),
  [7002] = filler("Warrior Only", 10, 18, 500, { classMask = 1 }),
  [7003] = filler("Either Way", 10, 18, 500, { prereq = { any = { 7004, 965 } } }),
  [7005] = filler("Exclusive", 10, 18, 500, { exclusiveTo = { 965 } }),
  [7006] = filler("Breadcrumb", 10, 18, 500, { breadcrumbOf = 966 }),
  [7007] = filler("Broken Record", nil, 18, 500),
  [7008] = filler("Too Late", 10, 18, 500, { requiredMaxLevel = 15 }),
}

ns.Data.npcs = {
  [3649] = { "Sentinel Shaya", 1, 16, { { 1439, 37.4, 40.1 } } },
  [3965] = { "Gelkak Gyromast", 1, 18, { { 1439, 55.0, 24.9 } } },
  [3371] = { "Marine Tidehunter", 1, 17, { { 1439, 37.0, 44.0 } } },
}

ns.Data.zones = {
  [1439] = { name = "Darkshore", continent = 1414, faction = 1, minLevel = 10, maxLevel = 20,
    live = true, complete = true, yards = { 6000, 4000 }, rect = { 0.38, 0.52, 0.12, 0.33 },
    links = {
      { to = 1440, kind = "walk", x = 45, y = 90, label = "walk south" },
      { to = 1432, kind = "boat", x = 32, y = 44, label = "boat from Auberdine" },
    } },
  [1440] = { name = "Ashenvale", continent = 1414, faction = 3, minLevel = 18, maxLevel = 30,
    live = true, complete = true, yards = { 5800, 3866 }, rect = { 0.30, 0.55, 0.33, 0.50 },
    links = {
      { to = 1439, kind = "walk", x = 40, y = 5, label = "walk north" },
      { to = 1411, kind = "walk", x = 90, y = 50, label = "walk east" },
      { to = 1432, kind = "zeppelin", x = 40, y = 12, label = "zeppelin (Horde)", faction = 2 },
    } },
  [1432] = { name = "Loch Modan", continent = 1415, faction = 1, minLevel = 10, maxLevel = 20,
    live = true, complete = true, yards = { 2750, 1833 }, rect = { 0.55, 0.62, 0.55, 0.63 },
    links = {} },
  [1411] = { name = "Durotar", continent = 1414, faction = 2, minLevel = 1, maxLevel = 12,
    live = true, complete = true, yards = { 5300, 3533 }, rect = { 0.58, 0.70, 0.42, 0.62 },
    links = {
      { to = 1440, kind = "walk", x = 10, y = 50, label = "walk west" },
    } },
}

ns.Data.continents = {
  [1414] = { name = "Kalimdor", yards = { 36800, 24533 } },
  [1415] = { name = "Eastern Kingdoms", yards = { 40740, 27160 } },
}

ns.Data.dungeons = {
  BFD = { name = "Blackfathom Deeps", entrance = { 1440, 14.0, 14.0 }, minLevel = 22, maxLevel = 28,
    groupSize = 5, faction = 3, live = true, quests = { 1199, 1275, 6563, 6922 } },
  WC = { name = "Wailing Caverns", entrance = { 1440, 90.0, 60.0 }, minLevel = 17, maxLevel = 24,
    groupSize = 5, faction = 3, live = true, quests = { 1486 } },
}

ns.Data.meta = { built = "2026-11-24", gameData = "1.60.1", sources = { "fixture" },
  counts = { quests = 26, npcs = 3 } }
