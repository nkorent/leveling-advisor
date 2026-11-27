local addon = require("spec.helpers.addon")
local mapcanvas = require("spec.helpers.mapcanvas")
local PIN_TEMPLATE = mapcanvas.template("LevelingAdvisor/UI/MapPins.xml", "LevelingAdvisorMapPinTemplate")

local FILES = { "Core/Util.lua", "Core/Init.lua", "Core/Settings.lua", "UI/MapPins.lua" }

local function newTexture()
  local t = { shown = true, calls = {} }
  function t:SetAtlas(a) self.atlas = a; self.texture = nil end
  function t:SetTexture(x)
    if self.failTexture then return false end
    self.texture = x; self.atlas = nil
  end
  function t:GetTexture() return self.texture end
  function t:SetBlendMode() end
  function t:SetAtlas(a) self.atlas = a; self.texture = nil end
  function t:SetColorTexture(...) self.color = { ... } end
  function t:SetDesaturated(v) self.desaturated = v end
  function t:SetVertexColor(...) self.vertex = { ... } end
  function t:SetSize(w, h) self.w, self.h = w, h end
  function t:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... } end
  function t:ClearAllPoints() self.points = nil end
  function t:SetAllPoints() self.allPoints = true end
  function t:Show() self.shown = true end
  function t:Hide() self.shown = false end
  function t:SetShown(v) self.shown = v and true or false end
  return t
end

-- Builds a fake client; opts.noAtlas, opts.noWaypoint, opts.noWorldMap. The world map is
-- the shared map canvas fake (spec/helpers/mapcanvas.lua) with the XML pin template; the
-- pin frames, holders and textures are this spec's own light fakes.
local function client(opts)
  opts = opts or {}
  local c = { tooltip = { lines = {} }, said = {}, hooks = {} }
  local mixins = mapcanvas.mixins()
  -- The pin frame's own (C) methods live in its metatable, under the mixin copies.
  local frameMethods = {}
  function frameMethods:SetPassThroughButtons(...)
    self.passThrough = { ... }
    c.passCalls = (c.passCalls or 0) + 1
  end
  function frameMethods:SetSize(w, h) self.w, self.h = w, h end
  function frameMethods:CreateTexture() local t = newTexture(); self.textures = self.textures or {}; self.textures[#self.textures + 1] = t; return t end
  function frameMethods:EnableMouse() end
  function frameMethods:SetScript(name, fn) self.scripts[name] = fn end
  function frameMethods:GetScript(name) return self.scripts[name] end
  function frameMethods:Show() self.shown = true end
  function frameMethods:Hide() self.shown = false end
  c.frameMethods = frameMethods

  local function newHolder(opts2)
    local h = {}
    function h:CreateTexture()
      local t = newTexture()
      t.failTexture = opts and opts.failTexture
      self.textures = self.textures or {}
      self.textures[#self.textures + 1] = t
      return t
    end
    function h:SetAllPoints() end
    function h:SetPoint() end
    function h:SetSize(w, hh) self.w, self.h = w, hh end
    function h:SetScale(v) self.scale = v end
    function h:SetAlpha(v) self.alpha = v end
    function h:EnableMouse(v) self.mouse = v end
    function h:Show() self.shown = true end
    return h
  end

  -- The world map is the map canvas (as on the client); c.pins are its acquired pins.
  local wmf = { shown = false }
  function wmf:HookScript(name, fn) c.hooks[name] = fn end
  function wmf:IsShown() return self.shown end
  mapcanvas.attach(wmf, {
    mapID = 1411,
    templates = { PIN_TEMPLATE },
    env = setmetatable({}, { __index = function(_, k) return c.env[k] end }),
    newFrame = function(_, _, name, t)
      local pin = setmetatable({ template = name, scripts = {}, Icon = newTexture() }, { __index = frameMethods })
      if t.size then pin.w, pin.h = t.size[1], t.size[2] end
      return pin
    end,
  })
  c.map, c.wmf = wmf, wmf
  c.providers, c.pins = wmf.providers, wmf.pins

  local tip = c.tooltip
  function tip:SetOwner(o, anchor) self.owner, self.anchor = o, anchor; self.lines = {} end
  function tip:GetOwner() return self.owner end
  function tip:AddLine(t, r, g, b) self.lines[#self.lines + 1] = { t, r = r, g = g, b = b } end
  function tip:AddDoubleLine(l, r, lr, lg, lb, rr, rg, rb)
    self.lines[#self.lines + 1] = { l, right = r, r = lr, g = lg, b = lb, rr = rr }
  end
  function tip:Show() self.shown = true end
  function tip:Hide() self.shown = false end

  local extra = {
    CreateFromMixins = mixins.CreateFromMixins,
    Mixin = mixins.Mixin,
    MapCanvasDataProviderMixin = mixins.MapCanvasDataProviderMixin,
    MapCanvasPinMixin = mixins.MapCanvasPinMixin,
    GameTooltip = tip,
    C_Texture = { GetAtlasInfo = function(a) if opts.noAtlas then return nil end; return { atlas = a } end },
    CreateFrame = function(_, _, parent)
      if not parent then return setmetatable({}, { __index = function() return function() end end }) end
      local h = newHolder(); h.parent = parent; if parent then parent.holders = parent.holders or {}; parent.holders[#parent.holders + 1] = h end; return h end,
  }
  if not opts.noWorldMap then extra.WorldMapFrame = wmf end
  if not opts.noWaypoint then
    c.waypoints = {}
    extra.UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, x = x, y = y } end }
    extra.C_Map = { SetUserWaypoint = function(p) c.waypoints[#c.waypoints + 1] = p end }
    extra.C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) c.superTracked = v end }
  end
  c.extra = extra
  return c
end

local function setup(opts)
  local c = client(opts)
  local ns, env, out = addon.load(FILES, c.extra)
  c.env = env
  c.ns, c.out = ns, out
  ns.db = { settings = {} }
  c.updateFns = {}
  c.shownFlags = {}
  ns.Advisor = {
    db = {
      quest = function() return nil end,
      npc = function(_, id) return id == 10 and { "Giver Ten" } or nil end,
      zone = function() return { name = "Durotar" } end,
    },
    last = { rec = { sections = {
      { key = "here", title = "Right Here", rows = {
        { questID = 1, name = "Quest One", level = 5, color = "green", xp = 120, state = "available",
          giver = { mapID = 1411, x = 10, y = 20.5, kind = 1, id = 10 } },
        { questID = 2, name = "Quest Two", level = 6, color = "red", xp = 300, state = "available",
          giver = { mapID = 1411, x = 10.2, y = 20.5, kind = 1, id = 10 } },
        { questID = 3, name = "Quest Three", level = 6, color = "yellow", xp = 50, state = "available",
          giver = { mapID = 1411, x = 50, y = 50, kind = 1, id = 10 } },
      } },
    } } },
    canPickUp = function() return true end,
    onUpdate = function(fn) c.updateFns[#c.updateFns + 1] = fn end,
    setMapShown = function(v) c.shownFlags[#c.shownFlags + 1] = v end,
  }
  return c
end

local function install(c)
  c.ns.MapPins.install()
  return c.providers[1]
end

describe("MapPins rendering", function()
  it("adds the provider once, at login", function()
    local c = setup()
    c.ns.Events.dispatch("PLAYER_LOGIN")
    assert.equals(1, #c.providers)
    c.ns.MapPins.install()
    assert.equals(1, #c.providers)
  end)

  it("skips silently without WorldMapFrame", function()
    local c = setup({ noWorldMap = true })
    assert.has_no.errors(function() c.ns.MapPins.install() end)
    assert.equals(0, #c.providers)
  end)

  it("acquires one pin per model entry", function()
    local c = setup()
    local p = install(c)
    p:RefreshAllData()
    assert.equals(2, #c.pins)
    assert.equals("LevelingAdvisorMapPinTemplate", c.pins[1].template)
    assert.equals(2, #c.pins[1].entry.quests)
    -- refresh again clears first, no duplicates
    p:RefreshAllData()
    assert.equals(2, #c.pins)
  end)

  it("positions pins in 0-1 map space", function()
    local c = setup()
    install(c):RefreshAllData()
    assert.near(0.10, c.pins[1].pos[1], 1e-9)
    assert.near(0.205, c.pins[1].pos[2], 1e-9)
  end)

  it("draws nothing when pinsAll is off, and live on toggle", function()
    local c = setup()
    local p = install(c)
    p:RefreshAllData()
    assert.equals(2, #c.pins)
    c.ns.Settings.set("pinsAll", false)
    assert.equals(0, #c.pins)
    c.ns.Settings.set("pinsAll", true)
    assert.equals(2, #c.pins)
  end)

  it("draws nothing without advisor results", function()
    local c = setup()
    c.ns.Advisor.last = nil
    install(c):RefreshAllData()
    assert.equals(0, #c.pins)
  end)

  it("only shows pins for the displayed map", function()
    local c = setup()
    local p = install(c)
    c.map.mapID = 1412
    p:RefreshAllData()
    assert.equals(0, #c.pins)
  end)

  it("refreshes after each advisor compute", function()
    local c = setup()
    install(c)
    assert.equals(1, #c.updateFns)
    c.updateFns[1]({}, c.ns.Advisor.last)
    assert.equals(2, #c.pins)
  end)

  it("treats the world map like a shown window and refreshes", function()
    local c = setup()
    install(c)
    c.hooks.OnShow()
    assert.same({ true }, c.shownFlags)
    assert.equals(2, #c.pins)
    c.hooks.OnHide()
    assert.same({ true, false }, c.shownFlags)
  end)

  describe("shield", function()
    local SHIELD = "Interface\\AddOns\\LevelingAdvisor\\Media\\PinShield"
    local GLOW = "Interface\\AddOns\\LevelingAdvisor\\Media\\PinShieldGlow"
    local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    local function layers(pin)
      local h = pin.laHolder
      assert.is_truthy(h)
      return h.textures
    end
    local function byTexture(pin, path)
      for _, t in ipairs(layers(pin)) do if t.texture == path then return t end end
    end
    local function bySize(pin, size)
      for _, t in ipairs(layers(pin)) do if t.w == size then return t end end
    end

    it("is a 16x18 frame with a 16x18 shield, a 26x29 glow and a 9px glyph", function()
      local c = setup()
      install(c):RefreshAllData()
      local pin = c.pins[1]
      assert.equals(16, pin.w)
      assert.equals(18, pin.h)
      local shield = byTexture(pin, SHIELD)
      assert.is_truthy(shield)
      assert.same({ 16, 18 }, { shield.w, shield.h })
      local glow = byTexture(pin, GLOW)
      assert.is_truthy(glow)
      assert.same({ 26, 29 }, { glow.w, glow.h })
      assert.equals(3, #layers(pin))
      assert.same({ 9, 9 }, { bySize(pin, 9).w, bySize(pin, 9).h })
    end)

    it("does not create the medallion layers when the shield loads", function()
      local c = setup()
      install(c):RefreshAllData()
      assert.is_nil(byTexture(c.pins[1], DISC))
      assert.is_nil(bySize(c.pins[1], 14))
    end)

    it("builds the texture paths from the addon folder name", function()
      local c = setup()
      install(c):RefreshAllData()
      assert.equals(SHIELD, c.pins[1].laShield.texture)
    end)

    it("offsets the glyph one pixel up", function()
      local c = setup()
      install(c):RefreshAllData()
      local g = bySize(c.pins[1], 9)
      assert.same({ "CENTER", 0, 1 }, g.points[#g.points])
    end)

    it("pickup glyph is the QuestNormal atlas", function()
      local c = setup()
      install(c):RefreshAllData()
      assert.equals("QuestNormal", bySize(c.pins[1], 9).atlas)
    end)

    it("turn-in glyph is the QuestTurnin atlas", function()
      local c = setup()
      local s = c.ns.Advisor.last.rec.sections[1]
      s.key = "turnin"
      for _, r in ipairs(s.rows) do r.state = "complete" end
      c.ns.Advisor.db.quest = function() return { turnIn = { kind = 1, id = 10, mapID = 1411, x = 70, y = 70 } } end
      install(c):RefreshAllData()
      assert.equals("QuestTurnin", bySize(c.pins[1], 9).atlas)
    end)

    it("glyph falls back to the GossipFrame files without the atlas", function()
      local c = setup({ noAtlas = true })
      install(c):RefreshAllData()
      assert.equals("Interface\\GossipFrame\\AvailableQuestIcon", bySize(c.pins[1], 9).texture)
    end)

    it("reuses the layers when a pooled pin is re-acquired with another kind", function()
      local c = setup()
      install(c):RefreshAllData()
      local pin = c.pins[1]
      local n = #layers(pin)
      pin:OnAcquired({ kind = "turnin", x = 1, y = 1, quests = {} })
      assert.equals(n, #layers(pin))
      assert.equals("QuestTurnin", bySize(pin, 9).atlas)
    end)

    it("disables mouse on the holder, never on the pin itself", function()
      local c = setup()
      install(c):RefreshAllData()
      assert.is_false(c.pins[1].laHolder.mouse)
    end)

    it("rests at alpha 0.86; hover shows the glow at alpha 1.0 and scale 1.35; leave restores", function()
      local c = setup()
      install(c):RefreshAllData()
      local pin = c.pins[1]
      local glow = byTexture(pin, GLOW)
      assert.is_false(glow.shown)
      assert.equals(1, pin.laHolder.scale)
      assert.equals(0.86, pin.laHolder.alpha)
      pin:LAOnEnter()
      assert.equals(1.35, pin.laHolder.scale)
      assert.equals(1.0, pin.laHolder.alpha)
      assert.is_true(glow.shown)
      pin:LAOnLeave()
      assert.equals(1, pin.laHolder.scale)
      assert.equals(0.86, pin.laHolder.alpha)
      assert.is_false(glow.shown)
    end)

    it("a missing glow texture just means no glow", function()
      local c = setup()
      local real = c.extra.CreateFrame
      c.env.CreateFrame = function(...)
        local h = real(...)
        local make = h.CreateTexture
        local n = 0
        function h:CreateTexture(...)
          local t = make(self, ...)
          n = n + 1
          if n == 1 then t.failTexture = true end -- glow is created first
          return t
        end
        return h
      end
      install(c):RefreshAllData()
      local pin = c.pins[1]
      assert.is_truthy(byTexture(pin, SHIELD))
      assert.has_no.errors(function() pin:LAOnEnter(); pin:LAOnLeave() end)
    end)

    it("ignores a legacy pinStyle value", function()
      local c = setup()
      c.ns.db.settings.pinStyle = "green"
      install(c):RefreshAllData()
      assert.equals(2, #c.pins)
      assert.equals(16, c.pins[1].w)
    end)

    it("survives a pin without SetSize and a holder without CreateTexture", function()
      local c = setup()
      c.env.CreateFrame = function(_, _, parent)
        local h = { SetAllPoints = function() end }
        if parent then parent.holders = { h } end
        return h
      end
      c.frameMethods.SetSize = function() error("boom") end
      assert.has_no.errors(function() install(c):RefreshAllData() end)
      assert.equals(2, #c.pins)
    end)
  end)

  describe("medallion fallback", function()
    local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    local function bySize(pin, size)
      for _, t in ipairs(pin.laHolder.textures) do if t.w == size then return t end end
    end

    it("draws the medallion discs when SetTexture fails", function()
      local c = setup({ failTexture = true })
      install(c):RefreshAllData()
      local pin = c.pins[1]
      assert.equals(16, pin.w)
      assert.same({ 1.0, 0.82, 0.0, 1 }, bySize(pin, 14).color)
      assert.same({ 0.10, 0.07, 0.03, 0.95 }, bySize(pin, 11).color)
      assert.is_truthy(bySize(pin, 22))
    end)

    it("falls back when GetTexture is nil after SetTexture", function()
      local c = setup()
      c.env.CreateFrame = function(_, _, parent)
        local h = {}
        function h:CreateTexture()
          local t = newTexture()
          function t:SetTexture() return nil end
          self.textures = self.textures or {}
          self.textures[#self.textures + 1] = t
          return t
        end
        function h:SetAllPoints() end
        function h:SetScale() end
        if parent then parent.holders = { h } end
        return h
      end
      install(c):RefreshAllData()
      local pin = c.pins[1]
      assert.is_nil(pin.laShield)
      local found = false
      for _, t in ipairs(pin.laHolder.textures) do if t.color then found = true end end
      assert.is_true(found)
    end)

    it("hover still scales and glows the medallion", function()
      local c = setup({ failTexture = true })
      install(c):RefreshAllData()
      local pin = c.pins[1]
      local glow = bySize(pin, 22)
      assert.is_false(glow.shown)
      pin:LAOnEnter()
      assert.equals(1.35, pin.laHolder.scale)
      assert.is_true(glow.shown)
      pin:LAOnLeave()
      assert.is_false(glow.shown)
    end)
  end)

  describe("tooltip", function()
    it("lists header, quests with colours, details and footer", function()
      local c = setup()
      install(c):RefreshAllData()
      local pin = c.pins[1]
      pin:LAOnEnter()
      local tip = c.tooltip
      assert.equals(pin, tip.owner)
      assert.equals("ANCHOR_RIGHT", tip.anchor)
      assert.is_true(tip.shown)
      local L = tip.lines
      assert.equals("Leveling Advisor", L[1][1])
      assert.equals("[5] Quest One", L[2][1])
      assert.equals("Right Here", L[2].right)
      assert.same({ 0.25, 0.75, 0.25 }, { L[2].r, L[2].g, L[2].b })
      assert.equals("~120 XP \194\183 Giver Ten", L[3][1])
      assert.equals("[6] Quest Two", L[4][1])
      assert.same({ 1.0, 0.1, 0.1 }, { L[4].r, L[4].g, L[4].b })
      assert.equals("Click: set waypoint", L[#L][1])
      pin:LAOnLeave()
      assert.is_false(tip.shown)
    end)

    it("omits the giver when unknown", function()
      local c = setup()
      c.ns.Advisor.last.rec.sections[1].rows[1].giver.id = 999
      install(c):RefreshAllData()
      c.pins[1]:LAOnEnter()
      assert.equals("~120 XP", c.tooltip.lines[3][1])
    end)
  end)

  describe("click", function()
    it("sets and super-tracks a waypoint and says so", function()
      local c = setup()
      install(c):RefreshAllData()
      c.pins[1]:LAOnClick("LeftButton")
      assert.equals(1, #c.waypoints)
      assert.same({ uiMapID = 1411, x = 0.10, y = 0.205 }, c.waypoints[1])
      assert.is_true(c.superTracked)
      assert.matches("Waypoint set: Quest One %(Durotar 10%.0, 20%.5%)", c.out[#c.out])
    end)

    it("says it is unavailable when the APIs are missing", function()
      local c = setup({ noWaypoint = true })
      install(c):RefreshAllData()
      assert.has_no.errors(function() c.pins[1]:LAOnClick("LeftButton") end)
      assert.matches("Waypoints are not available on this client.", c.out[#c.out])
    end)

    it("does not error when SetUserWaypoint throws", function()
      local c = setup()
      c.extra.C_Map.SetUserWaypoint = function() error("boom") end
      install(c):RefreshAllData()
      assert.has_no.errors(function() c.pins[1]:LAOnClick("LeftButton") end)
      assert.matches("not available", c.out[#c.out])
    end)

    it("ignores right clicks", function()
      local c = setup()
      install(c):RefreshAllData()
      c.pins[1]:LAOnClick("RightButton")
      assert.equals(0, #c.waypoints)
    end)
  end)

  describe("map canvas mouse overrides", function()
    -- Blizzard's AcquirePin replaces OnMouseUp with a handler that calls
    -- pin:OnMouseUp(btn, upInside) then pin:OnClick(btn); motion routes through
    -- pin.OnMouseEnter / OnMouseLeave (the shared canvas fake installs both).
    local function canvasMouseUp(pin, btn)
      pin:GetScript("OnMouseUp")(pin, btn, true)
    end
    local function acquire(c)
      install(c):RefreshAllData()
      return c.pins[1]
    end

    it("left click through OnClick sets the waypoint", function()
      local c = setup()
      local pin = acquire(c)
      canvasMouseUp(pin, "LeftButton")
      assert.equals(1, #c.waypoints)
      assert.is_true(c.superTracked)
      assert.matches("Waypoint set", c.out[#c.out])
    end)

    it("right click through OnClick does nothing", function()
      local c = setup()
      local pin = acquire(c)
      canvasMouseUp(pin, "RightButton")
      assert.equals(0, #c.waypoints)
    end)

    it("the XML OnMouseUp path still works and fires once", function()
      local c = setup()
      local pin = acquire(c)
      pin:LAOnClick("LeftButton")
      assert.equals(1, #c.waypoints)
    end)

    it("OnMouseEnter / OnMouseLeave drive the tooltip and hover state", function()
      local c = setup()
      local pin = acquire(c)
      pin:OnMouseEnter()
      assert.is_true(c.tooltip.shown)
      assert.equals(1.35, pin.laHolder.scale)
      pin:OnMouseLeave()
      assert.is_false(c.tooltip.shown)
      assert.equals(1, pin.laHolder.scale)
    end)

    it("the canvas's OnEnter / OnLeave scripts reach the same hover state", function()
      local c = setup()
      local pin = acquire(c)
      pin:GetScript("OnEnter")(pin)
      assert.is_true(c.tooltip.shown)
      assert.equals(1.35, pin.laHolder.scale)
      pin:GetScript("OnLeave")(pin)
      assert.is_false(c.tooltip.shown)
    end)

    it("a refresh releases the pins and acquires the pooled frames again", function()
      local c = setup()
      local p = install(c)
      p:RefreshAllData()
      local first = c.pins[1]
      p:RefreshAllData()
      assert.equals(2, #c.pins)
      assert.is_true(first == c.pins[1] or first == c.pins[2])
    end)
  end)

  describe("route", function()
    -- A stand-in for Advisor.plan (the real one is covered by ui_route_spec):
    -- the plan wraps what Advisor.route returns.
    local function withRoute(c)
      c.routeCalls = 0
      c.ns.Advisor.db.quest = function(_, id)
        if id == 31 then
          return { id = 31, name = "Route Pickup", level = 2, xp = 80,
            giver = { kind = 1, id = 10, mapID = 1411, x = 80, y = 80 } }
        end
      end
      c.ns.Advisor.route = function(mapID)
        c.routeCalls = c.routeCalls + 1
        return { { mapID = mapID, x = 0, y = 0, actions = { { 31, "pickup" } } } }
      end
      c.ns.Advisor.plan = function(mapID)
        local steps = c.ns.Advisor.route(mapID)
        return steps and { mapID = mapID, steps = steps } or nil
      end
    end

    it("adds route pins from the plan to the section pins", function()
      local c = setup()
      withRoute(c)
      install(c):RefreshAllData()
      assert.equals(3, #c.pins)
    end)

    it("asks the plan for the displayed map", function()
      local c = setup()
      withRoute(c)
      local asked = {}
      local plan = c.ns.Advisor.plan
      c.ns.Advisor.plan = function(mapID) asked[#asked + 1] = mapID; return plan(mapID) end
      local p = install(c)
      p:RefreshAllData()
      c.map.mapID = 1412
      p:RefreshAllData()
      assert.same({ 1411, 1412 }, asked)
    end)

    it("shows section pins only when the plan is nil (combat), and retries later", function()
      local c = setup()
      withRoute(c)
      local planFn = c.ns.Advisor.plan
      c.ns.Advisor.plan = function() return nil end
      local p = install(c)
      p:RefreshAllData()
      assert.equals(2, #c.pins)
      c.ns.Advisor.plan = planFn
      p:RefreshAllData()
      assert.equals(3, #c.pins)
    end)

    it("survives a failing plan", function()
      local c = setup()
      c.ns.Advisor.plan = function() error("boom") end
      install(c):RefreshAllData()
      assert.equals(2, #c.pins)
    end)

    it("shows only the section pins without Advisor.plan", function()
      local c = setup()
      c.ns.Advisor.plan = nil
      install(c):RefreshAllData()
      assert.equals(2, #c.pins)
    end)

    it("skips route actions the player has already done", function()
      local c = setup()
      withRoute(c)
      c.ns.Advisor.last.state = { level = 5, log = {}, completed = {} }
      c.ns.Advisor.actionDone = function(id, kind) return id == 31 and kind == "pickup" end
      install(c):RefreshAllData()
      assert.equals(2, #c.pins)
    end)
  end)

  -- I4 (final review): SetPassThroughButtons is restricted in combat (a
  -- blocked action, not a Lua error), from our OnLoad and from MapCanvas.
  describe("pass-through buttons", function()
    it("lets right clicks through the pin out of combat", function()
      local c = setup()
      install(c):RefreshAllData()
      assert.same({ "RightButton" }, c.pins[1].passThrough)
    end)

    it("is never called in combat, and is applied after the fight", function()
      local c = setup()
      c.env.InCombatLockdown = function() return true end
      install(c):RefreshAllData()
      local pin = c.pins[1]
      assert.is_nil(pin.passThrough)
      pin:SetPassThroughButtons("RightButton")   -- the map canvas's own call
      assert.is_nil(c.passCalls)
      c.env.InCombatLockdown = function() return false end
      c.ns.Events.dispatch("PLAYER_REGEN_ENABLED")
      assert.same({ "RightButton" }, pin.passThrough)
      assert.equals(#c.pins, c.passCalls)
      c.ns.Events.dispatch("PLAYER_REGEN_ENABLED")   -- applied once
      assert.equals(#c.pins, c.passCalls)
    end)
  end)

  -- Deferred P1 minor (final review): a released pin takes its tooltip along.
  describe("tooltip on refresh", function()
    it("hides the hovered pin's tooltip when the pins are released", function()
      local c = setup()
      local p = install(c)
      p:RefreshAllData()
      c.pins[1]:OnMouseEnter()
      assert.is_true(c.tooltip.shown)
      p:RefreshAllData()
      assert.is_false(c.tooltip.shown)
    end)

    it("leaves a tooltip it does not own alone", function()
      local c = setup()
      local p = install(c)
      p:RefreshAllData()
      c.pins[1]:OnMouseEnter()
      c.tooltip:SetOwner({}, "ANCHOR_RIGHT")
      c.tooltip:Show()
      p:RefreshAllData()
      assert.is_true(c.tooltip.shown)
    end)
  end)

  describe("describe", function()
    it("names the map and the count", function()
      local c = setup()
      install(c)
      assert.equals("Pins on map Durotar (1411): 2", c.ns.MapPins.describe())
    end)

    it("asks for /advisor when there is no recommendation", function()
      local c = setup()
      c.ns.Advisor.last = nil
      install(c)
      assert.equals("No recommendation yet: type /advisor first", c.ns.MapPins.describe())
    end)
  end)

  describe("count", function()
    it("counts pins on the current map, 0 when off", function()
      local c = setup()
      install(c)
      assert.equals(2, c.ns.MapPins.count())
      c.ns.Settings.set("pinsAll", false)
      assert.equals(0, c.ns.MapPins.count())
    end)
  end)
end)
