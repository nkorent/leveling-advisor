-- The map pin's XML wiring (UI/MapPins.xml) and the pins as the shared map canvas fake
-- (spec/helpers/mapcanvas.lua) acquires them from that template, on the strict widget fake.
local ui = require("spec.helpers.ui")
local mapcanvas = require("spec.helpers.mapcanvas")

local XML = "LevelingAdvisor/UI/MapPins.xml"
local TEMPLATE = "LevelingAdvisorMapPinTemplate"

describe("MapPins.xml wiring", function()
  local tpl = mapcanvas.template(XML, TEMPLATE)

  it("declares the pin template: a virtual 16 x 18 Frame with the mouse enabled", function()
    assert.is_truthy(tpl)
    assert.equal("Frame", tpl.frameType)
    assert.is_true(tpl.virtual)
    assert.is_true(tpl.enableMouse)
    assert.same({ 16, 18 }, tpl.size)
  end)

  it("names the mixin global that MapPins.lua defines", function()
    local _, env = ui.load({ noData = true })
    assert.equal("LevelingAdvisorMapPinMixin", tpl.mixin)
    local mx = env[tpl.mixin]
    assert.is_table(mx)
    -- the pin mixin itself, built on MapCanvasPinMixin
    assert.is_function(mx.OnAcquired)
    assert.is_function(mx.LAOnClick)
    assert.equal(env.MapCanvasPinMixin.UseFrameLevelType, mx.UseFrameLevelType)
  end)

  it("binds every <Scripts> method to a function of that mixin", function()
    local _, env = ui.load({ noData = true })
    local mx = env[tpl.mixin]
    assert.same({ { "OnLoad", "OnLoad" }, { "OnEnter", "LAOnEnter" }, { "OnLeave", "LAOnLeave" },
      { "OnMouseUp", "LAOnClick" } }, tpl.scripts)
    for _, s in ipairs(tpl.scripts) do
      assert.is_function(mx[s[2]], s[1] .. ' method="' .. s[2] .. '" is not on the mixin')
    end
  end)
end)

describe("map pins on the world map canvas", function()
  local function open(opts)
    opts = opts or {}
    opts.state = opts.state or "S18"
    opts.worldMap = true
    local ns, env, fake, out = ui.load(opts)
    local wm = env.WorldMapFrame
    wm:SetMapID(opts.mapID or 1439)
    wm:Show()
    return ns, env, fake, out, wm
  end

  it("a compute before the world map has a map (never opened) acquires nothing and reports no error", function()
    local ns, env = ui.load({ state = "S18", worldMap = true })
    assert.is_nil(env.WorldMapFrame:GetMapID())
    ns.Advisor.compute()
    assert.same({}, env.WorldMapFrame.pins)
    assert.same({}, env.errors)
  end)

  it("acquires one pin per model entry from the XML template, at the model's place", function()
    local ns, env, _, _, wm = open()
    local model = ns.MapPins.model(1439)
    assert.is_true(#model >= 2)
    assert.equal(#model, #wm.pins)
    for i, pin in ipairs(wm.pins) do
      assert.equal(TEMPLATE, pin.pinTemplate)
      assert.equal("Frame", pin:GetObjectType())
      assert.equal(wm, pin:GetParent())
      assert.same({ model[i].x / 100, model[i].y / 100 }, pin.pos)
      assert.same(model[i], pin.entry)
      assert.same({ 16, 18 }, { pin:GetWidth(), pin:GetHeight() })
    end
    assert.same({}, env.errors)
  end)

  it("draws the shield and the confirmed quest atlas on the strict widgets", function()
    local _, env, _, _, wm = open()
    local pin = wm.pins[1]
    assert.equal("Interface\\AddOns\\LevelingAdvisor\\Media\\PinShield", pin.laShield:GetTexture())
    assert.equal(pin.entry.kind == "turnin" and "QuestTurnin" or "QuestNormal", pin.laGlyph:GetAtlas())
    assert.same({}, env.errors)
  end)

  it("lets right clicks through the pin frame (OnLoad, out of combat)", function()
    local _, _, _, _, wm = open()
    local pass
    for _, c in ipairs(wm.pins[1].calls) do if c[1] == "SetPassThroughButtons" then pass = c end end
    assert.same({ "SetPassThroughButtons", "RightButton" }, pass)
  end)

  it("hover through the pin's OnEnter / OnLeave scripts shows and hides the tooltip", function()
    local _, env, fake, _, wm = open()
    local pin = wm.pins[1]
    pin:GetScript("OnEnter")(pin)
    assert.equal(pin, fake.tooltip.owner)
    assert.equal("Leveling Advisor", fake.tooltip.lines[1][1])
    assert.equal(1.35, pin.laHolder:GetScale())
    pin:GetScript("OnLeave")(pin)
    assert.is_false(fake.tooltip:IsShown())
    assert.equal(1, pin.laHolder:GetScale())
    assert.same({}, env.errors)
  end)

  it("a left click through the canvas's OnMouseUp sets the waypoint once; a right click does not", function()
    local _, env, fake, _, wm = open({ chardb = { settings = { guide = false } } }) -- no guide waypoint
    local pin = wm.pins[1]
    pin:GetScript("OnMouseUp")(pin, "RightButton", true)
    assert.same({}, fake.waypoints)
    pin:GetScript("OnMouseUp")(pin, "LeftButton", true)
    assert.same({ { uiMapID = 1439, x = pin.entry.x / 100, y = pin.entry.y / 100 } }, fake.waypoints)
    assert.is_true(fake.superTracked)
    assert.same({}, env.errors)
  end)

  it("a new map releases the old pins to the pool and reuses their frames", function()
    local _, env, _, _, wm = open()
    local first = wm.pins[1]
    local n = #wm.pins
    wm:SetMapID(1440)
    for _, pin in ipairs(wm.pins) do assert.equal(1440, pin.entry.mapID) end
    wm:SetMapID(1439)
    assert.equal(n, #wm.pins)
    local reused = false
    for _, pin in ipairs(wm.pins) do if pin == first then reused = true end end
    assert.is_true(reused)
    assert.same({}, env.errors)
  end)
end)

-- 0.3.0: the game's square user-waypoint pin ("map sharing pin", Blizzard's
-- WaypointLocationPinTemplate) is hidden while the user waypoint is the one we set; the
-- super-track pinpoint is the one marker left.
describe("the game's waypoint pin at our waypoint", function()
  local SHARING = "WaypointLocationPinTemplate"
  local GIVER = { mapID = 1439, x = 37.4, y = 40.1, quests = { { id = 4763, name = "The Blackwood Corrupted" } } }

  local function open(opts)
    opts = opts or {}
    opts.state = opts.state or "S18"
    opts.worldMap = true
    opts.waypointPin = true
    local ns, env, fake, out = ui.load(opts)
    local wm = env.WorldMapFrame
    wm:SetMapID(1439)
    wm:Show()
    return ns, env, fake, out, wm
  end

  local function sharingPins(wm)
    local list = {}
    for _, pin in ipairs(wm.pins) do
      if pin.pinTemplate == SHARING then list[#list + 1] = pin end
    end
    return list
  end

  local function onlySharingPin(wm)
    local list = sharingPins(wm)
    assert.equal(1, #list)
    return list[1]
  end

  it("setWaypoint returns true and the sharing pin at our waypoint is hidden", function()
    local ns, env, fake, _, wm = open()
    assert.is_true(ns.MapPins.setWaypoint(GIVER))
    assert.is_true(fake.superTracked)
    assert.is_false(onlySharingPin(wm):IsShown())
    assert.is_true(ns.MapPins.isOurWaypoint())
    assert.same({}, env.errors)
  end)

  it("the OnAcquired hook hides it again when the map acquires it anew", function()
    local ns, env, _, _, wm = open()
    ns.MapPins.setWaypoint(GIVER)
    wm:SetMapID(1440)
    assert.equal(0, #sharingPins(wm))
    wm:SetMapID(1439) -- the pooled pin is shown by AcquirePin, then hidden by our hook
    assert.is_false(onlySharingPin(wm):IsShown())
    assert.same({}, env.errors)
  end)

  it("without hooksecurefunc the sweeps hide it: after setWaypoint and on USER_WAYPOINT_UPDATED", function()
    local ns, env, fake, _, wm = open({ without = { "hooksecurefunc" } })
    ns.MapPins.setWaypoint(GIVER)
    local pin = onlySharingPin(wm)
    assert.is_false(pin:IsShown())
    pin:Show() -- the game redraws its pin outside a map refresh
    ns.Events.dispatch("USER_WAYPOINT_UPDATED")
    assert.is_false(pin:IsShown())
    pin:Show()
    ns.Events.dispatch("USER_WAYPOINT_UPDATED")
    pin:Show() -- the game's provider redraws after our handler
    fake.flush() -- the deferred sweep
    assert.is_false(pin:IsShown())
    assert.same({}, env.errors)
  end)

  it("our provider's refresh re-hides it: re-acquired on a map change (no hook), and on map show", function()
    local ns, env, _, _, wm = open({ without = { "hooksecurefunc" } })
    ns.MapPins.setWaypoint(GIVER)
    wm:SetMapID(1440)
    wm:SetMapID(1439) -- the game's provider re-acquires (shows) its pin, then ours refreshes
    assert.is_false(onlySharingPin(wm):IsShown())
    wm:Hide()
    onlySharingPin(wm):Show() -- redrawn while the map was closed
    wm:Show()
    assert.is_false(onlySharingPin(wm):IsShown())
    assert.same({}, env.errors)
  end)

  it("when our provider refreshes before the game's, the sweep a frame later hides it", function()
    local ns, env, fake, _, wm = open({ without = { "hooksecurefunc" } })
    ns.MapPins.setWaypoint(GIVER)
    fake.flush() -- setWaypoint's own deferred sweep
    local p = wm.providers
    p[1], p[#p] = p[#p], p[1] -- ours first
    wm:SetMapID(1440)
    wm:SetMapID(1439)
    assert.is_true(onlySharingPin(wm):IsShown())
    fake.flush()
    assert.is_false(onlySharingPin(wm):IsShown())
    assert.same({}, env.errors)
  end)

  it("releaseOurs (the guide turned off) shows the hidden pin again", function()
    local ns, env, fake, _, wm = open()
    ns.MapPins.setWaypoint(GIVER)
    assert.is_false(onlySharingPin(wm):IsShown())
    ns.MapPins.releaseOurs()
    assert.is_true(onlySharingPin(wm):IsShown())
    assert.is_false(ns.MapPins.isOurWaypoint())
    ns.Events.dispatch("USER_WAYPOINT_UPDATED")
    fake.flush()
    assert.is_true(onlySharingPin(wm):IsShown())
    assert.same({}, env.errors)
  end)

  it("a waypoint the player placed by hand keeps its pin", function()
    local ns, env, fake, _, wm = open()
    ns.MapPins.setWaypoint(GIVER)
    fake.setUserWaypoint(1439, 0.50, 0.50)
    ns.Events.dispatch("USER_WAYPOINT_UPDATED")
    fake.flush()
    assert.is_true(onlySharingPin(wm):IsShown())
    assert.is_false(ns.MapPins.isOurWaypoint())
    assert.same({}, env.errors)
  end)

  it("a pin we hid is shown again once the waypoint is no longer ours", function()
    local ns, _, fake, _, wm = open()
    ns.MapPins.setWaypoint(GIVER)
    local pin = onlySharingPin(wm)
    assert.is_false(pin:IsShown())
    -- the waypoint moves but the game does not redraw its pin: our sweep shows it again
    fake.userWaypoint = { uiMapID = 1439, position = { x = 0.6, y = 0.6 } }
    ns.Events.dispatch("USER_WAYPOINT_UPDATED")
    assert.is_true(pin:IsShown())
  end)

  it("ours means the same map and a position within 0.002", function()
    local ns, _, fake = open()
    ns.MapPins.setWaypoint(GIVER)
    fake.setUserWaypoint(1439, 0.3755, 0.4025)
    assert.is_true(ns.MapPins.isOurWaypoint())
    fake.setUserWaypoint(1439, 0.377, 0.401)
    assert.is_false(ns.MapPins.isOurWaypoint())
    fake.setUserWaypoint(1440, 0.374, 0.401)
    assert.is_false(ns.MapPins.isOurWaypoint())
    fake.setUserWaypoint(nil)
    assert.is_false(ns.MapPins.isOurWaypoint())
  end)

  it("a failed setWaypoint returns false and keeps the earlier waypoint ours", function()
    local ns, env, fake = open()
    ns.MapPins.setWaypoint(GIVER)
    env.C_SuperTrack.SetSuperTrackedUserWaypoint = function() error("blocked") end
    local before = fake.userWaypoint
    env.C_Map.SetUserWaypoint = function() error("blocked") end
    assert.is_false(ns.MapPins.setWaypoint({ mapID = 1440, x = 10, y = 10, quests = {} }))
    assert.equal(before, fake.userWaypoint)
    assert.is_true(ns.MapPins.isOurWaypoint())
  end)

  it("with none of the APIs nothing errors", function()
    local ns, env = ui.load({ state = "S18",
      without = { "hooksecurefunc", "WorldMapFrame", "C_Timer", "WaypointLocationPinMixin" } })
    env.C_Map.GetUserWaypoint = nil
    ns.MapPins.setWaypoint(GIVER)
    ns.Events.dispatch("USER_WAYPOINT_UPDATED")
    assert.is_false(ns.MapPins.isOurWaypoint())
    ns.Slash.handle("debug")
    env.C_Map = nil
    assert.is_false(ns.MapPins.setWaypoint(GIVER))
    ns.Events.dispatch("USER_WAYPOINT_UPDATED")
    assert.same({}, env.errors)
  end)

  it("a world map without pin enumeration or a mixin without OnAcquired does not error", function()
    local ns, env, _, _, wm = open({ globals = { WaypointLocationPinMixin = {} } })
    rawset(wm, "EnumeratePinsByTemplate", nil)
    ns.MapPins.setWaypoint(GIVER)
    ns.Events.dispatch("USER_WAYPOINT_UPDATED")
    rawset(wm, "EnumeratePinsByTemplate", function() error("boom") end)
    ns.Events.dispatch("USER_WAYPOINT_UPDATED")
    assert.same({}, env.errors)
  end)

  describe("/advisor debug", function()
    local function mapPinsLine(out)
      for i = #out, 1, -1 do
        if out[i]:find("map pins: ", 1, true) then return out[i] end
      end
    end

    it("lists the world map's pin templates with how many are hidden, and whose waypoint it is", function()
      local ns, env, _, out, wm = open()
      ns.MapPins.setWaypoint(GIVER)
      local n = 0
      for _, pin in ipairs(wm.pins) do
        if pin.pinTemplate == "LevelingAdvisorMapPinTemplate" then n = n + 1 end
      end
      assert.is_true(n > 0)
      ns.Slash.handle("debug")
      assert.equal("|cffffd100Leveling Advisor:|r map pins: LevelingAdvisorMapPinTemplate " .. n
        .. ", WaypointLocationPinTemplate 1 (hidden 1); waypoint: ours", mapPinsLine(out))
      -- without pinPools: EnumerateAllPins
      rawset(wm, "pinPools", nil)
      ns.Slash.handle("debug")
      assert.equal("|cffffd100Leveling Advisor:|r map pins: LevelingAdvisorMapPinTemplate " .. n
        .. ", WaypointLocationPinTemplate 1 (hidden 1); waypoint: ours", mapPinsLine(out))
      assert.same({}, env.errors)
    end)

    it("says when the waypoint is someone else's, when there is none, and when there is no map", function()
      local ns, _, fake, out = open()
      ns.Settings.set("pinsAll", false)
      fake.setUserWaypoint(1439, 0.5, 0.5)
      ns.Slash.handle("debug")
      assert.equal("|cffffd100Leveling Advisor:|r map pins: WaypointLocationPinTemplate 1; waypoint: not ours",
        mapPinsLine(out))
      fake.setUserWaypoint(nil)
      ns.Slash.handle("debug")
      assert.equal("|cffffd100Leveling Advisor:|r map pins: none; waypoint: none", mapPinsLine(out))

      local ns2, _, _, out2 = ui.load({ state = "S18" })
      ns2.Slash.handle("debug")
      assert.equal("|cffffd100Leveling Advisor:|r map pins: no world map", mapPinsLine(out2))
    end)
  end)
end)
