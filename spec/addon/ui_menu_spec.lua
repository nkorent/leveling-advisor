local ui = require("spec.helpers.ui")

describe("quest menu, Link to Chat and Ignore", function()
  local ns, env, fake, db, state, Menu
  local LINK = "|cffffff00|Hquest:4763:18|h[The Blackwood Corrupted]|h|r"

  local function load(opts)
    opts = opts or {}
    opts.state = opts.state or "S18"
    ns, env, fake = ui.load(opts)
    db, state, Menu = ns.Advisor.db, ns.Advisor.last.state, ns.UI.Menu
  end
  local function labels(e) local t = {} for i, x in ipairs(e) do t[i] = x.label end return t end
  local function button(label)
    for _, b in ipairs(fake.menu.buttons) do if b.label == label then return b end end
  end

  it("entries", function()
    load()
    local order = { "Show on Map", "Link to Chat", "Ignore This Quest", "Cancel" }
    assert.same(order, labels(Menu.entries(4763)))
    ns.chardb.ignored[4763] = true
    order[3] = "Stop Ignoring This Quest"
    assert.same(order, labels(Menu.entries(4763)))
    assert.equal("unignore", Menu.entries(4763)[3].action)
  end)

  it("right-click on a row opens the native menu with the quest title", function()
    load()
    ns.UI.open()
    local f = fake.rowFrame(4763)
    fake.click(f, "RightButton")
    assert.equal("The Blackwood Corrupted", fake.menu.title)
    assert.same({ "Show on Map", "Link to Chat", "Ignore This Quest", "Cancel" }, labels(fake.menu.buttons))
    assert.equal(f, fake.menu.owner)
    assert.same({ "LeftButtonUp", "RightButtonUp" }, f.clicks)
    assert.same({}, env.errors)
  end)

  it("Show on Map runs Nav.showQuest", function()
    load()
    local spy = ui.spy(ns.UI.Nav, "showQuest", function() return true end)
    Menu.open(fake.newFrame("Frame"), 4763)
    button("Show on Map").fn()
    assert.equal(4763, spy.calls[1][1])
  end)

  it("Ignore This Quest ignores, recomputes and says how to undo", function()
    load()
    local spy = ui.spy(ns.Advisor.scheduler, "request")
    Menu.open(fake.newFrame("Frame"), 4763)
    button("Ignore This Quest").fn()
    assert.is_true(ns.chardb.ignored[4763])
    assert.equal("settings", spy.calls[1][2])
    assert.truthy(fake.out[#fake.out]:find("Ignoring The Blackwood Corrupted. Type /advisor unignore 4763 to undo.", 1, true))
    Menu.open(fake.newFrame("Frame"), 4763)
    button("Stop Ignoring This Quest").fn()
    assert.is_nil(ns.chardb.ignored[4763])
    assert.equal(2, #spy.calls)
    assert.truthy(fake.out[#fake.out]:find("No longer ignoring The Blackwood Corrupted.", 1, true))
  end)

  it("Menu and Slash share Slash.setIgnored", function()
    load()
    ns.Slash.setIgnored(4763, true)
    assert.is_true(ns.chardb.ignored[4763])
    ns.Slash.setIgnored(4763, false)
    assert.is_nil(ns.chardb.ignored[4763])
  end)

  it("quest link falls back to a built link", function()
    load()
    assert.equal(LINK, Menu.questLink(db, 4763))
    assert.is_nil(Menu.questLink(db, 999999))
    fake.questLink = "|Hquest:4763:18|h[Game Link]|h"
    assert.equal("|Hquest:4763:18|h[Game Link]|h", Menu.questLink(db, 4763))
  end)

  it("link attempts stop at the first that works", function()
    load()
    fake.chat.insertLink = true
    assert.is_true(Menu.linkQuest(4763))
    assert.same({ { "ChatFrameUtil.InsertLink", true } }, Menu.lastLink)
    assert.equal(1, #fake.chat.calls)

    fake.chat.insertLink, fake.chat.calls = false, {}
    assert.is_true(Menu.linkQuest(4763))
    assert.same({ { "ChatFrameUtil.InsertLink", false }, { "ChatEdit_InsertLink", false },
      { "ChatFrameUtil.OpenChat", "ran" } }, Menu.lastLink)
    assert.same({ "OpenChat", LINK }, fake.chat.calls[3])
  end)

  it("ChatEdit_InsertLink is the last insert and a false return is a failure", function()
    load()
    fake.chat.edit = true
    assert.is_true(Menu.linkQuest(4763))
    assert.same({ { "ChatFrameUtil.InsertLink", false }, { "ChatEdit_InsertLink", true } }, Menu.lastLink)
  end)

  it("an open chat box takes the link before the unproven ChatEdit_InsertLink", function()
    local inserted = {}
    local box = { Insert = function(_, l) inserted[#inserted + 1] = l end }
    load({ globals = { ChatEdit_GetActiveWindow = function() return box end } })
    assert.is_true(Menu.linkQuest(4763))
    assert.same({ LINK }, inserted)
    assert.same({ { "ChatFrameUtil.InsertLink", false }, { "ChatEdit_GetActiveWindow", "ran" } }, Menu.lastLink)
    assert.equal(0, #fake.chat.calls - 1)
  end)

  it("a closed chat box is activated, then the link inserted", function()
    local inserted, activated = {}, {}
    local box = { Insert = function(_, l) inserted[#inserted + 1] = l end }
    load({ globals = {
      ChatEdit_GetActiveWindow = function() return nil end,
      ChatEdit_ChooseBoxForSend = function() return box end,
      ChatEdit_ActivateChat = function(b) activated[#activated + 1] = b end,
    } })
    assert.is_true(Menu.linkQuest(4763))
    assert.same({ box }, activated)
    assert.same({ LINK }, inserted)
    assert.same({ { "ChatFrameUtil.InsertLink", false }, { "ChatEdit_GetActiveWindow", false },
      { "ChatEdit_ActivateChat", "ran" } }, Menu.lastLink)
  end)

  it("nothing available says the link in chat and returns false", function()
    load({ without = { "ChatFrameUtil", "ChatEdit_InsertLink", "ChatFrame_OpenChat" } })
    assert.is_false(Menu.linkQuest(4763))
    assert.same({}, Menu.lastLink)
    assert.truthy(fake.out[#fake.out]:find("Quest link: " .. LINK, 1, true))
  end)

  it("ChatFrame_OpenChat is the last resort", function()
    load({ without = { "ChatFrameUtil" } })
    assert.is_true(Menu.linkQuest(4763))
    assert.same({ { "ChatEdit_InsertLink", false }, { "ChatFrame_OpenChat", "ran" } }, Menu.lastLink)
  end)

  it("Shift-click on a row links instead of opening", function()
    load()
    ns.UI.open()
    local show = ui.spy(ns.UI, "show")
    local link = ui.spy(Menu, "linkQuest", function() return true end)
    fake.modifier = "CHATLINK"
    fake.click(fake.rowFrame(4763))
    assert.equal(4763, link.calls[1][1])
    assert.equal(0, #show.calls)
  end)

  it("route lines and the detail title have the menu too", function()
    load()
    ns.UI.show({ kind = "zone", mapID = 1439 })
    local lines
    for _, box in ipairs(fake.scrollBoxes) do
      for _, r in ipairs(box.rows or {}) do
        if r.element.kind == "step" and r.element.step.index == 7 then lines = r.frame.laStep.lines end
      end
    end
    local line = lines[2]
    assert.same({ "LeftButtonUp", "RightButtonUp" }, line.clicks)
    fake.click(line, "RightButton")
    assert.equal(db:quest(5061).name, fake.menu.title)
    local link = ui.spy(Menu, "linkQuest", function() return true end)
    fake.modifier = "CHATLINK"
    fake.click(line)
    assert.equal(5061, link.calls[1][1])
    fake.modifier = nil

    local hit = ns.UI.RouteView.detail.parts.head.hit
    assert.same({ "LeftButtonUp", "RightButtonUp" }, hit.clicks)
    ns.UI.select(4763)
    fake.menu = nil
    fake.click(hit, "LeftButton")
    assert.is_nil(fake.menu)
    fake.click(hit, "RightButton")
    assert.equal("The Blackwood Corrupted", fake.menu.title)
    fake.modifier = "CHATLINK"
    fake.click(hit)
    assert.equal(4763, link.calls[2][1])
    assert.same({}, env.errors)
  end)

  it("no MenuUtil: right-click does nothing, no error", function()
    load({ without = { "MenuUtil" } })
    ns.UI.open()
    local show = ui.spy(ns.UI, "show")
    fake.click(fake.rowFrame(4763), "RightButton")
    assert.is_nil(fake.menu)
    assert.equal(0, #show.calls)
    assert.same({}, env.errors)
  end)

  it("/advisor debug shows the last link attempt on its own line", function()
    load()
    env.SlashCmdList.LEVELINGADVISOR("debug")
    assert.is_nil(fake.out[#fake.out]:find("last link", 1, true))
    Menu.linkQuest(4763)
    local n = #fake.out
    env.SlashCmdList.LEVELINGADVISOR("debug")
    assert.truthy(fake.out[n + 1]:match("log=2, grey=%S+$"))
    assert.truthy(fake.out[n + 2]:find("last link: ChatFrameUtil.InsertLink=false, ChatEdit_InsertLink=false, ChatFrameUtil.OpenChat=ran", 1, true))
  end)
  it("Menu.open is fail-soft without CreateButton or CreateTitle", function()
    load()
    local root = {}
    env.MenuUtil.CreateContextMenu = function(_, fn) fn(nil, root) end
    assert.has_no.errors(function() Menu.open(fake.newFrame("Frame"), 4763) end)
  end)

  it("handleClick survives a throwing IsModifiedClick", function()
    load()
    env.IsModifiedClick = function() error("boom") end
    assert.is_false(Menu.handleClick(fake.newFrame("Frame"), 4763, "LeftButton"))
  end)

  it("a plain click on the mini item button reaches the row; right-click opens the menu", function()
    load()
    ns.UI.open()
    local f = fake.rowFrame(4763)
    local btn
    local found = fake.findAll(function(w) return w.laMini and w.parent and w.parent.parent == f end)
    btn = found[1]
    assert.truthy(btn)
    btn.laItemID = 15204
    fake.click(btn, "RightButton")
    assert.equal("The Blackwood Corrupted", fake.menu.title)
  end)
end)
