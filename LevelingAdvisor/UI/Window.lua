local _, ns = ...

-- The advisor book (spec 5.5): one ButtonFrameTemplate window with two
-- parchment pages, a footer (settings toggles and the game data version), a
-- settings gear, a view registry and a back stack.
--
-- Views (UI/MainView.lua, UI/RouteView.lua, UI/Search.lua) call
-- UI.registerView at load time. A view builds its left and right page roots
-- once, the first time its kind is shown, and updates them on every render.
-- The window is a plain (non-secure) frame: it may open in combat and then
-- shows the advisor's last result; it never computes anything itself.
ns.UI = ns.UI or {}
local UI = ns.UI

local call, method = ns.Util.call, ns.Util.method
local Style = UI.Style

local TITLE = "Leveling Advisor"
local FRAME_NAME = "LevelingAdvisorFrame"

-- The book sits between the title strip and the footer. The strip from the
-- title bar down to y -62 stays free for the search box.
local BOOK = { left = 8, top = -62, right = -8, bottom = 34 }
local PAGE_W, PAGE_H = 418, Style.HEIGHT + BOOK.top - BOOK.bottom -- 2 x 418 + 8 px spine = book width
local SPINE_W, SPINE_ALPHA, FLAT_SPINE_ALPHA = 24, 0.35, 0.25
local PARCHMENT_ATLAS, PARCHMENT_FILE = "QuestBG-Parchment", "Interface\\QuestFrame\\QuestBG"
local GEAR_ATLAS, GEAR_FILE = "QuestLog-icon-setting", "Interface\\Buttons\\UI-OptionsButton"
local HIGHLIGHT_FILE = "Interface\\Buttons\\UI-Common-MouseHilight"

local FOOTER_TOGGLES = {
  { key = "elite", label = "Elite quests" },
  { key = "dungeons", label = "Dungeons" },
}
local TOGGLE_X, TOGGLE_SPACING, TOGGLE_Y, TOGGLE_SIZE = 14, 140, 6, 24

local MESSAGES = {
  noData = "No quest data loaded. Run the data pipeline and /reload.",
  loadError = "Quest data failed to load: ",
  loading = "Working out your recommendations…",
  unregistered = "Not available yet.",
}

local views = {} -- kind -> def
local roots = {} -- kind -> { left = frame, right = frame }
local broken = {} -- kind -> true after its build failed
local stack = {} -- back stack of views
local view = { kind = "main" }
local buildHooks = {}
local frame, pages, toggles
local restored = false   -- the last view is restored on the first open after login
local skipRender = false -- UI.show opens a closed book without rendering the old view

local function report(err)
  local handler = call(geterrorhandler)
  if handler then pcall(handler, err) end
end

---------------------------------------------------------------------------
-- Tooltips.
---------------------------------------------------------------------------
-- lines: { {text, r, g, b}, ... }; the first line is the tooltip's title.
local function showTooltip(owner, anchor, lines)
  local tip = GameTooltip
  if type(tip) ~= "table" then return end
  method(tip, "SetOwner", owner, anchor)
  for i, l in ipairs(lines) do
    if i == 1 then
      method(tip, "SetText", l[1], l[2], l[3], l[4])
    else
      method(tip, "AddLine", l[1], l[2], l[3], l[4], true)
    end
  end
  method(tip, "Show")
end

local function hideTooltip()
  if type(GameTooltip) == "table" then method(GameTooltip, "Hide") end
end

---------------------------------------------------------------------------
-- Frame chrome.
---------------------------------------------------------------------------
local function setTitle(f, text)
  if type(f.SetTitle) == "function" then
    f:SetTitle(text)
  elseif type(f.TitleText) == "table" then
    method(f.TitleText, "SetText", text)
  end
end

local function setPortrait(f)
  if type(f.SetPortraitToUnit) == "function" and pcall(f.SetPortraitToUnit, f, "player") then
    return
  end
  local holder = f.PortraitContainer
  local tex = type(holder) == "table" and holder.portrait or f.portrait
  if type(tex) == "table" then call(SetPortraitTexture, tex, "player") end
end

local function restorePosition(f)
  f:ClearAllPoints()
  local w = type(ns.db) == "table" and ns.db.window
  -- Init.migrate always creates db.window, so only a saved point counts.
  if type(w) == "table" and type(w.point) == "string" then
    f:SetPoint(w.point, UIParent, w.relPoint or w.point, tonumber(w.x) or 0, tonumber(w.y) or 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

local function savePosition(f)
  if type(ns.db) ~= "table" then return end
  local point, _, relPoint, x, y = f:GetPoint(1)
  if type(point) ~= "string" then return end
  if type(ns.db.window) ~= "table" then ns.db.window = {} end
  local w = ns.db.window
  w.point, w.relPoint, w.x, w.y = point, relPoint, x, y
end

---------------------------------------------------------------------------
-- The book: leather backdrop, two parchment pages.
---------------------------------------------------------------------------
-- A 24 px shadow along the page's inner edge, darkest at the spine.
local function spineShadow(page, side)
  local tex = page:CreateTexture(nil, "ARTWORK")
  local edge = side == "left" and "RIGHT" or "LEFT"
  tex:SetPoint("TOP" .. edge, page, "TOP" .. edge, 0, 0)
  tex:SetPoint("BOTTOM" .. edge, page, "BOTTOM" .. edge, 0, 0)
  tex:SetWidth(SPINE_W)
  -- The gradient scales this alpha from 0 (page side) to 1 (spine side); a
  -- client that ignores the gradient still shows a plain shadow, never a bar.
  tex:SetColorTexture(0, 0, 0, SPINE_ALPHA)
  local clear, dark = call(CreateColor, 0, 0, 0, 0), call(CreateColor, 0, 0, 0, 1)
  local ok = false
  if clear and dark then
    if side == "left" then
      ok = pcall(tex.SetGradient, tex, "HORIZONTAL", clear, dark)
    else
      ok = pcall(tex.SetGradient, tex, "HORIZONTAL", dark, clear)
    end
  end
  if not ok then tex:SetColorTexture(0, 0, 0, FLAT_SPINE_ALPHA) end
  return tex
end

local function newPage(book, side)
  local page = CreateFrame("Frame", nil, book)
  page:SetWidth(PAGE_W)
  local h = side == "left" and "LEFT" or "RIGHT"
  page:SetPoint("TOP" .. h, book, "TOP" .. h, 0, 0)
  page:SetPoint("BOTTOM" .. h, book, "BOTTOM" .. h, 0, 0)

  page.parchment = Style.texture(page, "BACKGROUND", PARCHMENT_ATLAS, PARCHMENT_FILE)
  page.parchment:SetAllPoints(page)
  page.spine = spineShadow(page, side)

  local content = CreateFrame("Frame", nil, page)
  content:SetPoint("TOPLEFT", page, "TOPLEFT", Style.PAGE_PAD, -Style.PAGE_PAD)
  content:SetSize(Style.CONTENT_W, PAGE_H - 2 * Style.PAGE_PAD)
  page.content = content

  local status = Style.text(page, "QuestFont", Style.INK)
  status:SetPoint("CENTER", content, "CENTER", 0, 0)
  status:SetWidth(Style.CONTENT_W - 40)
  status:SetJustifyH("CENTER")
  status:SetWordWrap(true)
  status:Hide()
  page.status = status
  return page
end

local function buildBook(f)
  local book = CreateFrame("Frame", nil, f)
  book:SetPoint("TOPLEFT", f, "TOPLEFT", BOOK.left, BOOK.top)
  book:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", BOOK.right, BOOK.bottom)
  local backdrop = book:CreateTexture(nil, "BACKGROUND", nil, -8)
  backdrop:SetAllPoints(book)
  backdrop:SetColorTexture(Style.LEATHER[1], Style.LEATHER[2], Style.LEATHER[3], 1)
  book.laBackdrop = backdrop
  pages = { left = newPage(book, "left"), right = newPage(book, "right") }
  f.laBook, f.laPages = book, pages
end

-- Shows `text` centred on the page, or hides the page's status line.
local function pageStatus(page, text)
  if text then
    page.status:SetText(text)
    page.status:Show()
  else
    page.status:SetText("")
    page.status:Hide()
  end
end

---------------------------------------------------------------------------
-- Footer and gear.
---------------------------------------------------------------------------
local function syncToggles()
  for key, cb in pairs(toggles or {}) do
    cb:SetChecked(ns.Settings.get(key) and true or false)
  end
end

local function versionText()
  local meta = type(ns.Data) == "table" and ns.Data.meta
  return "Game data " .. tostring(type(meta) == "table" and meta.gameData or "not built")
end

local function buildFooter(f)
  toggles = {}
  for i, opt in ipairs(FOOTER_TOGGLES) do
    local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    cb:SetSize(TOGGLE_SIZE, TOGGLE_SIZE)
    cb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", TOGGLE_X + (i - 1) * TOGGLE_SPACING, TOGGLE_Y)
    local label = cb.Text
    if type(label) ~= "table" then
      label = cb:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
      label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    end
    label:SetText(opt.label)
    cb:SetScript("OnClick", function(self)
      ns.Settings.set(opt.key, self:GetChecked() and true or false)
    end)
    toggles[opt.key] = cb
  end
  syncToggles()
  ns.Settings.onChange(function(key)
    if toggles[key] then syncToggles() end
  end)

  local ver = CreateFrame("Button", nil, f)
  method(ver, "SetNormalFontObject", "GameFontDisableSmall")
  method(ver, "SetHighlightFontObject", "GameFontHighlightSmall")
  ver:SetText(versionText())
  ver:SetSize((tonumber(method(ver, "GetTextWidth")) or 150) + 4, 18)
  ver:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 9)
  ver:SetScript("OnEnter", function(self)
    showTooltip(self, "ANCHOR_TOPRIGHT", {
      { TITLE, Style.GOLD[1], Style.GOLD[2], Style.GOLD[3] },
      { ns.Settings.aboutLine(), 1, 1, 1 },
    })
  end)
  ver:SetScript("OnLeave", hideTooltip)
  f.laVersion = ver
end

local function buildGear(f)
  local gear = CreateFrame("Button", nil, f)
  gear:SetSize(20, 20)
  if type(f.CloseButton) == "table" then
    gear:SetPoint("RIGHT", f.CloseButton, "LEFT", -2, 0)
  else
    gear:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -4)
  end
  gear.laIcon = Style.texture(gear, "ARTWORK", GEAR_ATLAS, GEAR_FILE)
  gear.laIcon:SetAllPoints(gear)
  gear:SetHighlightTexture(HIGHLIGHT_FILE, "ADD")
  -- Settings.open refuses in combat with its own message.
  gear:SetScript("OnClick", function() ns.Settings.open() end)
  gear:SetScript("OnEnter", function(self)
    showTooltip(self, "ANCHOR_BOTTOM", { { "Settings", 1, 1, 1 } })
  end)
  gear:SetScript("OnLeave", hideTooltip)
  f.laGear = gear
end

---------------------------------------------------------------------------
-- Rendering.
---------------------------------------------------------------------------
function UI.context()
  local A = ns.Advisor
  local last = A and A.last
  local status = "ok"
  if not (A and A.db) then
    status = "no-data"
  elseif not last then
    status = "loading"
  end
  return { status = status, rec = last and last.rec, state = last and last.state, db = A and A.db, last = last }
end

local function hideRoots(except)
  for kind, r in pairs(roots) do
    if kind ~= except then
      method(r.left, "Hide")
      method(r.right, "Hide")
    end
  end
end

-- The roots of view kind, built on first use; nil when the build failed.
local function rootsFor(kind, def)
  if roots[kind] then return roots[kind] end
  if broken[kind] then return nil end
  local ok, left, right = pcall(def.build, pages.left.content, pages.right.content)
  if not ok then
    broken[kind] = true
    report(left)
    return nil
  end
  roots[kind] = { left = left, right = right }
  return roots[kind]
end

local function statusMessage(ctx, def)
  if ctx.status == "no-data" then
    local err = ns.Advisor and ns.Advisor.loadError
    return err and (MESSAGES.loadError .. tostring(err)) or MESSAGES.noData
  elseif ctx.status == "loading" then
    return MESSAGES.loading
  elseif not def then
    return MESSAGES.unregistered
  end
  return nil
end

-- Renders the current view; does nothing while the book is closed.
local function render()
  if skipRender or not (frame and frame:IsShown()) then return end
  local ctx = UI.context()
  local def = views[view.kind]
  local message = statusMessage(ctx, def)
  local r = not message and rootsFor(view.kind, def) or nil
  if not r then
    hideRoots(nil)
    setTitle(frame, TITLE)
    pageStatus(pages.left, nil)
    pageStatus(pages.right, message or MESSAGES.unregistered)
    return
  end
  pageStatus(pages.left, nil)
  pageStatus(pages.right, nil)
  hideRoots(view.kind)
  method(r.left, "Show")
  method(r.right, "Show")
  local title
  if def.title then
    local ok, t = pcall(def.title, view, ctx)
    if ok then title = t else report(t) end
  end
  setTitle(frame, title and (TITLE .. " — " .. tostring(title)) or TITLE)
  local ok, err = pcall(def.update, view, ctx)
  if not ok then report(err) end
end

---------------------------------------------------------------------------
-- Build (once, on the first open).
---------------------------------------------------------------------------
local function build()
  local f = CreateFrame("Frame", FRAME_NAME, UIParent, "ButtonFrameTemplate")
  f:Hide()
  f:SetSize(Style.WIDTH, Style.HEIGHT)
  setTitle(f, TITLE)
  setPortrait(f)
  call(ButtonFrameTemplate_HideButtonBar, f)
  if type(f.Inset) == "table" then method(f.Inset, "Hide") end

  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  method(f, "SetDontSavePosition", true) -- the position lives in LevelingAdvisorDB.window
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savePosition(self)
  end)
  restorePosition(f)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, FRAME_NAME) end -- ESC closes

  buildBook(f)
  buildFooter(f)
  buildGear(f)

  f:HookScript("OnShow", function(self)
    self:Raise()
    ns.Advisor.setWindowShown(true)
    syncToggles()
    render()
    ns.Util.call(ns.UI.QuestLogTab.update)
  end)
  f:HookScript("OnHide", function()
    ns.Advisor.setWindowShown(false)
    hideTooltip()
    ns.Util.call(ns.UI.QuestLogTab.update)
  end)

  frame = f
  UI.frame = f
  local hooks = buildHooks
  buildHooks = {}
  for _, fn in ipairs(hooks) do
    local ok, err = pcall(fn, f)
    if not ok then report(err) end
  end
end

---------------------------------------------------------------------------
-- Public interface.
---------------------------------------------------------------------------
-- Runs fn(frame) once after the window is built, or at once when it is.
function UI.onBuild(fn)
  if frame then
    local ok, err = pcall(fn, frame)
    if not ok then report(err) end
  else
    buildHooks[#buildHooks + 1] = fn
  end
end

function UI.registerView(kind, def)
  views[kind] = def
end

function UI.isShown()
  return frame ~= nil and frame:IsShown() and true or false
end

-- Remembers the zone or dungeon page for the next login; the main page
-- forgets it. Other views (search) leave it unchanged.
local function saveLastView()
  local c = ns.chardb
  if type(c) ~= "table" then return end
  if view.kind == "zone" then
    c.lastView = { kind = "zone", mapID = view.mapID }
  elseif view.kind == "dungeon" then
    c.lastView = { kind = "dungeon", key = view.key }
  elseif view.kind == "main" then
    c.lastView = nil
  end
end

-- The first open after login: a saved zone page returns; a saved dungeon page
-- only while it is still the recommended dungeon.
local function restoreLastView()
  if restored then return end
  restored = true
  local lv = type(ns.chardb) == "table" and ns.chardb.lastView
  if type(lv) ~= "table" then return end
  if lv.kind == "zone" and lv.mapID then
    view = { kind = "zone", mapID = lv.mapID }
  elseif lv.kind == "dungeon" and lv.key then
    local last = ns.Advisor and ns.Advisor.last
    local d = last and last.rec and last.rec.dungeon
    if d and d.key == lv.key then view = { kind = "dungeon", key = lv.key } end
  end
end

function UI.open()
  if not frame then build() end
  if not frame:IsShown() then
    restoreLastView()
    frame:Show()
  end
end

function UI.close()
  if frame then frame:Hide() end
end

function UI.toggle()
  if UI.isShown() then UI.close() else UI.open() end
end

function UI.current()
  return view
end

-- Re-renders the open book (a closed book renders on its next open).
function UI.refresh()
  render()
end

-- Pushes the current view and shows v; opens a closed book first.
function UI.show(v)
  local wasClosed = not UI.isShown()
  if wasClosed then
    skipRender = true
    local ok, err = pcall(UI.open)
    skipRender = false
    if not ok then report(err) end
  end
  -- A restored last view is not a page the player came from: Back goes to main.
  if not wasClosed then stack[#stack + 1] = view end
  view = v
  saveLastView()
  render()
end

function UI.back()
  view = table.remove(stack) or { kind = "main" }
  saveLastView()
  render()
end

-- Selects a quest in the current view; the source belonged to the old quest.
function UI.select(questID)
  view.questID = questID
  view.source = nil
  render()
end

-- Opens the zone page of a quest's place (turn-in map when it is complete in
-- the log, else its giver's map, else its zone). Unknown quests do nothing.
function UI.openQuest(questID, source)
  local A = ns.Advisor
  local q = A and A.db and method(A.db, "quest", questID)
  if type(q) ~= "table" then return end
  local state = A.last and A.last.state
  local entry = type(state) == "table" and type(state.log) == "table" and state.log[questID]
  local place = (entry and entry.complete and q.turnIn) or q.giver
  local mapID = (type(place) == "table" and place.mapID) or q.zone
  if not mapID then return end
  UI.show({ kind = "zone", mapID = mapID, questID = questID, source = source })
end

-- The player's name, race, class, rested XP and zone name; every call fail-soft.
function UI.playerInfo()
  local info = { name = call(UnitName, "player"), race = (call(UnitRace, "player")),
    className = (call(UnitClass, "player")), rested = tonumber(call(GetXPExhaustion)) or 0 }
  local state = ns.Advisor and ns.Advisor.last and ns.Advisor.last.state
  local map = type(C_Map) == "table" and state and state.mapID and call(C_Map.GetMapInfo, state.mapID)
  info.zoneName = type(map) == "table" and map.name or nil
  return info
end

-- Advisor results re-render the open book.
ns.Advisor.onUpdate(function() UI.refresh() end)

-- A route page opened in combat has no plan; draw it once the fight is over.
ns.Events.on("PLAYER_REGEN_ENABLED", function()
  if UI.isShown() and (view.kind == "zone" or view.kind == "dungeon") then UI.refresh() end
end)

---------------------------------------------------------------------------
-- Key binding (Bindings.xml).
---------------------------------------------------------------------------
BINDING_HEADER_LEVELINGADVISOR = "Leveling Advisor"
BINDING_NAME_LEVELINGADVISOR_TOGGLE = "Toggle Leveling Advisor"

function LevelingAdvisor_Toggle()
  UI.toggle()
end
