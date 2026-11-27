local _, ns = ...

-- Decoder for Contract A data. Pure Lua, no WoW globals.
local DB = {}
DB.__index = DB
ns.DB = DB

local function sortedKeys(t)
  local out = {}
  for k in pairs(t or {}) do out[#out + 1] = k end
  table.sort(out)
  return out
end

local function hasFlag(flags, bit)
  return math.floor((flags or 0) / bit) % 2 == 1
end

local function decodePlace(p)
  if not p then return nil end
  return { kind = p[1], id = p[2], mapID = p[3], x = p[4], y = p[5] }
end

local function copyList(list)
  local out = {}
  for i, v in ipairs(list or {}) do out[i] = v end
  return out
end

-- Field 26: { {kind, id, name, count, from, fromKind, fromMore}, ... } (kind 1 npc, 2 object,
-- 3 item, 4 other; fromKind 1 NPCs, 2 objects). `from` is copied.
local function decodeObjectives(list)
  local out = {}
  for i, o in ipairs(list or {}) do
    out[i] = { index = i, kind = o[1], id = o[2], name = o[3], count = o[4],
      from = o[5] and copyList(o[5]) or nil, fromKind = o[6], fromMore = o[7] }
  end
  return out
end

local function decode(id, r)
  local flags = r[9] or 0
  local objectives = decodeObjectives(r[26])
  local points = {}
  for i, p in ipairs(r[13] or {}) do
    -- a 4th element is the objective's index in field 26 (nil: the point names no known objective)
    points[i] = { mapID = p[1], x = p[2], y = p[3], objective = p[4] and objectives[p[4]] or nil }
  end
  local chain
  if r[22] then chain = { id = r[22][1], index = r[22][2], length = r[22][3] } end
  local prereq = r[19] or {}
  return {
    id = id, name = r[1], faction = r[2], raceMask = r[3], classMask = r[4],
    requiredLevel = r[5], level = r[6], levelSource = r[7], zone = r[8],
    flags = flags,
    elite = hasFlag(flags, 1), classQuest = hasFlag(flags, 2),
    newInForever = hasFlag(flags, 4), unverified = hasFlag(flags, 8),
    repeatable = hasFlag(flags, 16), dungeonQuest = hasFlag(flags, 32),
    groupSize = r[10], giver = decodePlace(r[11]), turnIn = decodePlace(r[12]),
    points = points, objectiveText = r[14], items = r[15], rewards = r[16],
    xp = r[17], xpSource = r[18],
    prereq = { all = copyList(prereq.all), any = copyList(prereq.any) },
    exclusiveTo = copyList(r[20]), breadcrumbOf = r[21], chain = chain,
    dungeonKey = r[23], requiredMaxLevel = r[24],
    -- ineligible once any of these is completed or in the log (Eligibility only, never Route)
    unavailableAfter = copyList(r[25]),
    objectives = objectives,
  }
end

local function decodeStub(id, r)
  local prereq = r[7] or {}
  local start = r[8]
  return {
    id = id, name = r[1], level = r[2], requiredLevel = r[3], faction = r[4],
    raceMask = r[5], classMask = r[6],
    prereq = { all = copyList(prereq.all), any = copyList(prereq.any) },
    start = start and { kind = start.kind, name = start.name, mapID = start.mapID } or nil,
    reason = r[9],
  }
end

function DB.new(data)
  local self = setmetatable({}, DB)
  self.data = data
  self.cache = {}
  self.stubCache = {}
  self.zoneCache = {}
  self.ids = sortedKeys(data.quests)
  self.byZone = {}
  for _, id in ipairs(self.ids) do
    local g = data.quests[id][11]
    local map = g and g[3]
    if map then
      local list = self.byZone[map]
      if not list then list = {}; self.byZone[map] = list end
      list[#list + 1] = id
    end
  end
  return self
end

function DB:quest(id)
  local q = self.cache[id]
  if q then return q end
  local r = self.data.quests and self.data.quests[id]
  if not r then return nil end
  q = decode(id, r)
  self.cache[id] = q
  return q
end

-- An excluded quest that shipped quests need as a prerequisite (Contract A questStubs), or nil.
function DB:stub(id)
  local s = self.stubCache[id]
  if s then return s end
  local r = self.data.questStubs and self.data.questStubs[id]
  if not r then return nil end
  s = decodeStub(id, r)
  self.stubCache[id] = s
  return s
end

-- Fresh sorted copy each call.
function DB:questIDs() return copyList(self.ids) end
function DB:stubIDs() return sortedKeys(self.data.questStubs) end
function DB:questsInZone(mapID) return copyList(self.byZone[mapID]) end

function DB:npc(id) return self.data.npcs and self.data.npcs[id] end
-- Zone records are the data tables, except that kind is validated: only "city" and
-- "battleground" are known; anything else reads as nil (a leveling zone). Cached per DB.
local ZONE_KINDS = { city = true, battleground = true }
function DB:zone(mapID)
  local raw = self.data.zones and self.data.zones[mapID]
  if not raw then return nil end
  if raw.kind == nil then return raw end
  local z = self.zoneCache[mapID]
  if z then return z end
  z = {}
  for k, v in pairs(raw) do z[k] = v end
  if not ZONE_KINDS[z.kind] then z.kind = nil end
  self.zoneCache[mapID] = z
  return z
end
function DB:zoneIDs() return sortedKeys(self.data.zones) end
function DB:continent(mapID) return self.data.continents and self.data.continents[mapID] end
function DB:dungeon(key) return self.data.dungeons and self.data.dungeons[key] end
function DB:dungeonKeys() return sortedKeys(self.data.dungeons) end
