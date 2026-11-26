local ui = require("spec.helpers.ui")

local PREFIX = "|cffffd100Leveling Advisor:|r "
local NO_DATA = "No quest data loaded. Run the data pipeline and /reload."
local LOADING = "Working out your recommendations…"

local function frameOf(fake) return fake.named("LevelingAdvisorFrame") end

local function under(w, ancestor)
  while w do
    if w == ancestor then return true end
    w = w:GetParent()
  end
  return false
end

local function contains(lines, needle)
  for _, l in ipairs(lines) do
    if l:find(needle, 1, true) then return true end
  end
  return false
end

describe("book window", function()
  it("builds one ButtonFrameTemplate window on first toggle", function()
    local ns, env, fake = ui.load({ state = "S18" })
    assert.is_nil(frameOf(fake))
    ns.UI.toggle()
    local f = frameOf(fake)
    assert.equal(f, ns.UI.frame)
    assert.equal("ButtonFrameTemplate", f.template)
    assert.equal("Leveling Advisor", f.title)
    assert.equal("player", f.portraitUnit)
    assert.same({ 860, 620 }, { f:GetWidth(), f:GetHeight() })
    assert.is_true(f:IsShown())
    assert.is_true(ns.UI.isShown())
    assert.equal("HIGH", f.strata)
    assert.is_true(f.toplevel)
    assert.is_true(f.movable)
    assert.is_true(f.clamped)
    assert.same({ "LeftButton" }, f.drag)
    assert.same({ "LevelingAdvisorFrame" }, env.UISpecialFrames)
    ns.UI.toggle()
    assert.is_false(f:IsShown())
    assert.is_false(ns.UI.isShown())
    ns.UI.toggle()
    assert.is_true(f:IsShown())
    assert.equal(1, #fake.findAll(function(w) return w:GetName() == "LevelingAdvisorFrame" end))
    assert.same({ "LevelingAdvisorFrame" }, env.UISpecialFrames)
    assert.same({}, env.errors)
  end)

  it("open, close and the close button", function()
    local ns, _, fake = ui.load({ state = "S18" })
    assert.is_false(ns.UI.isShown())
    ns.UI.close() -- before the first build: nothing to do, no error
    ns.UI.open()
    local f = frameOf(fake)
    assert.is_true(f:IsShown())
    ns.UI.open()
    assert.is_true(f:IsShown())
    fake.click(f.CloseButton)
    assert.is_false(ns.UI.isShown())
    ns.UI.open()
    ns.UI.close()
    assert.is_false(f:IsShown())
  end)

  it("raises itself on show", function()
    local ns, _, fake = ui.load({ state = "S18" })
    ns.UI.open()
    assert.is_true((frameOf(fake).raised or 0) >= 1)
  end)

  it("tells the advisor when it is shown and hidden", function()
    local ns, env = ui.load({ state = "S18" })
    local spy = ui.spy(ns.Advisor, "setWindowShown")
    ns.UI.toggle()
    ns.UI.toggle()
    assert.equal(2, spy.n)
    assert.same({ true, false }, { spy.calls[1][1], spy.calls[2][1] })
    assert.same({}, env.errors)
  end)

  it("opens at the centre on the first run", function()
    local ns, env, fake = ui.load({ state = "S18" })
    assert.same({}, ns.db.window) -- Init.migrate always makes the table
    ns.UI.open()
    assert.same({ "CENTER", env.UIParent, "CENTER", 0, 0 }, { frameOf(fake):GetPoint(1) })
  end)

  it("saves its position on drag stop and restores it", function()
    local ns, env, fake = ui.load({ state = "S18" })
    ns.UI.open()
    local f = frameOf(fake)
    f:GetScript("OnDragStart")(f)
    assert.is_true(f.moving)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 120, -80)
    f:GetScript("OnDragStop")(f)
    assert.is_false(f.moving)
    assert.same({ point = "TOPLEFT", relPoint = "TOPLEFT", x = 120, y = -80 }, ns.db.window)

    local ns2, env2, fake2 = ui.load({ state = "S18", db = { window = ns.db.window } })
    ns2.UI.open()
    local f2 = frameOf(fake2)
    assert.equal(1, f2:GetNumPoints())
    assert.same({ "TOPLEFT", env2.UIParent, "TOPLEFT", 120, -80 }, { f2:GetPoint(1) })
  end)

  it("ignores a saved window table without a point", function()
    local ns, env, fake = ui.load({ state = "S18", db = { window = { x = 5 } } })
    ns.UI.open()
    assert.same({ "CENTER", env.UIParent, "CENTER", 0, 0 }, { frameOf(fake):GetPoint(1) })
  end)

  describe("book", function()
    it("has a leather backdrop and two parchment pages with spine shadows", function()
      local ns, _, fake = ui.load({ state = "S18" })
      ns.UI.open()
      local f = frameOf(fake)
      local book, pages = f.laBook, f.laPages
      assert.same({ "TOPLEFT", f, "TOPLEFT", 8, -62 }, { book:GetPoint(1) })
      assert.same({ "BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 34 }, { book:GetPoint(2) })
      local S = ns.UI.Style
      assert.same({ S.LEATHER[1], S.LEATHER[2], S.LEATHER[3], 1 }, book.laBackdrop.color)
      for _, side in ipairs({ "left", "right" }) do
        local p = pages[side]
        assert.equal(418, p:GetWidth())
        assert.equal("QuestBG-Parchment", p.parchment:GetAtlas())
        assert.equal(24, p.spine:GetWidth())
        assert.equal("HORIZONTAL", p.spine.gradient[1])
        assert.same({ 0, 0, 0, 0.35 }, p.spine.color)
        assert.equal(S.CONTENT_W, p.content:GetWidth())
        assert.same({ "TOPLEFT", p, "TOPLEFT", S.PAGE_PAD, -S.PAGE_PAD }, { p.content:GetPoint(1) })
      end
      assert.same({ "TOPLEFT", book, "TOPLEFT", 0, 0 }, { pages.left:GetPoint(1) })
      assert.same({ "TOPRIGHT", book, "TOPRIGHT", 0, 0 }, { pages.right:GetPoint(1) })
      -- the shadow darkens towards the spine: the left page's right edge, the right page's left edge
      assert.equal("RIGHT", (pages.left.spine:GetPoint(1)):match("RIGHT"))
      assert.equal("LEFT", (pages.right.spine:GetPoint(1)):match("LEFT"))
      assert.equal(0, pages.left.spine.gradient[2].a)
      assert.is_true(pages.left.spine.gradient[3].a > 0)
      assert.is_true(pages.right.spine.gradient[2].a > 0)
      assert.equal(0, pages.right.spine.gradient[3].a)
    end)

    it("falls back to the parchment file and a flat spine shadow", function()
      local ns, env, fake = ui.load({ state = "S18", noAtlas = true, without = { "CreateColor" } })
      ns.UI.open()
      local p = frameOf(fake).laPages.left
      assert.equal("Interface\\QuestFrame\\QuestBG", p.parchment:GetTexture())
      assert.is_nil(p.spine.gradient)
      assert.same({ 0, 0, 0, 0.25 }, p.spine.color)
      assert.same({}, env.errors)
    end)

    it("hides the button bar and the inset", function()
      local ns, _, fake = ui.load({ state = "S18", globals = {
        ButtonFrameTemplate_HideButtonBar = function(frame) frame.buttonBarHidden = true end,
      } })
      ns.UI.open()
      local f = frameOf(fake)
      assert.is_true(f.buttonBarHidden)
      assert.is_false(f.Inset:IsShown())
    end)
  end)

  describe("footer", function()
    it("mirrors the elite and dungeons settings", function()
      local ns, env, fake = ui.load({ state = "S18" })
      ns.UI.open()
      local elite = fake.text("Elite quests"):GetParent()
      local dungeons = fake.text("Dungeons"):GetParent()
      assert.equal("UICheckButtonTemplate", elite.template)
      assert.equal("UICheckButtonTemplate", dungeons.template)
      assert.is_true(fake.visible(elite))
      assert.is_true(elite:GetChecked())
      assert.is_true(dungeons:GetChecked())
      local _, _, _, x1 = elite:GetPoint(1)
      local _, _, _, x2 = dungeons:GetPoint(1)
      assert.equal(140, x2 - x1)

      fake.click(elite)
      assert.is_false(ns.Settings.get("elite"))
      assert.is_false(elite:GetChecked())
      fake.click(elite)
      assert.is_true(ns.Settings.get("elite"))

      ns.Settings.set("dungeons", false)
      assert.is_false(dungeons:GetChecked())
      ns.Settings.set("dungeons", true)
      assert.is_true(dungeons:GetChecked())
      assert.same({}, env.errors)
    end)

    it("starts from the saved settings", function()
      local ns, _, fake = ui.load({ state = "S18", db = { settings = { elite = false } } })
      ns.UI.open()
      assert.is_false(fake.text("Elite quests"):GetParent():GetChecked())
      assert.is_true(fake.text("Dungeons"):GetParent():GetChecked())
    end)

    it("shows the game data version and the about line on hover", function()
      local ns, _, fake = ui.load({ state = "S18" })
      ns.UI.open()
      local v = fake.text("Game data 1.60.1")
      assert.truthy(v)
      assert.is_true(fake.visible(v))
      fake.enter(v)
      assert.equal(v, fake.tooltip.owner)
      assert.is_true(fake.tooltip.shown)
      assert.equal("Leveling Advisor", fake.tooltip.lines[1][1])
      assert.equal(ns.Settings.aboutLine(), fake.tooltip.lines[2][1])
      fake.leave(v)
      assert.is_false(fake.tooltip.shown)
    end)

    it("says Game data not built without meta", function()
      local ns, _, fake = ui.load({ noData = true })
      ns.UI.open()
      assert.truthy(fake.text("Game data not built"))
    end)
  end)

  describe("gear", function()
    it("opens the settings, and refuses in combat", function()
      local ns, env, fake = ui.load({ state = "S18" })
      ns.UI.open()
      local f = frameOf(fake)
      local gear = f.laGear
      assert.same({ 20, 20 }, { gear:GetWidth(), gear:GetHeight() })
      local p, rel, relP = gear:GetPoint(1)
      assert.same({ "RIGHT", f.CloseButton, "LEFT" }, { p, rel, relP })
      assert.equal("QuestLog-icon-setting", gear.laIcon:GetAtlas())
      fake.enter(gear)
      assert.equal("Settings", fake.tooltip.lines[1][1])

      local open = ui.spy(ns.Settings, "open")
      fake.click(gear)
      assert.equal(1, open.n)

      fake.combat(true)
      fake.click(gear)
      assert.equal(2, open.n)
      assert.equal(PREFIX .. "Not in combat: try again after the fight.", fake.out[#fake.out])
      assert.same({}, env.errors)
    end)

    it("uses the options button file without the atlas", function()
      local ns, _, fake = ui.load({ state = "S18", noAtlas = true })
      ns.UI.open()
      assert.equal("Interface\\Buttons\\UI-OptionsButton", frameOf(fake).laGear.laIcon:GetTexture())
    end)
  end)

  describe("status", function()
    it("shows the no-data message on the right page", function()
      local ns, env, fake = ui.load({ noData = true })
      ns.UI.open()
      local t = fake.text(NO_DATA)
      assert.truthy(t)
      assert.is_true(fake.visible(t))
      assert.is_true(under(t, frameOf(fake).laPages.right))
      assert.equal("no-data", ns.UI.context().status)
      assert.same({}, env.errors)
    end)

    it("shows the data load error instead of the no-data text", function()
      local ns, _, fake = ui.load({ state = "S18" })
      ns.Advisor.db, ns.Advisor.loadError = nil, "boom"
      ns.UI.open()
      local t = fake.text("Quest data failed to load: boom")
      assert.is_true(fake.visible(t))
    end)

    it("shows the loading message before the first compute", function()
      local ns, env, fake = ui.load({})
      ns.UI.open()
      assert.equal("loading", ns.UI.context().status)
      local t = fake.text(LOADING)
      assert.is_true(fake.visible(t))
      assert.is_true(under(t, frameOf(fake).laPages.right))
      assert.same({}, env.errors)
    end)

    it("hides the message once the advisor has a result", function()
      local ns, _, fake = ui.load({})
      ns.UI.open()
      assert.truthy(fake.text(LOADING))
      fake.setState("S18")
      assert.is_nil(fake.text(LOADING))
    end)
  end)

  describe("views", function()
    local ns, env, fake, f
    before_each(function()
      ns, env, fake = ui.load({ state = "S18" })
    end)

    local function register(_, kind, title)
      local v = { builds = 0, updates = {} }
      ns.UI.registerView(kind, {
        build = function(left, right)
          v.builds = v.builds + 1
          v.leftParent, v.rightParent = left, right
          v.left = fake.newFrame("Frame", nil, left)
          v.right = fake.newFrame("Frame", nil, right)
          return v.left, v.right
        end,
        title = title and function() return title end or nil,
        update = function(view, ctx) v.updates[#v.updates + 1] = { view = view, ctx = ctx } end,
      })
      return v
    end

    it("renders a registered view, titles the window and goes back", function()
      local v = register(ns, "test", "Darkshore")
      ns.UI.open()
      f = frameOf(fake)
      ns.UI.show({ kind = "test", mapID = 1439 })
      assert.equal("Leveling Advisor — Darkshore", f.title)
      assert.equal(1, #v.updates)
      assert.equal(1439, v.updates[1].view.mapID)
      assert.equal("ok", v.updates[1].ctx.status)
      assert.equal(ns.Advisor.last.rec, v.updates[1].ctx.rec)
      assert.equal(ns.Advisor.last.state, v.updates[1].ctx.state)
      assert.equal(ns.Advisor.db, v.updates[1].ctx.db)
      assert.equal(ns.Advisor.last, v.updates[1].ctx.last)
      assert.equal(f.laPages.left.content, v.leftParent)
      assert.equal(f.laPages.right.content, v.rightParent)
      assert.is_true(fake.visible(v.left))
      assert.is_true(fake.visible(v.right))
      assert.equal("test", ns.UI.current().kind)

      ns.UI.back()
      assert.equal("main", ns.UI.current().kind)
      assert.equal("Leveling Advisor", f.title)
      assert.is_false(fake.visible(v.left))
      assert.is_false(fake.visible(v.right))
      assert.same({}, env.errors)
    end)

    it("builds each kind once and hides the roots of other kinds", function()
      local a = register(ns, "a")
      local b = register(ns, "b")
      ns.UI.show({ kind = "a" })
      ns.UI.show({ kind = "b" })
      ns.UI.show({ kind = "a" })
      assert.equal(1, a.builds)
      assert.equal(1, b.builds)
      assert.is_true(fake.visible(a.left))
      assert.is_false(fake.visible(b.left))
      assert.is_false(fake.visible(b.right))
      assert.equal("Leveling Advisor", frameOf(fake).title) -- no title function
    end)

    it("back pops the stack, and an empty stack gives main", function()
      register(ns, "a")
      register(ns, "b")
      ns.UI.show({ kind = "a", mapID = 1 })
      ns.UI.show({ kind = "b", mapID = 2 })
      ns.UI.back()
      assert.same({ kind = "a", mapID = 1 }, ns.UI.current())
      ns.UI.back()
      assert.equal("main", ns.UI.current().kind)
      ns.UI.back()
      assert.same({ kind = "main" }, ns.UI.current())
    end)

    it("show opens a closed book", function()
      local v = register(ns, "test")
      assert.is_false(ns.UI.isShown())
      ns.UI.show({ kind = "test" })
      assert.is_true(ns.UI.isShown())
      assert.is_true(fake.visible(v.right))
      ns.UI.back()
      assert.equal("main", ns.UI.current().kind)
    end)

    it("select sets the quest, drops the source and re-renders", function()
      local v = register(ns, "test")
      ns.UI.show({ kind = "test", mapID = 1439, questID = 1, source = { section = "here" } })
      ns.UI.select(4763)
      assert.equal(4763, ns.UI.current().questID)
      assert.is_nil(ns.UI.current().source)
      assert.equal(1439, ns.UI.current().mapID)
      assert.equal(2, #v.updates)
      assert.equal(4763, v.updates[2].view.questID)
    end)

    it("shows Not available yet. for an unregistered view", function()
      local v = register(ns, "test")
      ns.UI.show({ kind = "test" })
      ns.UI.show({ kind = "nope" })
      local t = fake.text("Not available yet.")
      assert.truthy(t)
      assert.is_true(fake.visible(t))
      assert.is_false(fake.visible(v.left))
      assert.equal("Leveling Advisor", frameOf(fake).title)
      ns.UI.back()
      assert.is_false(fake.visible(t))
      assert.is_true(fake.visible(v.left))
      assert.same({}, env.errors)
    end)

    it("hides the view while there is no data", function()
      local v = register(ns, "test")
      ns.UI.show({ kind = "test" })
      ns.Advisor.db = nil
      ns.UI.refresh()
      assert.is_false(fake.visible(v.left))
      assert.is_true(fake.visible(fake.text(NO_DATA)))
      assert.equal(1, #v.updates)
    end)

    it("a failing view reports the error and leaves the window usable", function()
      ns.UI.registerView("broken", {
        build = function(l, r) return fake.newFrame("Frame", nil, l), fake.newFrame("Frame", nil, r) end,
        update = function() error("view boom", 0) end,
      })
      ns.UI.show({ kind = "broken" })
      assert.same({ "view boom" }, env.errors)
      ns.UI.back()
      assert.equal("main", ns.UI.current().kind)
      ns.UI.toggle()
      assert.is_false(ns.UI.isShown())
    end)

    it("refreshes on advisor updates only while shown", function()
      local v = register(ns, "test")
      ns.UI.show({ kind = "test" })
      local n = #v.updates
      ns.Advisor.compute()
      assert.equal(n + 1, #v.updates)
      ns.UI.close()
      ns.Advisor.compute()
      ns.UI.refresh()
      assert.equal(n + 1, #v.updates)
      assert.same({}, env.errors)
    end)

    it("onBuild runs once after the build, or at once when built", function()
      local seen = {}
      ns.UI.onBuild(function(frame) seen[#seen + 1] = frame end)
      assert.same({}, seen)
      ns.UI.open()
      local f1 = frameOf(fake)
      assert.same({ f1 }, seen)
      ns.UI.toggle(); ns.UI.toggle()
      assert.equal(1, #seen)
      ns.UI.onBuild(function(frame) seen[#seen + 1] = frame end)
      assert.same({ f1, f1 }, seen)
    end)
  end)

  it("Review Focus 1: opens in combat with the last result and computes nothing", function()
    local ns, env, fake = ui.load({ state = "S18" })
    fake.combat(true)
    local before = ns.Advisor.computes
    ns.UI.toggle()
    fake.flush()
    local f = frameOf(fake)
    assert.is_true(f:IsShown())
    assert.equal(before, ns.Advisor.computes)
    assert.equal("ok", ns.UI.context().status)
    assert.is_nil(fake.text(LOADING))
    assert.same({}, env.errors)
  end)

  describe("slash and key binding", function()
    it("/advisor toggles the book", function()
      local _, env, fake = ui.load({ state = "S18" })
      env.SlashCmdList.LEVELINGADVISOR("")
      assert.is_true(frameOf(fake):IsShown())
      env.SlashCmdList.LEVELINGADVISOR("")
      assert.is_false(frameOf(fake):IsShown())
    end)

    it("/advisor summary prints the chat summary", function()
      local _, env, fake, out = ui.load({ state = "S18" })
      env.SlashCmdList.LEVELINGADVISOR("summary")
      assert.is_true(contains(out, "Zones:"))
      assert.equal(out, fake.out)
      local f = frameOf(fake)
      assert.is_true(f == nil or not f:IsShown())
    end)

    it("help lists the book and the summary", function()
      local _, env, _, out = ui.load({ state = "S18" })
      env.SlashCmdList.LEVELINGADVISOR("help")
      assert.is_true(contains(out, "  /advisor — open the advisor book"))
      assert.is_true(contains(out, "  /advisor summary — recommendations in chat"))
    end)

    it("defines the key binding globals", function()
      local _, env, fake = ui.load({ state = "S18" })
      assert.equal("Leveling Advisor", env.BINDING_HEADER_LEVELINGADVISOR)
      assert.equal("Toggle Leveling Advisor", env.BINDING_NAME_LEVELINGADVISOR_TOGGLE)
      env.LevelingAdvisor_Toggle()
      assert.is_true(frameOf(fake):IsShown())
      env.LevelingAdvisor_Toggle()
      assert.is_false(frameOf(fake):IsShown())
    end)
  end)

  describe("files", function()
    local function read(path)
      local f = assert(io.open(path, "r"))
      local s = f:read("*a")
      f:close()
      return s
    end

    it("Templates.xml and Bindings.xml are well-formed XML", function()
      local r = os.execute("xmllint --noout LevelingAdvisor/UI/Templates.xml LevelingAdvisor/Bindings.xml")
      assert.is_true(r == 0 or r == true)
    end)

    it("Templates.xml defines the list row template", function()
      local s = read("LevelingAdvisor/UI/Templates.xml")
      assert.truthy(s:find('<Button name="LevelingAdvisorListRowTemplate" virtual="true">', 1, true))
      assert.truthy(s:find('<Size x="382" y="44"/>', 1, true))
      assert.falsy(s:find("<Scripts>", 1, true))
    end)

    it("Bindings.xml is exactly the toggle binding", function()
      assert.equal(table.concat({
        "<Bindings>",
        '  <Binding name="LEVELINGADVISOR_TOGGLE" header="LEVELINGADVISOR" category="ADDONS">',
        "    LevelingAdvisor_Toggle()",
        "  </Binding>",
        "</Bindings>",
        "",
      }, "\n"), read("LevelingAdvisor/Bindings.xml"))
    end)

    it("the TOC lists every UI file after MapPins, in load order", function()
      local ui_files = {}
      for line in read("LevelingAdvisor/LevelingAdvisor.toc"):gmatch("[^\n]+") do
        if line:match("^UI\\") then ui_files[#ui_files + 1] = line end
      end
      assert.same({
        "UI\\MapPins.lua", "UI\\MapPins.xml", "UI\\Style.lua", "UI\\Templates.xml", "UI\\Window.lua",
        "UI\\List.lua", "UI\\ZoneArt.lua", "UI\\QuestInfo.lua", "UI\\Model.lua", "UI\\Nav.lua",
        "UI\\Items.lua", "UI\\Menu.lua", "UI\\QuestRow.lua", "UI\\MiniMap.lua", "UI\\QuestDetail.lua",
        "UI\\MainView.lua", "UI\\RouteView.lua", "UI\\Search.lua", "UI\\QuestLogTab.lua",
      }, ui_files)
      assert.falsy(read("LevelingAdvisor/LevelingAdvisor.toc"):find("Bindings.xml", 1, true))
    end)

    it("every stub module exists in ns.UI", function()
      local ns = ui.load({ noData = true })
      for _, name in ipairs({ "List", "ZoneArt", "QuestInfo", "Model", "Nav", "Items", "Menu",
          "QuestRow", "MiniMap", "QuestDetail", "MainView", "RouteView", "Search", "QuestLogTab" }) do
        assert.is_table(ns.UI[name], name)
      end
    end)
  end)
end)
