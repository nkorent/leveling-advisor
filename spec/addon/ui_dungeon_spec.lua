local ui = require("spec.helpers.ui")

describe("dungeon page", function()
  local ns, env, fake

  local function load(state)
    ns, env, fake = ui.load({ state = state or "S22" })
  end

  local function model(state)
    local s = state or ns.Advisor.last.state
    return ns.UI.Model.dungeon(ns.Advisor.last.rec.dungeon, s, ns.Advisor.db)
  end

  local function questRow(id)
    for _, box in ipairs(fake.scrollBoxes) do
      for _, r in ipairs(box.rows or {}) do
        if r.element.kind == "quest" and r.element.row.questID == id and fake.visible(r.frame) then return r.frame end
      end
    end
  end

  local function stepRows()
    local out = {}
    for _, box in ipairs(fake.scrollBoxes) do
      for _, r in ipairs(box.rows or {}) do
        if r.element.kind == "step" and fake.visible(r.frame) then
          out[r.element.step.index] = r
        end
      end
    end
    return out
  end

  it("dungeon model for S22", function()
    load()
    local m = model()
    assert.equal("Blackfathom Deeps", m.title)
    assert.equal("Before You Go · pick these up first", m.header)
    assert.equal("0 of 4 done", m.progress)
    assert.same({ "Darkshore — Twilight Falls", "Darkshore — Researching the Corruption",
      "Ashenvale — In Search of Thaelrid", "Loch Modan — Knowledge in the Deeps", "Dungeon entrance — Ashenvale" },
      { m.steps[1].title, m.steps[2].title, m.steps[3].title, m.steps[4].title, m.steps[5].title })
    assert.equal("Not picked up yet", m.steps[1].sub)
    assert.equal("(14.0, 14.0)", m.steps[5].sub)
    assert.is_true(m.steps[5].entrance)
    assert.same({ mapID = 1440, x = 14, y = 14 }, m.steps[5].place)
    assert.equal("pick up", m.steps[1].quests[1].what)
    assert.equal("Level 22–28 · 5 players · 4 quests · ~8,400 XP from quests", m.info.meta)
    assert.equal("Ashenvale (14.0, 14.0)", m.info.entrance)
    assert.equal(ns.Advisor.last.rec.dungeon.reason, m.info.why)
    assert.same({ 1199, 1275, 6563, 6922 }, m.quests)
    assert.is_true(m.steps[1].current); assert.is_false(m.steps[5].current)
  end)

  it("a picked-up dungeon quest is checked", function()
    load()
    local id = ns.Advisor.last.rec.dungeon.pickups[1].questID
    local s = ui.with("S22", { log = { [id] = { complete = false } } })
    local m = model(s)
    assert.equal("1 of 4 done", m.progress)
    assert.is_true(m.steps[1].done)
    assert.equal("In your quest log", m.steps[1].sub)
    assert.is_true(m.steps[2].current)
  end)

  it("the entrance is current once every pickup is done", function()
    load()
    local log = {}
    for _, p in ipairs(ns.Advisor.last.rec.dungeon.pickups) do log[p.questID] = { complete = false } end
    local m = model(ui.with("S22", { log = log }))
    assert.equal("4 of 4 done", m.progress)
    assert.is_true(m.steps[5].current)
  end)

  it("renders info, quest rows and Show Entrance on Map", function()
    load()
    ns.UI.show({ kind = "dungeon", key = "BFD" })
    assert.truthy(fake.visible(fake.text("Blackfathom Deeps")))
    assert.truthy(fake.visible(fake.text("Best at 22 — three of its quests start on your way")))
    assert.truthy(fake.visible(fake.text("Before You Go · pick these up first")))
    assert.truthy(fake.visible(fake.text("0 of 4 done")))
    for _, id in ipairs({ 1199, 1275, 6563, 6922 }) do assert.truthy(questRow(id), "row " .. id) end
    local spy = ui.spy(ns.UI.Nav, "showPlace", function() return true end)
    fake.click(fake.text("Show Entrance on Map"))
    assert.same({ { mapID = 1440, x = 14, y = 14 }, "Blackfathom Deeps entrance", "entrance" },
      { spy.calls[1][1], spy.calls[1][2], spy.calls[1][3] })
    assert.same({}, env.errors)
  end)

  it("a pickup step pin shows its giver; the entrance step shows the entrance", function()
    load()
    ns.UI.show({ kind = "dungeon", key = "BFD" })
    local spy = ui.spy(ns.UI.Nav, "showPlace", function() return true end)
    local rows = stepRows()
    assert.equal(5, #rows)
    fake.click(rows[5].frame.laStep.pin)
    assert.equal("entrance", spy.calls[1][3])
    assert.equal("Dungeon entrance — Ashenvale", spy.calls[1][2])
  end)

  it("a quest row opens its detail with a back link", function()
    load()
    ns.UI.show({ kind = "dungeon", key = "BFD" })
    fake.click(questRow(1275))
    assert.equal(1275, ns.UI.current().questID)
    assert.truthy(fake.visible(fake.text("Researching the Corruption")))
    assert.truthy(fake.text("A quest for Blackfathom Deeps: pick it up before you go."))
    assert.is_false(fake.text("Show Entrance on Map"):IsVisible())
    fake.click(fake.text("Back to Blackfathom Deeps"))
    assert.is_nil(ns.UI.current().questID)
    assert.truthy(fake.visible(fake.text("Show Entrance on Map")))
    assert.same({}, env.errors)
  end)

  it("says when the dungeon is no longer recommended", function()
    load("S18")
    ns.UI.show({ kind = "dungeon", key = "BFD" })
    assert.truthy(fake.visible(fake.text("This dungeon is not recommended right now.")))
    assert.same({}, env.errors)
  end)

  it("a model without a dungeon is nil", function()
    load()
    assert.is_nil(ns.UI.Model.dungeon(nil, {}, ns.Advisor.db))
  end)

  describe("chain badge", function()
    local C, R, N, B = 1199, 1275, 6922, 6563
    local ICON = "Interface\\AddOns\\LevelingAdvisor\\Media\\ChainLink"

    -- C: 4 earlier quests, the first startable one in The Barrens; R: chain ready; B: blocked;
    -- N: no prerequisites.
    local function stubPaths()
      local db = ns.Advisor.db
      db.zone = function(_, id) if id == 1413 then return { name = "The Barrens" } end end
      ns.Unlock.path = function(_, id)
        if id == C then
          local first = { questID = 1, name = "The Stagnant Oasis", status = "start",
            giver = { kind = 1, id = 3001, mapID = 1413, x = 50, y = 50 } }
          return { steps = { first }, total = 4, done = 0, remaining = 4, first = 1 }
        elseif id == R then
          return { steps = { { questID = 2, name = "Done One", status = "done" } }, total = 1, done = 1, remaining = 0 }
        elseif id == B then
          return { steps = { { questID = 3, name = "Other Faction", status = "blocked" } }, total = 2, done = 0,
            remaining = 2, blocked = true }
        end
      end
    end

    local function badgeOf(id) return questRow(id).laQuest.chain end

    local function show()
      load()
      stubPaths()
      ns.UI.show({ kind = "dungeon", key = "BFD" })
    end

    it("shows a tinted icon and the remaining count on a chain quest", function()
      show()
      local b = badgeOf(C)
      assert.is_true(fake.visible(b.frame))
      assert.equal(ICON, b.icon.texture)
      assert.same({ 17, 17 }, { b.icon:GetSize() })
      assert.same({ 0.48, 0.31, 0.07 }, { b.icon.vertex[1], b.icon.vertex[2], b.icon.vertex[3] })
      assert.is_true(fake.visible(b.count))
      assert.equal("4", b.count:GetText())
      assert.same({ 0.62, 0.12, 0.09 }, { b.count.textColor[1], b.count.textColor[2], b.count.textColor[3] })
      assert.equal("Start: The Stagnant Oasis · The Barrens", questRow(C).laQuest.sub:GetText())
      assert.same({}, env.errors)
    end)

    it("a ready chain is a green icon with no count; no prerequisites means no badge", function()
      show()
      local b = badgeOf(R)
      assert.is_true(fake.visible(b.frame))
      assert.same({ 0.18, 0.42, 0.12 }, { b.icon.vertex[1], b.icon.vertex[2], b.icon.vertex[3] })
      assert.is_false(b.count:IsShown())
      assert.is_false(badgeOf(N).frame:IsShown())
    end)

    it("the title is followed by the badge and no row with a path carries a Chain tag", function()
      show()
      for _, id in ipairs({ C, R, B }) do
        local p = questRow(id).laQuest
        for _, t in ipairs(p.tags) do
          assert.is_falsy((t:GetText() or ""):find("Chain ", 1, true), id)
        end
      end
      local p = questRow(C).laQuest
      assert.equal(p.title, p.chain.frame.points[1][2])
    end)

    it("sub lines: blocked, and a ready chain keeps the normal one", function()
      show()
      assert.equal("Not available to your character", questRow(B).laQuest.sub:GetText())
      assert.not_equal("Not available to your character", questRow(R).laQuest.sub:GetText())
    end)

    it("a blocked path is a grey icon, whatever is left (0.3.0)", function()
      show()
      local GREY = { 0.45, 0.45, 0.45 }
      local b = badgeOf(B)
      assert.same(GREY, { b.icon.vertex[1], b.icon.vertex[2], b.icon.vertex[3] })
      ns.Unlock.path = function(_, id)
        if id == R then
          return { steps = { { questID = 2, name = "Done One", status = "done" } }, total = 1, done = 1,
            remaining = 0, blocked = true }
        end
      end
      ns.UI.refresh()
      b = badgeOf(R)
      assert.same(GREY, { b.icon.vertex[1], b.icon.vertex[2], b.icon.vertex[3] })
      assert.is_false(b.count:IsShown())
      -- the tooltip is unchanged
      fake.enter(b.frame)
      assert.equal("Not available to your character", fake.tooltip.lines[2][1])
    end)

    -- A dungeon row whose own status is "Horde only", rendered with a path.
    local function renderBlocked(path, short)
      local row = ns.UI.QuestInfo.row(ns.Advisor.db, C, ns.Advisor.last.state)
      row.state, row.soon, row.short = "unavailable", false, short
      ns.Unlock.path = function() return path end
      local frame = fake.newFrame("Button", nil, env.UIParent)
      return ns.UI.QuestRow.render(frame, row, { chain = true, sub = ns.UI.QuestInfo.statusText(row) })
    end

    it("blocked by the quest itself: the sub line is the quest's own status (0.3.0)", function()
      load()
      -- no step of the path is blocked, so the quest itself is ruled out
      local p = renderBlocked({ steps = { { questID = 1, name = "Open Step", status = "start", number = 1 } },
        total = 2, done = 0, remaining = 2, blocked = true }, "Horde only")
      assert.equal("Horde only", p.sub:GetText())
      -- an any-group with one option still open is not a blocked step either
      p = renderBlocked({ steps = { { questID = 1, status = "blocked", number = 1 },
        { questID = 2, status = "locked", number = 1 } }, total = 2, done = 0, remaining = 2, blocked = true },
        "Horde only")
      assert.equal("Horde only", p.sub:GetText())
      -- no status text of its own: the generic line
      p = renderBlocked({ steps = { { questID = 1, status = "start", number = 1 } }, total = 2, done = 0,
        remaining = 2, blocked = true }, nil)
      assert.equal("Not available to your character", p.sub:GetText())
      assert.same({}, env.errors)
    end)

    it("blocked by an earlier step: the generic line stays", function()
      load()
      local p = renderBlocked({ steps = { { questID = 1, status = "blocked", number = 1 },
        { questID = 2, status = "blocked", number = 1 }, { questID = 3, status = "start", number = 2 } },
        total = 3, done = 0, remaining = 3, blocked = true }, "Horde only")
      assert.equal("Not available to your character", p.sub:GetText())
      -- steps without unit numbers (each its own unit)
      p = renderBlocked({ steps = { { questID = 1, status = "blocked" } }, total = 2, done = 0, remaining = 2,
        blocked = true }, "Horde only")
      assert.equal("Not available to your character", p.sub:GetText())
    end)

    it("a blocked path says not available even when it names a first step", function()
      show()
      ns.Unlock.path = function(_, id)
        if id == C then
          local first = { questID = 1, name = "The Stagnant Oasis", status = "start",
            giver = { kind = 1, id = 3001, mapID = 1413, x = 50, y = 50 } }
          return { steps = { first }, total = 2, done = 0, remaining = 2, first = 1, blocked = true }
        end
      end
      ns.UI.refresh()
      assert.equal("Not available to your character", questRow(C).laQuest.sub:GetText())
    end)

    it("sub line when the first not-done step is a stub or missing", function()
      show()
      ns.Unlock.path = function(_, id)
        if id == C then
          return { steps = { { name = "Damp Note Quest", status = "unknown", reason = "stub" } }, total = 2,
            done = 0, remaining = 2 }
        elseif id == R then
          return { steps = { { status = "done" }, { status = "unknown", reason = "missing" } }, total = 2,
            done = 1, remaining = 1 }
        end
      end
      ns.UI.refresh()
      assert.equal("First: Damp Note Quest · not in the advisor's data", questRow(C).laQuest.sub:GetText())
      assert.equal("First: Unknown quest · not in the advisor's data", questRow(R).laQuest.sub:GetText())
    end)

    it("start step without a zone says only the name", function()
      show()
      local db = ns.Advisor.db
      db.zone = function() return nil end
      ns.UI.refresh()
      assert.equal("Start: The Stagnant Oasis", questRow(C).laQuest.sub:GetText())
    end)

    it("the tooltip lines", function()
      show()
      local function lines(id)
        fake.enter(badgeOf(id).frame)
        local out = {}
        for i, l in ipairs(fake.tooltip.lines) do out[i] = l[1] end
        return out, fake.tooltip
      end
      local l, tip = lines(C)
      assert.same({ "Chain quest", "4 earlier quests to do first" }, l)
      assert.equal("ANCHOR_RIGHT", tip.anchor)
      assert.is_true(tip.shown)
      assert.same({ "Chain quest", "Earlier quests done" }, (lines(R)))
      local bl, btip = lines(B)
      assert.same({ "Chain quest", "Not available to your character" }, bl)
      assert.same({ 1, 0.2, 0.2 }, { btip.lines[2][2], btip.lines[2][3], btip.lines[2][4] })
      fake.leave(badgeOf(B).frame)
      assert.is_false(fake.tooltip.shown)
    end)

    it("one earlier quest is singular", function()
      show()
      ns.Unlock.path = function() return { steps = {}, total = 1, done = 0, remaining = 1 } end
      ns.UI.refresh()
      fake.enter(badgeOf(C).frame)
      assert.equal("1 earlier quest to do first", fake.tooltip.lines[2][1])
    end)

    it("a pooled row re-rendered for a quest without a path hides the badge", function()
      show()
      local frame = questRow(C)
      assert.is_true(fake.visible(frame.laQuest.chain.frame))
      ns.UI.QuestRow.render(frame, ns.UI.QuestInfo.row(ns.Advisor.db, N, ns.Advisor.last.state), { chain = true })
      assert.is_false(frame.laQuest.chain.frame:IsShown())
    end)

    it("rows without opts.chain never show the badge", function()
      show()
      local frame = questRow(C)
      ns.UI.QuestRow.render(frame, ns.UI.QuestInfo.row(ns.Advisor.db, C, ns.Advisor.last.state), {})
      assert.is_false(frame.laQuest.chain.frame:IsShown())
    end)

    it("the badge passes clicks to the row when the client can propagate them", function()
      show()
      local b = badgeOf(C)
      assert.is_true(b.frame.mouse)
      assert.is_true(b.frame.propagateClicks)
      assert.is_nil(b.frame.scripts.OnMouseUp)
    end)

    it("without click propagation, a mouse-up on the badge reaches the row with the same button", function()
      load()
      local orig = env.CreateFrame
      env.CreateFrame = function(...)
        local f = orig(...)
        rawset(f, "SetPropagateMouseClicks", false) -- this client has no such method
        return f
      end
      local frame = fake.newFrame("Button", nil, env.UIParent)
      local row = ns.UI.QuestInfo.row(ns.Advisor.db, C, ns.Advisor.last.state)
      ns.Unlock.path = function() return { steps = {}, total = 1, done = 0, remaining = 1 } end
      local p = ns.UI.QuestRow.render(frame, row, { chain = true })
      env.CreateFrame = orig
      assert.is_nil(p.chain.frame.propagateClicks)
      local spy = ui.spy(ns.UI.Menu, "handleClick", function() return true end)
      p.chain.frame.scripts.OnMouseUp(p.chain.frame, "RightButton")
      assert.equal(1, spy.n)
      assert.equal("RightButton", spy.calls[1][3])
      assert.equal(C, spy.calls[1][2])
    end)

    it("end to end with the real Unlock: 1275 needs 3765", function()
      local function patch(data)
        local prereq = {}
        for i, v in pairs(data.quests[1010]) do prereq[i] = v end
        prereq[1] = "The Corruption Abroad"; prereq[8] = 1439
        prereq[11] = { 1, 3649, 1439, 37.4, 40.1 }; prereq[12] = prereq[11]
        data.quests[3765] = prereq
        data.quests[1275][19] = { all = { 3765 } }
      end
      local function rowFor(completed)
        ns, env, fake = ui.load({ state = ui.with("S22", { completed = completed }), patch = patch })
        ns.UI.show({ kind = "dungeon", key = "BFD" })
        return questRow(1275).laQuest
      end
      local p = rowFor({ [4762] = true, [965] = true, [3765] = true })
      assert.is_true(fake.visible(p.chain.frame))
      assert.is_false(p.chain.count:IsShown())
      assert.same({ 0.18, 0.42, 0.12 }, { p.chain.icon.vertex[1], p.chain.icon.vertex[2], p.chain.icon.vertex[3] })
      p = rowFor({ [4762] = true, [965] = true })
      assert.is_true(fake.visible(p.chain.frame))
      assert.equal("1", p.chain.count:GetText())
      assert.equal("Start: The Corruption Abroad · Darkshore", p.sub:GetText())
      assert.same({}, env.errors)
    end)

    it("without the new engine file (an update and /reload only), rows render with no badge", function()
      local all, keep = ui.FILES, {}
      for _, f in ipairs(all) do
        if f ~= "Engine/Unlock.lua" and f ~= "UI/UnlockPath.lua" then keep[#keep + 1] = f end
      end
      ui.FILES = keep
      local ok, err = pcall(load)
      ui.FILES = all
      assert(ok, err)
      assert.is_nil(ns.Unlock)
      ns.UI.show({ kind = "dungeon", key = "BFD" })
      for _, id in ipairs({ C, R, N, B }) do
        local p = questRow(id).laQuest
        assert.is_false(p.chain.frame:IsShown(), id)
        assert.is_falsy((p.sub:GetText() or ""):find("Start:", 1, true), id)
        for _, t in ipairs(p.tags) do
          assert.is_falsy(t:IsShown() and (t:GetText() or ""):find("Chain ", 1, true), id)
        end
      end
      fake.click(questRow(R)) -- the detail page opens too
      assert.equal(R, ns.UI.current().questID)
      assert.truthy(fake.visible(fake.text("Researching the Corruption")))
      assert.same({}, env.errors)
    end)

    it("Unlock.path throwing: rows render with no badge and the error is reported", function()
      load()
      ns.Unlock.path = function() error("unlock broke") end
      ns.UI.show({ kind = "dungeon", key = "BFD" })
      for _, id in ipairs({ C, R, N, B }) do
        assert.is_false(questRow(id).laQuest.chain.frame:IsShown(), id)
      end
      assert.is_true(#env.errors > 0)
      assert.truthy(env.errors[1]:find("unlock broke", 1, true))
    end)

    it("rows without opts.chain (zone pages) show the Chain n/m tag of the chain position (R7)", function()
      load("S18")
      -- 967: outof.games step 3 of 6; the data has 965 -> 966 -> 967
      local row = ns.UI.QuestInfo.row(ns.Advisor.db, 967, ns.Advisor.last.state)
      local frame = fake.newFrame("Button", nil, env.UIParent)
      local p = ns.UI.QuestRow.render(frame, row, {})
      assert.equal("Chain 3/3", p.tags[1]:GetText())
      assert.is_true(p.tags[1]:IsShown())
      assert.is_false(p.chain.frame:IsShown())
      -- as a dungeon row (it has a path): the badge instead of the tag
      p = ns.UI.QuestRow.render(frame, row, { chain = true })
      assert.is_true(p.chain.frame:IsShown())
      assert.is_false(p.tags[1]:IsShown())
    end)

    it("a dungeon row with no path keeps its Chain tag, which can only be Chain 1/m (R4, R7)", function()
      -- a quest that needs N: N has no path but starts a chain of two
      ns, env, fake = ui.load({ state = "S22", patch = function(data)
        local r = {}
        for i, v in pairs(data.quests[1010]) do r[i] = v end
        r[1] = "Knowledge Returned"; r[19] = { all = { N } }
        data.quests[6923] = r
      end })
      ns.UI.show({ kind = "dungeon", key = "BFD" })
      local p = questRow(N).laQuest
      assert.is_false(p.chain.frame:IsShown())
      assert.equal("Chain 1/2", p.tags[1]:GetText())
      assert.is_true(p.tags[1]:IsShown())
      -- with a path the badge takes its place
      ns.Unlock.path = function() return { steps = {}, total = 1, done = 0, remaining = 1 } end
      local frame = fake.newFrame("Button", nil, env.UIParent)
      p = ns.UI.QuestRow.render(frame, ns.UI.QuestInfo.row(ns.Advisor.db, N, ns.Advisor.last.state), { chain = true })
      assert.is_true(p.chain.frame:IsShown())
      for _, t in ipairs(p.tags) do
        assert.is_falsy(t:IsShown() and (t:GetText() or ""):find("Chain ", 1, true))
      end
      assert.same({}, env.errors)
    end)
  end)

  describe("task 7 fold-ins", function()
    it("a zone page update builds the route once", function()
      load("S18")
      ns.UI.show({ kind = "zone", mapID = 1439 })
      local spy = ui.spy(ns.UI.Model, "route")
      ns.UI.refresh()
      assert.equal(1, spy.n)
    end)

    it("show on a closed book does not push the restored view; Back goes to main", function()
      load("S18")
      ns.chardb.lastView = { kind = "zone", mapID = 1440 }
      ns.UI.show({ kind = "zone", mapID = 1439 })
      ns.UI.back()
      assert.equal("main", ns.UI.current().kind)
    end)
  end)
  describe("task 12 fold-ins", function()
    local function patched(fn)
      local d = {}
      for k, v in pairs(ns.Advisor.last.rec.dungeon) do d[k] = v end
      fn(d)
      return d
    end

    it("a missing entrance says so instead of (0.0, 0.0)", function()
      load()
      local d = patched(function(x) x.entrance = nil end)
      local m = ns.UI.Model.dungeon(d, ns.Advisor.last.state, ns.Advisor.db)
      assert.equal("Entrance unknown", m.info.entrance)
      assert.equal("Entrance unknown", m.steps[#m.steps].sub)
      assert.is_nil(m.info.place)
      assert.is_nil(m.steps[#m.steps].place)
    end)

    it("the page hides the entrance pin and disables the map button without an entrance", function()
      load()
      ns.Advisor.last.rec.dungeon.entrance = nil
      ns.UI.show({ kind = "dungeon", key = "BFD" })
      assert.truthy(fake.visible(fake.text("Entrance unknown")))
      local spy = ui.spy(ns.UI.Nav, "showPlace", function() return true end)
      local btn = fake.text("Show Entrance on Map")
      assert.is_false(btn.enabled ~= false)
      fake.click(btn)
      assert.equal(0, spy.n)
      assert.is_false(fake.visible(ns.UI.RouteView.dungeonParts.pin))
      assert.same({}, env.errors)
    end)

    it("zero pickups: only the entrance step and a 0 of 0 progress", function()
      load()
      local d = patched(function(x) x.pickups = {} end)
      local m = ns.UI.Model.dungeon(d, ns.Advisor.last.state, ns.Advisor.db)
      assert.equal(1, #m.steps)
      assert.is_true(m.steps[1].entrance)
      assert.is_true(m.steps[1].current)
      assert.equal("0 of 0 done", m.progress)
    end)

    -- I1 (final review): rows carry their status; impossible quests never
    -- look available, and the actionable ones come first.
    it("quest rows carry their status, actionable ones first", function()
      ns, env, fake = ui.load({ state = "S22", patch = function(data)
        local q = data.dungeons.BFD.quests
        table.insert(q, 1, 6382)   -- Horde only
        table.insert(q, 2, 7002)   -- Warrior only
        table.insert(q, 3, 4762)   -- completed
      end })
      ns.UI.show({ kind = "dungeon", key = "BFD" })
      assert.truthy(fake.visible(fake.text("All quests (7)")))
      local order = {}
      for _, r in ipairs(ns.UI.RouteView.dungeonParts.questList.box.rows) do
        order[#order + 1] = r.element.row.questID
      end
      assert.same({ 1199, 1275, 6563, 6922, 4762, 6382, 7002 }, order)
      local function part(id) return questRow(id).laQuest end
      assert.equal("Horde only", part(6382).sub.text)
      assert.equal("Other class", part(7002).sub.text)
      assert.equal("Completed", part(4762).sub.text)
      assert.is_true(part(6382).marker.desaturated)
      assert.not_equal("Available", part(1199).sub.text)
      assert.falsy(part(1199).marker.desaturated)
      assert.same({}, env.errors)
    end)

    it("the quest list is labelled with its own count", function()
      load()
      ns.UI.show({ kind = "dungeon", key = "BFD" })
      assert.truthy(fake.visible(fake.text("All quests (4)")))
    end)
  end)
end)
