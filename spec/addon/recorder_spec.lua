local addon = require("spec.helpers.addon")

local FILES = { "Core/Util.lua", "Core/Init.lua", "Core/Settings.lua", "Core/Recorder.lua" }

local function fakeApi(o)
  o = o or {}
  local api = {
    questID = function() return 4763 end,
    npcGUID = function() return "Creature-0-1-1-1-3649-0" end,
    mapID = function() return 1439 end,
    position = function() return 0.374, 0.401 end,
    rewardXP = function() return 1700 end,
    numChoices = function() return 3 end,
    choiceLink = function(i)
      local ids = { 15204, 15202, 15203 }
      return "|cff0070dd|Hitem:" .. ids[i] .. "::::::::18:::::|h[Item]|h|r"
    end,
    numRewards = function() return 0 end,
    rewardLink = function() return nil end,
    level = function() return 18 end,
    now = function() return 5000 end,
    gossipAvailable = function() return { { questID = 100, questLevel = 12 }, { questID = 101, questLevel = 14 } } end,
    greetingAvailable = function() return { { questID = 200, questLevel = 20 } } end,
  }
  for k, v in pairs(o) do api[k] = v end
  return api
end

local function setup(api, settings)
  local ns = addon.load(FILES)
  ns.db = { settings = settings or {}, recorder = { xp = {}, levels = {}, details = {}, accepted = {} } }
  return ns, ns.Recorder.new(ns.db.recorder, api or fakeApi())
end

describe("Recorder", function()
  it("records quest details", function()
    local ns, rec = setup()
    rec:onDetail()
    local d = ns.db.recorder.details[4763]
    assert.same({ npcID = 3649, mapID = 1439, x = 37.4, y = 40.1, xp = 1700, level = 18,
      choices = { 15204, 15202, 15203 }, rewards = {}, seen = 1, at = 5000 }, d)
    assert.equals(1700, ns.db.recorder.xp[4763][18])
    rec:onDetail()
    assert.equals(2, ns.db.recorder.details[4763].seen)
  end)

  it("ignores nil or zero questID", function()
    local ns, rec = setup(fakeApi({ questID = function() return 0 end }))
    rec:onDetail(); rec:onComplete(); rec:onTurnedIn(0, 100)
    assert.same({}, ns.db.recorder.details)
    assert.same({}, ns.db.recorder.xp)
  end)

  it("records turn-in XP at the level seen at QUEST_COMPLETE", function()
    local lvl = 18
    local ns, rec = setup(fakeApi({ level = function() return lvl end }))
    rec:onComplete()
    lvl = 19
    rec:onTurnedIn(4763, 1700)
    assert.equals(1700, ns.db.recorder.xp[4763][18])
    assert.is_nil(ns.db.recorder.xp[4763][19])
  end)

  it("records turn-in at current level without onComplete", function()
    local ns, rec = setup()
    rec:onTurnedIn(55, 300)
    assert.equals(300, ns.db.recorder.xp[55][18])
  end)

  it("records nothing for zero XP", function()
    local ns, rec = setup()
    rec:onTurnedIn(4763, 0)
    assert.same({}, ns.db.recorder.xp)
  end)

  it("caps accepted at 500", function()
    local ns, rec = setup()
    for i = 1, 501 do rec:onAccepted(i) end
    local a = ns.db.recorder.accepted
    assert.equals(500, #a)
    assert.equals(2, a[1][1])
    assert.equals(501, a[500][1])
    assert.equals(5000, a[1][2])
  end)

  it("parses accepted argument forms", function()
    assert.equals(4763, addon.load(FILES).Recorder.questIDFromAccepted(3, 4763))
    assert.equals(4763, addon.load(FILES).Recorder.questIDFromAccepted(4763))
  end)

  it("stores gossip and greeting levels", function()
    local ns, rec = setup()
    rec:onGossip(); rec:onGreeting()
    assert.same({ [100] = 12, [101] = 14, [200] = 20 }, ns.db.recorder.levels)
  end)

  it("writes nothing when the setting is off", function()
    local ns, rec = setup(nil, { recorder = false })
    rec:onDetail(); rec:onGossip(); rec:onGreeting(); rec:onComplete()
    rec:onTurnedIn(4763, 1700); rec:onAccepted(4763)
    local r = ns.db.recorder
    assert.same({}, r.details); assert.same({}, r.xp); assert.same({}, r.levels)
    assert.same({}, r.accepted)
  end)

  it("realApi is fail-soft with no globals", function()
    local ns = addon.load(FILES)
    local api = ns.Recorder.realApi()
    assert.is_nil(api.questID())
    assert.equals(0, api.numChoices())
    assert.same({}, api.gossipAvailable())
    assert.same({}, api.greetingAvailable())
    assert.is_nil(api.position(1))
  end)
end)
