local ui = require("spec.helpers.ui")

local function tabs(fake)
  return fake.findAll(function(w) return (w:GetName() or ""):match("^LevelingAdvisorQuestLogTab") end)
end

describe("quest log bookmark tab", function()
  it("sits below the last native side tab of QuestMapFrame", function()
    local ns, env, fake = ui.load({ state = "S18", questMap = "tabs" })
    local tab = fake.named("LevelingAdvisorQuestLogTab1")
    assert.equal(env.QuestMapFrame, tab:GetParent())
    assert.same({ 36, 40 }, { tab:GetWidth(), tab:GetHeight() })
    assert.equal(env.QuestMapFrame:GetFrameLevel() + 10, tab:GetFrameLevel())
    local p, rel, relp, x, y = tab:GetPoint(1)
    assert.same({ "TOP", env.QuestMapFrame.MapLegendTab, "BOTTOM", 0, -3 }, { p, rel, relp, x, y })
    assert.same({}, env.errors)
  end)

  it("falls back to the host's right edge when there is no world map frame", function()
    local _, env, fake = ui.load({ state = "S18", questMap = "plain" })
    local tab = fake.named("LevelingAdvisorQuestLogTab1")
    assert.same({ "TOPLEFT", env.QuestMapFrame, "TOPRIGHT", -7, -60 }, { tab:GetPoint(1) })
  end)

  it("without native tabs, tucks under WorldMapFrame's right border", function()
    local _, env, fake = ui.load({ state = "S18", questMap = "plain", worldMap = true })
    local tab = fake.named("LevelingAdvisorQuestLogTab1")
    assert.equal(env.QuestMapFrame, tab:GetParent())
    assert.same({ "TOPLEFT", env.WorldMapFrame, "TOPRIGHT", -7, -60 }, { tab:GetPoint(1) })
    assert.same({ 36, 40 }, { tab:GetWidth(), tab:GetHeight() })
    assert.is_true(tab:GetFrameLevel() < env.WorldMapFrame:GetFrameLevel())
    assert.same({}, env.errors)
  end)

  it("prefers WorldMapFrame.BorderFrame and sits below its frame level", function()
    local ns, env, fake = ui.load({ state = "S18", worldMap = true })
    env.WorldMapFrame.BorderFrame = fake.newFrame("Frame", nil, env.WorldMapFrame)
    env.WorldMapFrame.BorderFrame:SetFrameLevel(50)
    env.QuestMapFrame = fake.newFrame("Frame", "QuestMapFrame", env.UIParent)
    ns.Events.dispatch("ADDON_LOADED", "Blizzard_WorldMap")
    local tab = fake.named("LevelingAdvisorQuestLogTab1")
    assert.same({ "TOPLEFT", env.WorldMapFrame.BorderFrame, "TOPRIGHT", -7, -60 }, { tab:GetPoint(1) })
    assert.is_true(tab:GetFrameLevel() < 50)
    assert.same({}, env.errors)
  end)

  describe("close button anchor and calibration", function()
    local function withClose(opts)
      local ns, env, fake = ui.load({ state = "S18", worldMap = true })
      local wm = env.WorldMapFrame
      wm.BorderFrame = fake.newFrame("Frame", nil, wm)
      wm.BorderFrame.CloseButton = fake.newFrame("Button", nil, wm.BorderFrame)
      wm.BorderFrame.GetTop = function() return 800 end
      wm.BorderFrame.CloseButton.GetTop = function() return 795 end
      wm.BorderFrame.CloseButton.GetRight = function() return 1000.4 end
      if opts and opts.db then ns.db.window = ns.db.window or {} end
      env.QuestMapFrame = fake.newFrame("Frame", "QuestMapFrame", env.UIParent)
      ns.Events.dispatch("ADDON_LOADED", "Blizzard_WorldMap")
      return ns, env, fake, fake.named("LevelingAdvisorQuestLogTab1")
    end

    it("anchors to the close button's right at x = -6, top measured from the frame", function()
      local _, env, _, tab = withClose()
      local border = env.WorldMapFrame.BorderFrame
      assert.same({ "TOPLEFT", border.CloseButton, "TOPRIGHT", -6, -55 }, { tab:GetPoint(1) })
    end)

    local function nativeTabs(shown)
      local ns, env, fake = ui.load({ state = "S18", worldMap = true })
      local wm = env.WorldMapFrame
      wm.BorderFrame = fake.newFrame("Frame", nil, wm)
      wm.BorderFrame.CloseButton = fake.newFrame("Button", nil, wm.BorderFrame)
      env.QuestMapFrame = fake.newFrame("Frame", "QuestMapFrame", env.UIParent)
      env.QuestMapFrame.QuestsTab = fake.newFrame("Button", nil, env.QuestMapFrame)
      env.QuestMapFrame.MapLegendTab = fake.newFrame("Button", nil, env.QuestMapFrame)
      env.QuestMapFrame.QuestsTab:SetShown(shown)
      env.QuestMapFrame.MapLegendTab:SetShown(shown)
      ns.Events.dispatch("ADDON_LOADED", "Blizzard_WorldMap")
      return ns, env, fake, fake.named("LevelingAdvisorQuestLogTab1")
    end

    it("ignores hidden native tab tables and anchors to the close button", function()
      local ns, env, _, tab = nativeTabs(false)
      local close = env.WorldMapFrame.BorderFrame.CloseButton
      assert.same({ "TOPLEFT", close, "TOPRIGHT", -6, -60 }, { tab:GetPoint(1) })
      assert.matches("^anchor close button", ns.UI.QuestLogTab.describe())
    end)

    it("anchors below a shown native tab and calibrates there too", function()
      local ns, env, _, tab = nativeTabs(true)
      local legend = env.QuestMapFrame.MapLegendTab
      assert.same({ "TOP", legend, "BOTTOM", 0, -3 }, { tab:GetPoint(1) })
      assert.matches("^anchor below side tab MapLegendTab", ns.UI.QuestLogTab.describe())
      ns.Slash.handle("tab 5 -4")
      assert.same({ "TOP", legend, "BOTTOM", 5, -7 }, { tab:GetPoint(1) })
    end)

    it("switches anchor when native tabs appear later", function()
      local ns, env, _, tab = nativeTabs(false)
      env.QuestMapFrame.QuestsTab:SetShown(true)
      ns.UI.QuestLogTab.reanchor()
      assert.equal(env.QuestMapFrame.QuestsTab, (select(2, tab:GetPoint(1))))
    end)

    it("falls back to the frame's right edge without a close button", function()
      local _, env, _, tab = (function()
        local ns, env, fake = ui.load({ state = "S18", worldMap = true })
        env.QuestMapFrame = fake.newFrame("Frame", "QuestMapFrame", env.UIParent)
        ns.Events.dispatch("ADDON_LOADED", "Blizzard_WorldMap")
        return ns, env, fake, fake.named("LevelingAdvisorQuestLogTab1")
      end)()
      assert.same({ "TOPLEFT", env.WorldMapFrame, "TOPRIGHT", -7, -60 }, { tab:GetPoint(1) })
    end)

    it("applies, persists and resets the calibration offset", function()
      local ns, env, _, tab = withClose()
      local close = env.WorldMapFrame.BorderFrame.CloseButton
      ns.Slash.handle("tab 4 -2")
      assert.same({ "TOPLEFT", close, "TOPRIGHT", -2, -57 }, { tab:GetPoint(1) })
      assert.same({ x = 4, y = -2 }, ns.db.window.tabOffset)
      ns.Slash.handle("tab 1 1")
      assert.same({ x = 5, y = -1 }, ns.db.window.tabOffset)
      ns.Slash.handle("tab reset")
      assert.is_nil(ns.db.window.tabOffset)
      assert.same({ "TOPLEFT", close, "TOPRIGHT", -6, -55 }, { tab:GetPoint(1) })
    end)

    it("clamps a huge nudge and repeated nudges to +-200, and says so", function()
      local ns, env = withClose()
      ns.Slash.handle("tab 99999 -99999")
      assert.same({ x = 200, y = -200 }, ns.db.window.tabOffset)
      ns.Slash.handle("tab 50 50")
      assert.same({ x = 200, y = -150 }, ns.db.window.tabOffset)
      assert.same({}, env.errors)
      assert.is_true(ns.UI.QuestLogTab.clampedLast)
    end)

    it("reads a malformed tabOffset as 0,0", function()
      local ns = withClose()
      for _, bad in ipairs({ "x", 5, { x = "a", y = 1 }, { x = 1 }, true }) do
        ns.db.window.tabOffset = bad
        assert.same({ 0, 0 }, { ns.UI.QuestLogTab.getOffset() })
      end
    end)

    it("prints the offset and frame positions with no arguments", function()
      local ns, env = withClose()
      env.WorldMapFrame.BorderFrame.CloseButton.GetRight = function() return 1000.4 end
      local line = ns.UI.QuestLogTab.describe()
      assert.matches("tab offset 0,0", line)
      assert.matches("close button R 1000 T 795", line)
      assert.matches("QuestMapFrame R n/a T n/a", line)
      ns.Slash.handle("tab")
      assert.same({}, env.errors)
    end)

    it("re-anchors when the map frame resizes", function()
      local ns, env, _, tab = withClose()
      ns.db.window.tabOffset = { x = 3, y = 0 }
      env.WorldMapFrame.BorderFrame:GetScript("OnSizeChanged")(env.WorldMapFrame.BorderFrame)
      assert.equal(-3, select(4, tab:GetPoint(1)))
    end)
  end)

  it("uses the logo as the icon, centred in the visible part", function()
    local ns, _, fake = ui.load({ state = "S18", questMap = "plain" })
    local tab = fake.named("LevelingAdvisorQuestLogTab1")
    local logo = "Interface\\AddOns\\LevelingAdvisor\\Media\\Logo"
    assert.equal(logo, ns.UI.QuestLogTab.ICON)
    assert.equal(logo, tab.laIcon:GetTexture())
    assert.same({ 26, 26 }, { tab.laIcon:GetWidth(), tab.laIcon:GetHeight() })
    assert.same({ "CENTER", tab, "CENTER", 3, 0 }, { tab.laIcon:GetPoint(1) })
  end)

  it("uses the bookmark texture with a hover highlight and a selected border glow", function()
    local _, _, fake = ui.load({ state = "S18", questMap = "plain" })
    local tab = fake.named("LevelingAdvisorQuestLogTab1")
    local bg = fake.find(function(w)
      return w.parent == tab and type(w.texture) == "string" and w.texture:match("Media\\BookmarkTab$")
    end)
    assert.is_truthy(bg)
    assert.equal("Interface\\AddOns\\LevelingAdvisor\\Media\\BookmarkTab", bg.texture)
    assert.equal("ADD", tab.laSelected.blend)
    assert.matches("Media\\BookmarkTab$", tab.laSelected.texture)
  end)

  it("toggles the book and shows the selected glow while open", function()
    local ns, _, fake = ui.load({ state = "S18", questMap = "plain" })
    local tab = fake.named("LevelingAdvisorQuestLogTab1")
    assert.is_false(tab.laSelected:IsShown())
    fake.click(tab)
    assert.is_true(ns.UI.isShown()); assert.is_true(tab.laSelected:IsShown())
    fake.click(tab)
    assert.is_false(ns.UI.isShown()); assert.is_false(tab.laSelected:IsShown())
  end)

  it("keeps the glow in step when the book opens or closes by other means", function()
    local ns, _, fake = ui.load({ state = "S18", questMap = "plain" })
    local tab = fake.named("LevelingAdvisorQuestLogTab1")
    ns.UI.open(); assert.is_true(tab.laSelected:IsShown())
    ns.UI.close(); assert.is_false(tab.laSelected:IsShown())
  end)

  it("shows a tooltip", function()
    local _, _, fake = ui.load({ state = "S18", questMap = "plain" })
    local tab = fake.named("LevelingAdvisorQuestLogTab1")
    fake.enter(tab)
    assert.equal(tab, fake.tooltip.owner)
    assert.equal("ANCHOR_RIGHT", fake.tooltip.anchor)
    assert.equal("Leveling Advisor", fake.tooltip.lines[1][1])
    assert.equal("Open the leveling book", fake.tooltip.lines[2][1])
    assert.is_true(fake.tooltip.shown)
    fake.leave(tab)
    assert.is_false(fake.tooltip.shown)
  end)

  it("Review Focus 5: attaches when Blizzard_WorldMap loads later, once", function()
    local ns, env, fake = ui.load({ state = "S18", questMap = nil })
    assert.is_nil(fake.named("LevelingAdvisorQuestLogTab1"))
    env.QuestMapFrame = fake.newFrame("Frame")
    ns.Events.dispatch("ADDON_LOADED", "Blizzard_WorldMap")
    ns.Events.dispatch("ADDON_LOADED", "Blizzard_WorldMap")
    assert.equal(1, #tabs(fake))
  end)

  it("Review Focus 5: no host at all is silent", function()
    local ns, env, fake = ui.load({ state = "S18" })
    assert.equal(0, ns.UI.QuestLogTab.attach())
    assert.same({}, env.errors)
    assert.equal(0, #tabs(fake))
  end)

  it("attaches to QuestMapFrame only when both frames exist", function()
    local ns, env, fake = ui.load({ state = "S18", questMap = "plain", questLog = true })
    assert.equal(1, ns.UI.QuestLogTab.attach())
    assert.equal(1, #tabs(fake))
    assert.equal(env.QuestMapFrame, tabs(fake)[1]:GetParent())
  end)

  it("falls back to QuestLogFrame when QuestMapFrame does not exist", function()
    local ns, env, fake = ui.load({ state = "S18", questLog = true })
    assert.equal(1, ns.UI.QuestLogTab.attach())
    assert.equal(1, #tabs(fake))
    assert.equal(env.QuestLogFrame, tabs(fake)[1]:GetParent())
  end)

  it("registers the addon compartment entry", function()
    local ns, env, fake = ui.load({ state = "S18", compartment = true })
    local e = fake.compartment[1]
    assert.equal(1, #fake.compartment)
    assert.equal("Leveling Advisor", e.text)
    assert.equal(ns.UI.QuestLogTab.ICON, e.icon)
    assert.equal("Interface\\AddOns\\LevelingAdvisor\\Media\\Logo", e.icon)
    assert.is_true(e.notCheckable)
    e.func()
    assert.is_true(ns.UI.isShown())
    e.func()
    assert.is_false(ns.UI.isShown())
    assert.same({}, env.errors)
  end)

  it("survives a missing AddonCompartmentFrame", function()
    local ns, env = ui.load({ state = "S18" })
    assert.is_false(ns.UI.QuestLogTab.registerCompartment())
    assert.same({}, env.errors)
  end)
end)

-- 0.3.0 (dungeon-chains Task 7): the bookmark looks like the quest log's side tabs and sits in
-- their column.
describe("quest log side tab", function()
  local LOGO = "Interface\\AddOns\\LevelingAdvisor\\Media\\Logo"
  local TEMPLATE = "QuestLogTabButtonTemplate"
  local SIDE_ATLASES = { "questlog-tab-side", "questlog-tab-side-glow-hover", "questlog-tab-side-glow-select" }

  local function describeLine(ns) return ns.UI.QuestLogTab.describe() end

  -- A full left click on the client: mouse down, mouse up inside, then OnClick.
  local function press(fake, w)
    local down, up = w:GetScript("OnMouseDown"), w:GetScript("OnMouseUp")
    if down then down(w, "LeftButton") end
    if up then up(w, "LeftButton", true) end
    fake.click(w)
  end

  -- The Map & Quest Log as the client builds it: QuestMapFrame (right edge at
  -- x 1000, with SetDisplayMode) inside WorldMapFrame with a border frame and a
  -- close button. setup(env, fake, qmf) runs before Blizzard_WorldMap loads and
  -- the tab attaches.
  local function mapLog(opts, setup)
    opts = opts or {}
    opts.state, opts.worldMap = opts.state or "S18", true
    local ns, env, fake = ui.load(opts)
    local wm = env.WorldMapFrame
    wm.BorderFrame = fake.newFrame("Frame", nil, wm)
    wm.BorderFrame.CloseButton = fake.newFrame("Button", nil, wm.BorderFrame)
    local qmf = fake.newFrame("Frame", "QuestMapFrame", wm)
    qmf.GetRight = function() return 1000 end
    qmf.modes = {}
    function qmf:SetDisplayMode(mode) self.modes[#self.modes + 1] = mode end
    if setup then setup(env, fake, qmf) end
    ns.Events.dispatch("ADDON_LOADED", "Blizzard_WorldMap")
    return ns, env, fake, fake.named("LevelingAdvisorQuestLogTab1"), qmf
  end

  -- Another addon's side tab: a Button whose left edge is at the quest log's
  -- right edge (+2), 43 x 55 unless `size` says otherwise.
  local function otherTab(fake, parent, bottom, name, size)
    local b = fake.newFrame("Button", name, parent)
    b:SetSize(size and size[1] or 43, size and size[2] or 55)
    b.GetLeft = function() return 1002 end
    b.GetBottom = function() return bottom end
    return b
  end

  -- The native tabs, built from the template and hidden; MapLegendTab hangs
  -- `gap` below QuestsTab.
  local function hiddenNatives(fake, qmf, gap)
    qmf.QuestsTab = fake.newFrame("Button", nil, qmf, TEMPLATE)
    qmf.QuestsTab:SetPoint("TOPLEFT", qmf, "TOPRIGHT", -2, -30)
    qmf.MapLegendTab = fake.newFrame("Button", nil, qmf, TEMPLATE)
    qmf.MapLegendTab:SetPoint("TOP", qmf.QuestsTab, "BOTTOM", 0, gap or -3)
    qmf.QuestsTab:Hide()
    qmf.MapLegendTab:Hide()
  end

  local function anchorOf(t) return (select(2, t:GetPoint(1))) end

  -- Our tab's first texture on `layer`.
  local function region(fake, t, layer)
    return fake.find(function(w) return w.parent == t and w.kind == "Texture" and w.layer == layer end)
  end

  -- Records the template of every CreateFrame call (setup helper).
  local function recordTemplates(env)
    local seen = {}
    local create = env.CreateFrame
    env.CreateFrame = function(kind, name, parent, template)
      seen[#seen + 1] = { name = name, template = template }
      return create(kind, name, parent, template)
    end
    return seen
  end

  describe("copied from a native side tab", function()
    it("copies a hidden native tab's frame textures and size onto a plain button; the icon is our logo", function()
      local created
      local ns, env, fake, t, qmf = mapLog({ sideTabTemplate = true }, function(env, fake, qmf)
        created = recordTemplates(env)
        hiddenNatives(fake, qmf)
        qmf.QuestsTab:SetSize(44, 56)
        qmf.QuestsTab.Icon:SetAtlas("questlog-tab-icon-quest")
      end)
      for _, c in ipairs(created) do assert.is_nil(c.template, tostring(c.name)) end
      assert.is_nil(t.template)
      assert.is_nil(t.OnMouseUp) -- no template mixin on ours
      assert.equal("Button", t:GetObjectType())
      assert.equal(qmf, t:GetParent())
      assert.same({ 44, 56 }, { t:GetSize() })
      local bg = region(fake, t, "BACKGROUND")
      assert.equal("questlog-tab-side", bg:GetAtlas())
      assert.same({ "CENTER", t, "CENTER", 0, 0 }, { bg:GetPoint(1) })
      assert.equal("questlog-tab-side-glow-hover", region(fake, t, "HIGHLIGHT"):GetAtlas())
      assert.equal("questlog-tab-side-glow-select", t.laSelected:GetAtlas())
      assert.equal("OVERLAY", t.laSelected.layer)
      assert.is_false(t.laSelected:IsShown())
      assert.equal(LOGO, t.laIcon:GetTexture())
      assert.same({ 28, 28 }, { t.laIcon:GetSize() })
      assert.same({ "CENTER", t, "CENTER", -2, 0 }, { t.laIcon:GetPoint(1) }) -- the native icon's place
      assert.is_nil(fake.find(function(w) return w.parent == t and w.atlas == "questlog-tab-icon-quest" end))
      assert.equal(1, #tabs(fake))
      assert.matches("look copied%-from QuestsTab", describeLine(ns))
      assert.same({}, env.errors)
    end)

    it("sizes the logo like the native tabs' icons", function()
      local _, _, _, t = mapLog({ sideTabTemplate = true }, function(_, fake, qmf)
        hiddenNatives(fake, qmf)
        qmf.QuestsTab.Icon:SetSize(24, 24)
      end)
      assert.same({ 24, 24 }, { t.laIcon:GetSize() })
    end)

    it("copies from the next native tab when the first has nothing to copy", function()
      local ns, _, fake, t = mapLog({ sideTabTemplate = true }, function(_, fake, qmf)
        hiddenNatives(fake, qmf)
        qmf.QuestsTab = fake.newFrame("Button", nil, qmf) -- no textures
        qmf.QuestsTab:Hide()
      end)
      assert.equal("questlog-tab-side", region(fake, t, "BACKGROUND"):GetAtlas())
      assert.matches("look copied%-from MapLegendTab", describeLine(ns))
    end)

    it("copies file textures (tex coords, blend), the button's highlight texture and an unnamed glow", function()
      local ART = "Interface\\QuestFrame\\SideTab"
      local _, env, fake, t = mapLog({}, function(_, fake, qmf)
        local n = fake.newFrame("Button", nil, qmf)
        n:SetSize(40, 50)
        local bg = n:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(ART)
        bg:SetTexCoord(0, 0.5, 0, 1)
        n.Icon = n:CreateTexture(nil, "ARTWORK")
        n.Icon:SetTexture("Interface\\Icons\\Quest")
        local hl = n:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture(ART .. "Highlight")
        hl:SetBlendMode("ADD")
        n:SetHighlightTexture(hl)
        local glow = n:CreateTexture(nil, "OVERLAY")
        glow:SetPoint("CENTER")
        glow:SetSize(60, 70)
        glow:SetTexture(ART .. "Glow")
        glow:Hide()
        n:Hide()
        qmf.QuestsTab = n
      end)
      assert.same({ 40, 50 }, { t:GetSize() })
      local bg = region(fake, t, "BACKGROUND")
      assert.equal(ART, bg:GetTexture())
      assert.same({ 0, 0, 0, 1, 0.5, 0, 0.5, 1 }, bg.texCoord)
      assert.same({ { "TOPLEFT", t, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, 0 } },
        { { bg:GetPoint(1) }, { bg:GetPoint(2) } })
      local hover = region(fake, t, "HIGHLIGHT")
      assert.equal(ART .. "Highlight", hover:GetTexture())
      assert.equal("ADD", hover.blend)
      assert.equal(ART .. "Glow", t.laSelected:GetTexture())
      assert.same({ 60, 70 }, { t.laSelected:GetSize() })
      assert.equal(LOGO, t.laIcon:GetTexture())
      assert.is_nil(fake.find(function(w) return w.parent == t and w.texture == "Interface\\Icons\\Quest" end))
      assert.same({}, env.errors)
    end)

    it("a click toggles the book and never switches the quest log's display mode", function()
      local ns, env, fake, t, qmf = mapLog({ sideTabTemplate = true }, function(_, fake, qmf)
        hiddenNatives(fake, qmf)
      end)
      press(fake, t)
      assert.is_true(ns.UI.isShown())
      press(fake, t)
      assert.is_false(ns.UI.isShown())
      assert.same({}, qmf.modes)
      fake.enter(t)
      assert.equal(t, fake.tooltip.owner)
      assert.equal("ANCHOR_RIGHT", fake.tooltip.anchor)
      local lines = fake.tooltip.lines
      assert.same({ "Leveling Advisor", "Open the leveling book" }, { lines[1][1], lines[2][1] })
      fake.leave(t)
      assert.is_false(fake.tooltip.shown)
      assert.same({}, env.errors)
    end)

    it("the gold select glow follows the book, however it opens or closes", function()
      local ns, _, fake, t = mapLog({ sideTabTemplate = true }, function(_, fake, qmf)
        hiddenNatives(fake, qmf)
      end)
      assert.is_false(t.laSelected:IsShown())
      press(fake, t)
      assert.is_true(t.laSelected:IsShown())
      ns.UI.close()
      assert.is_false(t.laSelected:IsShown())
      ns.UI.open()
      assert.is_true(t.laSelected:IsShown())
    end)
  end)

  describe("without a native tab to copy", function()
    -- Native tabs that exist but carry no textures.
    local function bareNatives(fake, qmf)
      qmf.QuestsTab = fake.newFrame("Button", nil, qmf)
      qmf.QuestsTab:Hide()
    end

    it("a native tab with nothing to copy: the side-tab look from the known atlases", function()
      local ns, env, fake, t = mapLog({ atlases = SIDE_ATLASES }, function(_, fake, qmf) bareNatives(fake, qmf) end)
      assert.is_nil(t.template)
      assert.same({ 43, 55 }, { t:GetSize() })
      assert.equal("questlog-tab-side", region(fake, t, "BACKGROUND"):GetAtlas())
      assert.equal("questlog-tab-side-glow-hover", region(fake, t, "HIGHLIGHT"):GetAtlas())
      assert.equal("questlog-tab-side-glow-select", t.laSelected:GetAtlas())
      assert.equal(LOGO, t.laIcon:GetTexture())
      assert.same({ 28, 28 }, { t.laIcon:GetSize() })
      assert.is_false(t.laSelected:IsShown())
      press(fake, t)
      assert.is_true(ns.UI.isShown()); assert.is_true(t.laSelected:IsShown())
      assert.matches("look atlases", describeLine(ns))
      assert.same({}, env.errors)
    end)

    it("without the glow atlases, the background atlas tinted gold makes hover and select", function()
      local _, _, fake, t = mapLog({ atlases = { "questlog-tab-side" } })
      local hover = region(fake, t, "HIGHLIGHT")
      assert.equal("questlog-tab-side", hover:GetAtlas())
      assert.equal("ADD", hover.blend)
      assert.equal("questlog-tab-side", t.laSelected:GetAtlas())
      assert.equal("ADD", t.laSelected.blend)
    end)

    it("nothing to copy and no atlases: the bookmark, without errors", function()
      local ns, env, fake, t = mapLog({}, function(_, fake, qmf) bareNatives(fake, qmf) end)
      assert.same({ 36, 40 }, { t:GetSize() })
      assert.matches("Media\\BookmarkTab$", region(fake, t, "BACKGROUND").texture)
      assert.matches("look fallback", describeLine(ns))
      assert.same({}, env.errors)
    end)
  end)

  describe("placement in the tab column", function()
    it("below the lower of two visible side tabs of another addon; other frames do not count", function()
      local lower
      local ns, env, _, t = mapLog({ sideTabTemplate = true }, function(env, fake, qmf)
        local wm = env.WorldMapFrame
        otherTab(fake, wm, 700, "OtherAddonTab1")
        lower = otherTab(fake, wm, 642)
        otherTab(fake, qmf, 500, "TooFarLeft").GetLeft = function() return 950 end
        otherTab(fake, qmf, 400, "TooSmall", { 20, 20 })
        otherTab(fake, qmf, 300, "TooTall", { 43, 90 })
        otherTab(fake, qmf, 200, "HiddenTab"):Hide()
        otherTab(fake, qmf, 150, "SecureTab").IsProtected = function() return true end
        local plain = fake.newFrame("Frame", "NotAButton", qmf)
        plain:SetSize(43, 55)
        plain.GetLeft = function() return 1002 end
        plain.GetBottom = function() return 100 end
      end)
      assert.same({ "TOP", lower, "BOTTOM", 0, -3 }, { t:GetPoint(1) })
      assert.equal(env.QuestMapFrame:GetFrameLevel() + 10, t:GetFrameLevel())
      local line = describeLine(ns)
      assert.matches("anchor below side tab unnamed 43x55", line)
      assert.matches("side tabs OtherAddonTab1, unnamed 43x55;", line)
      assert.same({}, env.errors)
    end)

    it("a tab another addon builds from the template counts, even before it has a position", function()
      local other
      local ns, _, _, t = mapLog({ sideTabTemplate = true }, function(_, fake, qmf)
        other = fake.newFrame("Frame", "OtherQuestTab", qmf, TEMPLATE)
      end)
      assert.equal(other, anchorOf(t))
      assert.matches("anchor below side tab OtherQuestTab", describeLine(ns))
    end)

    it("no visible side tab: the first native tab's slot, with the calibration on top", function()
      local ns, env, _, t, qmf = mapLog({ sideTabTemplate = true }, function(_, fake, qmf)
        hiddenNatives(fake, qmf)
      end)
      assert.same({ "TOPLEFT", qmf, "TOPRIGHT", -2, -30 }, { t:GetPoint(1) })
      assert.matches("^anchor native slot", describeLine(ns))
      assert.matches("side tabs none", describeLine(ns))
      ns.Slash.handle("tab 3 -4")
      assert.same({ "TOPLEFT", qmf, "TOPRIGHT", 1, -34 }, { t:GetPoint(1) })
      assert.same({}, env.errors)
    end)

    it("nothing at all: the close button", function()
      local ns, env, _, t = mapLog({ sideTabTemplate = true })
      local close = env.WorldMapFrame.BorderFrame.CloseButton
      assert.equal(close, anchorOf(t))
      assert.matches("^anchor close button", describeLine(ns))
    end)

    it("native tabs shown and hidden later move it, with the gap read from their anchors", function()
      local _, _, _, t, qmf = mapLog({ sideTabTemplate = true }, function(_, fake, qmf)
        hiddenNatives(fake, qmf, -5)
      end)
      qmf.QuestsTab:Show()
      assert.same({ "TOP", qmf.QuestsTab, "BOTTOM", 0, -5 }, { t:GetPoint(1) })
      qmf.MapLegendTab:Show()
      assert.same({ "TOP", qmf.MapLegendTab, "BOTTOM", 0, -5 }, { t:GetPoint(1) })
      qmf.MapLegendTab:Hide()
      assert.equal(qmf.QuestsTab, anchorOf(t))
    end)

    it("another addon's tab that appears later: re-anchored when the quest log shows, and a frame later", function()
      local ns, env, fake, t, qmf = mapLog({ sideTabTemplate = true })
      local late = otherTab(fake, env.WorldMapFrame, 600, "LateTab")
      qmf:Hide()
      qmf:Show()
      assert.equal(late, anchorOf(t))
      local later = otherTab(fake, env.WorldMapFrame, 540, "LaterTab") -- placed in another addon's OnShow
      fake.flush()
      assert.equal(later, anchorOf(t))
      later:Hide() -- a detected tab's OnHide re-anchors
      assert.equal(late, anchorOf(t))
      assert.matches("anchor below side tab LateTab", describeLine(ns))
      assert.same({}, env.errors)
    end)

    it("re-anchors after the quest log switches its display mode", function()
      local _, _, _, t, qmf = mapLog({ sideTabTemplate = true }, function(_, fake, qmf)
        hiddenNatives(fake, qmf)
      end)
      qmf.QuestsTab.shown = true -- shown without an OnShow we could hear
      qmf:SetDisplayMode("Quests")
      assert.equal(qmf.QuestsTab, anchorOf(t))
      assert.same({ "Quests" }, qmf.modes)
    end)
  end)
end)

-- 0.3.0: "Recommended — take it" under the quest giver's quest page.
describe("quest giver ribbon", function()
  local GREEN = { 0.25, 0.75, 0.25 }
  local ns, env, fake

  local function load(opts)
    opts = opts or {}
    opts.state = opts.state or "S18"
    if opts.questFrame == nil then opts.questFrame = true end
    ns, env, fake = ui.load(opts)
    return ns, env, fake
  end

  -- The game shows quest `id` at a giver: QUEST_DETAIL, then the dialog opens.
  local function detail(id)
    fake.questID = id
    ns.Events.dispatch("QUEST_DETAIL")
    env.QuestFrame:Show()
  end

  local function ribbon() return fake.named("LevelingAdvisorGiverRibbon") end

  local function shown() local r = ribbon(); return r ~= nil and fake.visible(r) end

  local function xpOf(id)
    local s = ns.Advisor.last.state
    return ns.XP.estimate(ns.Advisor.db:quest(id), s.level, s.recordedXP)
  end

  it("a section row: shown under QuestFrame with the logo, the green line and the section", function()
    load()
    detail(4763)
    local r = ribbon()
    assert.is_true(shown())
    assert.equal(env.QuestFrame, r:GetParent())
    assert.same({ "TOP", env.QuestFrame, "BOTTOM", 0, -2 }, { r:GetPoint(1) })
    assert.same({ 260, 36 }, { r:GetSize() })
    assert.equal("Interface\\AddOns\\LevelingAdvisor\\Media\\Logo", r.laLogo:GetTexture())
    assert.same({ 20, 20 }, { r.laLogo:GetSize() })
    assert.equal("Recommended — take it", r.laTitle:GetText())
    assert.equal("GameFontNormal", r.laTitle:GetFontObject())
    assert.same(GREEN, { r.laTitle.textColor[1], r.laTitle.textColor[2], r.laTitle.textColor[3] })
    assert.equal("Right Here · ~1,700 XP", r.laReason:GetText())
    assert.equal("GameFontNormalSmall", r.laReason:GetFontObject())
    assert.same(ns.UI.Style.INK_SOFT, { r.laReason.textColor[1], r.laReason.textColor[2], r.laReason.textColor[3] })
    assert.same({}, env.errors)
  end)

  it("a step of the zone route (the frozen plan) names the step", function()
    load()
    ns.Advisor.plan(1439) -- the book or the map planned the zone
    detail(1000)
    assert.is_true(shown())
    assert.equal("Zone route step 4 · ~" .. ns.UI.Style.number(xpOf(1000)) .. " XP", ribbon().laReason:GetText())
  end)

  it("the route is never planned in the event: without a plan a route-only quest shows nothing", function()
    load({ chardb = { settings = { guide = false } } }) -- the guide plans the top zone on every result
    local route = ui.spy(ns.Engine, "route")
    detail(1000)
    assert.equal(0, route.n)
    assert.is_false(shown())
  end)

  it("a pickup for the recommended dungeon", function()
    load({ state = "S22" }) -- BFD's quests are orange at 20 and fit from 22
    detail(6922)
    assert.is_true(shown())
    assert.equal("Blackfathom Deeps: pick up before you go · ~" .. ns.UI.Style.number(xpOf(6922)) .. " XP",
      ribbon().laReason:GetText())
  end)

  it("no XP part when the XP is not known", function()
    load()
    for _, row in ipairs(ns.Advisor.last.rec.sections[2].rows) do row.xp = 0 end
    detail(4763)
    assert.equal("Right Here", ribbon().laReason:GetText())
  end)

  it("a quest that is not recommended shows nothing, and a turn-in row is no pickup", function()
    load()
    detail(6382)
    assert.is_false(shown())
    detail(4730) -- Ready to Turn In (in the log)
    assert.is_false(shown())
    assert.same({}, env.errors)
  end)

  it("only an eligible row counts: a class quest you are too low for (soon) shows nothing", function()
    load()
    local row = fake.row(5061)
    assert.is_false(row.soon)
    detail(5061)
    assert.is_true(shown())
    load({ patch = function(data) data.quests[5061][5], data.quests[5061][6] = 19, 19 end })
    row = fake.row(5061)
    assert.is_true(row.soon) -- the soon class quest is listed in Later
    detail(5061)
    assert.is_false(shown())
    assert.same({}, env.errors)
  end)

  -- Level fit (0.3.0): the Later section lists quests too high for now; none is a recommendation.
  it("a row of the Later section shows nothing (991 is orange at 18)", function()
    load()
    local row = fake.row(991)
    assert.is_true(row.later)
    assert.same({ "available", false }, { row.state, row.soon }) -- it could be picked up
    detail(991)
    assert.is_false(shown())
    assert.same({}, env.errors)
  end)

  it("a later page of another quest hides the ribbon of the earlier one", function()
    load()
    detail(4763)
    assert.is_true(shown())
    detail(6382)
    assert.is_false(shown())
  end)

  it("the setting off shows nothing and hides a shown ribbon", function()
    load()
    detail(4763)
    ns.Settings.set("giverRibbon", false)
    assert.is_false(shown())
    detail(4763)
    assert.is_false(shown())
    ns.Settings.set("giverRibbon", true)
    detail(4763)
    assert.is_true(shown())
  end)

  it("hides on QUEST_FINISHED, the other quest pages and QuestFrame's OnHide", function()
    load()
    for _, event in ipairs({ "QUEST_FINISHED", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_GREETING" }) do
      detail(4763)
      assert.is_true(shown(), event)
      ns.Events.dispatch(event)
      assert.is_false(ribbon():IsShown(), event)
    end
    detail(4763)
    env.QuestFrame:Hide()
    assert.is_false(ribbon():IsShown())
    env.QuestFrame:Show()
    assert.is_false(shown())
    assert.same({}, env.errors)
  end)

  it("a stale result shows nothing: the quest is in the log or done, or the level changed", function()
    load()
    ns.Advisor.last.state.log[4763] = { complete = false }
    detail(4763)
    assert.is_false(shown())
    ns.Advisor.last.state.log[4763] = nil
    ns.Advisor.last.state.completed[4763] = true
    detail(4763)
    assert.is_false(shown())
    ns.Advisor.last.state.completed[4763] = nil
    env.UnitLevel = function() return 19 end
    detail(4763)
    assert.is_false(shown())
    env.UnitLevel = function() return 18 end
    detail(4763)
    assert.is_true(shown())
  end)

  it("without a result it asks for a compute later (never in the event) and shows the ribbon then", function()
    load()
    ns.Advisor.last = nil
    local compute = ui.spy(ns.Advisor, "compute")
    -- the scheduler calls the run function it was given at init; count the engine instead
    local engine = ui.spy(ns.Engine, "compute")
    detail(4763)
    assert.is_false(shown())
    assert.equal(0, engine.n)
    fake.flush()
    assert.equal(1, engine.n)
    assert.is_true(shown())
    assert.equal("Right Here · ~1,700 XP", ribbon().laReason:GetText())
    -- the dialog moved on before the compute finished: nothing shows
    ns.Advisor.last = nil
    detail(4763)
    ns.Events.dispatch("QUEST_FINISHED")
    env.QuestFrame:Hide()
    fake.flush()
    assert.is_false(ribbon():IsShown())
    assert.equal(0, compute.n)
    assert.same({}, env.errors)
  end)

  it("no QuestFrame or no GetQuestID: no error and no ribbon", function()
    load({ questFrame = false })
    fake.questID = 4763
    ns.Events.dispatch("QUEST_DETAIL")
    ns.Events.dispatch("QUEST_FINISHED")
    assert.is_nil(ribbon())
    load({ without = { "GetQuestID" } })
    ns.Events.dispatch("QUEST_DETAIL")
    assert.is_nil(ribbon())
    assert.same({}, env.errors)
  end)
end)
