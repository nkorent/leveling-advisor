local ui = require("spec.helpers.ui")

describe("main page, right side", function()
  local ns, env, fake, db, state

  local function open(opts)
    opts = opts or {}
    opts.state = opts.state or "S18"
    ns, env, fake = ui.load(opts)
    db, state = ns.Advisor.db, ns.Advisor.last.state
    ns.UI.open()
    return fake.scrollBoxes[1]
  end

  local function sub(id) return ns.UI.QuestInfo.subLine(db, fake.row(id), state) end

  it("questList for S18 in section order", function()
    ns = ui.load({ state = "S18" })
    local el = ns.UI.Model.questList(ns.Advisor.last.rec, {})
    local seq = {}
    for i, e in ipairs(el) do seq[i] = e.kind == "header" and e.key or e.row.questID end
    assert.same({ "turnin", 4730, "here", 4763, 7003, "class", 5061, "next", 1010, 1007, 1100 }, seq)
    assert.same({ "Ready to Turn In", 1, false, 26 }, { el[1].title, el[1].count, el[1].collapsed, el[1].height })
    assert.equal(44, el[2].height)
    assert.equal("turnin", el[2].sectionKey)
    assert.equal(9, #ns.UI.Model.questList(ns.Advisor.last.rec, { here = true }))
  end)

  it("questList with no sections gives the text element", function()
    ns = ui.load({})
    local el = ns.UI.Model.questList({ sections = {} }, {})
    assert.same({ { kind = "text", text = "Nothing to do right here. Pick one of the recommended zones.", height = 40 } }, el)
    assert.equal(1, #ns.UI.Model.questList(nil, nil))
  end)

  it("sub lines", function()
    open()
    assert.equal("Turn in: Marine Tidehunter · 134 yd · ~880 XP", sub(4730))
    assert.equal("Sentinel Shaya · 51 yd · ~1,700 XP", sub(4763))
    assert.equal("126 yd · ~500 XP", sub(7003))
    assert.equal("Ashenvale · ~1,450 XP", sub(1010))
  end)

  it("shared helpers: npc, zone, class names and the place", function()
    open()
    local QI = ns.UI.QuestInfo
    assert.equal("Sentinel Shaya", QI.npcName(db, { kind = 1, id = 3649 }))
    assert.is_nil(QI.npcName(db, { kind = 1, id = 1 }))
    assert.is_nil(QI.npcName(db, { kind = 2, id = 3649 }))
    assert.equal("Darkshore", QI.zoneName(db, 1439))
    assert.is_nil(QI.zoneName(db, 999999))
    assert.equal("Druid", QI.className("DRUID"))
    local q = db:quest(4730)
    assert.same({ q.turnIn, true }, { QI.place(db, q, "complete"), true })
    assert.equal(q.giver, QI.place(db, q, "available"))
    assert.equal(q.turnIn, QI.place(db, q, state))
  end)

  it("class names and colours come from the client tables", function()
    ns, _, fake = ui.load({ state = "S18", globals = {
      LOCALIZED_CLASS_NAMES_MALE = { DRUID = "Druide" },
      RAID_CLASS_COLORS = { DRUID = { r = 1, g = 0.49, b = 0.04 } } } })
    local t = ns.UI.QuestInfo.tags(fake.row(5061), nil)
    assert.same({ "Druide", { 1, 0.49, 0.04 } }, { t[1].text, t[1].color })
  end)

  it("tags", function()
    ns, env, fake = ui.load({ state = "S18" })
    local QI = ns.UI.QuestInfo
    local druid = QI.tags(fake.row(5061), nil)
    assert.equal(1, #druid)
    assert.equal("Druid", druid[1].text)
    assert.same(ns.UI.Style.INK_SOFT, druid[1].color)
    local unv = QI.tags(fake.row(1100), db)
    assert.same({ "unverified" }, { unv[1].text })
    local row = { tags = { chain = { index = 2, length = 6 }, elite = true, group = 5 } }
    local texts = {}
    for i, t in ipairs(QI.tags(row, nil)) do texts[i] = t.text end
    assert.same({ "Chain 2/6", "5 players", "Elite" }, texts)
    local soon = QI.tags({ soon = true, tags = {} }, { requiredLevel = 20 })
    assert.equal("Unlocks at 20", soon[1].text)
  end)

  it("markers", function()
    ns = ui.load({})
    local m = ns.UI.QuestInfo.marker
    assert.same({ atlas = "QuestNormal", desaturated = false }, m("available"))
    assert.same({ atlas = "QuestTurnin", desaturated = false }, m("complete"))
    assert.same({ atlas = "QuestTurnin", desaturated = true }, m("progress"))
    assert.same({ file = "Interface\\Buttons\\UI-CheckBox-Check" }, m("done"))
    assert.same({ atlas = "QuestNormal", desaturated = true }, m("unavailable"))
  end)

  it("renders headers and rows in a ScrollBox", function()
    local box = open()
    assert.equal(11, #box.rows)
    assert.equal("Ready to Turn In", box.rows[1].frame.laHeader.title:GetText())
    assert.equal("1", box.rows[1].frame.laHeader.count:GetText())
    local r = box.rows[2].frame.laQuest
    assert.equal("QuestTurnin", r.marker:GetAtlas())
    assert.equal("17", r.level:GetText())
    assert.same({ 1.0, 0.82, 0.0 }, { r.level.textColor[1], r.level.textColor[2], r.level.textColor[3] })
    assert.equal("Beached Sea Creature", r.title:GetText())
    assert.equal(44, box.rows[2].extent)
    assert.equal(26, box.rows[1].extent)
    assert.equal("Turn in: Marine Tidehunter · 134 yd · ~880 XP", r.sub:GetText())
    assert.equal("Recommended Quests", fake.text("Recommended Quests"):GetText())
  end)

  it("a progress row has the grey ? marker", function()
    open()
    local frame = fake.rowFrame(4763)
    local row = {}
    for k, v in pairs(fake.row(4763)) do row[k] = v end
    row.state = "progress"
    ns.UI.QuestRow.render(frame, row, {})
    assert.equal("QuestTurnin", frame.laQuest.marker:GetAtlas())
    assert.is_true(frame.laQuest.marker.desaturated)
  end)

  it("a missing atlas falls back to the gossip file", function()
    open({ noAtlas = true })
    assert.equal("Interface\\GossipFrame\\ActiveQuestIcon", fake.rowFrame(4730).laQuest.marker:GetTexture())
  end)

  it("row click opens the quest's zone page", function()
    open()
    local spy = ui.spy(ns.UI, "show", function() end)
    fake.click(fake.rowFrame(4763))
    assert.equal(1, spy.n)
    local v = spy.calls[1][1]
    assert.same({ "zone", 1439, 4763, "here" }, { v.kind, v.mapID, v.questID, v.source.section })
    assert.near(50.9, v.source.yards, 0.1)
  end)

  it("openQuest uses the turn-in map for a complete log quest and ignores unknown quests", function()
    open()
    local spy = ui.spy(ns.UI, "show", function() end)
    ns.UI.openQuest(4730, nil)
    ns.UI.openQuest(1010, nil)
    ns.UI.openQuest(424242, nil)
    assert.equal(2, spy.n)
    assert.equal(1439, spy.calls[1][1].mapID)
    assert.equal(1440, spy.calls[2][1].mapID)
  end)

  it("pin button shows the quest on the map", function()
    open()
    local spy = ui.spy(ns.UI.Nav, "showQuest", function() return true end)
    fake.click(fake.rowFrame(4730).laQuest.pin)
    assert.same({ 4730 }, { spy.calls[1][1] })
    assert.equal("Show on Map", (function()
      fake.enter(fake.rowFrame(4730).laQuest.pin); return fake.tooltip.lines[1][1] end)())
  end)

  it("header click collapses and persists", function()
    local box = open()
    fake.click(fake.text("Right Here").parent.parent)
    assert.is_true(ns.chardb.collapsed.here)
    assert.equal(9, #box.rows)
    fake.click(box.rows[3].frame)
    assert.is_nil(ns.chardb.collapsed.here)
    assert.equal(11, #box.rows)
  end)

  it("a pooled frame reused for another kind hides the old parts", function()
    local box = open()
    local frame = box.rows[1].frame
    assert.is_true(frame.laHeader.root:IsShown())
    ns.UI.MainView.initRow(frame, { kind = "quest", row = fake.row(4730), sectionKey = "turnin" })
    assert.is_false(frame.laHeader.root:IsShown())
    assert.is_true(frame.laQuest.root:IsShown())
  end)

  it("an empty rec shows the text element", function()
    local box = open()
    ns.Advisor.last.rec.sections = {}
    ns.UI.refresh()
    assert.equal("Nothing to do right here. Pick one of the recommended zones.", box.rows[1].frame.laText.text:GetText())
  end)

  it("a recompute keeps the scroll position", function()
    open()
    local spy = ui.spy(fake.scrollBoxes[1], "SetDataProvider")
    ns.UI.refresh()
    assert.is_true(spy.calls[1][3])
  end)

  it("missing ScrollBox API shows the fallback text", function()
    open({ without = { "CreateScrollBoxListLinearView" } })
    assert.is_truthy(fake.text("The quest list is not available on this client."))
    assert.same({}, env.errors)
  end)

  it("zone cards: shadowed texts and a capped name width", function()
    open()
    local card = fake.find(function(w) return w.laCard and w.laCard.nameText.text == "Darkshore" end).laCard
    local shadow
    for _, c in ipairs(card.nameText.calls) do if c[1] == "SetShadowOffset" then shadow = c end end
    assert.same({ 1, -1 }, { shadow[2], shadow[3] })
    card:set({ mapID = 1439, name = string.rep("Long ", 30), levels = "10–20", stats = "", reason = "" }, "zone")
    assert.is_true(card.nameText:GetWidth() <= 382 - 20 - 8 - card.levelsText:GetStringWidth())
    assert.is_false(card.nameText.wordWrap)
  end)

  it("no errors while rendering", function()
    open()
    assert.same({}, env.errors)
  end)
end)
