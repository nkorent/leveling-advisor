local ui = require("spec.helpers.ui")

describe("zone route page", function()
  local ns, env, fake, db

  local function load(opts)
    opts = opts or {}
    opts.state = opts.state or "S18"
    ns, env, fake = ui.load(opts)
    db = ns.Advisor.db
  end

  local function stepRows()
    local out = {}
    for _, box in ipairs(fake.scrollBoxes) do
      for _, r in ipairs(box.rows or {}) do
        if r.element.kind == "step" then out[r.element.step.index] = r end
      end
    end
    return out
  end

  describe("advisor", function()
    it("actionDone", function()
      load()
      local D = ns.Advisor.actionDone
      local s = ui.with("S18", { log = { [4763] = { complete = false }, [966] = { complete = true } } })
      assert.is_true(D(4763, "pickup", s)); assert.is_true(D(966, "objective", s))
      assert.is_false(D(966, "turnin", s)); assert.is_false(D(4730, "turnin", ui.with("S18")))
      assert.is_false(D(1, "pickup", {})); assert.is_false(D(1, "pickup", nil))
      assert.is_true(D(965, "turnin", ui.with("S18")))
    end)

    it("plan is cached per zone and replanned on a key change", function()
      load()
      local calls = ui.spy(ns.Engine, "route")
      local p = ns.Advisor.plan(1439); assert.equal(p, ns.Advisor.plan(1439)); assert.equal(1, calls.n)
      fake.setState(ui.with("S18", { level = 19 })); ns.Advisor.plan(1439); assert.equal(2, calls.n)
      ns.Advisor.replan(1439); ns.Advisor.plan(1439); assert.equal(3, calls.n)
      ns.Advisor.replan(); ns.Advisor.plan(1439); assert.equal(4, calls.n)
    end)

    it("plan in combat: the stale plan, or nil when there is none", function()
      load()
      fake.combat(true)
      assert.is_nil(ns.Advisor.plan(1439))
      fake.combat(false)
      local p = ns.Advisor.plan(1439)
      fake.setState(ui.with("S18", { level = 19 }))   -- key change
      fake.combat(true)
      assert.equal(p, ns.Advisor.plan(1439))
      ns.Advisor.replan(1439)
      assert.is_nil(ns.Advisor.plan(1439))
    end)

    it("replans when every step is done", function()
      load()
      local calls = ui.spy(ns.Engine, "route")
      local p = ns.Advisor.plan(1439)
      local completed = {}
      for _, step in ipairs(p.steps) do
        for _, a in ipairs(step.actions) do completed[a[1]] = true end
      end
      fake.setState(ui.with("S18", { completed = completed, log = {} }))
      ns.Advisor.plan(1439)
      assert.equal(2, calls.n)
      ns.Advisor.plan(1439)   -- same result: not rebuilt on every call
      assert.equal(2, calls.n)
    end)

    local function planned(plan, id)
      for _, step in ipairs(plan.steps) do
        for _, a in ipairs(step.actions) do if a[1] == id then return true end end
      end
      return false
    end
    -- The Lost Mine (1000) is ruled out once Bathran's Hair (1010) is taken.
    local function exclusiveMine(data) data.quests[1000][20] = { 1010 } end
    local function took1010()
      return ui.with("S18", { log = { [966] = { complete = false }, [4730] = { complete = true },
        [1010] = { complete = false } } })
    end

    -- I2 (final review): the frozen plan is checked again on each result.
    it("replans once when a planned quest is ruled out, and drops it", function()
      load({ patch = exclusiveMine })
      local calls = ui.spy(ns.Engine, "route")
      assert.is_true(planned(ns.Advisor.plan(1439), 1000))
      fake.setState(took1010())
      local p = ns.Advisor.plan(1439)
      assert.equal(2, calls.n)
      assert.is_false(planned(p, 1000))
      ns.Advisor.plan(1439)   -- same result: not rebuilt again
      assert.equal(2, calls.n)
    end)

    it("a waiting chain step is not ruled out", function()
      load()
      local calls = ui.spy(ns.Engine, "route")
      local p = ns.Advisor.plan(1439)
      assert.is_true(planned(p, 967))   -- needs 966 (in the log) first
      fake.setState(ui.with("S18"))
      assert.equal(p, ns.Advisor.plan(1439))
      assert.equal(1, calls.n)
      assert.is_false(ns.Advisor.questDropped(db, 967, ns.Advisor.last.state))
    end)

    it("in combat the stale plan marks the ruled-out quest and does not wait for it", function()
      load({ patch = exclusiveMine })
      local p = ns.Advisor.plan(1439)
      fake.combat(true)
      fake.setState(took1010())
      assert.equal(p, ns.Advisor.plan(1439))
      local r = ns.UI.Model.route(p, ns.Advisor.last.state, db)
      local line = r.steps[4].quests[1]
      assert.equal(1000, line.questID)
      assert.same({ "unavailable", true, true, "no longer available" }, { line.state, line.dropped, line.done, line.what })
      assert.is_true(r.steps[4].done)
      assert.equal("Darkshore · 10–20 · 6 quests left", r.header)
      -- a step chain blocked only by the ruled-out quest lets the route finish
      local all = { completed = {}, log = { [1010] = { complete = false } } }
      for _, step in ipairs(p.steps) do
        for _, a in ipairs(step.actions) do if a[1] ~= 1000 then all.completed[a[1]] = true end end
      end
      assert.equal("Your route is done.", ns.UI.Model.route(p, ui.with("S18", all), db).progress)
    end)

    it("the plan key holds the ignored set, not just its size", function()
      load({ state = ui.with("S18", { ignored = { [7008] = true } }) })
      local calls = ui.spy(ns.Engine, "route")
      ns.Advisor.plan(1439)
      fake.setState(ui.with("S18", { ignored = { [7007] = true } }))
      ns.Advisor.plan(1439)
      assert.equal(2, calls.n)
    end)

    it("an empty plan is kept", function()
      load()
      local calls = ui.spy(ns.Engine, "route", function() return {} end)
      assert.same({}, ns.Advisor.plan(1439).steps)
      ns.Advisor.plan(1439)
      assert.equal(1, calls.n)
    end)
  end)

  describe("model", function()
    it("route model for S18", function()
      load()
      local st = ns.Advisor.last.state
      local r = ns.UI.Model.route(ns.Advisor.plan(1439), st, db)
      assert.equal("Darkshore · 10–20 · 7 quests left", r.header); assert.equal("Your route · step 1 of 7", r.progress)
      assert.equal(1, r.current)
      assert.same({ "Sentinel Shaya", "Darkshore (40.0, 40.0)", "Objectives near (52.5, 33.4)" },
        { r.steps[1].title, r.steps[2].title, r.steps[3].title })
      assert.equal("Pick up 1 · Objectives 2 · Turn in 2 · ~2,350 XP", r.steps[5].sub)
      assert.same({ "The Tower of Althalaxx", "pick up, objectives, turn in" },
        { r.steps[5].quests[2].name, r.steps[5].quests[2].what })
      assert.same({ mapID = 1439, x = 37.4, y = 40.1 }, r.steps[1].place)
      assert.is_true(r.steps[1].current); assert.is_false(r.steps[2].current)
      assert.equal("progress", r.steps[5].quests[1].state)
      assert.equal("complete", r.steps[7].quests[1].state)
      assert.equal("available", r.steps[1].quests[1].state)
    end)

    -- C1 (final review): The Tower of Althalaxx part 3 (967) needs part 2
    -- (966, in the log): no "!" at Gelkak until 966 is turned in.
    local function after966()
      local s = ui.with("S18")
      s.completed[966] = true; s.log[966] = nil
      return s
    end

    it("a latent chain step gets no map pin until its prerequisite is done", function()
      load()
      local plan = ns.Advisor.plan(1439)
      local function pinKind(state, id)
        for _, pin in ipairs(ns.MapPins.build(ns.Advisor.last.rec, db, 1439, plan.steps, state)) do
          for _, q in ipairs(pin.quests) do if q.id == id then return pin.kind end end
        end
      end
      local st = ns.Advisor.last.state
      assert.is_nil(pinKind(st, 967))
      assert.is_nil(pinKind(st, 966))   -- in progress: no "!" at its giver, no "?" yet
      assert.equal("pickup", pinKind(after966(), 967))
    end)

    it("a latent chain step shows the grey marker on the route page", function()
      load()
      local plan = ns.Advisor.plan(1439)
      local r = ns.UI.Model.route(plan, ns.Advisor.last.state, db)
      assert.equal(967, r.steps[5].quests[2].questID)
      assert.equal("unavailable", r.steps[5].quests[2].state)
      assert.is_false(r.steps[5].quests[2].done)
      assert.equal("available", ns.UI.Model.route(plan, after966(), db).steps[5].quests[2].state)
    end)

    it("selected flag and nil plan", function()
      load()
      local r = ns.UI.Model.route(ns.Advisor.plan(1439), ns.Advisor.last.state, db, 5061)
      assert.is_true(r.steps[7].quests[2].selected); assert.is_false(r.steps[7].quests[1].selected)
      assert.is_nil(ns.UI.Model.route(nil, {}, db))
    end)

    it("progress texts for a done and an empty route", function()
      load()
      local plan = { mapID = 1439, steps = { { mapID = 1439, x = 1, y = 2, actions = { { 4730, "turnin" } },
        counts = { pickup = 0, objective = 0, turnin = 1 }, xp = 0 } } }
      local done = ns.UI.Model.route(plan, { completed = { [4730] = true }, log = {} }, db)
      assert.equal("Your route is done.", done.progress)
      assert.is_nil(done.current)
      assert.equal("Darkshore · 10–20 · 0 quests left", done.header)
      assert.equal("Nothing to do here right now.",
        ns.UI.Model.route({ mapID = 1439, steps = {} }, {}, db).progress)
    end)

    it("a picked-up quest checks its step and advances the progress", function()
      load()
      local p = ns.Advisor.plan(1439)
      fake.setState(ui.with("S18", { log = { [966] = { complete = false }, [4730] = { complete = true },
        [4763] = { complete = false } } }))
      assert.equal(p, ns.Advisor.plan(1439))   -- same key: the plan is kept, not rebuilt
      local r = ns.UI.Model.route(p, ns.Advisor.last.state, db)
      assert.is_true(r.steps[1].done); assert.equal("Your route · step 2 of 7", r.progress)
    end)

    it("map pins and the zone page agree", function()
      load()
      local plan = ns.Advisor.plan(1439)
      local function pickupPinned(state, id, onlyPickup)
        for _, pin in ipairs(ns.MapPins.build(ns.Advisor.last.rec, db, 1439, plan.steps, state)) do
          for _, q in ipairs(pin.quests) do
            if q.id == id and (pin.kind == "pickup" or not onlyPickup) then return true end
          end
        end
        return false
      end
      local st = ns.Advisor.last.state
      for _, step in ipairs(plan.steps) do
        for _, a in ipairs(step.actions) do
          local g = db:quest(a[1]).giver
          if a[2] == "pickup" and g and g.mapID == 1439 then
            local open = not ns.Advisor.actionDone(a[1], "pickup", st) and ns.Advisor.canPickUp(db, a[1], st)
            assert.equal(open, pickupPinned(st, a[1]), "quest " .. a[1])
          end
        end
      end
      assert.is_true(pickupPinned(st, 4763))
      local after = ui.with("S18", { log = { [966] = { complete = false }, [4730] = { complete = true },
        [4763] = { complete = false } } })
      assert.is_false(pickupPinned(after, 4763, true))
    end)
  end)

  describe("page", function()
    it("renders steps; a line click selects; the step pin shows its place", function()
      load()
      ns.UI.show({ kind = "zone", mapID = 1439 })   -- default selection 4763
      assert.truthy(fake.visible(fake.text("The Blackwood Corrupted")))
      local rows = stepRows()
      assert.equal(7, #rows)
      assert.equal(30 + 18 * 1 + 18, rows[1].element.height)
      assert.equal(30 + 18 * 2 + 18, rows[7].element.height)
      assert.is_true(rows[1].frame.laStep.step.current)
      local line = rows[7].frame.laStep.lines[2]
      assert.equal("Aquatic Form — pick up, turn in", line.text.text)
      fake.click(line)
      assert.equal(5061, ns.UI.current().questID)
      assert.same({}, env.errors)
      local spy = ui.spy(ns.UI.Nav, "showPlace", function() return true end)
      fake.click(stepRows()[1].frame.laStep.pin)
      assert.same({ { mapID = 1439, x = 37.4, y = 40.1 }, "Sentinel Shaya", "pickup" },
        { spy.calls[1][1], spy.calls[1][2], spy.calls[1][3] })
    end)

    it("the selected line is highlighted and the detail names its step", function()
      load()
      ns.UI.show({ kind = "zone", mapID = 1439 })
      assert.is_true(stepRows()[1].frame.laStep.lines[1].bg:IsShown())
      ns.UI.select(5061)
      assert.is_true(stepRows()[7].frame.laStep.lines[2].bg:IsShown())
      assert.is_false(stepRows()[1].frame.laStep.lines[1].bg:IsShown())
      assert.truthy(fake.text("Step 7 of your Darkshore route. Done together with 1 other quest there."))
    end)

    it("a source that was passed in is kept for the opened quest", function()
      load()
      ns.UI.show({ kind = "zone", mapID = 1439, questID = 4763, source = { section = "here", yards = 50.9 } })
      assert.truthy(fake.text("Its quest giver is 51 yd from you."))
    end)

    -- I5 (final review): the route list keeps its scroll only for the same zone.
    it("the route list keeps its scroll on a refresh and starts at the top for another zone", function()
      load()
      ns.UI.show({ kind = "zone", mapID = 1439 })
      local box = stepRows()[1].frame:GetParent()
      ns.UI.refresh()
      assert.is_true(box.retained)
      ns.UI.select(4730)
      assert.is_true(box.retained)
      ns.UI.show({ kind = "zone", mapID = 1440 })
      assert.is_falsy(box.retained)
      ns.UI.back()
      assert.is_falsy(box.retained)
    end)

    it("Recalculate route replans", function()
      load()
      ns.UI.show({ kind = "zone", mapID = 1439 })
      local spy = ui.spy(ns.Advisor, "replan")
      fake.click(fake.text("Recalculate route"))
      assert.equal(1, spy.n); assert.equal(1439, spy.calls[1][1])
    end)

    it("combat without a plan shows the after-combat text, and refreshes after the fight", function()
      load()
      fake.combat(true)
      ns.UI.show({ kind = "zone", mapID = 1440 })
      assert.truthy(fake.visible(fake.text("Your route is worked out after combat.")))
      fake.combat(false)
      ns.Events.dispatch("PLAYER_REGEN_ENABLED")
      assert.is_false(fake.text("Your route is worked out after combat."):IsVisible())
      assert.same({}, env.errors)
    end)

    it("the selected quest turned in refreshes cleanly", function()
      load()
      ns.UI.show({ kind = "zone", mapID = 1439 })
      ns.UI.select(4730)
      local s = ui.with("S18")
      s.completed[4730] = true; s.log[4730] = nil
      fake.setState(s)
      assert.truthy(fake.text("You have completed this quest."))
      assert.same({}, env.errors)
    end)
  end)

  describe("last view", function()
    it("restores the last zone view on the first open after login", function()
      load({ chardb = { lastView = { kind = "zone", mapID = 1440 } } })
      ns.UI.open()
      assert.same({ kind = "zone", mapID = 1440 }, { kind = ns.UI.current().kind, mapID = ns.UI.current().mapID })
    end)

    it("restores only on the first open", function()
      load({ chardb = { lastView = { kind = "zone", mapID = 1440 } } })
      ns.UI.open(); ns.UI.close()
      ns.UI.back()
      assert.equal("main", ns.UI.current().kind)
      ns.UI.close(); ns.UI.open()
      assert.equal("main", ns.UI.current().kind)
    end)

    it("a stale dungeon lastView opens main", function()
      load({ chardb = { lastView = { kind = "dungeon", key = "nope" } } })
      ns.UI.open()
      assert.equal("main", ns.UI.current().kind)
    end)

    it("a current dungeon lastView is restored", function()
      load({ state = "S20" })
      local d = ns.Advisor.last.rec.dungeon
      assert.truthy(d)
      ns.chardb.lastView = { kind = "dungeon", key = d.key }
      ns.UI.open()
      assert.equal("dungeon", ns.UI.current().kind)
    end)

    it("show and back store the zone view; main clears it; search leaves it", function()
      load()
      ns.UI.show({ kind = "zone", mapID = 1439 })
      assert.same({ kind = "zone", mapID = 1439 }, ns.chardb.lastView)
      ns.UI.show({ kind = "search", query = "x" })
      assert.same({ kind = "zone", mapID = 1439 }, ns.chardb.lastView)
      ns.UI.back(); ns.UI.back()
      assert.is_nil(ns.chardb.lastView)
    end)

    it("show on a closed book renders only the requested view", function()
      load()
      local mainRenders = ui.spy(ns.UI.Model, "left")   -- the main page's update calls it
      ns.UI.show({ kind = "zone", mapID = 1439 })
      assert.equal(0, mainRenders.n)
      assert.equal("zone", ns.UI.current().kind)
      assert.same({}, env.errors)
    end)
  end)
end)
