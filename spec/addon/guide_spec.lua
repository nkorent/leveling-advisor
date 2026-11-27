-- The guide (0.3.0): a waypoint to the next step of the top zone's route, set
-- quietly on each advisor result when the target changes. It pauses when the
-- player removes or replaces its waypoint, and "Continue with waypoint" resumes it.
local ui = require("spec.helpers.ui")

-- The fixture's Darkshore (1439) plan for S18: step 1 picks up The Blackwood
-- Corrupted (4763) at 37.4, 40.1; step 2 picks up Either Way (7003) at 40, 40;
-- step 3 is 4763's objectives at 52.5, 33.4.
local LOG18 = { [966] = { complete = false }, [4730] = { complete = true } }

local function withLog(extra, completed)
  local log = {}
  for k, v in pairs(LOG18) do log[k] = v end
  for k, v in pairs(extra or {}) do log[k] = v end
  local done = { [4762] = true, [965] = true }
  for k, v in pairs(completed or {}) do done[k] = v end
  return ui.with("S18", { log = log, completed = done })
end

-- 4763 picked up: step 1 is done, step 2 is next.
local function took4763() return withLog({ [4763] = { complete = false } }) end
-- ... and Either Way done: step 3 is next.
local function did7003() return withLog({ [4763] = { complete = false } }, { [7003] = true }) end

local function vector(x, y)
  local v = { x = x, y = y }
  function v:GetXY() return self.x, self.y end
  return v
end

local function at(wp, mapID, x, y)
  assert.is_table(wp)
  assert.equal(mapID, wp.uiMapID)
  assert.near(x, wp.x, 1e-9)
  assert.near(y, wp.y, 1e-9)
end

local function said(out, text)
  for _, line in ipairs(out) do
    if line:find(text, 1, true) then return true end
  end
  return false
end

describe("Guide", function()
  local ns, env, fake, out, Guide

  local function load(opts)
    opts = opts or {}
    if opts.state == nil then opts.state = "S18" end
    ns, env, fake, out = ui.load(opts)
    Guide = ns.UI.Guide
  end

  describe("target", function()
    it("is the current step of the top zone's route, with its first open quest", function()
      load()
      assert.same({ mapID = 1439, x = 37.4, y = 40.1, questID = 4763, kind = "pickup",
        label = "The Blackwood Corrupted" }, Guide.target())
    end)

    it("follows the route", function()
      load()
      fake.setState(took4763())
      assert.same({ mapID = 1439, x = 40, y = 40, questID = 7003, kind = "pickup", label = "Either Way" },
        Guide.target())
      fake.setState(did7003())
      local t = Guide.target()
      assert.same({ 1439, 52.5, 33.4, 4763, "objective" }, { t.mapID, t.x, t.y, t.questID, t.kind })
    end)

    it("is nil without a result or without a recommended zone", function()
      load({ state = false })
      assert.is_nil(Guide.target())
      fake.setState("H20")
      assert.same({}, ns.Advisor.last.rec.zones)
      assert.is_nil(Guide.target())
      assert.equal(0, #fake.waypoints)
      assert.same({}, env.errors)
    end)
  end)

  describe("on each advisor result", function()
    it("sets a waypoint on the first result, without a chat line", function()
      load()
      assert.equal(1, #fake.waypoints)
      at(fake.waypoints[1], 1439, 0.374, 0.401)
      assert.is_true(fake.superTracked)
      assert.is_true(ns.MapPins.isOurWaypoint())
      assert.is_false(said(out, "Waypoint set"))
      assert.is_true(Guide.enabled())
      assert.is_false(Guide.paused())
      assert.same({}, env.errors)
    end)

    it("does not set it again for the same target", function()
      load()
      ns.Advisor.compute()
      ns.Advisor.compute()
      assert.equal(1, #fake.waypoints)
    end)

    it("sets a new one when the step changes", function()
      load()
      fake.setState(took4763())
      assert.equal(2, #fake.waypoints)
      at(fake.waypoints[2], 1439, 0.40, 0.40)
      fake.setState(did7003())
      assert.equal(3, #fake.waypoints)
      at(fake.waypoints[3], 1439, 0.525, 0.334)
      assert.is_false(said(out, "Waypoint set"))
    end)

    it("sets nothing when it is off", function()
      load({ chardb = { settings = { guide = false } } })
      assert.is_false(Guide.enabled())
      fake.setState(took4763())
      assert.equal(0, #fake.waypoints)
    end)

    it("off stops it and removes its own waypoint", function()
      load()
      assert.is_true(ns.MapPins.isOurWaypoint())
      Guide.setEnabled(false)
      assert.equal(1, fake.cleared)
      assert.is_nil(fake.userWaypoint)
      ns.Events.dispatch("USER_WAYPOINT_UPDATED") -- the game reports the clear
      fake.setState(took4763())
      assert.equal(1, #fake.waypoints)
      assert.is_nil(fake.userWaypoint)
      assert.is_false(Guide.paused())
      assert.same({}, env.errors)
    end)

    it("never replaces a waypoint the player placed before it set one", function()
      load({ state = false })
      fake.setUserWaypoint(1439, 0.5, 0.5)
      fake.setState("S18")
      assert.equal(0, #fake.waypoints)
      assert.is_true(Guide.paused())
      assert.equal(0.5, fake.userWaypoint.position.x)
    end)

    it("after a reload its own waypoint (the saved spot) is still its own", function()
      load({ state = false, chardb = { guideState = { spot = { mapID = 1439, x = 37.4, y = 40.1 } } } })
      fake.setUserWaypoint(1439, 0.374, 0.401)
      fake.setState("S18")
      assert.is_false(Guide.paused())
      assert.equal(1, #fake.waypoints)
      assert.is_true(ns.MapPins.isOurWaypoint())
    end)
  end)

  describe("the player's waypoint", function()
    it("pauses when the player removes the guide's waypoint", function()
      load()
      fake.setUserWaypoint(nil)
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      assert.is_true(Guide.paused())
      fake.setState(took4763())
      assert.equal(1, #fake.waypoints)
      assert.is_nil(fake.userWaypoint)
    end)

    it("pauses when the player places a waypoint of their own", function()
      load()
      fake.setUserWaypoint(1439, 0.5, 0.5)
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      assert.is_true(Guide.paused())
      fake.setState(took4763())
      assert.equal(1, #fake.waypoints)
      assert.equal(0.5, fake.userWaypoint.position.x)
    end)

    it("pauses for a Show on Map waypoint too (the player chose it)", function()
      load()
      ns.MapPins.setWaypoint({ mapID = 1440, x = 10, y = 10, quests = { { name = "Elsewhere" } } })
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      assert.is_true(Guide.paused())
      fake.setState(took4763())
      at(fake.waypoints[#fake.waypoints], 1440, 0.1, 0.1)
    end)

    it("does not pause for its own waypoint", function()
      load()
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      fake.setState(took4763())
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      assert.is_false(Guide.paused())
    end)

    it("does not pause when it has set nothing", function()
      load({ state = "H20" })
      fake.setUserWaypoint(1439, 0.5, 0.5)
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      assert.is_false(Guide.paused())
    end)

    it("a login-time update with no waypoint restored does not pause it (it set none this session)", function()
      load({ state = false, chardb = { guideState = { spot = { mapID = 1439, x = 37.4, y = 40.1 } } } })
      assert.is_nil(fake.userWaypoint)
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      assert.is_false(Guide.paused())
      fake.setState("S18")
      assert.equal(1, #fake.waypoints)
      at(fake.waypoints[1], 1439, 0.374, 0.401)
      -- from now on a removal pauses it
      fake.setUserWaypoint(nil)
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      assert.is_true(Guide.paused())
    end)

    it("a waypoint the game clears on arrival does not pause it", function()
      load()
      env.C_Map.GetPlayerMapPosition = function(mapID, unit)
        assert.equal("player", unit)
        if mapID == 1439 then return vector(0.375, 0.402) end
      end
      fake.setUserWaypoint(nil)
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      assert.is_false(Guide.paused())
      fake.setState(took4763())
      assert.equal(2, #fake.waypoints)
      at(fake.waypoints[2], 1439, 0.40, 0.40)
    end)

    it("a removal far from the waypoint is the player's: it pauses", function()
      load()
      env.C_Map.GetPlayerMapPosition = function() return vector(0.6, 0.6) end
      fake.setUserWaypoint(nil)
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      assert.is_true(Guide.paused())
    end)

    it("says once in chat that it paused, and how to resume", function()
      load()
      local line = "|cffffd100Leveling Advisor:|r guide paused — use Continue with waypoint to resume."
      local function count()
        local n = 0
        for _, l in ipairs(out) do if l == line then n = n + 1 end end
        return n
      end
      assert.equal(0, count())
      ns.MapPins.setWaypoint({ mapID = 1440, x = 10, y = 10, quests = { { name = "Elsewhere" } } })
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      assert.equal(1, count())
      fake.setUserWaypoint(nil)
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      fake.setState(took4763())
      assert.equal(1, count())
      Guide.continue()
      fake.setUserWaypoint(nil)
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      assert.equal(2, count())
      -- a pause kept from an earlier session is not a new one
      local saved = env.LevelingAdvisorCharDB
      load({ chardb = saved })
      assert.is_true(Guide.paused())
      assert.is_false(said(out, "guide paused"))
    end)

    it("the pause is kept per character", function()
      load()
      fake.setUserWaypoint(nil)
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      assert.is_true(env.LevelingAdvisorCharDB.guideState.paused)
      local saved = env.LevelingAdvisorCharDB
      load({ chardb = saved })
      assert.is_true(Guide.paused())
      assert.equal(0, #fake.waypoints)
    end)
  end)

  describe("continue", function()
    it("resumes and sets the current target at once", function()
      load()
      fake.setUserWaypoint(nil)
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      assert.equal("set", Guide.continue())
      assert.is_false(Guide.paused())
      assert.equal(2, #fake.waypoints)
      at(fake.waypoints[2], 1439, 0.374, 0.401)
      fake.setState(took4763())
      assert.equal(3, #fake.waypoints)
    end)

    it("replaces the player's own waypoint: they asked for it", function()
      load()
      fake.setUserWaypoint(1439, 0.5, 0.5)
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      Guide.continue()
      at(fake.waypoints[#fake.waypoints], 1439, 0.374, 0.401)
      assert.is_true(ns.MapPins.isOurWaypoint())
    end)

    it("waits for the end of combat", function()
      load()
      fake.setUserWaypoint(nil)
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      fake.combat(true)
      assert.equal("combat", Guide.continue())
      assert.equal(1, #fake.waypoints)
      fake.combat(false)
      ns.Events.dispatch("PLAYER_REGEN_ENABLED")
      assert.equal(2, #fake.waypoints)
      assert.is_false(Guide.paused())
    end)

    it("does nothing while the guide is off", function()
      load()
      Guide.setEnabled(false)
      assert.equal("off", Guide.continue())
      assert.equal(1, #fake.waypoints)
    end)

    it("says when there is no next step", function()
      load({ state = "H20" })
      assert.equal("none", Guide.continue())
    end)
  end)

  describe("combat", function()
    it("defers the update to the end of combat, then sets the latest target once", function()
      load()
      fake.combat(true)
      fake.setState(took4763())
      fake.setState(did7003())
      assert.equal(1, #fake.waypoints)
      fake.combat(false)
      ns.Events.dispatch("PLAYER_REGEN_ENABLED")
      assert.equal(2, #fake.waypoints)
      at(fake.waypoints[2], 1439, 0.525, 0.334)
      ns.Events.dispatch("PLAYER_REGEN_ENABLED")
      ns.Advisor.compute()
      assert.equal(2, #fake.waypoints)
    end)

    it("a removal during the fight still wins over the deferred update", function()
      load()
      fake.combat(true)
      fake.setState(took4763())
      fake.setUserWaypoint(nil)
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      fake.combat(false)
      ns.Events.dispatch("PLAYER_REGEN_ENABLED")
      assert.equal(1, #fake.waypoints)
      assert.is_true(Guide.paused())
    end)
  end)

  describe("on and off", function()
    it("is kept per character, on by default", function()
      load()
      assert.is_true(ns.Settings.get("guide"))
      Guide.setEnabled(false)
      assert.is_false(env.LevelingAdvisorCharDB.settings.guide)
      assert.is_nil(env.LevelingAdvisorDB.settings.guide)
      assert.is_false(ns.Settings.get("guide"))
    end)

    it("turning it back on resumes and sets the current target", function()
      load()
      fake.setUserWaypoint(nil)
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      Guide.setEnabled(false)
      fake.setState(took4763())
      Guide.setEnabled(true)
      assert.is_false(Guide.paused())
      assert.equal(2, #fake.waypoints)
      at(fake.waypoints[2], 1439, 0.40, 0.40)
    end)

    it("the settings checkbox drives it", function()
      load()
      ns.Settings.set("guide", false)
      assert.is_false(Guide.enabled())
      fake.setState(took4763())
      assert.equal(1, #fake.waypoints)
    end)

    it("onChange listeners hear on/off, pause/resume and a new waypoint (protected)", function()
      load()
      local seen = {}
      Guide.onChange(function() error("boom") end)
      Guide.onChange(function(reason) seen[#seen + 1] = reason end)
      fake.setState(took4763())
      fake.setUserWaypoint(nil)
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      Guide.continue()
      Guide.setEnabled(false)
      assert.same({ "target", "paused", "paused", "target", "enabled" }, seen)
      assert.equal(5, #env.errors)
      assert.matches("boom", env.errors[1])
    end)
  end)

  describe("off and the waypoint", function()
    local SHARING = "WaypointLocationPinTemplate"
    local function mapLoad(opts)
      opts = opts or {}
      opts.worldMap, opts.waypointPin = true, true
      load(opts)
      env.WorldMapFrame:SetMapID(1439)
      env.WorldMapFrame:Show()
    end
    local function sharingPin()
      for _, pin in ipairs(env.WorldMapFrame.pins) do
        if pin.pinTemplate == SHARING then return pin end
      end
    end

    it("off with its own waypoint: cleared, and nothing of ours is left", function()
      mapLoad()
      assert.is_false(sharingPin():IsShown())
      Guide.setEnabled(false)
      assert.equal(1, fake.cleared)
      assert.is_nil(fake.userWaypoint)
      assert.is_false(ns.MapPins.isOurWaypoint())
      assert.same({}, env.errors)
    end)

    it("off while another waypoint is current: it stays, and shows the game's pin", function()
      mapLoad()
      fake.setUserWaypoint(1439, 0.5, 0.5)
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      Guide.setEnabled(false)
      assert.is_nil(fake.cleared)
      assert.equal(0.5, fake.userWaypoint.position.x)
      -- a Show on Map waypoint (ours, its pin hidden) stays too, and gets its pin back
      Guide.setEnabled(true)
      ns.MapPins.setWaypoint({ mapID = 1439, x = 60, y = 60, quests = { { name = "Elsewhere" } } })
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      assert.is_true(Guide.paused())
      assert.is_false(sharingPin():IsShown())
      Guide.setEnabled(false)
      assert.is_nil(fake.cleared)
      at(fake.waypoints[#fake.waypoints], 1439, 0.6, 0.6)
      assert.equal(0.6, fake.userWaypoint.position.x)
      assert.is_false(ns.MapPins.isOurWaypoint())
      assert.is_true(sharingPin():IsShown())
      assert.same({}, env.errors)
    end)

    it("pause keeps the waypoint as it is", function()
      mapLoad()
      fake.setUserWaypoint(1439, 0.5, 0.5)
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      assert.is_true(Guide.paused())
      assert.is_nil(fake.cleared)
      assert.equal(0.5, fake.userWaypoint.position.x)
    end)

    it("without C_Map.ClearUserWaypoint: no error; its waypoint stays and shows the game's pin", function()
      mapLoad()
      env.C_Map.ClearUserWaypoint = nil
      assert.is_false(sharingPin():IsShown())
      Guide.setEnabled(false)
      assert.same({}, env.errors)
      at(fake.waypoints[1], 1439, 0.374, 0.401)
      assert.equal(0.374, fake.userWaypoint.position.x)
      assert.is_false(ns.MapPins.isOurWaypoint())
      assert.is_true(sharingPin():IsShown())
    end)

    it("the slash, the settings checkbox, the minimap menu and the book's toggle all clear it", function()
      load()
      ns.Slash.handle("guide off")
      assert.equal(1, fake.cleared)
      Guide.setEnabled(true)
      ns.Settings.set("guide", false) -- the settings checkbox
      assert.equal(2, fake.cleared)
      Guide.setEnabled(true)
      ns.UI.Menu.openGuide(nil)
      for _, b in ipairs(fake.menu.buttons) do
        if b.label == "Guide: On" then b.fn() end
      end
      assert.equal(3, fake.cleared)
      Guide.setEnabled(true)
      ns.UI.open()
      fake.click(fake.find(function(w) return w.kind == "Button" and w.text == "Guide: On" end), "LeftButton")
      assert.is_false(Guide.enabled())
      assert.equal(4, fake.cleared)
      assert.is_nil(fake.userWaypoint)
      assert.same({}, env.errors)
    end)
  end)

  describe("results while the book is closed", function()
    local function questLog(inLog, complete)
      env.C_QuestLog = {
        GetLogIndexForQuestID = function(id) return inLog[id] end,
        IsComplete = function(id) return complete[id] or false end,
        IsQuestFlaggedCompleted = function() return false end,
      }
    end

    it("asks for one when the target's quest is picked up, and sets the next step", function()
      load()
      fake.flush()
      local n = ns.Advisor.computes
      questLog({ [4763] = 5 }, {})
      ns.Adapter.snapshot = function() return took4763() end
      ns.Events.dispatch("QUEST_LOG_UPDATE")
      fake.flush()
      assert.equal(n + 1, ns.Advisor.computes)
      assert.equal(2, #fake.waypoints)
      at(fake.waypoints[2], 1439, 0.40, 0.40)
    end)

    it("asks for one when the target's objectives are complete", function()
      load()
      fake.setState(did7003())
      assert.equal("objective", Guide.target().kind)
      fake.flush()
      local n = ns.Advisor.computes
      questLog({ [4763] = 5 }, { [4763] = true })
      ns.Events.dispatch("QUEST_LOG_UPDATE")
      fake.flush()
      assert.equal(n + 1, ns.Advisor.computes)
    end)

    it("asks for nothing while the target is not done, paused or off", function()
      load()
      fake.flush()
      local n = ns.Advisor.computes
      questLog({}, {})
      ns.Events.dispatch("QUEST_LOG_UPDATE")
      fake.flush()
      assert.equal(n, ns.Advisor.computes)
      questLog({ [4763] = 5 }, {})
      Guide.setEnabled(false)
      fake.flush()
      n = ns.Advisor.computes
      ns.Events.dispatch("QUEST_LOG_UPDATE")
      fake.flush()
      assert.equal(n, ns.Advisor.computes)
    end)

    it("asks at most twice for the same target", function()
      load()
      fake.flush()
      local n = ns.Advisor.computes
      questLog({ [4763] = 5 }, {}) -- the result never agrees: no loop
      for _ = 1, 5 do
        ns.Events.dispatch("QUEST_LOG_UPDATE")
        fake.flush()
      end
      assert.equal(n + 2, ns.Advisor.computes)
    end)

    it("asks for one on a level up", function()
      load()
      fake.flush()
      local n = ns.Advisor.computes
      ns.Events.dispatch("PLAYER_LEVEL_UP", 19)
      fake.flush()
      assert.equal(n + 1, ns.Advisor.computes)
    end)
  end)

  describe("without client APIs", function()
    it("no C_Map: no error and no chat line", function()
      load({ without = { "C_Map" } })
      assert.equal(1439, Guide.target().mapID)
      fake.setState(took4763())
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      Guide.continue()
      ns.Events.dispatch("QUEST_LOG_UPDATE")
      ns.Slash.handle("guide")
      ns.Slash.handle("debug")
      assert.same({}, env.errors)
      assert.is_false(said(out, "Waypoints are not available"))
      assert.is_false(Guide.paused())
    end)

    it("no C_SuperTrack, UiMapPoint or C_QuestLog: no error", function()
      load({ without = { "C_SuperTrack", "UiMapPoint", "C_QuestLog" } })
      fake.setState(took4763())
      ns.Events.dispatch("QUEST_LOG_UPDATE")
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      Guide.continue()
      assert.same({}, env.errors)
    end)

    it("a waypoint the client silently ignores is a failed set: no pause later, it tries again", function()
      load({ state = false })
      local real = env.C_Map.SetUserWaypoint
      env.C_Map.SetUserWaypoint = function(p) fake.waypoints[#fake.waypoints + 1] = p end
      fake.setState("S18")
      assert.equal(1, #fake.waypoints)
      assert.is_nil(fake.userWaypoint)
      assert.is_nil((env.LevelingAdvisorCharDB.guideState or {}).spot)
      assert.matches("the last waypoint did not take", Guide.debugLine(), 1, true)
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      assert.is_false(Guide.paused())
      env.C_Map.SetUserWaypoint = real
      ns.Advisor.compute()
      assert.equal(2, #fake.waypoints)
      assert.is_true(ns.MapPins.isWaypointAt({ mapID = 1439, x = 37.4, y = 40.1 }))
      assert.is_nil(Guide.debugLine():find("did not take", 1, true))
      assert.same({}, env.errors)
    end)

    it("a client that cannot read the user waypoint never pauses it", function()
      load()
      env.C_Map.GetUserWaypoint = nil
      ns.Events.dispatch("USER_WAYPOINT_UPDATED")
      assert.is_false(Guide.paused())
      fake.setState(took4763())
      assert.equal(2, #fake.waypoints)
    end)
  end)
end)

describe("MapPins waypoint helpers", function()
  local ENTRY = { mapID = 1439, x = 37.4, y = 40.1, quests = { { id = 4763, name = "The Blackwood Corrupted" } } }

  it("setWaypoint with quiet prints nothing", function()
    local ns, _, fake, out = ui.load({ state = "S18", chardb = { settings = { guide = false } } })
    local n = #out
    assert.is_true(ns.MapPins.setWaypoint(ENTRY, { quiet = true }))
    assert.equal(n, #out)
    assert.equal(1, #fake.waypoints)
    assert.is_true(ns.MapPins.setWaypoint(ENTRY))
    assert.matches("Waypoint set: The Blackwood Corrupted", out[#out])
  end)

  it("hasUserWaypoint: true, false, or nil when the client cannot tell", function()
    local ns, env, fake = ui.load({ state = "S18", chardb = { settings = { guide = false } } })
    assert.is_false(ns.MapPins.hasUserWaypoint())
    fake.setUserWaypoint(1439, 0.5, 0.5)
    assert.is_true(ns.MapPins.hasUserWaypoint())
    env.C_Map.GetUserWaypoint = nil
    assert.is_nil(ns.MapPins.hasUserWaypoint())
  end)

  it("releaseOurs: the waypoint is no longer ours; no error without a world map", function()
    local ns, env = ui.load({ state = "S18", chardb = { settings = { guide = false } } })
    ns.MapPins.setWaypoint(ENTRY, { quiet = true })
    assert.is_true(ns.MapPins.isOurWaypoint())
    ns.MapPins.releaseOurs()
    assert.is_false(ns.MapPins.isOurWaypoint())
    assert.is_true(ns.MapPins.hasUserWaypoint())
    assert.same({}, env.errors)
  end)

  it("isWaypointAt: the same map and within 0.002", function()
    local ns, _, fake = ui.load({ state = "S18", chardb = { settings = { guide = false } } })
    local spot = { mapID = 1439, x = 37.4, y = 40.1 }
    assert.is_false(ns.MapPins.isWaypointAt(spot))
    fake.setUserWaypoint(1439, 0.3755, 0.4025)
    assert.is_true(ns.MapPins.isWaypointAt(spot))
    fake.setUserWaypoint(1440, 0.374, 0.401)
    assert.is_false(ns.MapPins.isWaypointAt(spot))
    assert.is_false(ns.MapPins.isWaypointAt(nil))
  end)
end)

describe("/advisor guide", function()
  local function load(opts)
    opts = opts or {}
    opts.state = opts.state or "S18"
    local ns, env, fake, out = ui.load(opts)
    return ns, env, fake, out
  end

  it("off and on", function()
    local ns, env, fake, out = load()
    ns.Slash.handle("guide off")
    assert.is_false(ns.UI.Guide.enabled())
    assert.equal("|cffffd100Leveling Advisor:|r Guide off.", out[#out])
    assert.is_nil(fake.userWaypoint)
    fake.setState(took4763())
    ns.Slash.handle("guide on")
    assert.is_true(ns.UI.Guide.enabled())
    assert.equal("|cffffd100Leveling Advisor:|r Guide on: a waypoint marks your next step.", out[#out])
    at(fake.waypoints[#fake.waypoints], 1439, 0.40, 0.40)
    assert.same({}, env.errors)
  end)

  it("continue", function()
    local ns, _, fake, out = load()
    fake.setUserWaypoint(nil)
    ns.Events.dispatch("USER_WAYPOINT_UPDATED")
    ns.Slash.handle("guide continue")
    assert.equal("|cffffd100Leveling Advisor:|r Guide: waypoint set to The Blackwood Corrupted.", out[#out])
    fake.combat(true)
    ns.Slash.handle("guide continue")
    assert.equal("|cffffd100Leveling Advisor:|r Guide: the waypoint is set after the fight.", out[#out])
    fake.combat(false)
    ns.Slash.handle("guide off")
    ns.Slash.handle("guide continue")
    assert.equal("|cffffd100Leveling Advisor:|r The guide is off. Type /advisor guide on to turn it on.", out[#out])
  end)

  it("continue without a next step", function()
    local ns, _, _, out = load({ state = "H20" })
    ns.Slash.handle("guide continue")
    assert.equal("|cffffd100Leveling Advisor:|r Guide: no next step right now.", out[#out])
  end)

  it("status, and usage for anything else", function()
    local ns, _, fake, out = load()
    ns.Slash.handle("guide")
    assert.equal("|cffffd100Leveling Advisor:|r Guide: on — next: The Blackwood Corrupted (pick up),"
      .. " Darkshore (37.4, 40.1).", out[#out])
    fake.setUserWaypoint(1439, 0.5, 0.5)
    ns.Events.dispatch("USER_WAYPOINT_UPDATED")
    ns.Slash.handle("guide")
    assert.equal("|cffffd100Leveling Advisor:|r Guide: paused — another waypoint was set."
      .. " Type /advisor guide continue to resume.", out[#out])
    ns.Slash.handle("guide continue")
    fake.setUserWaypoint(nil)
    ns.Events.dispatch("USER_WAYPOINT_UPDATED")
    ns.Slash.handle("guide")
    assert.equal("|cffffd100Leveling Advisor:|r Guide: paused — you removed its waypoint."
      .. " Type /advisor guide continue to resume.", out[#out])
    ns.Slash.handle("guide off")
    ns.Slash.handle("guide")
    assert.equal("|cffffd100Leveling Advisor:|r Guide: off. Type /advisor guide on to turn it on.", out[#out])
    ns.Slash.handle("guide sideways")
    assert.equal("|cffffd100Leveling Advisor:|r Usage: /advisor guide on|off|continue", out[#out])
  end)

  it("without UI/Guide.lua (an update applied with /reload only) it says so and nothing errors", function()
    local all, keep = ui.FILES, {}
    for _, f in ipairs(all) do
      if f ~= "UI/Guide.lua" then keep[#keep + 1] = f end
    end
    assert.equal(#all - 1, #keep) -- the TOC lists it
    ui.FILES = keep
    local ok, ns, env, _, out = pcall(load)
    ui.FILES = all
    assert.is_true(ok, tostring(ns))
    ns.Slash.handle("guide continue")
    assert.equal("|cffffd100Leveling Advisor:|r The guide is not available.", out[#out])
    ns.Slash.handle("debug")
    assert.same({}, env.errors)
  end)

  it("help lists it and debug shows its state and target", function()
    local ns, env, _, out = load()
    ns.Slash.handle("help")
    assert.is_true(said(out, "/advisor guide [on|off|continue] — a waypoint to your next step"))
    ns.Slash.handle("debug")
    assert.is_true(said(out, "guide: on, not paused, target 4763 pickup 1439 37.4,40.1, waypoint guide"))
    assert.same({}, env.errors)
  end)
end)
