local ui = require("spec.helpers.ui")

describe("dungeon page", function()
  local ns, env, fake

  local function load(state)
    ns, env, fake = ui.load({ state = state or "S20" })
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

  it("dungeon model for S20", function()
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
    local s = ui.with("S20", { log = { [id] = { complete = false } } })
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
    local m = model(ui.with("S20", { log = log }))
    assert.equal("4 of 4 done", m.progress)
    assert.is_true(m.steps[5].current)
  end)

  it("renders info, quest rows and Show Entrance on Map", function()
    load()
    ns.UI.show({ kind = "dungeon", key = "BFD" })
    assert.truthy(fake.visible(fake.text("Blackfathom Deeps")))
    assert.truthy(fake.visible(fake.text("Best at 21 — three of its quests start on your way")))
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
end)
