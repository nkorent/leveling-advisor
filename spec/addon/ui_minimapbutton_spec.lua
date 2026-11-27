local ui = require("spec.helpers.ui")

local function load(opts)
  opts = opts or {}
  opts.state = opts.state or "S18"
  opts.minimap = opts.minimap ~= false
  local ns, env, fake, out = ui.load(opts)
  return ns, env, fake, out, fake.named("LevelingAdvisorMinimapButton")
end

-- Radius = 140 / 2 + 10 = 80.
local function offsetOf(btn)
  local p, rel, relp, x, y = btn:GetPoint(1)
  return p, rel, relp, x, y
end

describe("minimap button", function()
  it("is created on ready, on the minimap edge at the default 200 degrees", function()
    local _, env, _, _, btn = load()
    assert.is_truthy(btn)
    assert.equal(env.Minimap, btn:GetParent())
    local p, rel, relp, x, y = offsetOf(btn)
    assert.same({ "CENTER", env.Minimap, "CENTER" }, { p, rel, relp })
    assert.near(80 * math.cos(math.rad(200)), x, 0.01)
    assert.near(80 * math.sin(math.rad(200)), y, 0.01)
    assert.same({}, env.errors)
  end)

  it("matches the standard minimap button look", function()
    local _, env, fake, _, btn = load()
    assert.same({ 31, 31 }, { btn:GetWidth(), btn:GetHeight() })
    assert.equal("MEDIUM", btn:GetFrameStrata())
    assert.is_true(btn:GetFrameLevel() > env.Minimap:GetFrameLevel())
    local function tex(path)
      return fake.find(function(w) return w.parent == btn and w.texture == path end)
    end
    local bg = tex("Interface\\Minimap\\UI-Minimap-Background")
    assert.same({ 20, 20 }, { bg:GetWidth(), bg:GetHeight() })
    local border = tex("Interface\\Minimap\\MiniMap-TrackingBorder")
    assert.same({ 50, 50 }, { border:GetWidth(), border:GetHeight() })
    assert.equal("TOPLEFT", (border:GetPoint(1)))
    local hl = tex("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    assert.equal("ADD", hl.blend)
    local icon = btn.laIcon
    assert.equal("Interface\\AddOns\\LevelingAdvisor\\Media\\Logo", icon:GetTexture())
    assert.same({ 18, 18 }, { icon:GetWidth(), icon:GetHeight() })
    assert.same({ "CENTER", btn, "CENTER", 1, -1 }, { icon:GetPoint(1) })
    local mask
    for _, c in ipairs(icon.calls) do if c[1] == "SetMask" then mask = c[2] end end
    assert.equal("Interface\\CharacterFrame\\TempPortraitAlphaMask", mask)
  end)

  it("shifts the icon 1 px while the mouse is down", function()
    local _, _, _, _, btn = load()
    btn:GetScript("OnMouseDown")(btn)
    assert.same({ "CENTER", btn, "CENTER", 2, -2 }, { btn.laIcon:GetPoint(1) })
    btn:GetScript("OnMouseUp")(btn)
    assert.same({ "CENTER", btn, "CENTER", 1, -1 }, { btn.laIcon:GetPoint(1) })
  end)

  it("restores the saved angle", function()
    local _, _, _, _, btn = load({ db = { window = { minimap = { angle = 90 } } } })
    local _, _, _, x, y = btn:GetPoint(1)
    assert.near(0, x, 0.01)
    assert.near(80, y, 0.01)
  end)

  it("ignores a malformed saved angle", function()
    local _, _, _, _, btn = load({ db = { window = { minimap = { angle = "x" } } } })
    local _, _, _, x = btn:GetPoint(1)
    assert.near(80 * math.cos(math.rad(200)), x, 0.01)
  end)

  it("follows the cursor while dragging and saves the angle", function()
    local ns, env, fake, _, btn = load()
    btn:GetScript("OnDragStart")(btn)
    fake.cursor = { 500, 700 } -- straight up from the centre
    btn:GetScript("OnUpdate")(btn, 0.01)
    local _, _, _, x, y = btn:GetPoint(1)
    assert.near(0, x, 0.01)
    assert.near(80, y, 0.01)
    assert.near(90, ns.db.window.minimap.angle, 0.01)
    btn:GetScript("OnDragStop")(btn)
    fake.cursor = { 700, 500 }
    if btn:GetScript("OnUpdate") then btn:GetScript("OnUpdate")(btn, 0.01) end
    assert.near(90, ns.db.window.minimap.angle, 0.01)
    assert.same({}, env.errors)
  end)

  it("wraps negative cursor angles into 0-360", function()
    local ns, _, fake, _, btn = load()
    btn:GetScript("OnDragStart")(btn)
    fake.cursor = { 500, 300 } -- straight down
    btn:GetScript("OnUpdate")(btn, 0.01)
    assert.near(270, ns.db.window.minimap.angle, 0.01)
  end)

  it("left-click toggles the book", function()
    local ns, _, fake, _, btn = load()
    fake.click(btn, "LeftButton")
    assert.is_true(ns.UI.isShown())
    fake.click(btn, "LeftButton")
    assert.is_false(ns.UI.isShown())
  end)

  it("right-click opens settings", function()
    local ns, env, fake, _, btn = load()
    local spy = ui.spy(ns.Settings, "open", function() end)
    fake.click(btn, "RightButton")
    assert.equal(1, spy.n)
    assert.is_false(ns.UI.isShown())
    assert.same({}, env.errors)
  end)

  it("right-click in combat prints the combat message instead", function()
    local _, _, fake, out, btn = load()
    fake.combat(true)
    fake.click(btn, "RightButton")
    local found
    for _, l in ipairs(out) do if tostring(l):match("Not in combat") then found = true end end
    assert.is_true(found)
  end)

  it("shows the tooltip", function()
    local _, _, fake, _, btn = load()
    fake.enter(btn)
    assert.equal(btn, fake.tooltip.owner)
    local L = fake.tooltip.lines
    assert.equal("Leveling Advisor", L[1][1])
    assert.equal("Click: open the book", L[2][1])
    assert.equal("Right-click: settings", L[3][1])
    assert.equal("Drag: move", L[4][1])
    assert.same({ 0.7, 0.7, 0.7 }, { L[2][2], L[2][3], L[2][4] })
    assert.is_true(fake.tooltip.shown)
    fake.leave(btn)
    assert.is_false(fake.tooltip.shown)
  end)

  describe("visibility", function()
    it("is shown by default and hidden by the setting", function()
      local ns, _, _, _, btn = load()
      assert.is_true(btn:IsShown())
      ns.Settings.set("minimap", false)
      assert.is_false(btn:IsShown())
      ns.Settings.set("minimap", true)
      assert.is_true(btn:IsShown())
    end)

    it("starts hidden when the saved setting says so", function()
      local _, _, _, _, btn = load({ db = { settings = { minimap = false } } })
      assert.is_false(btn:IsShown())
    end)

    it("/advisor minimap toggles it and the state persists", function()
      local ns, env, _, _, btn = load()
      ns.Slash.handle("minimap")
      assert.is_false(btn:IsShown())
      assert.is_false(ns.db.settings.minimap)
      ns.Slash.handle("minimap")
      assert.is_true(btn:IsShown())
      assert.is_true(ns.db.settings.minimap)
      assert.same({}, env.errors)
    end)

    it("has a settings checkbox that shows and hides it", function()
      local ns, _, fake, _, btn = load()
      local label = fake.text("Show minimap button")
      assert.is_truthy(label)
      local cb = label.parent
      cb.parent.scripts.OnShow(cb.parent)
      fake.click(cb)
      assert.is_false(btn:IsShown())
      fake.click(cb)
      assert.is_true(btn:IsShown())
    end)

    it("is listed in help", function()
      local ns, _, _, out = load()
      ns.Slash.handle("help")
      local found
      for _, l in ipairs(out) do if tostring(l):match("/advisor minimap") then found = true end end
      assert.is_true(found)
    end)
  end)

  describe("shape", function()
    it("clamps to the square edge when GetMinimapShape says SQUARE", function()
      local _, _, _, _, btn = load({ globals = { GetMinimapShape = function() return "SQUARE" end },
        db = { window = { minimap = { angle = 45 } } } })
      local _, _, _, x, y = btn:GetPoint(1)
      assert.near(80, x, 0.01)
      assert.near(80, y, 0.01)
    end)

    it("keeps points inside the square edge on the axis", function()
      local _, _, _, _, btn = load({ globals = { GetMinimapShape = function() return "SQUARE" end },
        db = { window = { minimap = { angle = 0 } } } })
      local _, _, _, x, y = btn:GetPoint(1)
      assert.near(80, x, 0.01)
      assert.near(0, y, 0.01)
    end)

    it("is round when GetMinimapShape is missing or throws", function()
      local _, _, _, _, btn = load({ db = { window = { minimap = { angle = 45 } } } })
      local _, _, _, x = btn:GetPoint(1)
      assert.near(80 * math.cos(math.rad(45)), x, 0.01)
      local _, env, _, _, btn2 = load({ globals = { GetMinimapShape = function() error("boom") end },
        db = { window = { minimap = { angle = 45 } } } })
      assert.near(80 * math.cos(math.rad(45)), (select(4, btn2:GetPoint(1))), 0.01)
      assert.same({}, env.errors)
    end)
  end)

  it("a missing Minimap global means no button and no error", function()
    local ns, env, fake = load({ minimap = false })
    assert.is_nil(fake.named("LevelingAdvisorMinimapButton"))
    assert.is_nil(ns.UI.MinimapButton.attach())
    ns.Settings.set("minimap", false)
    ns.Slash.handle("minimap")
    assert.same({}, env.errors)
  end)

  it("falls back to the plain icon when SetMask throws", function()
    local ns, env, fake, _, first = load()
    local mt = getmetatable(first.laIcon) -- the Texture type: SetMask is a texture method
    local orig = mt.__index -- the kind's method table, as on the client
    mt.__index = function(_, k)
      if k == "SetMask" then return function() error("no masks") end end
      return orig[k]
    end
    local btn = ns.UI.MinimapButton.build()
    mt.__index = orig
    assert.is_truthy(btn)
    assert.equal("Interface\\AddOns\\LevelingAdvisor\\Media\\Logo", btn.laIcon:GetTexture())
    assert.same({}, env.errors)
  end)
end)
