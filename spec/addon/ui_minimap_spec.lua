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

  it("model: giver and turn-in merged, objective, player", function()
    load()
    local m = model(4763)
    assert.same({ 1439, "Darkshore" }, { m.mapID, m.mapName })
    assert.same({ "giver", 37.4, 40.1, "Quest giver and turn-in: Sentinel Shaya" },
      { m.points[1].kind, m.points[1].x, m.points[1].y, m.points[1].label })
    assert.same({ "objective", 52.5, 33.4, "Objective" },
      { m.points[2].kind, m.points[2].x, m.points[2].y, m.points[2].label })
    assert.same({ x = 38.0, y = 41.0 }, m.player)
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
    assert.is_true(fake.visible(mm.player))
    fake.enter(g)
    assert.equal("Quest giver and turn-in: Sentinel Shaya (37.4, 40.1)", fake.tooltip.lines[1][1])
    local spy = ui.spy(ns.UI.Nav, "showPlace", function() return true end)
    fake.click(g)
    assert.same({ { mapID = 1439, x = 37.4, y = 40.1 }, "Quest giver and turn-in: Sentinel Shaya", "giver" },
      { spy.calls[1][1], spy.calls[1][2], spy.calls[1][3] })
    assert.is_truthy(fake.text("Darkshore — click a marker for a waypoint"))
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

  it("README lists the book, the bookmark and the new commands", function()
    local f = assert(io.open("README.md")); local s = f:read("*a"); f:close()
    assert.truthy(s:find("bookmark", 1, true))
    assert.truthy(s:find("/advisor summary", 1, true))
    assert.truthy(s:find("/advisor map", 1, true))
    assert.is_nil(s:find("dev/LevelingAdvisorDiag", 1, true))
    assert.is_nil(s:find("docs/superpowers", 1, true))
  end)
end)
