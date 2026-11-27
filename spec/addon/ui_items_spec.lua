local ui = require("spec.helpers.ui")

describe("quest items and rewards", function()
  local ns, env, fake, db, state, Items

  local function load(opts)
    opts = opts or {}
    opts.state = opts.state or "S18"
    ns, env, fake = ui.load(opts)
    db, state, Items = ns.Advisor.db, ns.Advisor.last.state, ns.UI.Items
  end
  local function zero() return 0 end
  local function patch(d)
    d.quests[4763][15] = { provided = { 12346 }, required = { { 12355, 1 } } }
    local r = d.quests[4763][16]
    r.rep = { { "Darnassus", 150 } }
  end
  local function btn() return Items.newButton(fake.newFrame("Frame"), 37) end

  it("model from the database", function()
    load({ patch = patch })
    local m = Items.model(db, db:quest(4763), state, { count = zero })
    assert.same({ { itemID = 12346, note = "given" } }, m.provided)
    assert.same({ { itemID = 12355, count = 1, have = 0, note = "needed" } }, m.required)
    assert.same({ 15204, 15202, 15203 }, { m.choice[1].itemID, m.choice[2].itemID, m.choice[3].itemID })
    assert.equal("You will be able to choose one of these rewards:", m.choiceLabel)
    assert.is_nil(m.fixedLabel)
    assert.same({ "Experience: ~1,700", "Darnassus reputation +150" }, m.lines)
    assert.is_true(m.hasRewards)
  end)

  it("live log rewards win", function()
    load()
    local live = { choice = { { itemID = 7750, count = 1, usable = true } }, fixed = { { itemID = 7751, count = 1 } },
      money = 0, xp = 3300 }
    local m = Items.model(db, db:quest(4763), state, { count = zero, live = live })
    assert.equal(7750, m.choice[1].itemID)
    assert.equal(7751, m.fixed[1].itemID)
    assert.equal("You will also receive:", m.fixedLabel)
    assert.equal("Experience: 3,300", m.lines[1])
  end)

  it("fixed only uses You will receive:, money and spell lines", function()
    load()
    local q = { id = 1, level = 10, xp = 0, rewards = { fixed = { { 15204, 1 } }, money = 12403, spellID = 5061 } }
    local m = Items.model(db, q, state, { count = zero, spellName = function() return "Aquatic Form" end })
    assert.equal("You will receive:", m.fixedLabel)
    assert.is_nil(m.choiceLabel)
    assert.same({ "Money: 1g 24s 3c", "You will learn: Aquatic Form" }, m.lines)
    m = Items.model(db, q, state, { count = zero, spellName = function() return nil end })
    assert.equal("You will learn a spell.", m.lines[2])
  end)

  it("no rewards gives no Rewards section", function()
    load({ patch = function(d) d.quests[7003][17] = 0 end })
    local q = { id = 1, level = 10, xp = 0, rewards = {} }
    assert.is_false(Items.model(db, q, state, { count = zero }).hasRewards)
    local d = ns.UI.QuestDetail.new(fake.newFrame("Frame"))
    d:show(7003)
    assert.is_falsy(fake.visible(fake.text("Rewards")))
  end)

  it("canUse", function()
    local c = Items.canUse
    assert.is_false(c("DRUID", 2, 19))
    assert.is_true(c("DRUID", 4, 2, "INVTYPE_LEGS"))
    assert.is_false(c("DRUID", 4, 4, "INVTYPE_CHEST"))
    assert.is_false(c("DRUID", 4, 6, "INVTYPE_SHIELD"))
    assert.is_true(c("DRUID", 4, 1, "INVTYPE_CLOAK"))
    assert.is_true(c("DRUID", 4, 0, "INVTYPE_HOLDABLE"))
    assert.is_true(c("DRUID", 0, 0))
    assert.is_true(c("MAGE", 2, 15))
    assert.is_false(c("MAGE", 2, 4))
    assert.is_false(c("WARRIOR", 2, 19))
    assert.is_true(c("NOPE", 4, 4, "INVTYPE_CHEST"))
  end)

  it("Review Focus 3: icon at once, name after load, quality border", function()
    load()
    local b = btn(); Items.setItem(b, { itemID = 15204 })
    assert.equal(135473, fake.itemButtonTexture[b])
    assert.are_not.equal("Moonstone Wand", b.laName:GetText())
    fake.loadItems(15204)
    assert.equal("Moonstone Wand", b.laName:GetText())
    assert.same({ b, 2, 15204 }, fake.lastQuality)
  end)

  it("Review Focus 3: a recycled button ignores the late load of its old item", function()
    load()
    local b = btn()
    Items.setItem(b, { itemID = 15204 }); Items.setItem(b, { itemID = 15202 })
    fake.loadItems(15202); fake.loadItems(15204)
    assert.equal("Wildkeeper Leggings", b.laName:GetText())
  end)

  it("red tint for a wand on a druid; live usable wins", function()
    load({ state = ui.with("S18", { classFile = "DRUID" }) })
    local b = btn(); Items.setItem(b, { itemID = 15204 })
    assert.same({ 1, 0.1, 0.1 }, fake.itemButtonVertex[b])
    local b2 = btn(); Items.setItem(b2, { itemID = 15204, usable = true })
    assert.is_nil(fake.itemButtonVertex[b2])
    local b3 = btn(); Items.setItem(b3, { itemID = 15202 })
    assert.is_nil(fake.itemButtonVertex[b3])
  end)

  it("a recycled button loses the red tint of the item it showed before", function()
    load({ state = ui.with("S18", { classFile = "DRUID" }) })
    local b = btn()
    Items.setItem(b, { itemID = 15204 })   -- wand: a druid cannot use it
    assert.same({ 1, 0.1, 0.1 }, fake.itemButtonVertex[b])
    Items.setItem(b, { itemID = 15202 })   -- leggings: usable
    assert.same({ 1, 1, 1 }, fake.itemButtonVertex[b])
    Items.setItem(b, { itemID = 15204, usable = true })
    assert.same({ 1, 1, 1 }, fake.itemButtonVertex[b])
    Items.setItem(b, { itemID = 15204 })
    assert.same({ 1, 0.1, 0.1 }, fake.itemButtonVertex[b])
  end)

  it("tooltip with the advisor note", function()
    load()
    local b = btn(); Items.setItem(b, { itemID = 12355, count = 1, have = 0, note = "needed" }, "The Blackwood Corrupted")
    fake.enter(b)
    assert.equal(12355, fake.tooltip.itemID)
    assert.is_true(fake.tooltip.shown)
    local last = fake.tooltip.lines[#fake.tooltip.lines]
    assert.equal("Leveling Advisor: needed for The Blackwood Corrupted", last[1])
  end)

  it("Shift/Ctrl click goes through HandleModifiedItemClick; no link says so", function()
    load()
    env.IsShiftKeyDown = function() return true end
    local b = btn(); Items.setItem(b, { itemID = 15204 })
    fake.click(b)
    assert.equal(0, #fake.itemClicks)
    assert.truthy(fake.out[#fake.out]:find("No link for this item yet", 1, true))
    fake.loadItems(15204)
    fake.click(b)
    assert.equal(1, #fake.itemClicks)
    assert.truthy(fake.itemClicks[1]:find("item:15204", 1, true))
    assert.same({}, env.errors)
  end)

  it("a plain click on a detail item button does nothing", function()
    load()
    local b = btn(); Items.setItem(b, { itemID = 15204 })
    local n = #fake.out
    fake.click(b)
    assert.equal(0, #fake.itemClicks)
    assert.equal(n, #fake.out)
    fake.loadItems(15204)
    fake.click(b)
    assert.equal(0, #fake.itemClicks)
  end)

  it("a button reused for an uncached item loses the old quality border", function()
    load()
    fake.loadItems(15204)
    local b = btn()
    Items.setItem(b, { itemID = 15204 })
    assert.same({ b, 2, 15204 }, fake.lastQuality)
    Items.setItem(b, { itemID = 15202 })
    assert.equal(b, fake.lastQuality[1])
    assert.is_nil(fake.lastQuality[2])
  end)

  it("a failing Item:CreateFromItemID does not break setItem", function()
    load()
    env.Item = { CreateFromItemID = function() error("boom") end }
    local b = btn()
    Items.setItem(b, { itemID = 15204 })
    assert.equal(135473, fake.itemButtonTexture[b])
    assert.same({}, env.errors)
  end)

  it("cosmetic armor is never unusable", function()
    load()
    assert.is_true(Items.canUse("MAGE", 4, 5, "INVTYPE_CHEST"))
    assert.is_true(Items.canUse("WARRIOR", 4, 5, "INVTYPE_HEAD"))
  end)

  it("falls back to the global item APIs without C_Item", function()
    local g = {
      GetItemInfoInstant = function(id) return id, "t", "s", "INVTYPE_LEGS", 777, 4, 2 end,
      GetItemInfo = function(id) return "Global Item", "|Hitem:" .. id .. "|h[Global Item]|h", 2 end,
      GetItemCount = function() return 4 end,
    }
    load({ without = { "C_Item" }, globals = g })
    env.IsShiftKeyDown = function() return true end
    local b = btn(); Items.setItem(b, { itemID = 15204 })
    assert.equal(777, fake.itemButtonTexture[b])
    assert.equal("Global Item", b.laName:GetText())
    fake.click(b)
    assert.truthy(fake.itemClicks[1]:find("item:15204", 1, true))
    assert.equal(4, Items.realEnv(1).count(15204))
    assert.same({}, env.errors)
  end)

  it("required count shows 0/1 on the Count text, never through SetItemButtonCount", function()
    load()
    local b = btn(); Items.setItem(b, { itemID = 12355, count = 1, have = 0 })
    assert.equal("0/1", b.Count:GetText())
    assert.is_nil(fake.itemButtonCount[b])
    local b2 = btn(); Items.setItem(b2, { itemID = 15204, count = 3 })
    assert.equal(3, fake.itemButtonCount[b2])
  end)

  it("the detail page shows provided, required and reward buttons", function()
    load({ patch = patch })
    local d = ns.UI.QuestDetail.new(fake.newFrame("Frame"))
    d:show(4763)
    assert.is_truthy(fake.visible(fake.text("Provided item")))
    assert.is_truthy(fake.visible(fake.text("Required item")))
    assert.is_truthy(fake.visible(fake.text("Rewards")))
    assert.is_truthy(fake.visible(fake.text("You will be able to choose one of these rewards:")))
    assert.is_truthy(fake.visible(fake.text("Darnassus reputation +150")))
    assert.is_nil(fake.text("Provided items"))
  end)

  it("realEnv reads the log by questID", function()
    load()
    assert.is_nil(Items.liveRewards(4763))
    fake.setLog(4763, { choices = { { "Wand", 1, 1, 2, true, 15204 } }, rewards = {}, money = 0, xp = 3300 })
    local live = Items.liveRewards(4763)
    assert.equal(15204, live.choice[1].itemID)
    assert.equal(3300, live.xp)
    assert.same({}, live.fixed)
  end)

  it("rows show up to three reward icons", function()
    load()
    ns.UI.open()
    local function minis(id)
      local rf = fake.rowFrame(id)
      return fake.findAll(function(w) return w.laMini and w.laItemID and w:IsVisible() and w.parent and w.parent.parent == rf end)
    end
    local f = fake.rowFrame(4763)
    assert.truthy(f)
    local ids = {}
    for _, w in ipairs(minis(4763)) do ids[#ids + 1] = w.laItemID end
    assert.same({ 15204, 15202, 15203 }, ids)
    assert.equal(0, #minis(7003))
  end)

  -- I6 (final review): the ItemButton art is drawn for 37 px, so the mini
  -- buttons are 37 px buttons scaled down (slot frame and border shrink too).
  it("mini reward buttons are 37 px item buttons scaled to 22 px", function()
    load()
    local b = Items.newButton(fake.newFrame("Frame"), 22, true)
    assert.same({ 37, 37 }, { b.width, b.height })
    assert.near(22 / 37, b:GetScale(), 1e-9)
    ns.UI.open()
    local f = fake.rowFrame(4763)
    local mini = fake.find(function(w) return w.laMini and w.laItemID == 15203 and w.parent and w.parent.parent == f end)
    -- the anchor offset is in the button's own (scaled) units: 26 + 8 px from the row's edge
    local _, _, _, x = mini:GetPoint(1)
    assert.near(-(26 + 8) * 37 / 22, x, 1e-6)
  end)
end)
