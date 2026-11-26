local ui = require("spec.helpers.ui")

describe("UI.Style", function()
  local ns, S, fake
  before_each(function()
    local _
    ns, _, fake = ui.load({ noData = true })
    S = ns.UI.Style
  end)

  it("colours and sizes", function()
    assert.same({ 0.20, 0.13, 0.05 }, S.INK)
    assert.same({ 0.40, 0.29, 0.14 }, S.INK_SOFT)
    assert.same({ 1.0, 0.82, 0.0 }, S.GOLD)
    assert.same({ 0.56, 0.89, 0.56 }, S.REASON)
    assert.same({ 0.23, 0.15, 0.07 }, S.LEATHER)
    assert.same({ 860, 620, 18, 382 }, { S.WIDTH, S.HEIGHT, S.PAGE_PAD, S.CONTENT_W })
  end)

  it("DIFFICULTY is the map pins' colour table", function()
    assert.equal(ns.MapPins.COLORS, S.DIFFICULTY)
    assert.same({
      grey = { 0.5, 0.5, 0.5 },
      green = { 0.25, 0.75, 0.25 },
      yellow = { 1.0, 0.82, 0.0 },
      orange = { 1.0, 0.5, 0.25 },
      red = { 1.0, 0.1, 0.1 },
    }, S.DIFFICULTY)
  end)

  it("number", function()
    assert.equal("7,030", S.number(7030))
    assert.equal("900", S.number(900))
    assert.equal("1,234,567", S.number(1234567))
    assert.equal("0", S.number(0))
    assert.equal("1,000", S.number(1000))
    assert.equal("100", S.number(99.6))
    assert.equal("-1,500", S.number(-1500))
  end)

  it("levels", function()
    assert.equal("10–20", S.levels(10, 20))
  end)

  it("coords", function()
    assert.equal("(37.4, 40.1)", S.coords(37.4, 40.1))
    assert.equal("(40.0, 40.0)", S.coords(40, 40))
  end)

  it("money", function()
    assert.equal("25s", S.money(2500))
    assert.equal("1g 24s 3c", S.money(12403))
    assert.equal("1g", S.money(10000))
    assert.equal("2g 5c", S.money(20005))
    assert.equal("7c", S.money(7))
    assert.equal("0c", S.money(0))
  end)

  it("plural", function()
    assert.equal("1 quest", S.plural(1, "quest"))
    assert.equal("6 quests", S.plural(6, "quest"))
    assert.equal("0 quests", S.plural(0, "quest"))
  end)

  it("text", function()
    local parent = fake.newFrame("Frame")
    local t = S.text(parent, "QuestFont", S.INK)
    assert.equal("FontString", t.kind)
    assert.equal(parent, t:GetParent())
    assert.equal("QuestFont", t.font)
    assert.same({ 0.20, 0.13, 0.05 }, { t.textColor[1], t.textColor[2], t.textColor[3] })
  end)

  it("heading", function()
    local parent = fake.newFrame("Frame")
    local h = S.heading(parent, "Recommended Zones")
    assert.equal("Recommended Zones", h:GetText())
    assert.equal("QuestTitleFont", h.font)
    assert.same({ 0.20, 0.13, 0.05 }, { h.textColor[1], h.textColor[2], h.textColor[3] })
    local rule = h.rule
    assert.equal(1, rule:GetHeight())
    assert.same({ 0.20, 0.13, 0.05, 0.35 }, rule.color)
    local p, rel, rp = rule:GetPoint(1)
    assert.same({ "TOPLEFT", h, "BOTTOMLEFT" }, { p, rel, rp })
  end)

  it("texture prefers the atlas", function()
    local parent = fake.newFrame("Frame")
    local t = S.texture(parent, "BACKGROUND", "QuestBG-Parchment", "Interface\\QuestFrame\\QuestBG")
    assert.equal("QuestBG-Parchment", t:GetAtlas())
    assert.equal("BACKGROUND", t.layer)
  end)

  it("texture falls back to the file without the atlas", function()
    local ns2, env2, fake2 = ui.load({ noData = true, noAtlas = true })
    local t = ns2.UI.Style.texture(fake2.newFrame("Frame"), "ARTWORK", "QuestBG-Parchment", "Interface\\QuestFrame\\QuestBG")
    assert.is_nil(t:GetAtlas())
    assert.equal("Interface\\QuestFrame\\QuestBG", t:GetTexture())
    local ns3, _, fake3 = ui.load({ noData = true, without = { "C_Texture" } })
    local t3 = ns3.UI.Style.texture(fake3.newFrame("Frame"), "ARTWORK", "QuestBG-Parchment", "file")
    assert.equal("file", t3:GetTexture())
    assert.same({}, env2.errors)
  end)

  it("button", function()
    local parent = fake.newFrame("Frame")
    local b = S.button(parent, "Back", 80)
    assert.equal("Button", b.kind)
    assert.equal("UIPanelButtonTemplate", b.template)
    assert.equal("Back", b:GetText())
    assert.same({ 80, 22 }, { b:GetWidth(), b:GetHeight() })
  end)
end)
