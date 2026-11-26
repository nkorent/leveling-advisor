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
    assert.is_nil(d.chainText)
  end)

  it("detail for a chain step in the log", function()
    load()
    local d = ns.UI.QuestInfo.detail(db, 966, state, nil)
    assert.equal("Chain 2/6", d.chainText)
    assert.equal("~2,350 XP for the rest of the chain", d.chainXpText)
    assert.truthy(d.giver.status:match("^In your quest log"))
    assert.equal("progress", d.state)
  end)

  it("a chain's last step says so, and chainXP needs two counted steps", function()
    load()
    local QI = ns.UI.QuestInfo
    assert.equal(2350, QI.chainXP(db, db:quest(966), state))
    assert.is_nil(QI.chainXP(db, db:quest(967), state))
    assert.is_nil(QI.chainXP(db, db:quest(4763), state))
    local q = db:quest(967)
    local copy = {}
    for k, v in pairs(q) do copy[k] = v end
    copy.chain = { id = 965, index = 6, length = 6 }
    db.cache[967] = copy
    assert.equal("Chain 6/6 · last step", QI.detail(db, 967, state, nil).chainText)
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
    assert.equal("The next step of a chain you have started (step 2 of 6).", why(966, { section = "chains" }))
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
    assert.same({ index = 1, length = 7 }, r.tags.chain)
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
    assert.same({ "head", "giver", "map", "why", "objective", "items", "actions" }, names)
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
end)
