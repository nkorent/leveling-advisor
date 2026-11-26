local addon = require("spec.helpers.addon")
local H = require("spec.helpers.engine")

local FILES = { "Core/Util.lua", "Core/Init.lua", "Core/Settings.lua", "Core/Adapter.lua" }

local function fakeApi(over)
  local api = {
    faction = function() return "Alliance" end,
    race = function() return 4 end,
    class = function() return "DRUID", 11 end,
    level = function() return 18 end,
    xp = function() return 4500 end,
    xpMax = function() return 7300 end,
    mapID = function() return 1439 end,
    position = function() return 0.374, 0.401 end,
    completed = function() return { 965, 1000 } end,
    logEntries = function() return { [966] = { complete = false }, [4730] = { complete = true } } end,
    greyAtOrBelow = function() return nil end,
  }
  for k, v in pairs(over or {}) do api[k] = v end
  return api
end

local function setup()
  local ns, env = addon.load(FILES)
  ns.db = { settings = {}, recorder = { xp = { [966] = { [18] = 700 } } } }
  return ns, env
end

describe("Adapter.snapshot", function()
  it("builds Contract B for a level-18 Night Elf Druid", function()
    local ns = setup()
    local chardb = { ignored = { [55] = true } }
    local s = ns.Adapter.snapshot(fakeApi(), ns.db, chardb)
    assert.equals("Alliance", s.faction)
    assert.equals(8, s.raceMask)
    assert.equals(1024, s.classMask)
    assert.equals("DRUID", s.classFile)
    assert.equals(18, s.level)
    assert.equals(4500, s.xp)
    assert.equals(7300, s.xpMax)
    assert.equals(1439, s.mapID)
    assert.equals(37.4, s.x)
    assert.equals(40.1, s.y)
    assert.is_false(s.log[966].complete)
    assert.is_true(s.log[4730].complete)
    assert.is_true(s.completed[965])
    assert.equals(ns.db.recorder.xp, s.recordedXP)
    assert.same({ elite = true, dungeons = true }, s.settings)
  end)

  it("returns a new table each call", function()
    local ns = setup()
    local a = ns.Adapter.snapshot(fakeApi(), ns.db, { ignored = {} })
    local b = ns.Adapter.snapshot(fakeApi(), ns.db, { ignored = {} })
    assert.are_not.equal(a, b)
  end)

  it("leaves mapID, x, y nil in an instance and never calls position", function()
    local ns = setup()
    local called = 0
    local api = fakeApi({
      mapID = function() return nil end,
      position = function() called = called + 1; return 0.1, 0.2 end,
    })
    local s = ns.Adapter.snapshot(api, ns.db, { ignored = {} })
    assert.is_nil(s.mapID)
    assert.is_nil(s.x)
    assert.is_nil(s.y)
    assert.equals(0, called)
  end)

  it("keeps mapID with nil x/y when the position is unavailable (instance map)", function()
    local ns = addon.load({
      "Core/Util.lua", "Core/Init.lua", "Core/Settings.lua", "Core/Adapter.lua",
      "Core/DB.lua", "Engine/Tuning.lua", "Engine/Difficulty.lua", "Engine/XP.lua",
      "Engine/Geo.lua", "Engine/Eligibility.lua", "Engine/Hubs.lua",
      "Engine/Travel.lua", "Engine/Candidates.lua", "Engine/ZoneScore.lua",
      "Engine/Sections.lua", "Engine/Dungeons.lua", "Engine/Route.lua",
      "Engine/RouteImprove.lua", "Engine/Engine.lua",
    })
    ns.db = { settings = {}, recorder = { xp = {} } }
    local api = fakeApi({
      mapID = function() return 227 end, -- an instance uiMapID
      position = function() return nil end,
    })
    local s = ns.Adapter.snapshot(api, ns.db, { ignored = {} })
    assert.equals(227, s.mapID)
    assert.is_nil(s.x)
    assert.is_nil(s.y)
    local rec = ns.Engine.compute(ns.DB.new(H.data()), s)
    assert.is_table(rec)
    assert.is_table(rec.zones)
    assert.is_table(rec.sections)
    assert.is_true(rec.dungeon == nil or type(rec.dungeon) == "table")
  end)

  it("drops a Neutral faction", function()
    local ns = setup()
    local s = ns.Adapter.snapshot(fakeApi({ faction = function() return "Neutral" end }), ns.db, { ignored = {} })
    assert.is_nil(s.faction)
  end)

  it("maps the Forever Skyborne races to their ChrRaces bits (race only)", function()
    local ns = setup()
    local function masks(raceID, classID)
      local s = ns.Adapter.snapshot(fakeApi({
        race = function() return raceID end,
        class = function() return "WARRIOR", classID end,
      }), ns.db, { ignored = {} })
      return s.raceMask, s.classMask
    end
    assert.equals(2 ^ 32, (masks(95, 1)))          -- High Order Skyborne
    assert.equals(2 ^ 33, (masks(96, 1)))          -- Windshaper Skyborne
    assert.equals(4294967296, (masks(95, 1)))      -- exact, not a 32-bit wrap
    assert.equals(256, (masks(9, 1)))              -- Goblin: 2^(id-1)
    assert.equals(1, (masks(1, 1)))
    local _, classMask = masks(95, 11)
    assert.equals(1024, classMask)                 -- the class mask stays 2^(id-1)
  end)

  it("gives nil masks when race or class are unknown", function()
    local ns = setup()
    local s = ns.Adapter.snapshot(fakeApi({
      race = function() return nil end,
      class = function() return nil end,
    }), ns.db, { ignored = {} })
    assert.is_nil(s.raceMask)
    assert.is_nil(s.classMask)
  end)

  it("copies ignored", function()
    local ns = setup()
    local chardb = { ignored = { [55] = true } }
    local s = ns.Adapter.snapshot(fakeApi(), ns.db, chardb)
    assert.is_true(s.ignored[55])
    s.ignored[56] = true
    assert.is_nil(chardb.ignored[56])
  end)

  it("feeds Engine.compute from an instance snapshot (Review Focus 2)", function()
    local ns = addon.load({
      "Core/Util.lua", "Core/Init.lua", "Core/Settings.lua", "Core/Adapter.lua",
      "Core/DB.lua", "Engine/Tuning.lua", "Engine/Difficulty.lua", "Engine/XP.lua",
      "Engine/Geo.lua", "Engine/Eligibility.lua", "Engine/Hubs.lua",
      "Engine/Travel.lua", "Engine/Candidates.lua", "Engine/ZoneScore.lua",
      "Engine/Sections.lua", "Engine/Dungeons.lua", "Engine/Route.lua",
      "Engine/RouteImprove.lua", "Engine/Engine.lua",
    })
    ns.db = { settings = {}, recorder = { xp = {} } }
    local api = fakeApi({ mapID = function() return nil end })
    local s = ns.Adapter.snapshot(api, ns.db, { ignored = {} })
    local rec = ns.Engine.compute(ns.DB.new(H.data()), s)
    assert.is_table(rec)
    assert.is_table(rec.zones)
    assert.is_table(rec.sections)
    assert.is_true(rec.dungeon == nil or type(rec.dungeon) == "table")
  end)
end)

describe("Adapter.realApi", function()
  it("is fail-soft when every WoW global is missing", function()
    local ns = addon.load(FILES, { UnitFactionGroup = false })
    local api = ns.Adapter.realApi()
    assert.is_nil(api.faction())
    assert.is_nil(api.race())
    assert.is_nil(api.class())
    assert.is_nil(api.level())
    assert.is_nil(api.mapID())
    assert.is_nil(api.position(1))
    assert.same({}, api.completed())
    assert.same({}, api.logEntries())
    assert.is_nil(api.greyAtOrBelow())
  end)

  it("reads the WoW API and skips headers and hidden entries", function()
    local infos = {
      { questID = 1, isHeader = true },
      { questID = 966, isComplete = false },
      { questID = 2, isHidden = true },
      { questID = 4730, isComplete = false },
    }
    local ns = addon.load(FILES, {
      UnitRace = function() return "Night Elf", "NightElf", 4 end,
      UnitClass = function() return "Druid", "DRUID", 11 end,
      UnitLevel = function() return 18 end,
      C_Map = {
        GetBestMapForUnit = function() return 1439 end,
        GetPlayerMapPosition = function() return { GetXY = function() return 0.374, 0.401 end } end,
      },
      C_QuestLog = {
        GetAllCompletedQuestIDs = function() return { 965 } end,
        GetNumQuestLogEntries = function() return #infos end,
        GetInfo = function(i) return infos[i] end,
        IsComplete = function(id) return id == 4730 end,
      },
    })
    local api = ns.Adapter.realApi()
    assert.equals(4, api.race())
    local cname, cid = api.class()
    assert.equals("DRUID", cname)
    assert.equals(11, cid)
    assert.equals(18, api.level())
    assert.equals(1439, api.mapID())
    assert.equals(0.374, api.position(1439))
    assert.same({ 965 }, api.completed())
    local log = api.logEntries()
    assert.is_nil(log[1])
    assert.is_nil(log[2])
    assert.is_false(log[966].complete)
    assert.is_true(log[4730].complete)
  end)

  it("returns {} when the log iteration throws", function()
    local ns = addon.load(FILES, {
      C_QuestLog = {
        GetNumQuestLogEntries = function() return 1 end,
        GetInfo = function() error("boom") end,
      },
    })
    assert.same({}, ns.Adapter.realApi().logEntries())
  end)
end)

describe("Adapter grey level", function()
  it("greyLevel", function()
    local ns = addon.load(FILES)
    local g = ns.Adapter.greyLevel
    assert.equal(32, g(38, 5, {}))
    assert.is_nil(g(38, nil, {}))
    assert.is_nil(g(38, 0, { { level = 33, trivial = true } }))
    assert.equal(33, g(38, 5, { { level = 33, trivial = true } }))
    assert.equal(31, g(38, 5, { { level = 32, trivial = false } }))
    assert.equal(32, g(38, 5, { { level = 20, trivial = true }, { level = 40, trivial = nil } }))
  end)

  it("realApi.greyAtOrBelow reads UnitQuestTrivialLevelRange and the log", function()
    local infos = {
      { questID = 1, isHeader = true, level = 99 },
      { questID = 7, level = 33 },
      { questID = 8, level = 40 },
    }
    local ns = addon.load(FILES, {
      UnitLevel = function() return 38 end,
      UnitQuestTrivialLevelRange = function() return 5 end,
      C_QuestLog = {
        GetNumQuestLogEntries = function() return #infos end,
        GetInfo = function(i) return infos[i] end,
        IsQuestTrivial = function(id) return id == 7 end,
      },
    })
    assert.equal(33, ns.Adapter.realApi().greyAtOrBelow())
  end)

  it("realApi.greyAtOrBelow works without a log and fails soft", function()
    local ns = addon.load(FILES, {
      UnitLevel = function() return 38 end,
      UnitQuestTrivialLevelRange = function() return 5 end,
    })
    assert.equal(32, ns.Adapter.realApi().greyAtOrBelow())
  end)
end)
