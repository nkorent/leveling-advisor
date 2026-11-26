local addon = require("spec.helpers.addon")

local FILES = { "Core/Util.lua", "Core/Init.lua", "Core/Settings.lua" }

-- Fake frame that records text and checked state, like a retail check button.
local function fakeFrames(created)
  local function newFS()
    local fs = {}
    function fs:SetText(t) self.text = t end
    function fs:SetPoint() end
    function fs:SetFontObject() end
    return fs
  end
  local function newFrame(kind, name, parent, template)
    local f = { kind = kind, template = template, scripts = {} }
    function f:RegisterEvent() end
    function f:SetPoint() end
    function f:SetSize() end
    function f:SetText(t) self.text = t end
    function f:SetChecked(v) self.checked = v end
    function f:GetChecked() return self.checked end
    function f:SetScript(n, fn) self.scripts[n] = fn end
    function f:CreateFontString() local fs = newFS(); self.fontStrings = self.fontStrings or {}; self.fontStrings[#self.fontStrings + 1] = fs; return fs end
    if template == "UICheckButtonTemplate" then f.Text = newFS() end
    created[#created + 1] = f
    return f
  end
  return newFrame
end

local function setup(extra)
  local created = {}
  local e = { CreateFrame = fakeFrames(created) }
  for k, v in pairs(extra or {}) do e[k] = v end
  local ns, env, out = addon.load(FILES, e)
  ns.db = { settings = {} }
  return ns, env, out, created
end

local function checkboxes(created)
  local list = {}
  for _, f in ipairs(created) do
    if f.template == "UICheckButtonTemplate" then list[#list + 1] = f end
  end
  return list
end

describe("Settings", function()
  it("returns defaults when unset", function()
    local ns = setup()
    for _, k in ipairs({ "elite", "dungeons", "pinsAll", "recorder", "minimap" }) do
      assert.is_true(ns.Settings.get(k))
    end
    assert.same({ elite = true, dungeons = true, pinsAll = true, recorder = true, minimap = true }, ns.Settings.DEFAULTS)
  end)

  it("set then get, including false", function()
    local ns = setup()
    ns.Settings.set("elite", false)
    assert.is_false(ns.Settings.get("elite"))
    assert.is_false(ns.db.settings.elite)
  end)

  it("calls onChange listeners with key and value, protected", function()
    local ns = setup()
    local seen = {}
    ns.Settings.onChange(function() error("boom") end)
    ns.Settings.onChange(function(k, v) seen[#seen + 1] = { k, v } end)
    ns.Settings.set("elite", false)
    assert.same({ { "elite", false } }, seen)
    assert.is_false(ns.Settings.get("elite"))
  end)

  it("forEngine returns a fresh table each call", function()
    local ns = setup()
    ns.Settings.set("dungeons", false)
    local a, b = ns.Settings.forEngine(), ns.Settings.forEngine()
    assert.are_not.equal(a, b)
    assert.same({ elite = true, dungeons = false }, a)
  end)

  -- spec 5.9: every data source is credited in the About line (final review).
  local SOURCES = "data: QuestieDB Forever (GPL-3.0), outof.games, OpenMap (MIT), an in-game census of map sizes"
    .. " and your own recorder."

  it("aboutLine with and without data meta", function()
    local ns = setup()
    assert.equals("Leveling Advisor 0.1.0 — GPL-3.0 — " .. SOURCES .. " Game data not built.",
      ns.Settings.aboutLine())
    ns.Data = { meta = { gameData = "1.60.1" } }
    assert.equals("Leveling Advisor 0.1.0 — GPL-3.0 — " .. SOURCES .. " Game data 1.60.1.",
      ns.Settings.aboutLine())
  end)

  it("the README names the same data sources and promises no step distance", function()
    local f = assert(io.open("README.md", "r"))
    local readme = f:read("*a")
    f:close()
    local status = readme:match("\nStatus: ([^\n]*)")
    for _, name in ipairs({ "QuestieDB Forever", "outof.games", "OpenMap", "in-game census" }) do
      assert.truthy(status:find(name, 1, true), name)
    end
    assert.falsy(readme:find("distance to the next", 1, true))
  end)

  describe("registerPanel", function()
    local LABELS = {
      "Include elite and group quests",
      "Recommend dungeons and their quests",
      "Show pins for all recommended quest givers",
      "Record quest data (local only)",
      "Show minimap button",
    }

    it("uses Settings when present and builds five labelled checkboxes", function()
      local registered = {}
      local cat = { GetID = function() return 42 end }
      local ns, _, _, created = setup({
        Settings = {
          RegisterCanvasLayoutCategory = function(frame, name) registered.frame, registered.name = frame, name; return cat end,
          RegisterAddOnCategory = function(c) registered.cat = c end,
        },
      })
      ns.Settings.set("pinsAll", false)
      local got = ns.Settings.registerPanel()
      assert.equals(cat, got)
      assert.equals(cat, registered.cat)
      assert.equals("Leveling Advisor", registered.name)
      local boxes = checkboxes(created)
      assert.equals(5, #boxes)
      for i, b in ipairs(boxes) do assert.equals(LABELS[i], b.Text.text) end
      -- OnShow reflects settings
      registered.frame.scripts.OnShow(registered.frame)
      assert.is_true(boxes[1].checked)
      assert.is_false(boxes[3].checked)
      -- clicking stores the value
      boxes[1].checked = false
      boxes[1].scripts.OnClick(boxes[1])
      assert.is_false(ns.Settings.get("elite"))
      -- about line below the checkboxes
      local found
      for _, fs in ipairs(registered.frame.fontStrings or {}) do
        if fs.text == ns.Settings.aboutLine() then found = true end
      end
      assert.is_true(found)
    end)

    it("falls back to InterfaceOptions_AddCategory when Settings is nil", function()
      local added
      local ns = setup({ InterfaceOptions_AddCategory = function(f) added = f end })
      local got = ns.Settings.registerPanel()
      assert.is_truthy(added)
      assert.equals("Leveling Advisor", added.name)
      assert.equals(added, got)
    end)

    it("returns nil without error when both are missing", function()
      local ns = setup()
      assert.is_nil(ns.Settings.registerPanel())
    end)

    it("fails soft when registration calls error", function()
      local ns = setup({ Settings = { RegisterCanvasLayoutCategory = function() error("x") end } })
      assert.is_nil(ns.Settings.registerPanel())
    end)
  end)

  describe("open", function()
    it("refuses in combat", function()
      local opened = false
      local ns, _, out = setup({
        InCombatLockdown = function() return true end,
        Settings = {
          RegisterCanvasLayoutCategory = function() return { GetID = function() return 1 end } end,
          RegisterAddOnCategory = function() end,
          OpenToCategory = function() opened = true end,
        },
      })
      ns.Settings.registerPanel()
      ns.Settings.open()
      assert.is_false(opened)
      assert.same({ "|cffffd100Leveling Advisor:|r Not in combat: try again after the fight." }, out)
    end)

    it("opens by category id", function()
      local id
      local ns = setup({
        Settings = {
          RegisterCanvasLayoutCategory = function() return { GetID = function() return 7 end } end,
          RegisterAddOnCategory = function() end,
          OpenToCategory = function(i) id = i end,
        },
      })
      ns.Settings.registerPanel()
      ns.Settings.open()
      assert.equals(7, id)
    end)

    it("falls back to the legacy opener", function()
      local opened
      local ns = setup({
        InterfaceOptions_AddCategory = function() end,
        InterfaceOptionsFrame_OpenToCategory = function(f) opened = f end,
      })
      local frame = ns.Settings.registerPanel()
      ns.Settings.open()
      assert.equals(frame, opened)
    end)
  end)
end)

describe("Settings pinStyle removal", function()
  it("is not a default and has no checkbox", function()
    local ns, _, _, created = setup()
    assert.is_nil(ns.Settings.DEFAULTS.pinStyle)
    ns.Settings.registerPanel()
    for _, b in ipairs(checkboxes(created)) do
      assert.is_nil(b.Text.text:find("Green pins", 1, true))
    end
  end)
end)
