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
    local _, env, fake, _, wm = open()
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
