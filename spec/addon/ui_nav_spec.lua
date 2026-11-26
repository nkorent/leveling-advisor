local ui = require("spec.helpers.ui")

local PREFIX = "|cffffd100Leveling Advisor:|r "

local function pinsFor(ns, mapID) return ns.MapPins.model(mapID) end

local function questIDs(pin)
  local ids = {}
  for _, q in ipairs(pin.quests) do ids[#ids + 1] = q.id end
  return ids
end

describe("Nav.placeFor", function()
  it("picks giver, turn-in or objective by log state", function()
    local ns = ui.load({ state = "S18" })
    local db, s = ns.Advisor.db, ns.Advisor.last.state
    local p, k = ns.UI.Nav.placeFor(db, 4763, s)
    assert.same({ 1439, 37.4, 40.1, "giver" }, { p.mapID, p.x, p.y, k })
    p, k = ns.UI.Nav.placeFor(db, 4730, s)
    assert.same({ 1439, 37.0, 44.0, "turnin" }, { p.mapID, p.x, p.y, k })
    p, k = ns.UI.Nav.placeFor(db, 966, s)
    assert.same({ 1439, 56.0, 26.0, "objective" }, { p.mapID, p.x, p.y, k })
    assert.is_nil(ns.UI.Nav.placeFor(db, 999999, s))
  end)

  it("an in-progress quest without points falls back to its turn-in", function()
    local ns = ui.load({ state = "S18" })
    local db, s = ns.Advisor.db, ns.Advisor.last.state
    s.log[965] = { complete = false }
    local p, k = ns.UI.Nav.placeFor(db, 965, s)
    assert.same({ 1439, 55.0, 24.9, "turnin" }, { p.mapID, p.x, p.y, k })
  end)
end)

describe("Nav.showQuest", function()
  it("sets the waypoint, a focus pin, closes the book and opens the map", function()
    local ns, _, fake, out = ui.load({ state = "S18" })
    ns.UI.open()
    assert.is_true(ns.UI.Nav.showQuest(4763))
    assert.same({ uiMapID = 1439, x = 0.374, y = 0.401 }, fake.waypoints[1])
    assert.is_true(fake.superTracked)
    assert.same({ 1439 }, fake.openedMaps)
    assert.is_false(ns.UI.isShown())
    assert.equal(PREFIX .. "Waypoint set: The Blackwood Corrupted (Darkshore 37.4, 40.1)", out[#out])
  end)

  it("super-tracks an in-progress quest, with no user waypoint", function()
    local ns, env, fake, out = ui.load({ state = "S18" })
    assert.is_true(ns.UI.Nav.showQuest(966))
    assert.equal(966, fake.superTrackedQuest)
    assert.same({}, fake.waypoints)
    assert.same({ 1439 }, fake.openedMaps)
    assert.equal(PREFIX .. "Tracking The Tower of Althalaxx on the map.", out[#out])
    assert.same({}, env.errors)
  end)

  it("falls back to a waypoint without the quest super-track API", function()
    local ns, env, fake = ui.load({ state = "S18" })
    env.C_SuperTrack.SetSuperTrackedQuestID = nil
    assert.is_true(ns.UI.Nav.showQuest(966))
    assert.same({ uiMapID = 1439, x = 0.56, y = 0.26 }, fake.waypoints[1])
    assert.is_nil(fake.superTrackedQuest)
  end)

  it("says when no position is known", function()
    local ns, _, fake, out = ui.load({ state = "S18", patch = function(d) d.quests[7007][11] = nil end })
    assert.is_false(ns.UI.Nav.showQuest(7007))
    assert.equal(PREFIX .. "No map position known for Broken Record.", out[#out])
    assert.same({}, fake.openedMaps)
    assert.same({}, fake.waypoints)
  end)

  it("in combat the waypoint is set now and the map opens once after the fight", function()
    local ns, _, fake, out = ui.load({ state = "S18" })
    fake.combat(true)
    ns.UI.Nav.showQuest(1010)
    ns.UI.Nav.showQuest(4763)
    assert.equal(2, #fake.waypoints)
    assert.same({}, fake.openedMaps)
    local n = 0
    for _, l in ipairs(out) do if l == PREFIX .. "The map opens after the fight." then n = n + 1 end end
    assert.equal(1, n)
    fake.combat(false)
    ns.Events.dispatch("PLAYER_REGEN_ENABLED")
    ns.Events.dispatch("PLAYER_REGEN_ENABLED")
    assert.same({ 1439 }, fake.openedMaps)
  end)

  it("falls back to WorldMapFrame without OpenWorldMap, and to nothing without either", function()
    local ns, env, fake = ui.load({ state = "S18", worldMap = true, without = { "OpenWorldMap" } })
    ns.UI.Nav.showQuest(4763)
    assert.is_true(env.WorldMapFrame:IsShown())
    assert.equal(1439, env.WorldMapFrame.mapID)

    local ns2, env2, fake2, out2 = ui.load({ state = "S18", without = { "OpenWorldMap" } })
    assert.is_true(ns2.UI.Nav.showQuest(4763))
    assert.same({}, fake2.openedMaps)
    assert.same({}, env2.errors)
    assert.is_nil(fake.superTrackedQuest)
  end)

  it("uses ShowUIPanel for the map when the client has it", function()
    local shown
    local ns, env = ui.load({ state = "S18", worldMap = true, without = { "OpenWorldMap" },
      globals = { ShowUIPanel = function(f) shown = f; f:Show() end } })
    ns.UI.Nav.showQuest(4763)
    assert.equal(env.WorldMapFrame, shown)
    assert.equal(1439, env.WorldMapFrame.mapID)
  end)
end)

describe("focus pin", function()
  it("shows with pinsAll off and only on its own map", function()
    local ns = ui.load({ state = "S18" })
    ns.Settings.set("pinsAll", false)
    ns.UI.Nav.showQuest(1010) -- Ashenvale giver
    local a, d = pinsFor(ns, 1440), pinsFor(ns, 1439)
    assert.equal(1, #a)
    assert.same({ 1010 }, questIDs(a[1]))
    assert.equal("Shown on map", a[1].quests[1].section)
    assert.equal("pickup", a[1].kind)
    assert.equal(0, #d)
  end)

  it("does not duplicate a recommended quest's pin", function()
    local ns = ui.load({ state = "S18" })
    ns.Settings.set("pinsAll", true)
    local before = #pinsFor(ns, 1439)
    ns.UI.Nav.showQuest(4763)
    local pins = pinsFor(ns, 1439)
    assert.equal(before, #pins)
    local count = 0
    for _, p in ipairs(pins) do
      for _, id in ipairs(questIDs(p)) do if id == 4763 then count = count + 1 end end
    end
    assert.equal(1, count)
  end)

  it("count and describe read the model, focus included", function()
    local ns, env = ui.load({ state = "S18", worldMap = true })
    ns.Settings.set("pinsAll", false)
    ns.UI.Nav.showQuest(1010)
    env.WorldMapFrame:SetMapID(1440)
    env.WorldMapFrame:Show()
    assert.equal(1440, ns.MapPins.model(1440)[1].mapID)
    assert.equal(1, ns.MapPins.count())
    assert.truthy(ns.MapPins.describe():find(": 1", 1, true))
  end)

  it("is dropped once its quest is completed, or a pickup is in the log (F26)", function()
    local ns = ui.load({ state = "S18" })
    ns.Settings.set("pinsAll", false)
    ns.UI.Nav.showQuest(1010)
    assert.equal(1, #pinsFor(ns, 1440))
    ns.Advisor.last.state.log[1010] = { complete = false }
    assert.equal(0, #pinsFor(ns, 1440))

    ns.Advisor.last.state.log[1010] = nil
    ns.UI.Nav.showQuest(1010)
    assert.equal(1, #pinsFor(ns, 1440))
    ns.Advisor.last.state.completed[1010] = true
    assert.equal(0, #pinsFor(ns, 1440))
  end)

  it("a turn-in focus stays while its quest is in the log", function()
    local ns = ui.load({ state = "S18" })
    ns.Settings.set("pinsAll", false)
    ns.UI.Nav.showQuest(4730) -- complete in the log
    local pins = pinsFor(ns, 1439)
    assert.equal(1, #pins)
    assert.equal("turnin", pins[1].kind)
  end)
end)

describe("Nav.showPlace", function()
  it("sets a waypoint and focus pin for a bare place", function()
    local ns, _, fake, out = ui.load({ state = "S18" })
    ns.Settings.set("pinsAll", false)
    ns.UI.open()
    assert.is_true(ns.UI.Nav.showPlace({ mapID = 1440, x = 30, y = 40 }, "Somewhere", "turnin"))
    assert.same({ uiMapID = 1440, x = 0.3, y = 0.4 }, fake.waypoints[1])
    assert.same({ 1440 }, fake.openedMaps)
    assert.is_false(ns.UI.isShown())
    assert.equal("turnin", pinsFor(ns, 1440)[1].kind)
    assert.equal(PREFIX .. "Waypoint set: Somewhere (Ashenvale 30.0, 40.0)", out[#out])
  end)
end)

describe("/advisor map", function()
  it("shows the quest, and prints usage for a bad argument", function()
    local ns, _, fake, out = ui.load({ state = "S18" })
    ns.Slash.handle("map 4763")
    assert.same({ 1439 }, fake.openedMaps)
    ns.Slash.handle("map x")
    assert.equal(PREFIX .. "Usage: /advisor map <questID>", out[#out])
    ns.Slash.handle("help")
    local found
    for _, l in ipairs(out) do
      if l == "  /advisor map <questID> — show a quest on the map" then found = true end
    end
    assert.is_true(found)
  end)
end)
