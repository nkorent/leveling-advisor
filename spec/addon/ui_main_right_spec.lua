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
    -- Later starts collapsed: its header only
    assert.same({ "turnin", 4730, "here", 4763, 7003, "class", 5061, "next", 1010, 1007, 1100, "later" }, seq)
    local later = el[#el]
    assert.same({ "later", 1, true }, { later.key, later.count, later.collapsed })
    local open = ns.UI.Model.questList(ns.Advisor.last.rec, {}, true)
    assert.same({ "later", 991 }, { open[#open - 1].key, open[#open].row.questID })
    assert.same({ "Ready to Turn In", 1, false, 26 }, { el[1].title, el[1].count, el[1].collapsed, el[1].height })
    assert.equal(44, el[2].height)
    assert.equal("turnin", el[2].sectionKey)
    assert.equal(10, #ns.UI.Model.questList(ns.Advisor.last.rec, { here = true }))
  end)

  it("questList with no sections gives the text element", function()
    ns = ui.load({})
    local el = ns.UI.Model.questList({ sections = {} }, {})
    assert.same({ { kind = "text", text = "Nothing to do right here. Pick one of the recommended zones.", height = 40 } }, el)
    assert.equal(1, #ns.UI.Model.questList(nil, nil))
  end)

  it("questList with only the Later section shows the text above its header", function()
    ns = ui.load({})
    local rec = { sections = { { key = "later", title = "Later — too high for now",
      rows = { { questID = 991 } } } } }
    local el = ns.UI.Model.questList(rec, {})
    assert.equal(2, #el)
    assert.same({ kind = "text", text = "Nothing to do right here. Pick one of the recommended zones.", height = 40 }, el[1])
    assert.same({ "header", "later", true }, { el[2].kind, el[2].key, el[2].collapsed })
    local open = ns.UI.Model.questList(rec, {}, true)
    assert.same({ "text", "header", "quest" }, { open[1].kind, open[2].kind, open[3].kind })
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
    -- the chain chip comes from the chain position (R7): 965 -> 966 -> 967 in the data
    local function texts(...)
      local out = {}
      for i, t in ipairs(QI.tags(...)) do out[i] = t.text end
      return out
    end
    local row = { questID = 966, tags = { elite = true, group = 5 } }
    local d, s = ns.Advisor.db, ns.Advisor.last.state
    assert.same({ "Chain 2/3", "5 players", "Elite" }, texts(row, nil, d, s))
    -- without db and state, or for a quest outside any chain, there is none
    assert.same({ "5 players", "Elite" }, texts(row, nil))
    assert.same({ "5 players", "Elite" }, texts({ questID = 1010, tags = row.tags }, nil, d, s))
    local soon = QI.tags({ soon = true, tags = {} }, { requiredLevel = 20 })
    assert.equal("Unlocks at 20", soon[1].text)
  end)

  it("a section row's Chain tag counts the prerequisite graph, as the Unlock Path does (R7)", function()
    open({ state = ui.with("S18", { completed = { [4762] = true, [965] = true, [966] = true },
      log = { [4730] = { complete = true } } }) })
    -- 967 continues a started chain; outof.games has it as step 3 of 6, the data as 965 -> 966 -> 967
    local p = fake.rowFrame(967).laQuest
    assert.is_true(p.tags[1]:IsShown())
    assert.equal("Chain 3/3", p.tags[1]:GetText())
    -- 4763 needs 4762: on no outof.games chain, step 2 of 2 in the data
    assert.equal("Chain 2/2", fake.rowFrame(4763).laQuest.tags[1]:GetText())
    -- no prerequisites, nothing needs it: no Chain tag
    for _, t in ipairs(fake.rowFrame(1010).laQuest.tags) do
      assert.is_falsy(t:IsShown() and (t:GetText() or ""):find("Chain ", 1, true))
    end
    fake.click(fake.rowFrame(967))
    assert.truthy(fake.visible(fake.text("The next step of a chain you have started (step 3 of 3).")))
    assert.same({}, env.errors)
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
    assert.equal(12, #box.rows) -- 6 headers (Later last, collapsed) and 6 rows
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
    assert.equal(10, #box.rows)
    fake.click(box.rows[3].frame)
    assert.is_nil(ns.chardb.collapsed.here)
    assert.equal(12, #box.rows)
  end)

  it("the Later header shows its count, starts collapsed, expands on click and persists", function()
    local box = open()
    local header = fake.text("Later — too high for now").parent.parent
    assert.equal("1", header.laHeader.count:GetText())
    assert.equal(12, #box.rows) -- 991 is not listed
    assert.is_nil(fake.rowFrame(991))
    fake.click(header)
    assert.is_true(ns.chardb.ui.laterOpen)
    assert.equal(13, #box.rows)
    assert.is_truthy(fake.rowFrame(991))
    -- a new session of the same character finds it open
    open({ chardb = { ignored = {}, collapsed = {}, ui = { laterOpen = true } } })
    assert.is_truthy(fake.rowFrame(991))
    fake.click(fake.text("Later — too high for now").parent.parent)
    assert.is_false(ns.chardb.ui.laterOpen)
    assert.is_nil(fake.rowFrame(991))
  end)

  it("Later rows say when they get good", function()
    open()
    assert.equal("Good at level 19", sub(991))
    local logged = ui.with("S18", { log = { [991] = { complete = false } } })
    open({ state = logged })
    assert.equal("In your log — better at level 19", sub(991))
  end)

  it("a Later row never gets the bright quest marker", function()
    open()
    ns.chardb.ui = { laterOpen = true }
    ns.UI.refresh()
    local row = fake.row(991)
    assert.equal("available", row.state)
    local marker = fake.rowFrame(991).laQuest.marker
    assert.is_true(marker.desaturated)
  end)

  it("Why Now for a Later quest", function()
    open()
    assert.equal("Too high for now — good at level 19.",
      ns.UI.QuestInfo.why(db, db:quest(991), state, { section = "later" }))
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

  describe("guide controls", function()
    local function btn(label)
      return fake.find(function(w) return w.text == label end)
    end

    it("shows the toggle and Continue, the toggle labelled with the state", function()
      open()
      assert.is_truthy(btn("Guide: On"))
      assert.is_truthy(btn("Continue with waypoint"))
      assert.is_true(btn("Continue with waypoint"):IsEnabled())
    end)

    it("the toggle switches the guide and its label follows", function()
      open()
      fake.click(btn("Guide: On"), "LeftButton")
      assert.is_false(ns.UI.Guide.enabled())
      assert.is_nil(btn("Guide: On"))
      assert.is_truthy(btn("Guide: Off"))
      assert.is_false(btn("Continue with waypoint"):IsEnabled())
      fake.click(btn("Guide: Off"), "LeftButton")
      assert.is_true(ns.UI.Guide.enabled())
      assert.is_true(btn("Continue with waypoint"):IsEnabled())
    end)

    it("the labels follow a change made elsewhere (menu or slash)", function()
      open()
      ns.UI.Guide.setEnabled(false)
      assert.is_truthy(btn("Guide: Off"))
      assert.is_false(btn("Continue with waypoint"):IsEnabled())
    end)

    it("reads Guide: Paused while paused; Continue stays on and the toggle turns it off", function()
      open()
      ns.MapPins.setWaypoint({ mapID = 1440, x = 10, y = 10, quests = { { name = "Elsewhere" } } })
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      assert.is_true(ns.UI.Guide.paused())
      assert.is_nil(btn("Guide: On"))
      assert.is_truthy(btn("Guide: Paused"))
      assert.is_true(btn("Continue with waypoint"):IsEnabled())
      fake.click(btn("Guide: Paused"), "LeftButton")
      assert.is_false(ns.UI.Guide.enabled())
      assert.is_truthy(btn("Guide: Off"))
      fake.click(btn("Guide: Off"), "LeftButton")
      assert.is_truthy(btn("Guide: On"))
    end)

    it("reads Guide: Paused when the book opens on a pause kept from an earlier session", function()
      open({ chardb = { guideState = { paused = true, why = "replaced" } } })
      assert.is_truthy(btn("Guide: Paused"))
      fake.click(btn("Continue with waypoint"), "LeftButton")
      assert.is_false(ns.UI.Guide.paused())
      assert.is_truthy(btn("Guide: On"))
    end)

    it("Continue calls Guide.continue", function()
      open()
      local spy = ui.spy(ns.UI.Guide, "continue", function() end)
      fake.click(btn("Continue with waypoint"), "LeftButton")
      assert.equal(1, spy.n)
    end)

    it("starts with Guide: Off when the setting is off", function()
      open({ chardb = { settings = { guide = false } } })
      assert.is_truthy(btn("Guide: Off"))
      assert.is_false(btn("Continue with waypoint"):IsEnabled())
    end)

    it("without the guide module the controls are hidden", function()
      ns, env, fake = ui.load({ state = "S18" })
      ns.UI.Guide = nil
      ns.UI.open()
      assert.is_nil(btn("Guide: On"))
    end)

    describe("layout", function()
      local function point(w, name)
        for _, p in ipairs(w.points) do if p[1] == name then return p end end
      end
      -- the list is the one frame hung from the pane's top-left at a negative offset
      local function listOffset(right)
        local found
        fake.find(function(w)
          local p = w.points and point(w, "TOPLEFT")
          if p and p[2] == right and p[5] and p[5] < -20 and w.kind ~= "FontString" and w ~= right then
            found = p[5]
            return true
          end
        end)
        return found
      end

      it("sits on its own row under the heading's rule, and the list below it", function()
        open()
        local heading = fake.find(function(w) return w.text == "Recommended Quests" end)
        local toggle, cont = btn("Guide: On"), btn("Continue with waypoint")
        -- sized from the text (the fake measures 6 px a character) + 24, at least 80 / 150;
        -- the toggle fits its widest label, "Guide: Paused" (13 characters)
        assert.same({ 13 * 6 + 24, 22 * 6 + 24 }, { toggle:GetWidth(), cont:GetWidth() })
        local p = point(cont, "TOPRIGHT")
        assert.equal(heading.rule, p[2])
        assert.same({ "BOTTOMRIGHT", 0, -4 }, { p[3], p[4], p[5] })
        assert.equal(cont, point(toggle, "RIGHT")[2])
        local right = heading:GetParent()
        assert.is_true(listOffset(right) <= -(28 + 4 + 22))
      end)

      it("a client that cannot measure the text gets 100 and 170 px", function()
        ns, env, fake = ui.load({ state = "S18" })
        local made = ns.UI.Style.button
        ns.UI.Style.button = function(...)
          local b = made(...)
          b.GetFontString = function() return nil end
          return b
        end
        ns.UI.open()
        assert.same({ 100, 170 }, { btn("Guide: On"):GetWidth(), btn("Continue with waypoint"):GetWidth() })
        assert.same({}, env.errors)
      end)

      it("short labels keep the minimum widths", function()
        ns, env, fake = ui.load({ state = "S18" })
        local made = ns.UI.Style.button
        ns.UI.Style.button = function(...)
          local b = made(...)
          b.GetFontString = function() return { GetStringWidth = function() return 20 end } end
          return b
        end
        ns.UI.open()
        assert.same({ 80, 150 }, { btn("Guide: On"):GetWidth(), btn("Continue with waypoint"):GetWidth() })
      end)

      it("without the guide module the list keeps its old offset", function()
        ns, env, fake = ui.load({ state = "S18" })
        ns.UI.Guide = nil
        ns.UI.open()
        local heading = fake.find(function(w) return w.text == "Recommended Quests" end)
        assert.equal(-28, listOffset(heading:GetParent()))
      end)
    end)
  end)
end)
