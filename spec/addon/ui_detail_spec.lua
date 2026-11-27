local ui = require("spec.helpers.ui")

describe("quest detail page", function()
  local ns, env, fake, db, state

  local function load(opts)
    opts = opts or {}
    opts.state = opts.state or "S18"
    ns, env, fake = ui.load(opts)
    db, state = ns.Advisor.db, ns.Advisor.last.state
  end

  local function A(id)
    local s, t, sh = ns.UI.QuestInfo.availability(db, db:quest(id), state)
    return { s, t, sh }
  end

  it("availability texts for S18", function()
    load()
    assert.same({ "unavailable", "Horde only.", "Horde only" }, A(6382))
    assert.same({ "unavailable", "Not available to your race.", "Other race" }, A(7001))
    assert.same({ "unavailable", "Not available to your class.", "Other class" }, A(7002))
    assert.same({ "done", "You have completed this quest.", "Completed" }, A(965))
    assert.same({ "unavailable", "Needs The Tower of Althalaxx first.", "Needs an earlier quest" }, A(967))
    assert.same({ "unavailable", "Only up to level 15.", "Too late" }, A(7008))
    assert.same({ "complete", "Ready to turn in.", "Ready to turn in" }, A(4730))
    assert.same({ "progress", "In your quest log.", "In your log" }, A(966))
    assert.same({ "available", "You can pick it up now.", "Available" }, A(4763))
    assert.same({ "unavailable", "You did a quest that rules this one out.", "Ruled out" }, A(7005))
    assert.same({ "unavailable", "You already have the quest it leads to.", "Not needed" }, A(7006))
    assert.same({ "unavailable", "Not enough data to recommend this quest.", "No data" }, A(7007))
    assert.same({ "soon", "Unlocks at level 18.", "Unlocks at 18" },
      (function() local s = ui.with("S18", { level = 17 }); fake.setState(s); state = ns.Advisor.last.state; return A(991) end)())
  end)

  it("availability: grey, ignored, level, too-high", function()
    load({ state = ui.with("S18", { level = 25, ignored = { [4763] = true } }) })
    assert.same({ "unavailable", "Too low for your level (grey).", "Grey" }, A(1081))
    assert.same({ "unavailable", "You are ignoring this quest.", "Ignored" }, A(4763))
    load({ state = ui.with("S18", { level = 10 }) })
    assert.same({ "unavailable", "Requires level 15.", "Requires level 15" }, A(4763))
    assert.same({ "unavailable", "Quest level 18 is too high for you yet.", "Too high" }, A(7003))
  end)

  it("detail for 4763 from the Right Here section", function()
    load()
    local d = ns.UI.QuestInfo.detail(db, 4763, state, { section = "here", yards = 50.9 })
    assert.same({ "The Blackwood Corrupted", 18, "yellow", "Requires level 15", "~1,700 XP" },
      { d.title, d.level, d.color, d.requiredText, d.xpText })
    assert.same({ "Sentinel Shaya, Darkshore", "(37.4, 40.1)", "Not picked up yet · 51 yd · turn in to the same NPC" },
      { d.giver.title, d.giver.coords, d.giver.status })
    assert.equal("Its quest giver is 51 yd from you.", d.why)
    assert.equal("Objective of The Blackwood Corrupted", d.objective)
    assert.equal(1439, d.giver.place.mapID)
    -- 4763 needs 4762 (done): no outof.games chain, but step 2 of 2 in the prerequisite graph
    assert.equal("Chain 2/2 · last step", d.chainText)
  end)

  it("detail for a chain step in the log", function()
    load()
    local d = ns.UI.QuestInfo.detail(db, 966, state, nil)
    assert.equal("~2,350 XP for the rest of the chain", d.chainXpText)
    assert.truthy(d.giver.status:match("^In your quest log"))
    assert.equal("progress", d.state)
  end)

  it("the head's Chain n/m counts the quests the Unlock Path counts (R7)", function()
    load()
    local QI = ns.UI.QuestInfo
    -- outof.games has 966 as step 2 of 6; the prerequisite graph is 965 -> 966 -> 967
    local d = QI.detail(db, 966, state, nil)
    assert.equal(1, d.unlock.total)
    assert.equal("Chain 2/3", d.chainText)
    assert.equal("~2,350 XP for the rest of the chain", d.chainXpText) -- the chain XP stays as it was
    -- 965 has no prerequisites: no path, still the first step of the chain
    d = QI.detail(db, 965, state, nil)
    assert.is_nil(d.unlock)
    assert.equal("Chain 1/3", d.chainText)
    -- the rendered head, beside the Unlock Path's count
    ns.UI.show({ kind = "zone", mapID = 1439, questID = 966 })
    local head = ns.UI.RouteView.detail.parts.head
    assert.truthy(head.meta:GetText():find("Chain 2/3", 1, true))
    assert.truthy(fake.visible(fake.text("1 quest before this one · 1 done")))
    assert.is_true(head.chainXp:IsShown())
    assert.equal("~2,350 XP for the rest of the chain", head.chainXp:GetText())
    -- the chain has its own text: no Chain chip among the head's tags
    for _, t in ipairs(QI.detail(db, 966, state, nil).tags) do
      assert.is_falsy(t.text:find("Chain ", 1, true))
    end
  end)

  it("a chain's last step says so, and chainXP needs two counted steps", function()
    load()
    local QI = ns.UI.QuestInfo
    assert.equal(2350, QI.chainXP(db, db:quest(966), state))
    assert.is_nil(QI.chainXP(db, db:quest(967), state))
    assert.is_nil(QI.chainXP(db, db:quest(4763), state))
    -- outof.games: 3 of 6; nothing in the data needs 967
    assert.equal("Chain 3/3 · last step", QI.detail(db, 967, state, nil).chainText)
    -- no prerequisites and no followers: no chain text, whatever outof.games says (991: 1 of 7)
    assert.is_nil(QI.detail(db, 991, state, nil).chainText)
  end)

  it("detail for a complete quest shows the turn-in NPC", function()
    load()
    local d = ns.UI.QuestInfo.detail(db, 4730, state, nil)
    assert.equal("Marine Tidehunter, Darkshore", d.giver.title)
    assert.truthy(d.giver.status:match("^Ready to turn in · %d+ yd$"))
    assert.equal("It is complete: turn it in to Marine Tidehunter.", d.why)
    assert.equal(37.0, d.giver.place.x)
  end)

  it("a done quest has no turn-in part (F29)", function()
    load()
    local d = ns.UI.QuestInfo.detail(db, 965, state, nil)
    assert.equal("Completed", d.giver.status:match("^Completed"))
    assert.is_nil(d.giver.status:match("turn in"))
  end)

  it("why texts by source", function()
    load()
    local QI = ns.UI.QuestInfo
    local function why(id, src) return QI.detail(db, id, state, src).why end
    assert.equal("A Druid class quest.", why(5061, { section = "class" }))
    assert.equal("One of the first quests in Ashenvale, your next recommended zone.", why(1010, { section = "next" }))
    assert.equal("The next step of a chain you have started (step 2 of 3).", why(966, { section = "chains" }))
    -- no chain position: the sentence without the step
    assert.equal("The next step of a chain you have started.", why(1010, { section = "chains" }))
    assert.equal("Step 5 of your Darkshore route. Done together with 1 other quest there.",
      why(4763, { stepIndex = 5, zoneName = "Darkshore", others = 1 }))
    assert.equal("Step 5 of your Darkshore route. Done together with 2 other quests there.",
      why(4763, { stepIndex = 5, zoneName = "Darkshore", others = 2 }))
    assert.equal("Step 5 of your Darkshore route.", why(4763, { stepIndex = 5, zoneName = "Darkshore", others = 0 }))
    assert.equal("A quest for Blackfathom Deeps: pick it up before you go.", why(4763, { dungeon = "BFD" }))
    assert.equal("You can pick it up now.", why(4763, nil))
    assert.equal("Its quest giver is close to you.", why(4763, { section = "here" }))
  end)

  it("Why Now ignores the source for quests that cannot be picked up", function()
    load()
    local QI = ns.UI.QuestInfo
    assert.equal("You have completed this quest.", QI.detail(db, 965, state, { dungeon = "BFD" }).why)
    assert.equal("Not available to your class.",
      QI.detail(db, 7002, state, { stepIndex = 3, zoneName = "Darkshore", others = 0 }).why)
    assert.equal("Horde only.", QI.detail(db, 6382, state, { section = "here", yards = 10 }).why)
  end)

  it("Review Focus 4: records with gaps", function()
    load()
    local QI = ns.UI.QuestInfo
    local d7 = QI.detail(db, 7007, state, nil)
    assert.is_nil(d7.requiredText)
    assert.equal("Not enough data to recommend this quest.", d7.why)
    local q = db:quest(4763)
    local copy = {}
    for k, v in pairs(q) do copy[k] = v end
    copy.giver = { kind = 1, id = 99999, mapID = 1439, x = 37.4, y = 40.1 }
    copy.turnIn = copy.giver
    copy.objectiveText = nil
    db.cache[4763] = copy
    local d = QI.detail(db, 4763, state, nil)
    assert.equal("Quest giver, Darkshore", d.giver.title)
    assert.is_nil(d.objective)
    assert.is_nil(QI.detail(db, 424242, state, nil))
  end)

  it("giver titles for objects and items", function()
    load()
    local QI = ns.UI.QuestInfo
    local q = db:quest(4763)
    local function with(kind)
      local copy = {}
      for k, v in pairs(q) do copy[k] = v end
      copy.giver = { kind = kind, id = 1, mapID = 1439, x = 1, y = 2 }
      copy.turnIn = nil
      db.cache[4763] = copy
      return QI.detail(db, 4763, state, nil).giver
    end
    assert.equal("An object, Darkshore", with(2).title)
    assert.equal("Starts from an item", with(3).title)
  end)

  it("QuestInfo.row for a quest outside the sections", function()
    load()
    local r = ns.UI.QuestInfo.row(db, 991, state)
    assert.same({ "available", 1050, "orange" }, { r.state, r.xp, r.color })
    -- rows carry no chain position: the tag chips compute it (QuestInfo.tags with db and state)
    assert.is_nil(r.tags.chain)
    assert.same({}, ns.UI.QuestInfo.tags(r, db:quest(991), db, state)) -- outof.games 1/7, no prerequisite links
    assert.is_nil(r.tags.class)
    assert.is_nil(r.tags.group)
    assert.is_nil(ns.UI.QuestInfo.row(db, 424242, state))
    -- mirrors Sections.makeRow: yards to the turn-in when complete
    local mine, theirs = ns.UI.QuestInfo.row(db, 4730, state), fake.row(4730)
    assert.near(theirs.yards, mine.yards, 0.001)
    assert.equal("complete", mine.state)
    assert.same(theirs.tags, mine.tags)
    local m5061 = ns.UI.QuestInfo.row(db, 5061, state)
    assert.equal("DRUID", m5061.tags.class)
  end)

  -- I3 (final review): another class's class quest names that class.
  it("another class's class quest is tagged with its own class, not the player's", function()
    load({ state = ui.with("S18", { classFile = "WARRIOR", classMask = 1 }) })
    local QI = ns.UI.QuestInfo
    local r = QI.row(db, 5061, state)   -- Aquatic Form, druid only
    assert.equal("DRUID", r.tags.class)
    assert.equal("Druid", QI.tags(r, db:quest(5061))[1].text)
    local d = QI.detail(db, 5061, state)
    assert.equal("Druid", d.tags[1].text)
  end)

  -- I5 (final review): an advisor refresh of the same quest keeps the scroll.
  it("the detail page keeps its scroll on a refresh and resets it for another quest", function()
    load()
    ns.UI.show({ kind = "zone", mapID = 1439, questID = 4763 })
    local d = ns.UI.RouteView.detail
    d.scroll:SetVerticalScroll(120)
    fake.setState(ui.with("S18"))   -- an advisor result re-renders the open book
    assert.equal(120, d.scroll.verticalScroll)
    ns.UI.select(4730)
    assert.equal(0, d.scroll.verticalScroll)
  end)

  it("subLine falls back to the giver without a Turn in prefix", function()
    load()
    local QI = ns.UI.QuestInfo
    local row = { questID = 424242, state = "complete", yards = 10, xp = 0,
      giver = { kind = 1, id = 3649, mapID = 1439 } }
    assert.equal("Sentinel Shaya · 10 yd", QI.subLine(db, row, state))
  end)

  it("renders the detail page from a row click", function()
    load()
    ns.UI.open()
    local spy = ui.spy(ns.UI.Nav, "showQuest", function() return true end)
    fake.click(fake.rowFrame(4763))
    assert.truthy(fake.visible(fake.text("The Blackwood Corrupted")))
    assert.truthy(fake.visible(fake.text("Back")))
    assert.truthy(fake.visible(fake.text("Why Now")))
    assert.truthy(fake.visible(fake.text("Its quest giver is 51 yd from you.")))
    assert.truthy(fake.visible(fake.text("Objective")))
    assert.truthy(fake.visible(fake.text("Right-click a quest for more")))
    fake.click(fake.text("Show on Map"))
    assert.equal(4763, spy.calls[1][1])
    assert.same({}, env.errors)
  end)

  it("sections are named in layout order and stack top-down", function()
    load()
    ns.UI.open()
    fake.click(fake.rowFrame(4763))
    local d = ns.UI.RouteView.detail
    local names = {}
    for i, s in ipairs(d.sections) do names[i] = s.name end
    assert.same({ "head", "giver", "unlock", "map", "why", "objective", "items", "actions" }, names)
    assert.equal(360, d.content.width)
    assert.is_true(d.content.height > 100)
  end)

  it("zone title and the Back button", function()
    load()
    ns.UI.open()
    fake.click(fake.rowFrame(4763))
    assert.equal("Darkshore", ns.UI.RouteView.title({ mapID = 1439 }))
    assert.equal("Zone", ns.UI.RouteView.title({ mapID = 4242 }))
    fake.click(fake.text("Back"))
    assert.equal("main", ns.UI.current().kind)
  end)

  it("a zone view with no quest to select asks to pick one; unknown quest says so", function()
    load()
    ns.UI.show({ kind = "zone", mapID = 99999 })
    assert.truthy(fake.visible(fake.text("Pick a quest to see its details.")))
    ns.UI.show({ kind = "zone", mapID = 1439, questID = 424242 })
    assert.truthy(fake.visible(fake.text("This quest is not in the advisor's database.")))
  end)

  it("selecting another quest drops the source", function()
    load()
    ns.UI.show({ kind = "zone", mapID = 1439, questID = 4763, source = { section = "here", yards = 50.9 } })
    ns.UI.select(4730)
    assert.truthy(fake.visible(fake.text("It is complete: turn it in to Marine Tidehunter.")))
  end)

  it("the main list's selected row follows the selection", function()
    load()
    ns.UI.open()
    local f1, f2 = fake.rowFrame(4763), fake.rowFrame(4730)
    assert.is_false(f1.laQuest.bg:IsShown())
    ns.UI.select(4763)
    assert.is_true(fake.rowFrame(4763).laQuest.bg:IsShown())
    ns.UI.select(4730)
    assert.is_false(fake.rowFrame(4763).laQuest.bg:IsShown())
    assert.is_true(fake.rowFrame(4730).laQuest.bg:IsShown())
    assert.truthy(f1 and f2)
  end)

  describe("Unlock Path", function()
    -- Contract A record: an Alliance quest in Darkshore given by Sentinel Shaya (required 15,
    -- level 18) unless o overrides. o: all, any, faction, level, requiredLevel, xp.
    local function Q(name, o)
      o = o or {}
      local r = {}
      r[1] = name; r[2] = o.faction or 1; r[5] = o.requiredLevel or 15; r[6] = o.level or 18; r[7] = 1
      r[8] = 1439; r[9] = 0; r[11] = { 1, 3649, 1439, 37.4, 40.1 }; r[12] = { 1, 3649, 1439, 37.4, 40.1 }
      r[14] = "Objective of " .. name; r[17] = o.xp or 1000; r[18] = 1
      if o.all or o.any then r[19] = { all = o.all, any = o.any } end
      return r
    end

    -- S18 with extra quests (and quest stubs); `completed` adds to S18's completed quests.
    local function loadWith(quests, stubs, completed)
      local done = { [4762] = true, [965] = true }
      for _, id in ipairs(completed or {}) do done[id] = true end
      load({ state = ui.with("S18", { completed = done }), patch = function(data)
        for id, r in pairs(quests) do data.quests[id] = r end
        data.questStubs = stubs
      end })
    end

    -- Leaders of the Fang (8105) needs 8104 <- 8103 <- 8102 <- 8101 (startable).
    local FANG = {
      [8101] = Q("The Stagnant Oasis"),
      [8102] = Q("Altered Beings", { all = { 8101 } }),
      [8103] = Q("Hamuul Runetotem", { all = { 8102 } }),
      [8104] = Q("Nara Wildmane", { all = { 8103 } }),
      [8105] = Q("Leaders of the Fang", { all = { 8104 } }),
    }

    -- Fold Target (8207) needs a line of six: 8201 .. 8206.
    local function foldChain()
      local quests = { [8201] = Q("Fold Step 1") }
      for i = 2, 6 do quests[8200 + i] = Q("Fold Step " .. i, { all = { 8200 + i - 1 } }) end
      quests[8207] = Q("Fold Target", { all = { 8206 } })
      return quests
    end

    local function detail(questID)
      ns.UI.show({ kind = "zone", mapID = 1439, questID = questID })
      local d = ns.UI.RouteView.detail
      return d, d.parts.unlock
    end

    local function shownRows(up)
      local out = {}
      for _, r in ipairs(up.rows) do
        if r:IsShown() then out[#out + 1] = r end
      end
      return out
    end

    local function shownCount(list)
      local n = 0
      for _, w in ipairs(list) do
        if w:IsShown() then n = n + 1 end
      end
      return n
    end

    local function texts(rows, key)
      local out = {}
      for i, r in ipairs(rows) do out[i] = r[key]:GetText() end
      return out
    end

    it("a 2-step path: heading, summary, the steps and this quest", function()
      load()
      local d, up = detail(967) -- 965 completed, 966 in the log
      assert.is_true(d.byName.unlock.height > 0)
      assert.truthy(fake.visible(fake.text("Unlock Path")))
      assert.truthy(fake.visible(fake.text("2 quests before this one · 1 done")))
      local rows = shownRows(up)
      assert.equal(3, #rows)
      assert.same({ "The Tower of Althalaxx", "The Tower of Althalaxx", "The Tower of Althalaxx" }, texts(rows, "name"))
      -- 965's giver is not in the NPC data: the zone alone
      assert.same({ "Darkshore", "Gelkak Gyromast, Darkshore", "This quest · Gelkak Gyromast, Darkshore" },
        texts(rows, "sub"))
      -- dots: done check, the in-log step's number, the quest itself as total + 1
      assert.is_true(rows[1].dot.check:IsShown())
      assert.is_false(rows[1].dot.glyph:IsShown())
      assert.same({ "2", "3" }, { rows[2].dot.glyph:GetText(), rows[3].dot.glyph:GetText() })
      assert.is_true(rows[2].pin:IsShown()) -- in the log, with a giver
      assert.is_false(rows[1].pin:IsShown())
      assert.is_false(rows[3].pin:IsShown())
      for _, r in ipairs(rows) do assert.is_false(r.tag:IsShown()) end
      -- one connector between each pair of dots: soft ink, as neither lower dot is done
      assert.equal(2, shownCount(up.lines))
      assert.same({ 0.40, 0.29, 0.14, 0.6 }, up.lines[1].color)
      assert.same({ "18", "18", "18" }, texts(rows, "level"))
      assert.same({}, env.errors)
    end)

    it("START HERE and a pin on the first start step; clicks open the quest or the map", function()
      loadWith(FANG)
      local _, up = detail(8105)
      local rows = shownRows(up)
      assert.equal(5, #rows)
      assert.same({ "The Stagnant Oasis", "Altered Beings", "Hamuul Runetotem", "Nara Wildmane",
        "Leaders of the Fang" }, texts(rows, "name"))
      assert.is_true(rows[1].tag:IsShown())
      assert.equal("START HERE", rows[1].tag:GetText())
      -- ink text on the parchment has no drop shadow (the tag's red is dark ink)
      assert.same({ 0, 0 }, { rows[1].tag:GetShadowOffset() })
      assert.same({ 0, 0 }, { rows[1].sub:GetShadowOffset() })
      for i = 2, 5 do assert.is_false(rows[i].tag:IsShown()) end
      assert.is_true(rows[1].pin:IsShown())
      for i = 2, 5 do assert.is_false(rows[i].pin:IsShown()) end
      local xp = ns.XP.estimate(db:quest(8101), state.level, state.recordedXP)
      assert.equal("Sentinel Shaya, Darkshore · ~" .. ns.UI.Style.number(xp) .. " XP", rows[1].sub:GetText())
      assert.equal("Sentinel Shaya, Darkshore", rows[2].sub:GetText()) -- locked by its prerequisite
      assert.truthy(fake.visible(fake.text("4 quests before this one")))
      assert.truthy(up.summary2:IsShown())
      assert.truthy(up.summary2:GetText():match("^~[%d,]+ XP on the way$"))

      local nav = ui.spy(ns.UI.Nav, "showQuest", function() return true end)
      fake.click(rows[1].pin)
      assert.equal(1, nav.n)
      assert.equal(8101, nav.calls[1][1])
      local open = ui.spy(ns.UI, "openQuest", function() end)
      fake.click(rows[2])
      assert.equal(1, open.n)
      assert.equal(8102, open.calls[1][1])
      fake.click(rows[5]) -- the quest itself does not react
      assert.equal(1, open.n)
      assert.same({}, env.errors)
    end)

    it("the giver status names the earlier quests and where to start", function()
      loadWith(FANG)
      local m = ns.UI.QuestInfo.detail(db, 8105, state)
      assert.equal("Needs 4 earlier quests first. Start with The Stagnant Oasis.", m.giver.status)
      local status, text, short = ns.UI.QuestInfo.availability(db, db:quest(8105), state, m.unlock)
      assert.same({ "unavailable", "Needs 4 earlier quests first. Start with The Stagnant Oasis.",
        "Needs 4 earlier quests" }, { status, text, short })
      local d = detail(8105)
      assert.equal("Needs 4 earlier quests first. Start with The Stagnant Oasis.", d.parts.giver.status:GetText())
      -- one step left keeps the existing texts (967: 966 is in the log)
      load()
      assert.truthy(ns.UI.QuestInfo.detail(db, 967, state).giver.status:match("^Needs an earlier quest · "))
    end)

    it("a quest with no prerequisites has no Unlock Path", function()
      load()
      local d, up = detail(4730)
      assert.is_nil(d.model.unlock)
      assert.equal(0, d.byName.unlock.height)
      assert.is_false(d.byName.unlock.frame:IsShown())
      assert.is_falsy(fake.visible(fake.text("Unlock Path")))
      assert.equal(0, #shownRows(up))
    end)

    it("more than 3 done steps fold into one row; Show all expands them", function()
      loadWith(foldChain(), nil, { 8201, 8202, 8203, 8204, 8205 })
      local d, up = detail(8207)
      assert.truthy(fake.visible(fake.text("6 quests before this one · 5 done")))
      assert.truthy(fake.visible(fake.text("5 earlier steps done")))
      assert.truthy(fake.visible(fake.text("Show all")))
      assert.is_true(up.fold.dot.check:IsShown())
      assert.same({ "Fold Step 6", "Fold Target" }, texts(shownRows(up), "name"))
      assert.equal("6", shownRows(up)[1].dot.glyph:GetText())
      local before = d.byName.unlock.height
      fake.click(fake.text("Show all"))
      local rows = shownRows(up)
      assert.equal(7, #rows)
      local done = 0
      for _, r in ipairs(rows) do
        if r.step and r.step.status == "done" then done = done + 1 end
      end
      assert.equal(5, done)
      assert.is_false(up.fold:IsShown())
      assert.is_true(d.byName.unlock.height > before)
      assert.is_true(up.expanded)
      assert.same({}, env.errors)
    end)

    it("another quest hides the extra pooled rows and resets Show all", function()
      loadWith(foldChain(), nil, { 8201, 8202, 8203, 8204, 8205 })
      local d, up = detail(8207)
      fake.click(fake.text("Show all"))
      assert.equal(7, #shownRows(up))
      assert.equal(6, shownCount(up.lines))
      ns.UI.select(4763) -- 4762 completed: a 1-step path
      local rows = shownRows(up)
      assert.same({ "The Cliffspring River", "The Blackwood Corrupted" }, texts(rows, "name"))
      for i = 3, #up.rows do assert.is_false(up.rows[i]:IsShown()) end
      assert.equal(1, shownCount(up.lines))
      assert.is_false(up.fold:IsShown())
      assert.is_false(up.expanded)
      assert.truthy(fake.visible(fake.text("1 quest before this one · 1 done")))
      ns.UI.select(8207)
      assert.truthy(fake.visible(fake.text("5 earlier steps done")))
      assert.equal(2, #shownRows(up))
      -- an advisor refresh of the same quest keeps Show all
      fake.click(fake.text("Show all"))
      fake.setState(ui.with("S18", { completed = { [4762] = true, [965] = true, [8201] = true, [8202] = true,
        [8203] = true, [8204] = true, [8205] = true } }))
      assert.equal(7, #shownRows(up))
      assert.equal(d.byName.unlock.height, d.byName.unlock.frame.height)
    end)

    it("a stub step that starts from an item", function()
      loadWith({ [8302] = Q("Allegiance to the Old Gods", { all = { 8301 } }) },
        { [8301] = { "Allegiance to the Old Gods", 25, 20, nil, nil, nil, nil, { kind = 3, name = "Damp Note" },
          "no-giver-coords" } })
      local _, up = detail(8302)
      local rows = shownRows(up)
      assert.equal(2, #rows)
      assert.equal("Starts from an item: Damp Note", rows[1].sub:GetText())
      assert.equal("?", rows[1].dot.glyph:GetText())
      assert.equal("25", rows[1].level:GetText())
      assert.truthy(fake.visible(fake.text("1 quest before this one")))
      assert.is_false(rows[1].pin:IsShown())
      local open = ui.spy(ns.UI, "openQuest", function() end)
      fake.click(rows[1]) -- not in the shipped quests: no page to open
      assert.equal(0, open.n)
    end)

    it("a blocked path says so under the heading", function()
      loadWith({ [8401] = Q("Blocked Chain", { all = { 6382 } }) }) -- 6382 is Horde only
      local _, up = detail(8401)
      assert.truthy(fake.visible(fake.text("This chain is not available to your character.")))
      local rows = shownRows(up)
      assert.equal("Not available: Horde only", rows[1].sub:GetText())
      assert.equal("X", rows[1].dot.glyph:GetText())
      load()
      local _, up2 = detail(967)
      assert.is_false(up2.blockedLine:IsShown())
    end)

    it("a chain the character cannot finish names no place to start", function()
      -- 8403 can be started now, 6382 is Horde only: the chain cannot be finished
      loadWith({ [8403] = Q("Open Step"), [8404] = Q("Mixed Chain", { all = { 8403, 6382 } }),
        [8405] = Q("Horde Chain", { all = { 8403 }, faction = 2 }) })
      local QI = ns.UI.QuestInfo
      local m = QI.detail(db, 8404, state)
      assert.is_true(m.unlock.blocked)
      assert.is_nil(m.unlock.first)
      local blockedText = "Needs earlier quests that are not available to your character."
      assert.equal(blockedText, m.giver.status)
      local status, text, short = QI.availability(db, db:quest(8404), state, m.unlock)
      assert.same({ "unavailable", blockedText, "Needs unavailable quests" }, { status, text, short })

      local d, up = detail(8404)
      assert.equal(blockedText, d.parts.giver.status:GetText())
      assert.truthy(fake.visible(fake.text("This chain is not available to your character.")))
      local rows = shownRows(up)
      assert.same({ "Open Step", "The Ashenvale Hunt", "Mixed Chain" }, texts(rows, "name"))
      for _, r in ipairs(rows) do assert.is_false(r.tag:IsShown()) end
      assert.equal("start", rows[1].step.status)
      assert.equal("Sentinel Shaya, Darkshore", rows[1].sub:GetText()) -- no start-step XP hint

      -- the quest itself is Horde only: its own reason, and still no place to start
      d, up = detail(8405)
      assert.truthy(d.parts.giver.status:GetText():match("^Horde only"))
      assert.truthy(fake.visible(fake.text("This chain is not available to your character.")))
      rows = shownRows(up)
      assert.equal(2, #rows)
      for _, r in ipairs(rows) do assert.is_false(r.tag:IsShown()) end
      assert.equal("Sentinel Shaya, Darkshore", rows[1].sub:GetText())
      assert.same({}, env.errors)
    end)

    -- R7: the Tome of Twilight case (94972 in the shipped data): outof.games said 15/21 beside
    -- "20 quests before this one". The head now counts the same quests as the Unlock Path.
    it("a 21-quest chain: Chain 21/21 beside 20 quests before this one", function()
      local quests = { [8601] = Q("Twilight Step 1") }
      for i = 2, 20 do quests[8600 + i] = Q("Twilight Step " .. i, { all = { 8600 + i - 1 } }) end
      quests[8621] = Q("Tome of Twilight", { all = { 8620 } })
      loadWith(quests)
      local d = detail(8621)
      assert.truthy(fake.visible(fake.text("20 quests before this one")))
      assert.truthy(d.parts.head.meta:GetText():find("Chain 21/21 · last step", 1, true))
      d = detail(8615)
      assert.truthy(fake.visible(fake.text("14 quests before this one")))
      assert.truthy(d.parts.head.meta:GetText():find("Chain 15/21", 1, true))
      assert.is_falsy(d.parts.head.meta:GetText():find("last step", 1, true))
      assert.same({}, env.errors)
    end)

    describe("fail-soft without the new files", function()
      local NEW_FILES = { "Engine/Unlock.lua", "UI/UnlockPath.lua" }

      -- An update applied with /reload only: the client does not load files new in it.
      local function loadWithout(files)
        local all, drop, keep = ui.FILES, {}, {}
        for _, f in ipairs(files) do drop[f] = true end
        for _, f in ipairs(all) do
          if not drop[f] then keep[#keep + 1] = f end
        end
        assert.equal(#all - #files, #keep) -- the TOC lists them
        ui.FILES = keep
        local ok, err = pcall(load)
        ui.FILES = all
        if not ok then error(err, 0) end
      end

      it("a detail page renders without the Unlock Path section", function()
        loadWithout(NEW_FILES)
        assert.is_nil(ns.Unlock)
        assert.is_nil(ns.UI.UnlockPath)
        assert.is_nil(ns.UI.QuestInfo.unlockPath(db, 967, state))
        local m = ns.UI.QuestInfo.detail(db, 967, state)
        assert.is_nil(m.unlock)
        assert.truthy(m.giver.status:match("^Needs an earlier quest · "))
        local d, up = detail(967)
        assert.is_nil(up)
        assert.equal(967, d.questID)
        assert.equal(0, d.byName.unlock.height)
        assert.is_false(d.byName.unlock.frame:IsShown())
        assert.is_falsy(fake.visible(fake.text("Unlock Path")))
        assert.truthy(fake.visible(fake.text("The Tower of Althalaxx")))
        assert.is_true(d.byName.why.height > 0)
        assert.same({}, env.errors)
      end)

      it("no chain text, tag or step number, and nothing errors", function()
        loadWithout(NEW_FILES)
        local QI = ns.UI.QuestInfo
        assert.is_nil(QI.chainPosition(db, 966, state))
        local m = QI.detail(db, 966, state, { section = "chains" })
        assert.is_nil(m.chainText)
        assert.equal("~2,350 XP for the rest of the chain", m.chainXpText)
        assert.equal("The next step of a chain you have started.", m.why)
        assert.same({}, QI.tags({ questID = 4763, tags = {} }, db:quest(4763), db, state))
        ns.UI.open()
        local p = fake.rowFrame(4763).laQuest
        for _, t in ipairs(p.tags) do
          assert.is_falsy(t:IsShown() and (t:GetText() or ""):find("Chain ", 1, true))
        end
        local d = detail(966)
        assert.is_falsy(d.parts.head.meta:GetText():find("Chain ", 1, true))
        assert.same({}, env.errors)
      end)

      it("Unlock.position throwing: no chain text and the error is reported", function()
        load()
        ns.Unlock.position = function() error("position broke") end
        local QI = ns.UI.QuestInfo
        assert.is_nil(QI.chainPosition(db, 966, state))
        assert.equal(1, #env.errors)
        assert.truthy(env.errors[1]:find("position broke", 1, true))
        assert.is_nil(QI.detail(db, 966, state).chainText)
        assert.same({}, QI.tags({ questID = 4763, tags = {} }, db:quest(4763), db, state))
        local d = detail(966)
        assert.is_falsy(d.parts.head.meta:GetText():find("Chain ", 1, true))
        assert.truthy(fake.visible(fake.text("1 quest before this one · 1 done"))) -- the path still shows
      end)

      it("Unlock.path throwing: the page renders without the section and the error is reported", function()
        load()
        ns.Unlock.path = function() error("unlock broke") end
        assert.is_nil(ns.UI.QuestInfo.unlockPath(db, 967, state))
        assert.equal(1, #env.errors)
        assert.truthy(env.errors[1]:find("unlock broke", 1, true))
        local d, up = detail(967)
        assert.is_nil(d.model.unlock)
        assert.equal(0, d.byName.unlock.height)
        assert.equal(0, #shownRows(up))
        assert.is_falsy(fake.visible(fake.text("Unlock Path")))
        assert.truthy(d.parts.giver.status:GetText():match("^Needs an earlier quest · "))
        assert.is_true(#env.errors >= 2)
      end)
    end)

    it("groups get a label row and indented members; a missing step is an unknown quest", function()
      loadWith({
        [8501] = Q("Twin Paths", { all = { 8502, 8503, 8509 }, any = { 8504, 8505 } }),
        [8502] = Q("Left Path"), [8503] = Q("Right Path"),
        [8504] = Q("Either A"), [8505] = Q("Either B"),
      })
      local _, up = detail(8501)
      local rows = shownRows(up)
      assert.same({ "Left Path", "Right Path", "Unknown quest", "Either A", "Either B", "Twin Paths" },
        texts(rows, "name"))
      assert.equal("Not in the advisor's data", rows[3].sub:GetText())
      assert.equal("?", rows[3].dot.glyph:GetText())
      local labels = {}
      for _, l in ipairs(up.labels) do
        if l:IsShown() then labels[#labels + 1] = l:GetText() end
      end
      assert.same({ "NEEDS ALL 3", "ONE OF" }, labels)
      for i = 1, 5 do assert.equal(18, select(4, rows[i]:GetPoint(1))) end
      assert.equal(0, select(4, rows[6]:GetPoint(1)))
      -- only the first start step is the place to start; every start step is tinted
      assert.is_true(rows[1].tag:IsShown())
      for i = 2, 6 do assert.is_false(rows[i].tag:IsShown()) end
      assert.same({ true, true, false, true, true, false },
        { rows[1].bg:IsShown(), rows[2].bg:IsShown(), rows[3].bg:IsShown(), rows[4].bg:IsShown(),
          rows[5].bg:IsShown(), rows[6].bg:IsShown() })
    end)

    it("sub lines for every step state", function()
      load()
      local _, up = detail(4763)
      local function step(id, status, reason, o)
        local s = { questID = id, name = "Step " .. id, level = 18, status = status, reason = reason, number = 1 }
        for k, v in pairs(o or {}) do s[k] = v end
        return s
      end
      local stub = function(start) return { start = start } end
      local giver = db:quest(4763).giver
      local steps = {
        step(1, "unknown", "conflict"),
        step(2, "unknown", "no-data"),
        step(3, "unknown", "stub", { stub = stub({ kind = 2, name = "Dusty Chest" }) }),
        step(4, "unknown", "stub", { stub = stub({ kind = 2 }) }),
        step(5, "unknown", "stub", { stub = stub({ kind = 3 }) }),
        step(6, "unknown", "stub", { stub = stub({ kind = 1, name = "James Halloran", mapID = 1437 }) }),
        step(7, "unknown", "stub", { stub = stub({ kind = 1 }) }),
        step(8, "unknown", "stub", { stub = stub(nil) }),
        step(9, "unknown", "missing"),
        step(10, "blocked", "race"),
        step(11, "blocked", "class"),
        step(12, "blocked", "exclusive"),
        step(13, "blocked", "unavailable"),
        step(14, "blocked", "faction", { stub = { faction = 1 } }),
        step(4763, "locked", "level"),
        step(4762, "locked", "prereq", { giver = giver }),
        step(15, "unknown", "ignored"),
        step(16, "blocked", "max-level"),
        step(17, "unknown", "stub", { stub = stub({ kind = 1, name = "Orgrul", mapID = 1440 }) }),
        step(18, "done", "implied", { stub = stub({ kind = 1, name = "Orgrul", mapID = 1440 }) }),
      }
      steps[9].name, steps[9].level = nil, nil -- missing: no record, no name, no level
      up:render({ questID = 4763, steps = steps, total = #steps, done = 0, remaining = #steps, xp = 0,
        blocked = true }, { title = "The Blackwood Corrupted", level = 18, color = "yellow" }, db, state)
      assert.same({
        "Unclear in the advisor's data", "Not in the advisor's data", "Starts at an object: Dusty Chest",
        "Starts at an object", "Starts from an item", "James Halloran (location unknown)",
        "Not in the advisor's data", "Not in the advisor's data", "Not in the advisor's data",
        "Not available: other race", "Not available: other class",
        "Not available: ruled out by another quest", "Not available: ruled out by another quest",
        "Not available: Alliance only", "Unlocks at level 15", "Sentinel Shaya, Darkshore",
        "Not in the advisor's data", "Not available to your character",
        "Orgrul, Ashenvale", "Orgrul, Ashenvale",
        "This quest · Sentinel Shaya, Darkshore",
      }, texts(shownRows(up), "sub"))
      assert.equal("Unknown quest", shownRows(up)[9].name:GetText())
      assert.equal("?", shownRows(up)[9].level:GetText())
      assert.equal("?", shownRows(up)[1].dot.glyph:GetText())
      assert.is_falsy(fake.visible(up.summary2))
    end)
  end)
end)
