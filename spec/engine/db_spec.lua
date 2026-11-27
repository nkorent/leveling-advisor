local H = require("spec.helpers.engine")
local ns = H.load()
local db = ns.DB.new(H.data())

describe("DB", function()
  it("decodes positional quest fields", function()
    local q = db:quest(4763)
    assert.equals("The Blackwood Corrupted", q.name)
    assert.equals(15, q.requiredLevel); assert.equals(18, q.level)
    assert.same({ kind = 1, id = 3649, mapID = 1439, x = 37.4, y = 40.1 }, q.giver)
    assert.same({ kind = 1, id = 3649, mapID = 1439, x = 37.4, y = 40.1 }, q.turnIn)
    assert.same({ 4762 }, q.prereq.all); assert.same({}, q.prereq.any)
    assert.equals(15204, q.rewards.choice[1][1])
    assert.same({ { mapID = 1439, x = 52.5, y = 33.4 } }, q.points)
    assert.is_nil(q.chain)
  end)
  it("decodes chain, prereqs and empty tables", function()
    assert.same({ id = 965, index = 2, length = 6 }, db:quest(966).chain)
    local q = db:quest(1081)
    assert.same({}, q.prereq.all); assert.same({}, q.prereq.any)
    assert.same({}, q.exclusiveTo); assert.same({}, q.points)
    assert.same({ 7004, 965 }, db:quest(7003).prereq.any)
    assert.same({ 965 }, db:quest(7005).exclusiveTo)
    assert.equals(966, db:quest(7006).breadcrumbOf)
    assert.is_nil(db:quest(7007).requiredLevel)
    assert.equals(15, db:quest(7008).requiredMaxLevel)
    assert.is_nil(db:quest(7003).requiredMaxLevel)
  end)
  it("decodes field 25 unavailableAfter (empty list when absent)", function()
    local data = H.data()
    local r = {}
    for k, v in pairs(data.quests[7003]) do r[k] = v end
    r[25] = { 1302, 420 }
    data.quests[7009] = r
    local d = ns.DB.new(data)
    assert.same({ 1302, 420 }, d:quest(7009).unavailableAfter)
    assert.same({}, d:quest(7003).unavailableAfter)
  end)
  it("decodes field 26 objectives and the field 13 objective index", function()
    local data = H.data()
    local r = {}
    for k, v in pairs(data.quests[4763]) do r[k] = v end
    r[13] = { { 1439, 45.2, 35.2, 2 }, { 1439, 46.0, 36.0 }, { 1440, 10.0, 10.0, 1 } }
    r[26] = {
      { 1, 6, "Kobold Vermin", 10 },
      { 3, 750, "Tough Wolf Meat", 8, { "Young Wolf", "Timber Wolf" }, 1, true },
      { 4, nil, nil, nil },
    }
    data.quests[7010] = r
    local d = ns.DB.new(data)
    local q = d:quest(7010)
    assert.equals(3, #q.objectives)
    assert.same({ index = 1, kind = 1, id = 6, name = "Kobold Vermin", count = 10 }, q.objectives[1])
    assert.same({ index = 2, kind = 3, id = 750, name = "Tough Wolf Meat", count = 8,
      from = { "Young Wolf", "Timber Wolf" }, fromKind = 1, fromMore = true }, q.objectives[2])
    assert.same({ index = 3, kind = 4 }, q.objectives[3])
    -- the {mapID, x, y} reading is unchanged; an indexed point also has its objective
    assert.same({ 1439, 45.2, 35.2 }, { q.points[1].mapID, q.points[1].x, q.points[1].y })
    assert.equals(q.objectives[2], q.points[1].objective)
    assert.is_nil(q.points[2].objective)
    assert.equals(q.objectives[1], q.points[3].objective)
    -- the from list is a copy
    q.objectives[2].from[1] = "changed"
    assert.equals("Young Wolf", data.quests[7010][26][2][5][1])
    -- an index without an objective (bad data) is ignored
    r[13] = { { 1439, 1, 2, 9 } }
    data.quests[7011] = r
    assert.is_nil(ns.DB.new(data):quest(7011).points[1].objective)
    -- no field 26: an empty list
    assert.same({}, db:quest(4763).objectives)
  end)
  it("decodes flags", function()
    local q = db:quest(1100)
    assert.is_true(q.newInForever); assert.is_true(q.unverified); assert.is_false(q.elite)
    assert.is_true(db:quest(1000).elite); assert.is_true(db:quest(1275).dungeonQuest)
    assert.is_true(db:quest(5061).classQuest); assert.is_false(db:quest(5061).repeatable)
    assert.equals("BFD", db:quest(1275).dungeonKey); assert.equals(5, db:quest(1275).groupSize)
  end)
  it("caches decoded quests", function()
    assert.equals(db:quest(965), db:quest(965))
  end)
  it("indexes quests by giver zone", function()
    assert.same({ 991, 1007, 1010, 1100, 6382, 6563 }, db:questsInZone(1440))
    assert.same({}, db:questsInZone(9999))
  end)
  it("lists ids sorted", function()
    local ids = db:questIDs()
    assert.equals(840, ids[1]); assert.equals(7008, ids[#ids])
    local sorted = {}
    for i, id in ipairs(ids) do sorted[i] = id end
    table.sort(sorted)
    assert.same(sorted, ids)
  end)
  it("exposes npcs, zones, continents, dungeons", function()
    assert.equals("Sentinel Shaya", db:npc(3649)[1])
    assert.equals("Darkshore", db:zone(1439).name)
    assert.same({ 1411, 1432, 1439, 1440 }, db:zoneIDs())
    assert.equals("Kalimdor", db:continent(1414).name)
    assert.equals("Blackfathom Deeps", db:dungeon("BFD").name)
    assert.same({ "BFD", "WC" }, db:dungeonKeys())
  end)
  it("decodes zone kind; unknown values are nil", function()
    local data = H.data()
    data.zones[1439].kind = "city"
    data.zones[1440].kind = "battleground"
    data.zones[1432].kind = "dungeon"
    local d = ns.DB.new(data)
    assert.equals("city", d:zone(1439).kind)
    assert.equals("battleground", d:zone(1440).kind)
    assert.is_nil(d:zone(1432).kind)
    assert.is_nil(d:zone(1411).kind)
    assert.equals("Darkshore", d:zone(1439).name)
  end)
  it("decodes quest stubs (Contract A questStubs)", function()
    local data = H.data()
    data.questStubs = {
      [6564] = { "Damp Note", 60, 58, 2, 178, 1, { all = { 6000 }, any = { 5 } },
        { kind = 3, name = "Damp Note", mapID = 1440 }, "no-giver-coords" },
      [6000] = { "Bare Stub", nil, nil, nil, nil, nil, nil, nil, "needs-rep" },
    }
    local d = ns.DB.new(data)
    assert.same({ id = 6564, name = "Damp Note", level = 60, requiredLevel = 58, faction = 2,
      raceMask = 178, classMask = 1, prereq = { all = { 6000 }, any = { 5 } },
      start = { kind = 3, name = "Damp Note", mapID = 1440 }, reason = "no-giver-coords" }, d:stub(6564))
    local bare = d:stub(6000)
    assert.same({ all = {}, any = {} }, bare.prereq)
    assert.is_nil(bare.start); assert.is_nil(bare.faction); assert.is_nil(bare.level)
    assert.equals("needs-rep", bare.reason)
    assert.equals(d:stub(6564), d:stub(6564)) -- cached
    assert.is_nil(d:stub(123456))
    assert.is_nil(d:quest(6564))
  end)
  it("has no stubs when the data has no questStubs table", function()
    assert.is_nil(db:stub(6564))
  end)
  it("returns nil for unknown ids", function() assert.is_nil(db:quest(123456)) end)
  it("fixture states are independent", function()
    local S = H.states
    assert.equals(18, S.S18.level); assert.equals(20, S.S20.level)
    assert.is_not.equals(S.S18.completed, S.S20.completed)
    assert.equals(2, S.H20.raceMask)
  end)
end)
