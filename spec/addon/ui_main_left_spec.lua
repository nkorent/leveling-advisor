local ui = require("spec.helpers.ui")

describe("main page, left side", function()
  local L = { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 }

  local function open(opts)
    opts = opts or {}
    opts.state = opts.state or "S18"
    local ns, env, fake = ui.load(opts)
    ns.UI.open()
    return ns, env, fake
  end

  local function cardFor(fake, name)
    return fake.find(function(w) return w.kind == "Button" and w.laCard and w.laCard.nameText.text == name end)
  end

  it("left model for S18", function()
    local ns = ui.load({ state = ui.with("S18", { xp = 4526, xpMax = 7300 }) })
    local m = ns.UI.Model.left(ns.Advisor.last.rec, ns.Advisor.last.state, ns.Advisor.db,
      { name = "Elarin", race = "Night Elf", className = "Druid", rested = 0 })
    assert.equal("Elarin · Night Elf Druid · Darkshore", m.char.left)
    assert.equal("Level 18 · 62%", m.char.right)
    assert.same({ mapID = 1439, name = "Darkshore", levels = "10–20",
      stats = "6 quests for you · ~7,030 XP · 1 chain",
      reason = "You are here — finish before you leave", isHere = true }, m.zones[1])
    assert.equal("1 quest for you · ~900 XP", m.zones[3].stats)
    assert.is_nil(m.dungeon)
  end)

  it("char line leaves out an unknown zone and the percent without xpMax", function()
    local ns = ui.load({ state = ui.with("S18", { mapID = 99999 }) })
    local m = ns.UI.Model.left(ns.Advisor.last.rec, ns.Advisor.last.state, ns.Advisor.db,
      { name = "Elarin", race = "Night Elf", className = "Druid" })
    assert.equal("Elarin · Night Elf Druid", m.char.left)
    assert.equal("Level 18", m.char.right)
  end)

  it("dungeon card model for S20", function()
    local ns = ui.load({ state = "S20" })
    local m = ns.UI.Model.left(ns.Advisor.last.rec, ns.Advisor.last.state, ns.Advisor.db, {})
    assert.same({ key = "BFD", name = "Blackfathom Deeps", levels = "22–28", group = "5 players",
      stats = "4 quests for you · ~8,400 XP",
      reason = "Best at 21 — three of its quests start on your way", artMapID = 1440 }, m.dungeon)
  end)

  it("ZoneArt crop places 8 tiles, fit places 12", function()
    local ns = ui.load({})
    assert.equal(8, #ns.UI.ZoneArt.placement(L, 382, 88, "crop").tiles)
    local fit = ns.UI.ZoneArt.placement(L, 300, 200, "fit")
    assert.equal(12, #fit.tiles)
    assert.is_true(math.abs(fit.scale - 0.2994) < 1e-3)
  end)

  it("renders three zone cards and opens a zone on click", function()
    local ns, env, fake = open()
    for _, n in ipairs({ "Darkshore", "Ashenvale", "Loch Modan" }) do
      assert.is_true(fake.visible(fake.text(n)), n)
    end
    local show = ui.spy(ns.UI, "show", function() end)
    fake.click(cardFor(fake, "Ashenvale"))
    assert.same({ kind = "zone", mapID = 1440 }, show.calls[1][1])
    assert.same({}, env.errors)
  end)

  it("the here card has the gold border, the others the dark one", function()
    local _, _, fake = open()
    assert.same({ 1, 0.82, 0 }, { unpack(cardFor(fake, "Darkshore").laCard.border[1].color, 1, 3) })
    assert.same({ 0.16, 0.11, 0.05 }, { unpack(cardFor(fake, "Ashenvale").laCard.border[1].color, 1, 3) })
    local c = cardFor(fake, "Ashenvale")
    fake.enter(c)
    assert.same({ 0.66, 0.57, 0.36 }, { unpack(c.laCard.border[1].color, 1, 3) })
    fake.leave(c)
    assert.same({ 0.16, 0.11, 0.05 }, { unpack(c.laCard.border[1].color, 1, 3) })
  end)

  it("dungeon card hidden at S18, shown at S20 and opens the dungeon", function()
    local ns, _, fake = open()
    assert.is_false(fake.visible(fake.text("Blackfathom Deeps")) or false)
    assert.is_false(fake.visible(fake.text("Recommended Dungeon")) or false)
    fake.setState("S20")
    ns.UI.refresh()
    assert.is_true(fake.visible(fake.text("Blackfathom Deeps")))
    assert.is_true(fake.visible(fake.text("Recommended Dungeon")))
    local show = ui.spy(ns.UI, "show", function() end)
    fake.click(cardFor(fake, "Blackfathom Deeps"))
    assert.same({ kind = "dungeon", key = "BFD" }, show.calls[1][1])
  end)

  it("draws zone art tiles, and a plain card without the art API", function()
    local ns, env, fake = open({ art = "tiles" })
    local c = cardFor(fake, "Darkshore")
    local shown = fake.findAll(function(w)
      return w.kind == "Texture" and w.texture and w.parent == c.laCard.art.canvas and fake.visible(w)
    end)
    assert.equal(8, #shown)
    assert.same({}, env.errors)

    local ns2, env2, fake2 = open({})
    assert.equal("none", ns2.UI.ZoneArt.draw(ns2.UI.ZoneArt.newBox(fake2.globals.UIParent, 382, 88), 1439, "crop"))
    assert.same({}, env2.errors)
  end)

  it("XP bar values", function()
    local _, _, fake = open({ state = ui.with("S18", { xp = 4526, xpMax = 7300 }) })
    local bar = fake.find(function(w) return w.kind == "StatusBar" and w.max == 7300 and w.value == 4526 and w.barColor[1] == 0.58 end)
    assert.is_truthy(bar)
    assert.same({ 0.58, 0.0, 0.55 }, { unpack(bar.barColor, 1, 3) })
  end)

  it("empty zones message", function()
    local ns, _, fake = open()
    ns.Advisor.last.rec.zones = {}
    ns.UI.refresh()
    assert.is_true(fake.visible(fake.text("No zones to recommend right now.")))
  end)

  it("main build returns a right root for the right page", function()
    local ns, _, fake = open()
    assert.is_true(fake.visible(fake.find(function(w) return w.kind == "Frame" and w.parent == ns.UI.frame.laPages.right.content end)))
  end)
end)
