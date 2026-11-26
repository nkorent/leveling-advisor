local _, ns = ...

-- Turns WoW API calls into Contract B (PlayerState). The pure engine only ever
-- sees the table built here.
local Adapter = {}
ns.Adapter = Adapter

local call = ns.Util.call

local function maskOf(id)
  if type(id) ~= "number" or id < 1 then return nil end
  return 2 ^ (id - 1)
end

-- Forever ChrRaces 1.60.1 race bits (QuestieDB constants.raceMaskById): races 1..9 are
-- 2^(id-1); High Order Skyborne (95) is 2^32 and Windshaper Skyborne (96) 2^33, not 2^(id-1).
-- Masks up to 2^34 are exact in Lua doubles; only plain arithmetic is used on them.
local SKYBORNE_RACE_BITS = { [95] = 2 ^ 32, [96] = 2 ^ 33 }

local function raceMaskOf(id)
  return SKYBORNE_RACE_BITS[id] or maskOf(id)
end

local function copySet(t)
  local out = {}
  if type(t) == "table" then
    for k, v in pairs(t) do out[k] = v end
  end
  return out
end

-- Returns a NEW PlayerState table on every call (Engine.route reuses
-- candidates only for the same state table plus fingerprint).
function Adapter.snapshot(api, db, chardb)
  local faction = api.faction()
  if faction ~= "Alliance" and faction ~= "Horde" then faction = nil end

  local raceID = api.race()
  local classFile, classID = api.class()

  local mapID = api.mapID()
  local x, y
  if mapID then
    local px, py = api.position(mapID)
    if px and py then
      x = ns.Util.round1(px * 100)
      y = ns.Util.round1(py * 100)
    end
  end

  local completed = {}
  local list = api.completed()
  if type(list) == "table" then
    for i = 1, #list do completed[list[i]] = true end
  end

  return {
    faction = faction,
    raceMask = raceMaskOf(raceID),
    classMask = maskOf(classID),
    classFile = classFile,
    level = api.level(),
    xp = api.xp(),
    xpMax = api.xpMax(),
    mapID = mapID,
    x = x,
    y = y,
    greyAtOrBelow = api.greyAtOrBelow(),
    completed = completed,
    log = copySet(api.logEntries()),
    ignored = copySet(chardb and chardb.ignored),
    recordedXP = db and db.recorder and db.recorder.xp,
    settings = ns.Settings.forEngine(),
  }
end

-- level - range - 1, then each log sample corrects it: a trivial quest raises
-- the level to its own, a non-trivial one lowers it below its own.
function Adapter.greyLevel(level, range, samples)
  if type(level) ~= "number" or type(range) ~= "number" or range <= 0 then return nil end
  local g = level - range - 1
  for _, s in ipairs(samples or {}) do
    if type(s.level) == "number" then
      if s.trivial == true then g = math.max(g, s.level)
      elseif s.trivial == false then g = math.min(g, s.level - 1) end
    end
  end
  return g
end

-- Calls fn(info) for each visible quest of the log (no headers, no hidden).
local function eachLogQuest(fn)
  local n = C_QuestLog.GetNumQuestLogEntries() or 0
  for i = 1, n do
    local info = C_QuestLog.GetInfo(i)
    if info and not info.isHeader and not info.isHidden and info.questID then fn(info) end
  end
end

-- Fail-soft wrappers around the live WoW API. Globals are looked up at call
-- time so missing APIs just yield nil.
function Adapter.realApi()
  local api = {}

  function api.faction() return call(function() return UnitFactionGroup("player") end) end
  function api.race()
    return call(function() local _, _, id = UnitRace("player"); return id end)
  end
  function api.class()
    return call(function() local _, file, id = UnitClass("player"); return file, id end)
  end
  function api.level() return call(function() return UnitLevel("player") end) end
  function api.xp() return call(function() return UnitXP("player") end) end
  function api.xpMax() return call(function() return UnitXPMax("player") end) end
  function api.mapID() return call(function() return C_Map.GetBestMapForUnit("player") end) end

  function api.position(mapID)
    return call(function()
      local pos = C_Map.GetPlayerMapPosition(mapID, "player")
      if not pos then return nil end
      return pos:GetXY()
    end)
  end

  function api.completed()
    local list = call(function() return C_QuestLog.GetAllCompletedQuestIDs() end)
    if type(list) ~= "table" then return {} end
    return list
  end

  function api.logEntries()
    local ok, out = pcall(function()
      local log = {}
      eachLogQuest(function(info)
        local complete
        if C_QuestLog.IsComplete then
          complete = C_QuestLog.IsComplete(info.questID)
        else
          complete = info.isComplete
        end
        log[info.questID] = { complete = complete and true or false }
      end)
      return log
    end)
    if ok and type(out) == "table" then return out end
    return {}
  end

  -- Quest level at or below which a quest is grey: the client's trivial range,
  -- corrected by IsQuestTrivial for the quests in the log (diagnostic-results.md).
  function api.greyAtOrBelow()
    local level = call(function() return UnitLevel("player") end)
    local range = call(function() return UnitQuestTrivialLevelRange("player") end)
    local ok, samples = pcall(function()
      local list = {}
      eachLogQuest(function(info)
        local trivial
        if C_QuestLog.IsQuestTrivial then trivial = C_QuestLog.IsQuestTrivial(info.questID) end
        list[#list + 1] = { level = info.level, trivial = trivial }
      end)
      return list
    end)
    return Adapter.greyLevel(level, range, ok and samples or {})
  end

  return api
end
