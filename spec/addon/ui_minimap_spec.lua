local ui = require("spec.helpers.ui")

describe("quest mini map", function()
  local ns, env, fake, db, state

  local function load(opts)
    opts = opts or {}
    opts.state = opts.state or "S18"
    ns, env, fake = ui.load(opts)
    db, state = ns.Advisor.db, ns.Advisor.last.state
  end

  local function model(id, patch)
    local q = db:quest(id)
    if patch then
      local copy = {}
      for k, v in pairs(q) do copy[k] = v end
      patch(copy)
      q = copy
    end
    return ns.UI.QuestInfo.miniMap(db, q, state), q
  end

  it("model: giver and turn-in merged, objective; no player position (0.3.0)", function()
    load()
    local m = model(4763)
    assert.same({ 1439, "Darkshore" }, { m.mapID, m.mapName })
    assert.same({ "giver", 37.4, 40.1, "Quest giver and turn-in: Sentinel Shaya" },
      { m.points[1].kind, m.points[1].x, m.points[1].y, m.points[1].label })
    assert.same({ "objective", 52.5, 33.4, "Objective" },
      { m.points[2].kind, m.points[2].x, m.points[2].y, m.points[2].label })
    assert.is_nil(m.player)
    assert.same({}, m.others)
  end)

  it("model: separate turn-in NPC, unknown giver NPC drops the name", function()
    load()
    local m = model(965)
    assert.same({ "giver", 39.1, 43.6, "Quest giver" }, { m.points[1].kind, m.points[1].x, m.points[1].y, m.points[1].label })
    assert.same({ "turnin", 55.0, 24.9, "Turn in: Gelkak Gyromast" },
      { m.points[2].kind, m.points[2].x, m.points[2].y, m.points[2].label })
  end)

  it("model: objectives on another map", function()
    load()
    local m = model(4763, function(q)
      q.giver = { kind = 1, id = 3649, mapID = 1439, x = 40, y = 40 }
      q.turnIn = q.giver
      q.points = { { mapID = 1440, x = 10, y = 10 }, { mapID = 1440, x = 12, y = 12 } }
    end)
    assert.equal(1439, m.mapID)
    assert.same({ { mapID = 1440, name = "Ashenvale", count = 2 } }, m.others)
    assert.equal(1, #m.points)
  end)

  it("model: the map with most points wins", function()
    load()
    local m = model(4763, function(q)
      q.points = { { mapID = 1440, x = 10, y = 10 }, { mapID = 1440, x = 12, y = 12 }, { mapID = 1440, x = 14, y = 14 } }
    end)
    assert.equal(1440, m.mapID)
    assert.same({ { mapID = 1439, name = "Darkshore", count = 2 } }, m.others)
    assert.is_nil(m.player)
  end)

  it("model: no coordinates gives no mini map; the detail page hides the section", function()
    load()
    assert.is_nil(model(4763, function(q) q.giver, q.turnIn, q.points = nil, nil, {} end))
    ns.UI.open()
    ns.Data.quests[4763] = ns.Data.quests[4763]
    ns.UI.show({ kind = "zone", mapID = 1439, questID = 4763 })
    local d = ns.UI.RouteView.detail
    assert.is_true(d.byName.map.height > 0)
    local orig = ns.UI.QuestInfo.miniMap
    ns.UI.QuestInfo.miniMap = function() return nil end
    ns.UI.show({ kind = "zone", mapID = 1439, questID = 4730 })
    ns.UI.QuestInfo.miniMap = orig
    assert.equal(0, d.byName.map.height)
    assert.is_false(d.byName.map.frame:IsShown())
    assert.same({}, env.errors)
  end)

  local function mapMarkers()
    local mm = ns.UI.RouteView.detail.parts.map
    return mm, mm.markers
  end

  it("renders the art and markers; hover and click", function()
    load({ art = "tiles" })
    ns.UI.open()
    ns.UI.show({ kind = "zone", mapID = 1439, questID = 4763 })
    local mm, markers = mapMarkers()
    local tiles = fake.findAll(function(w)
      return w.kind == "Texture" and w.texture and w.parent == mm.box.canvas and fake.visible(w)
    end)
    assert.equal(12, #tiles)
    local g = markers[1]
    assert.same({ "CENTER", mm.box, "TOPLEFT", 0.374 * 300, -0.401 * 200 },
      { g.points[1][1], g.points[1][2], g.points[1][3], g.points[1][4], g.points[1][5] })
    assert.is_true(fake.visible(g))
    -- the objective keeps its red dot; there is no blue player dot (0.3.0)
    local o = markers[2]
    assert.equal("objective", o.point.kind)
    assert.is_true(fake.visible(o))
    assert.is_true(o.dot:IsShown())
    assert.same({ 0.9, 0.25, 0.15 }, { o.dot.vertex[1], o.dot.vertex[2], o.dot.vertex[3] })
    assert.is_nil(mm.player)
    assert.is_nil(mm.playerDot)
    assert.same({}, fake.findAll(function(w)
      return w.kind == "Texture" and w.vertex and w.vertex[1] == 0.35 and w.vertex[2] == 0.7 and w.vertex[3] == 1.0
    end))
    fake.enter(g)
    assert.equal("Quest giver and turn-in: Sentinel Shaya (37.4, 40.1)", fake.tooltip.lines[1][1])
    local spy = ui.spy(ns.UI.Nav, "showPlace", function() return true end)
    fake.click(g)
    assert.same({ { mapID = 1439, x = 37.4, y = 40.1 }, "Quest giver and turn-in: Sentinel Shaya", "giver" },
      { spy.calls[1][1], spy.calls[1][2], spy.calls[1][3] })
    assert.is_truthy(fake.visible(fake.text("Darkshore — click a marker for a waypoint")))
    assert.same({}, env.errors)
  end)

  it("caption lists the points on other maps", function()
    load()
    ns.UI.open()
    ns.UI.show({ kind = "zone", mapID = 1439, questID = 4763 })
    local mm = ns.UI.RouteView.detail.parts.map
    local m = model(4763, function(q)
      q.points = { { mapID = 1439, x = 5, y = 5 }, { mapID = 1440, x = 10, y = 10 } }
    end)
    mm:show(m)
    assert.equal("Darkshore — click a marker for a waypoint\n+1 point in Ashenvale", mm.caption.text)
  end)

  it("the giver glyph is the turn-in ? for a complete quest", function()
    load()
    ns.UI.open()
    ns.UI.show({ kind = "zone", mapID = 1439, questID = 4730 })
    local _, markers = mapMarkers()
    assert.is_truthy(markers[1].point.kind == "giver")
    local m = model(4730)
    assert.is_true(m.complete)
    assert.is_true(markers[1].glyph.atlas == "QuestTurnin" or markers[1].glyph.texture == "Interface\\GossipFrame\\ActiveQuestIcon")
    ns.UI.show({ kind = "zone", mapID = 1439, questID = 4763 })
    assert.is_false(model(4763).complete)
    assert.is_true(markers[1].glyph.atlas == "QuestNormal" or markers[1].glyph.texture == "Interface\\GossipFrame\\AvailableQuestIcon")
  end)

  ---------------------------------------------------------------------------
  -- Task 8: what each objective dot is (Contract A field 26, field 13 index).
  ---------------------------------------------------------------------------
  local WOLF = { 3, 750, "Tough Wolf Meat", 8, { "Young Wolf", "Timber Wolf", "Ragged Wolf" }, 1, true }
  local LIGHT, GREY = 0.8, 0.62

  -- Quest 4763's objectives and points replaced (its giver and turn-in stay at 37.4, 40.1).
  local function objectives(points, list, text)
    return function(d)
      local r = d.quests[4763]
      r[13], r[26] = points, list
      if text then r[14] = text end
    end
  end

  local function objectiveMarkers()
    ns.UI.open()
    ns.UI.show({ kind = "zone", mapID = 1439, questID = 4763 })
    local out = {}
    for _, m in ipairs(ns.UI.RouteView.detail.parts.map.markers) do
      if m:IsShown() and m.point.kind == "objective" then out[#out + 1] = m end
    end
    return out
  end

  local function tip(marker)
    fake.enter(marker)
    local out = {}
    for i, l in ipairs(fake.tooltip.lines) do out[i] = { l[1], l[2], l[3], l[4] } end
    return out
  end

  it("model: an objective point carries its objective; dots of one objective sort together", function()
    load({ patch = objectives({ { 1439, 50, 30, 2 }, { 1439, 51, 31 }, { 1439, 52, 32, 1 }, { 1439, 53, 33, 2 } },
      { { 1, 6, "Kobold Vermin", 10 }, WOLF }) })
    local m = model(4763)
    local objs = {}
    for _, p in ipairs(m.points) do
      if p.kind == "objective" then objs[#objs + 1] = { p.x, p.objective and p.objective.index or false, p.label } end
    end
    assert.same({ { 52, 1, "Kobold Vermin" }, { 50, 2, "Tough Wolf Meat" }, { 53, 2, "Tough Wolf Meat" },
      { 51, false, "Objective" } }, objs)
    assert.same({ 4763, "Objective of The Blackwood Corrupted" }, { m.questID, m.objectiveText })
  end)

  it("tooltip: an item with its count and where it drops", function()
    load({ patch = objectives({ { 1439, 45.2, 35.2, 1 } }, { WOLF }) })
    local markers = objectiveMarkers()
    assert.equal(1, #markers)
    assert.is_true(markers[1].dot:IsShown())          -- still the red disc
    assert.same({
      { "Tough Wolf Meat", 1, 1, 1 },
      { "Item · 8 needed", LIGHT, LIGHT, LIGHT },
      { "Drops from: Young Wolf, Timber Wolf, Ragged Wolf, …", LIGHT, LIGHT, LIGHT },
      { "45.2, 35.2 · Click: set waypoint", GREY, GREY, GREY },
    }, tip(markers[1]))
    assert.is_true(fake.tooltip.shown)
    assert.same({}, env.errors)
  end)

  it("tooltip: a kill, a talk-to, an object, an item found in objects, an event", function()
    load({ patch = objectives({ { 1439, 10, 10, 1 }, { 1439, 20, 20, 2 }, { 1439, 30, 30, 3 }, { 1439, 40, 40, 4 },
      { 1439, 50, 50, 5 } }, {
        { 1, 6, "Kobold Vermin", 10 }, { 1, 9, "Captain Placeholder" }, { 2, 52, "Old Crate" },
        { 3, 3910, "Snuff", nil, { "Battered Chest" }, 2 }, { 4, nil, "Peons Awoken", 12 },
      }, "Kill 10 Kobold Vermin, then speak with Captain Placeholder.") })
    local m = objectiveMarkers()
    local function line2(i) return tip(m[i])[2][1] end
    assert.equal("Kill · 10 needed", line2(1))
    assert.equal("Talk to", line2(2))
    assert.equal("Object · use or collect", line2(3))
    assert.equal("Item", line2(4))
    assert.equal("Found in: Battered Chest", tip(m[4])[3][1])
    assert.equal("Objective · 12 needed", line2(5))
    assert.equal(3, #tip(m[1]))                         -- name, kind, coordinates: no source line
  end)

  it("tooltip: an npc objective is Kill (not Talk to) when the text does not say speak or talk", function()
    load({ patch = objectives({ { 1439, 10, 10, 1 } }, { { 1, 9, "Captain Placeholder" } }, "Defeat the captain.") })
    assert.equal("Kill", tip(objectiveMarkers()[1])[2][1])
  end)

  it("tooltip: a point of an unknown objective", function()
    load({ patch = objectives({ { 1439, 45.2, 35.2 } }, { WOLF }) })
    assert.same({ { "Objective", 1, 1, 1 }, { "45.2, 35.2 · Click: set waypoint", GREY, GREY, GREY } },
      tip(objectiveMarkers()[1]))
    -- the old data shape (no field 26) reads the same
    load({ patch = objectives({ { 1439, 45.2, 35.2 } }, nil) })
    assert.same({ { "Objective", 1, 1, 1 }, { "45.2, 35.2 · Click: set waypoint", GREY, GREY, GREY } },
      tip(objectiveMarkers()[1]))
  end)

  it("tooltip: several dots of one objective say the same thing", function()
    load({ patch = objectives({ { 1439, 10, 10, 1 }, { 1439, 20, 20, 1 } }, { WOLF }) })
    local m = objectiveMarkers()
    local a, b = tip(m[1]), tip(m[2])
    a[#a], b[#b] = nil, nil                             -- only the coordinates differ
    assert.same(a, b)
  end)

  it("tooltip: live progress from the quest log wins over the static count", function()
    load({ patch = objectives({ { 1439, 45.2, 35.2, 1 } }, { WOLF }) })
    local m = objectiveMarkers()
    fake.setLog(4763, { objectives = {
      { text = "Peacebloom: 0/1", type = "item", finished = false, numFulfilled = 0, numRequired = 1 },
      { text = "Tough Wolf Meat: 3/10", type = "item", finished = false, numFulfilled = 3, numRequired = 10 },
    } })
    local lines = tip(m[1])
    assert.equal("Item · 10 needed", lines[2][1])
    assert.same({ "Progress: 3/10", 1, 1, 1 }, lines[4])
    fake.setLog(4763, { objectives = {
      { text = "Tough Wolf Meat: 10/10", type = "item", finished = true, numFulfilled = 10, numRequired = 10 },
    } })
    assert.same({ "Progress: 10/10", 0.1, 1, 0.1 }, tip(m[1])[4])
    -- no counts in the entry: read from its text, in either format the client uses
    fake.setLog(4763, { objectives = { { text = "Tough Wolf Meat: 4/8", type = "item", finished = false } } })
    assert.same({ "Progress: 4/8", 1, 1, 1 }, tip(m[1])[4])
    fake.setLog(4763, { objectives = { { text = "5/8 Tough Wolf Meat", type = "item", finished = false } } })
    assert.same({ "Progress: 5/8", 1, 1, 1 }, tip(m[1])[4])
    assert.same({}, env.errors)
  end)

  it("tooltip: a live count at its goal is done even without the finished flag", function()
    load({ patch = objectives({ { 1439, 45.2, 35.2, 1 } }, { WOLF }) })
    local m = objectiveMarkers()
    fake.setLog(4763, { objectives = { { text = "Tough Wolf Meat: 8/8", type = "item" } } })
    assert.same({ "Progress: 8/8", 0.1, 1, 0.1 }, tip(m[1])[4])
    fake.setLog(4763, { objectives = { { text = "Tough Wolf Meat: 7/8", type = "item" } } })
    assert.same({ "Progress: 7/8", 1, 1, 1 }, tip(m[1])[4])
  end)

  it("tooltip: one live entry holding the name is its progress; two are ambiguous and show none", function()
    load({ patch = objectives({ { 1439, 45.2, 35.2, 1 } }, { WOLF }) })
    local m = objectiveMarkers()
    fake.setLog(4763, { objectives = { { text = "Big Tough Wolf Meat: 1/8", type = "item" } } })
    assert.same({ "Progress: 1/8", 1, 1, 1 }, tip(m[1])[4])
    fake.setLog(4763, { objectives = {
      { text = "Big Tough Wolf Meat: 1/8", type = "item" },
      { text = "Small Tough Wolf Meat: 2/8", type = "item" },
    } })
    local lines = tip(m[1])
    assert.equal(4, #lines) -- name, kind, sources, coordinates
    assert.equal("Item · 8 needed", lines[2][1])
    assert.equal("45.2, 35.2 · Click: set waypoint", lines[4][1])
  end)

  it("tooltip: at most three sources, then an ellipsis", function()
    local function sources(names)
      load({ patch = objectives({ { 1439, 45.2, 35.2, 1 } }, { { 3, 750, "Tough Wolf Meat", 8, names, 1 } }) })
      return tip(objectiveMarkers()[1])[3][1]
    end
    assert.equal("Drops from: A, B, C", sources({ "A", "B", "C" }))
    assert.equal("Drops from: A, B, C, …", sources({ "A", "B", "C", "D" }))
  end)

  it("tooltip: no progress line when the quest is not in the log or the API fails", function()
    load({ patch = objectives({ { 1439, 45.2, 35.2, 1 } }, { WOLF }) })
    local m = objectiveMarkers()
    fake.setLog(1, { objectives = {} })                  -- the log has another quest only
    env.C_QuestLog.GetQuestObjectives = function()
      return { { text = "Tough Wolf Meat: 3/8", type = "item", numFulfilled = 3, numRequired = 8 } }
    end
    assert.equal(4, #tip(m[1]))
    fake.setLog(4763, {})
    env.C_QuestLog.GetQuestObjectives = function() error("boom") end
    local lines = tip(m[1])
    assert.equal(4, #lines)
    assert.equal("Item · 8 needed", lines[2][1])
    assert.same({}, env.errors)
  end)

  it("the giver shield tooltip is unchanged", function()
    load({ patch = objectives({ { 1439, 45.2, 35.2, 1 } }, { WOLF }) })
    ns.UI.open()
    ns.UI.show({ kind = "zone", mapID = 1439, questID = 4763 })
    local g = ns.UI.RouteView.detail.parts.map.markers[1]
    assert.equal("giver", g.point.kind)
    fake.enter(g)
    assert.same({ "Quest giver and turn-in: Sentinel Shaya (37.4, 40.1)" }, { fake.tooltip.lines[1][1] })
    assert.equal(1, #fake.tooltip.lines)
  end)

  it("README lists the book, the bookmark and the new commands", function()
    local f = assert(io.open("README.md")); local s = f:read("*a"); f:close()
    assert.truthy(s:find("bookmark", 1, true))
    assert.truthy(s:find("/advisor summary", 1, true))
    assert.truthy(s:find("/advisor map", 1, true))
    assert.is_nil(s:find("dev/LevelingAdvisorDiag", 1, true))
    assert.is_nil(s:find("docs/superpowers", 1, true))
  end)
end)
