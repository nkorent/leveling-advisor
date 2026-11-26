local addon = require("spec.helpers.addon")

local FILES = { "Core/Util.lua", "Core/Init.lua", "Core/Settings.lua", "UI/MapPins.lua" }

local function load(extra)
  local ns, env, out = addon.load(FILES, extra)
  ns.db = { settings = {} }
  return ns, env, out
end

-- Fake DB: quests keyed by id, NPC names.
local function fakeDb(quests)
  local npcs = { [10] = { "Giver Ten" }, [11] = { "Giver Eleven" }, [20] = { "Turner Twenty" } }
  return {
    quest = function(_, id) return quests[id] end,
    npc = function(_, id) return npcs[id] end,
    zone = function(_, id) return id == 1411 and { name = "Durotar" } or nil end,
  }
end

local function row(id, mapID, x, y, extra)
  local r = {
    questID = id, name = "Quest " .. id, level = 5, color = "yellow", xp = 100 + id,
    giver = { mapID = mapID, x = x, y = y, kind = 1, id = 10 },
  }
  for k, v in pairs(extra or {}) do r[k] = v end
  return r
end

local function rec(...)
  local sections = {}
  for _, s in ipairs({ ... }) do sections[#sections + 1] = s end
  return { sections = sections }
end

local function sec(key, ...)
  return { key = key, title = key .. " title", rows = { ... } }
end

describe("MapPins.build", function()
  local build
  local db
  before_each(function()
    local ns = load()
    build = ns.MapPins.build
    db = fakeDb({
      [7] = { turnIn = { kind = 1, id = 20, mapID = 1411, x = 60, y = 61 } },
    })
  end)

  it("returns {} for nil or empty rec", function()
    assert.same({}, build(nil, db, 1411))
    assert.same({}, build({}, db, 1411))
    assert.same({}, build({ sections = {} }, db, 1411))
  end)

  it("makes pickup pins from here, class, chains and next sections", function()
    local r = rec(
      sec("here", row(1, 1411, 10, 10)),
      sec("class", row(2, 1411, 20, 20)),
      sec("chains", row(3, 1411, 30, 30)),
      sec("next", row(4, 1411, 40, 40)))
    local pins = build(r, db, 1411)
    assert.equals(4, #pins)
    for _, p in ipairs(pins) do assert.equals("pickup", p.kind) end
    local q = pins[1].quests[1]
    assert.equals(1, q.id)
    assert.equals("Quest 1", q.name)
    assert.equals(5, q.level)
    assert.equals("yellow", q.color)
    assert.equals("here", q.sectionKey)
    assert.equals("here title", q.section)
    assert.equals(101, q.xp)
    assert.equals("Giver Ten", q.giverName)
    assert.equals(1411, pins[1].mapID)
    assert.equals(10, pins[1].x)
  end)

  it("makes turn-in pins at the turn-in point, not the giver", function()
    local r = rec(sec("turnin", row(7, 1411, 10, 10, { state = "complete" })))
    local pins = build(r, db, 1411)
    assert.equals(1, #pins)
    assert.equals("turnin", pins[1].kind)
    assert.equals(60, pins[1].x)
    assert.equals(61, pins[1].y)
    assert.equals("Turner Twenty", pins[1].quests[1].giverName)
  end)

  it("skips the turn-in row when the quest has no turn-in point", function()
    local r = rec(sec("turnin", row(8, 1411, 10, 10)))
    assert.same({}, build(r, db, 1411))
  end)

  it("filters by the displayed map", function()
    local r = rec(sec("here", row(1, 1411, 10, 10), row(2, 1412, 10, 10)))
    local pins = build(r, db, 1411)
    assert.equals(1, #pins)
    assert.equals(1, pins[1].quests[1].id)
    assert.same({}, build(r, db, 9999))
    assert.same({}, build(r, db, nil))
  end)

  it("merges rows within 0.5 units into one pin", function()
    local r = rec(sec("here", row(1, 1411, 10, 10), row(2, 1411, 10.4, 9.6), row(3, 1411, 10.6, 10)))
    local pins = build(r, db, 1411)
    assert.equals(2, #pins)
    assert.equals(2, #pins[1].quests)
    assert.equals(1, pins[1].quests[1].id)
    assert.equals(2, pins[1].quests[2].id)
    assert.equals(1, #pins[2].quests)
  end)

  it("lets the turn-in kind win a merged pin", function()
    local r = rec(
      sec("turnin", row(7, 1411, 0, 0)),
      sec("here", row(1, 1411, 60.2, 61.1)))
    local pins = build(r, db, 1411)
    assert.equals(1, #pins)
    assert.equals("turnin", pins[1].kind)
    assert.equals(2, #pins[1].quests)
  end)

  it("turn-in wins even when the pickup came first", function()
    local r = rec(
      sec("here", row(1, 1411, 60.2, 61.1)),
      sec("turnin", row(7, 1411, 0, 0)))
    local pins = build(r, db, 1411)
    assert.equals(1, #pins)
    assert.equals("turnin", pins[1].kind)
  end)

  it("skips rows without coordinates", function()
    local r = rec(sec("here",
      row(1, 1411, nil, nil),
      row(2, 1411, 10, nil),
      row(3, nil, 10, 10),
      { questID = 4, name = "No giver", level = 1, color = "grey" },
      row(5, 1411, 12, 12)))
    local pins = build(r, db, 1411)
    assert.equals(1, #pins)
    assert.equals(5, pins[1].quests[1].id)
  end)

  it("ignores unknown section keys", function()
    local r = rec(sec("zones", row(1, 1411, 10, 10)))
    assert.same({}, build(r, db, 1411))
  end)

  it("leaves giverName nil for object givers and unknown NPCs", function()
    local r = rec(sec("here",
      row(1, 1411, 10, 10, { giver = { mapID = 1411, x = 10, y = 10, kind = 2, id = 10 } }),
      row(2, 1411, 30, 30, { giver = { mapID = 1411, x = 30, y = 30, kind = 1, id = 999 } })))
    local pins = build(r, db, 1411)
    assert.is_nil(pins[1].quests[1].giverName)
    assert.is_nil(pins[2].quests[1].giverName)
  end)
end)

describe("MapPins.build with a zone route", function()
  local build, db
  before_each(function()
    local ns = load()
    build = ns.MapPins.build
    db = fakeDb({
      [31] = { id = 31, name = "Route Pickup", level = 2, xp = 80,
        giver = { kind = 1, id = 11, mapID = 1411, x = 30, y = 31 },
        turnIn = { kind = 1, id = 20, mapID = 1411, x = 70, y = 71 } },
      [32] = { id = 32, name = "Elsewhere", level = 2, xp = 80,
        giver = { kind = 1, id = 11, mapID = 1412, x = 30, y = 31 },
        turnIn = { kind = 1, id = 20, mapID = 1412, x = 70, y = 71 } },
      [1] = { id = 1, name = "Quest 1", level = 5, xp = 101,
        giver = { kind = 1, id = 10, mapID = 1411, x = 10, y = 10 } },
    })
  end)

  local function step(...) return { mapID = 1411, x = 0, y = 0, actions = { ... } } end

  it("makes a pin for a route-only pickup on the displayed map", function()
    local pins = build({}, db, 1411, { step({ 31, "pickup" }) })
    assert.equals(1, #pins)
    assert.equals("pickup", pins[1].kind)
    assert.equals(30, pins[1].x)
    local q = pins[1].quests[1]
    assert.equals(31, q.id)
    assert.equals("Route Pickup", q.name)
    assert.equals("Durotar", q.section)
    assert.equals(80, q.xp)
    assert.equals("Giver Eleven", q.giverName)
  end)

  it("falls back to 'This zone' without a zone name", function()
    db.zone = function() return nil end
    local pins = build({}, db, 1411, { step({ 31, "pickup" }) })
    assert.equals("This zone", pins[1].quests[1].section)
  end)

  it("makes a turn-in pin for a route turn-in", function()
    local pins = build({}, db, 1411, { step({ 31, "turnin" }) })
    assert.equals(1, #pins)
    assert.equals("turnin", pins[1].kind)
    assert.equals(70, pins[1].x)
    assert.equals("Turner Twenty", pins[1].quests[1].giverName)
  end)

  it("skips route turn-ins of quests that are not in the log yet", function()
    local pins = build({}, db, 1411, { step({ 31, "pickup" }, { 31, "turnin" }) }, { level = 1, log = {} })
    assert.equals(1, #pins)
    assert.equals("pickup", pins[1].kind)
    pins = build({}, db, 1411, { step({ 31, "turnin" }) }, { level = 1, log = { [31] = {} } })
    assert.equals("turnin", pins[1].kind)
  end)

  it("gives no pin for objectives or quests on another map", function()
    local pins = build({}, db, 1411, { step({ 31, "objective" }, { 32, "pickup" }, { 32, "turnin" }, { 999, "pickup" }) })
    assert.same({}, pins)
  end)

  it("lists a quest once when a section row and the route both have it", function()
    local r = rec(sec("here", row(1, 1411, 10, 10)))
    local pins = build(r, db, 1411, { step({ 1, "pickup" }, { 31, "pickup" }) })
    assert.equals(2, #pins)
    assert.equals(1, #pins[1].quests)
    assert.equals(1, pins[1].quests[1].id)
    assert.equals("here title", pins[1].quests[1].section)
  end)

  it("merges route quests into nearby section pins", function()
    local r = rec(sec("here", row(1, 1411, 30.2, 31.2)))
    local pins = build(r, db, 1411, { step({ 31, "pickup" }) })
    assert.equals(1, #pins)
    assert.equals(2, #pins[1].quests)
  end)

  it("colours route quests relative to the player level", function()
    local ns = load()
    ns.Difficulty = { color = function(q, p) return q .. "/" .. p end }
    local pins = ns.MapPins.build({}, db, 1411, { step({ 31, "pickup" }) }, { level = 9 })
    assert.equals("2/9", pins[1].quests[1].color)
  end)
end)
