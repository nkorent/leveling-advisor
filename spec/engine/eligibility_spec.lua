local H = require("spec.helpers.engine")

describe("Eligibility", function()
  local ns, db, E, S18, H20
  before_each(function()
    ns = H.load()
    db = ns.DB.new(H.data())
    E = ns.Eligibility
    S18, H20 = H.states.S18, H.states.H20
  end)

  local function check(id, state) return E.check(db, db:quest(id), state or S18) end

  it("completed", function()
    local s, r = check(965); assert.is_nil(s); assert.equals("completed", r)
  end)
  it("in-log", function()
    local s, r = check(966); assert.is_nil(s); assert.equals("in-log", r)
  end)
  it("eligible with prereq met", function()
    assert.equals("eligible", (check(4763)))
  end)
  it("prereq missing", function()
    local st = H.with(S18, { completed = { [965] = true } })
    local s, r = check(4763, st); assert.is_nil(s); assert.equals("prereq", r)
  end)
  it("faction", function()
    local s, r = check(6382); assert.is_nil(s); assert.equals("faction", r)
  end)
  it("race", function()
    local s, r = check(7001); assert.is_nil(s); assert.equals("race", r)
  end)
  it("class", function()
    local s, r = check(7002); assert.is_nil(s); assert.equals("class", r)
  end)
  it("prereq.any satisfied", function()
    assert.equals("eligible", (check(7003)))
  end)
  it("max-level: player above the maximum level", function()
    local s, r = check(7008); assert.is_nil(s); assert.equals("max-level", r)
    s, r = check(7008, H.states.S20); assert.is_nil(s); assert.equals("max-level", r)
  end)
  it("max-level: player at the maximum level is eligible", function()
    assert.equals("eligible", (check(7008, H.with(S18, { level = 15 }))))
  end)
  it("max-level: a quest without a maximum is unaffected", function()
    assert.is_nil(db:quest(7003).requiredMaxLevel)
    assert.equals("eligible", (check(7003)))
  end)
  it("exports its mask test and faction ids", function()
    assert.same({ Alliance = 1, Horde = 2 }, E.FACTION_ID)
    assert.is_true(E.maskAllows(nil, 2))
    assert.is_true(E.maskAllows(2 + 16, 16))
    assert.is_false(E.maskAllows(1, 2))
    assert.is_true(E.maskAllows(2 ^ 33 + 2, 2 ^ 33))
    assert.is_false(E.maskAllows(2, nil))
    assert.is_false(E.maskAllows(2, 0))
  end)
  it("exclusive", function()
    local s, r = check(7005); assert.is_nil(s); assert.equals("exclusive", r)
  end)
  describe("unavailableAfter (Contract A field 25)", function()
    -- 7009: like 7003 (eligible for S18) but unavailable once 1302 or 420 is completed or in the log
    local udb
    before_each(function()
      local data = H.data()
      local r = {}
      for k, v in pairs(data.quests[7003]) do r[k] = v end
      r[25] = { 1302, 420 }
      data.quests[7009] = r
      udb = ns.DB.new(data)
    end)
    local function ucheck(state) return E.check(udb, udb:quest(7009), state) end

    it("is eligible while no listed quest is completed or in the log", function()
      assert.equals("eligible", (ucheck(S18)))
    end)
    it("is ineligible once a listed quest is completed", function()
      local completed = {}
      for k, v in pairs(S18.completed) do completed[k] = v end
      completed[1302] = true
      local s, r = ucheck(H.with(S18, { completed = completed }))
      assert.is_nil(s); assert.equals("unavailable", r)
    end)
    it("is ineligible while a listed quest is in the log", function()
      local log = {}
      for k, v in pairs(S18.log or {}) do log[k] = v end
      log[420] = { complete = false }
      local s, r = ucheck(H.with(S18, { log = log }))
      assert.is_nil(s); assert.equals("unavailable", r)
    end)
    it("is never mutual exclusion: Route does not read it", function()
      assert.same({}, udb:quest(7009).exclusiveTo)
    end)
  end)
  it("breadcrumb", function()
    local s, r = check(7006); assert.is_nil(s); assert.equals("breadcrumb", r)
  end)
  it("no-data", function()
    local s, r = check(7007); assert.is_nil(s); assert.equals("no-data", r)
  end)
  it("level too low", function()
    local s, r = check(991, H.with(S18, { level = 15 }))
    assert.is_nil(s); assert.equals("level", r)
  end)
  it("soon", function()
    assert.equals("soon", (check(991, H.with(S18, { level = 17 }))))
  end)
  it("soon window edge: required level + 2 is soon, + 3 is level", function()
    -- 1100 needs level 18 (quest level 20, so not too high at 16); SOON_LEVELS is 2
    assert.equals(2, ns.Tuning.SOON_LEVELS)
    assert.equals("soon", (check(1100, H.with(S18, { level = 16 }))))
    local s, r = check(1100, H.with(S18, { level = 15 }))
    assert.is_nil(s); assert.equals("level", r)
  end)
  it("grey", function()
    local s, r = check(1081, H.with(S18, { level = 22 }))
    assert.is_nil(s); assert.equals("grey", r)
  end)
  it("ignored", function()
    local s, r = check(4763, H.with(S18, { ignored = { [4763] = true } }))
    assert.is_nil(s); assert.equals("ignored", r)
  end)
  it("horde quest for H20", function()
    assert.equals("eligible", (check(6382, H20)))
  end)
  it("grey for H20", function()
    local s, r = check(840, H20); assert.is_nil(s); assert.equals("grey", r)
  end)
  it("logState", function()
    assert.equals("complete", E.logState(S18, 4730))
    assert.equals("progress", E.logState(S18, 966))
    assert.is_nil(E.logState(S18, 1))
  end)
  it("tolerates nil fields and missing state tables", function()
    local q = { id = 1, faction = 3, requiredLevel = 1, level = 18,
      giver = { mapID = 1439 } }
    local st = { faction = "Alliance", level = 18 }
    assert.equals("eligible", (E.check(db, q, st)))
    assert.is_nil(E.logState(st, 1))
    local s, r = E.check(db, { id = 2, faction = 3, requiredLevel = 1, level = 18 }, st)
    assert.is_nil(s); assert.equals("no-data", r)
  end)
end)

-- Task 8c: Contract A race masks carry the Forever ChrRaces bits (High Order Skyborne 2^32,
-- Windshaper Skyborne 2^33). The records below are written the way pipeline/emit.py writes
-- them (plain integer literals), then loaded and decoded like the generated Data files.
describe("Eligibility with Forever race bits", function()
  local SRC = [[
local _, ns = ...
ns.Data = ns.Data or {}
local t = {}
ns.Data.quests = t
t[7101] = {"Alliance and High Order Skyborne", 1, 4294967373, nil, 10, 18, 1, 1439, 0, nil, {1, 3649, 1439, 37.4, 40.1}}
t[7102] = {"Classic Alliance Races Only", 1, 77, nil, 10, 18, 1, 1439, 0, nil, {1, 3649, 1439, 37.4, 40.1}}
t[7103] = {"Horde and Windshaper Skyborne", 2, 8589934770, nil, 10, 18, 1, 1411, 0, nil, {1, 3143, 1411, 52.0, 43.0}}
t[7104] = {"Night Elf and High Order Skyborne", 1, 4294967304, nil, 10, 18, 1, 1439, 0, nil, {1, 3649, 1439, 37.4, 40.1}}
]]
  local ns, db, E
  before_each(function()
    ns = H.load()
    local data = {}
    assert(loadstring(SRC))("LevelingAdvisor", data)
    db = ns.DB.new(data.Data)
    E = ns.Eligibility
  end)

  local function state(faction, raceMask)
    return H.with(H.states.S18, { faction = faction, raceMask = raceMask, classMask = 1,
                                  completed = {}, log = {} })
  end

  it("a High Order Skyborne passes a 77 + 2^32 quest and fails a 77-only quest", function()
    local skyborne = state("Alliance", 2 ^ 32)
    assert.equals("eligible", (E.check(db, db:quest(7101), skyborne)))
    local s, r = E.check(db, db:quest(7102), skyborne)
    assert.is_nil(s); assert.equals("race", r)
    assert.equals("eligible", (E.check(db, db:quest(7102), state("Alliance", 4))))   -- a Dwarf still passes
  end)

  it("a Windshaper Skyborne passes a 178 + 2^33 quest", function()
    local windshaper = H.with(state("Horde", 2 ^ 33), { mapID = 1411 })
    assert.equals("eligible", (E.check(db, db:quest(7103), windshaper)))
    local s, r = E.check(db, db:quest(7101), windshaper)
    assert.is_nil(s); assert.equals("faction", r)
  end)

  it("decodes an emitted 2^32 + 8 mask exactly and tests its bits", function()
    local q = db:quest(7104)
    assert.equals(2 ^ 32 + 8, q.raceMask)
    assert.equals(4294967304, q.raceMask)
    assert.equals("eligible", (E.check(db, q, state("Alliance", 8))))         -- Night Elf
    assert.equals("eligible", (E.check(db, q, state("Alliance", 2 ^ 32))))    -- High Order Skyborne
    local s, r = E.check(db, q, state("Alliance", 1))                         -- Human
    assert.is_nil(s); assert.equals("race", r)
  end)
end)

describe("Eligibility level ceiling", function()
  local SRC = [[
local _, ns = ...
ns.Data = ns.Data or {}
local t = {}
ns.Data.quests = t
t[7201] = {"Skill Book", 1, nil, nil, 1, 45, 1, 1439, 0, nil, {1, 3649, 1439, 37.4, 40.1}}
t[7202] = {"Edge Quest", 1, nil, nil, 10, 24, 1, 1439, 0, nil, {1, 3649, 1439, 37.4, 40.1}}
t[7203] = {"Too Far", 1, nil, nil, 10, 25, 1, 1439, 0, nil, {1, 3649, 1439, 37.4, 40.1}}
]]
  local ns, db, E
  before_each(function()
    ns = H.load()
    local data = {}
    assert(loadstring(SRC))("LevelingAdvisor", data)
    db = ns.DB.new(data.Data)
    E = ns.Eligibility
  end)

  local function state(level, over)
    return H.with(H.states.S18, H.with({ level = level, completed = {}, log = {} }, over))
  end

  it("a level-1 player does not get a q45 r1 quest", function()
    local s, r = E.check(db, db:quest(7201), state(1))
    assert.is_nil(s); assert.equals("too-high", r)
  end)
  it("the ceiling is 4 levels above the player", function()
    assert.equals(4, ns.Tuning.MAX_LEVELS_ABOVE)
    assert.equals("eligible", (E.check(db, db:quest(7202), state(20))))
    local s, r = E.check(db, db:quest(7203), state(20))
    assert.is_nil(s); assert.equals("too-high", r)
  end)
  it("an in-log quest is unaffected", function()
    local s, r = E.check(db, db:quest(7201), state(1, { log = { [7201] = {} } }))
    assert.is_nil(s); assert.equals("in-log", r)
    local c = ns.Candidates.build(db, state(1, { log = { [7201] = { complete = true } } }))
    assert.is_truthy(H.candidateFor(c, 7201))
  end)
end)

-- Final review C1 on the committed data: QuestieDB availability gates reach the engine.
local function exists(p)
  local f = io.open(p, "r")
  if f then f:close() end
  return f ~= nil
end
local QUESTS = "LevelingAdvisor/Data/Quests.lua"

;(exists(QUESTS) and describe or pending)("Eligibility on the real data (QuestieDB gates)", function()
  local ns, db
  setup(function()
    ns = H.load()
    assert(loadfile(QUESTS))("LevelingAdvisor", ns)
    db = ns.DB.new(ns.Data)
  end)
  local function human(level, completed, log)
    return {
      faction = "Alliance", raceMask = 1, classMask = 1, classFile = "WARRIOR", level = level,
      mapID = 1445, x = 66, y = 46, completed = completed or {}, log = log or {}, ignored = {},
      recordedXP = {}, settings = { elite = true, dungeons = true },
    }
  end

  it("1282 They Call Him Smiling Jim is ineligible once 1302 is completed or in the log", function()
    local q = db:quest(1282)
    assert.is_truthy(q)
    assert.equals("eligible", (ns.Eligibility.check(db, q, human(32))))
    local s, r = ns.Eligibility.check(db, q, human(32, { [1302] = true }))
    assert.is_nil(s); assert.equals("unavailable", r)
    s, r = ns.Eligibility.check(db, q, human(32, {}, { [1302] = { complete = false } }))
    assert.is_nil(s); assert.equals("unavailable", r)
  end)
  it("parentQuest quests are not in the data (339 Chapter I needs 338 in the log)", function()
    assert.is_nil(db:quest(339))
  end)
  it("availableStartingWith becomes a prerequisite (92595 needs 92514)", function()
    local q = db:quest(92595)
    assert.is_truthy(q)
    local found = false
    for _, p in ipairs(q.prereq.all) do if p == 92514 then found = true end end
    assert.is_true(found)
    local s, r = ns.Eligibility.check(db, q, {
      faction = "Horde", raceMask = 8589934592, classMask = 1, classFile = "WARRIOR", level = 5,
      mapID = 2521, x = 43, y = 44, completed = {}, log = {}, ignored = {}, recordedXP = {},
      settings = { elite = true, dungeons = true } })
    assert.is_nil(s); assert.equals("prereq", r)
  end)
end)

describe("Eligibility.otherFaction", function()
  local ns = H.load()
  local other = ns.Eligibility.otherFaction
  it("is true only for the other side's faction id", function()
    local FID = ns.Eligibility.FACTION_ID
    assert.same({ Alliance = 1, Horde = 2 }, FID)
    -- rows: the record's faction 1, 2, 3 (both), nil; columns: Alliance, Horde, unknown player
    local expected = {
      [1] = { false, true, true },
      [2] = { true, false, true },
      [3] = { false, false, false },
      none = { false, false, false },
    }
    for f, row in pairs(expected) do
      local fv = f ~= "none" and f or nil
      assert.equals(row[1], other(fv, FID.Alliance), tostring(f) .. " vs Alliance")
      assert.equals(row[2], other(fv, FID.Horde), tostring(f) .. " vs Horde")
      assert.equals(row[3], other(fv, nil), tostring(f) .. " vs nil")
    end
  end)
end)
