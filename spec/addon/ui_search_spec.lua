local ui = require("spec.helpers.ui")

describe("quest search", function()
  local ns, env, fake, db, state

  before_each(function()
    ns, env, fake = ui.load({ state = "S18" })
    db, state = ns.Advisor.db, ns.Advisor.last.state
  end)

  it("finds by name, prefix first, available before done", function()
    local r = ns.UI.Search.find(db, "tower", state)
    assert.same({ 966, 965, 967 }, { r[1].questID, r[2].questID, r[3].questID })
  end)

  it("an ID query puts that quest first", function()
    local r = ns.UI.Search.find(db, "4763", state)
    assert.equal(4763, r[1].questID)
  end)

  it("odd input", function()
    for _, q in ipairs({ "%", "(", "[", "%a", "zzzz" }) do
      local r, n = ns.UI.Search.find(db, q, state)
      assert.same({}, r)
      assert.equal(0, n)
    end
    local _, _, hint = ns.UI.Search.find(db, "a", state)
    assert.equal("Type at least 2 letters.", hint)
    _, _, hint = ns.UI.Search.find(db, "", state)
    assert.equal("Type at least 2 letters.", hint)
  end)

  it("caps at 50 and reports the total", function()
    local real = db.quest
    local list, fakeQ = {}, {}
    for i = 1, 120 do
      local id = 900000 + i
      list[i] = id
      fakeQ[id] = { id = id, name = "Wolf Hunt " .. i, level = 18, zone = 1439, giver = {} }
    end
    db.questIDs = function() return list end
    db.quest = function(self, id) return fakeQ[id] or real(self, id) end
    local r, n = ns.UI.Search.find(db, "wolf", state)
    assert.equal(50, #r)
    assert.equal(120, n)
    assert.equal('Showing 50 of 120 quests for "wolf"', ns.UI.Search.summary("wolf", 50, 120))
  end)

  it("summary texts", function()
    local S = ns.UI.Search
    assert.equal('No quests match "%".', S.summary("%", 0, 0))
    assert.equal('1 quest for "tower"', S.summary("tower", 1, 1))
    assert.equal('3 quests for "tower"', S.summary("tower", 3, 3))
  end)

  it("typing opens the search view; Enter selects; clearing goes back", function()
    ns.UI.open()
    local box = fake.named("LevelingAdvisorSearchBox")
    fake.type(box, "black")
    assert.same({}, env.errors)   -- the search view builds on the strict widget fake
    assert.equal("search", ns.UI.current().kind)
    assert.equal("black", ns.UI.current().query)
    fake.type(box, "blackw")
    ns.UI.back()
    assert.equal("main", ns.UI.current().kind)
    fake.type(box, "black")
    box:GetScript("OnEnterPressed")(box)
    assert.equal(4763, ns.UI.current().questID)
    assert.truthy(fake.visible(fake.text("The Blackwood Corrupted")))
    local prompt = fake.text("Pick a quest to see its details.")
    assert.falsy(prompt and fake.visible(prompt))
    fake.type(box, "")
    assert.equal("main", ns.UI.current().kind)
    assert.same({}, env.errors)
  end)

  it("search leaves lastView unchanged", function()
    ns.chardb.lastView = { kind = "zone", mapID = 1439 }
    ns.UI.open()
    fake.type(fake.named("LevelingAdvisorSearchBox"), "black")
    assert.same({ kind = "zone", mapID = 1439 }, ns.chardb.lastView)
  end)

  it("result rows show zone and availability", function()
    ns.UI.open()
    fake.type(fake.named("LevelingAdvisorSearchBox"), "6382")
    assert.truthy(fake.visible(fake.text("Ashenvale · Horde only")))
  end)

  it("prompt when nothing is selected", function()
    ns.UI.open()
    fake.type(fake.named("LevelingAdvisorSearchBox"), "tower")
    assert.truthy(fake.visible(fake.text("Pick a quest to see its details.")))
  end)

  it("right-click on a result opens the menu", function()
    ns.UI.open()
    fake.type(fake.named("LevelingAdvisorSearchBox"), "black")
    local f = fake.rowFrame(4763)
    assert.truthy(f)
    fake.click(f, "RightButton")
    assert.truthy(fake.menu)
    assert.equal("The Blackwood Corrupted", fake.menu.title)
    assert.equal(f, fake.menu.owner)
  end)

  it("keeps the template's OnTextChanged handler", function()
    ns.UI.open()
    local box = fake.named("LevelingAdvisorSearchBox")
    fake.type(box, "black")
    assert.equal(1, box.templateRan)
    assert.equal("search", ns.UI.current().kind)
  end)

  it("the clear button (no user input) goes back and the old text is not kept", function()
    ns.UI.open()
    local box = fake.named("LevelingAdvisorSearchBox")
    fake.type(box, "black")
    box:SetText("")   -- the clear button: SetText("") fires OnTextChanged(self, false)
    assert.equal("main", ns.UI.current().kind)
    assert.equal("", box:GetText())
  end)

  it("Back from search returns to the page the search started on (SetText re-entrancy)", function()
    -- UI.back clears the box after popping the view: SetText("") fires OnTextChanged(false),
    -- which must not run UI.back a second time
    ns.UI.open()
    ns.UI.show({ kind = "zone", mapID = 1439 })
    local box = fake.named("LevelingAdvisorSearchBox")
    fake.type(box, "black")
    assert.equal("search", ns.UI.current().kind)
    ns.UI.back()
    assert.same({ kind = "zone", mapID = 1439 }, { kind = ns.UI.current().kind, mapID = ns.UI.current().mapID })
    assert.equal("", box:GetText())
    ns.UI.back()
    assert.equal("main", ns.UI.current().kind)
  end)

  -- I5 (final review): a new query starts at the top; a refresh keeps the scroll.
  it("a new query starts the list at the top; a refresh of the same query keeps it", function()
    ns.UI.open()
    local box = fake.named("LevelingAdvisorSearchBox")
    fake.type(box, "tower")
    local list = fake.rowFrame(967):GetParent()
    assert.is_falsy(list.retained)
    ns.UI.refresh()
    assert.is_true(list.retained)
    ns.UI.select(967)
    assert.is_true(list.retained)
    fake.type(box, "towe")
    assert.is_falsy(list.retained)
  end)

  it("Back from search clears the box text", function()
    ns.UI.open()
    local box = fake.named("LevelingAdvisorSearchBox")
    fake.type(box, "black")
    ns.UI.back()
    assert.equal("", box:GetText())
  end)
end)
