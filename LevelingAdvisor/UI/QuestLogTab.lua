-- A side tab on the Map & Quest Log's right edge that opens the book, plus the
-- addon compartment entry. Fail-soft: a missing host or compartment is
-- skipped silently.
--
-- Look, the first that works, always on our own plain button (the side-tab
-- template is never instantiated): the frame textures and size copied from a
-- native side tab (QuestsTab, MapLegendTab, EventsTab, hidden or not) with our
-- logo as the icon; the same look built from the questlog-tab-side atlases;
-- our own bookmark texture.
-- Place, recomputed whenever it can change: below the lowest visible side tab
-- (the native ones, other frames built from the template, or another addon's
-- button at the quest log's right edge); else the first native tab's slot;
-- else next to the map's close button. /advisor tab <dx> <dy> nudges it.
local addonName, ns = ...; ns.UI = ns.UI or {}; ns.UI.QuestLogTab = ns.UI.QuestLogTab or {}
local QuestLogTab = ns.UI.QuestLogTab

-- QuestMapFrame is the quest log on this client; QuestLogFrame is only a
-- fallback for a client without it (never both).
QuestLogTab.HOSTS = { "QuestMapFrame", "QuestLogFrame" }
QuestLogTab.NATIVE_TABS = { "QuestsTab", "MapLegendTab", "EventsTab" }
-- Without side tabs or a native slot:
-- x: the tab's left edge tucks 7 px under the frame's right border (the border
--    frame is drawn over it, so it looks like a bookmark sticking out of a book).
-- y: 60 px below the frame's top, level with the top of the quest list area
--    (just under the title bar).
-- gap: spacing below the last side tab when the native tabs' anchors don't say.
QuestLogTab.OFFSET = { x = -7, y = -60, gap = -3 }
QuestLogTab.CLOSE_X = -6 -- overlap under the border when anchored to the close button
QuestLogTab.SIZE = { w = 36, h = 40 } -- the bookmark (fallback look)
QuestLogTab.ICON_SIZE = 26 -- the logo on the bookmark
QuestLogTab.SIDE_SIZE = { w = 43, h = 55 } -- a native side tab
QuestLogTab.SIDE_ICON_SIZE = 28 -- the logo on a side tab when no native icon gives a size
-- Candidate atlas names, first existing one wins (the client matches atlas
-- names case-insensitively).
QuestLogTab.ATLASES = {
  bg = { "questlog-tab-side" },
  hover = { "questlog-tab-side-glow-hover", "questlog-tab-side-hover" },
  select = { "questlog-tab-side-glow-select", "questlog-tab-side-select", "questlog-tab-side-selected" },
}
-- Another addon's side tab: a button whose left edge is within EDGE px of the
-- quest log's right edge, with a width and height in these ranges.
QuestLogTab.EDGE = 8
QuestLogTab.TAB_W, QuestLogTab.TAB_H = { 30, 60 }, { 30, 70 }
local MEDIA = "Interface\\AddOns\\" .. tostring(addonName) .. "\\Media\\"
QuestLogTab.ICON = MEDIA .. "Logo"

local BOOKMARK = MEDIA .. "BookmarkTab"
local tabs = {} -- host frame -> tab
local watched = setmetatable({}, { __mode = "k" }) -- side tabs whose OnShow/OnHide re-anchor
local deferred = false -- a next-frame re-anchor is queued
local displayHooked = false

local function findHost()
  for _, name in ipairs(QuestLogTab.HOSTS) do
    local host = _G[name]
    if type(host) == "table" then return host end
  end
end

local function field(t, key)
  local ok, v = pcall(function() return t[key] end)
  if ok then return v end
end

local function method(f, name, ...) return ns.Util.method(f, name, ...) end

local function num(frame, name)
  local v = method(frame, name)
  if type(v) == "number" then return v end
end

local function r(v) return v and math.floor(v + 0.5) or "n/a" end

local function nativeTab(host, key)
  local t = field(host, key)
  if type(t) == "table" then return t end
end

-- The frame that draws the visible outer border of the Map & Quest Log; only
-- meaningful when QuestMapFrame is the host (it lives inside WorldMapFrame).
local function borderFrame(host)
  if host ~= _G.QuestMapFrame then return host end
  local wm = _G.WorldMapFrame
  if type(wm) ~= "table" then return host end
  local border = field(wm, "BorderFrame")
  if type(border) == "table" then return border end
  return wm
end

-- The map frame's close button sits flush with the visible border (the frame's
-- own right edge lies about 20 px further out on this client).
local function closeButton(host)
  if host ~= _G.QuestMapFrame then return nil end
  local wm = _G.WorldMapFrame
  local ok, btn = pcall(function()
    local border = type(wm) == "table" and wm.BorderFrame
    return (type(border) == "table" and border.CloseButton) or _G.WorldMapFrameCloseButton
  end)
  if ok and type(btn) == "table" then return btn end
end

-- Calibration offset, persisted account-wide: LevelingAdvisorDB.window.tabOffset.
function QuestLogTab.getOffset()
  local w = type(ns.db) == "table" and ns.db.window
  local o = type(w) == "table" and w.tabOffset
  if type(o) == "table" and tonumber(o.x) and tonumber(o.y) then return o.x, o.y end
  return 0, 0
end

---------------------------------------------------------------------------
-- The side tabs in the quest log's tab column.
---------------------------------------------------------------------------
-- Built from QuestLogTabButtonTemplate: the template mixes its methods in.
local function fromTemplate(f)
  local mixin = _G.QuestLogTabButtonMixin
  if type(mixin) ~= "table" then return false end
  local ok, hit = pcall(function()
    for k, v in pairs(mixin) do
      if type(v) == "function" and f[k] == v then return true end
    end
    return false
  end)
  return ok and hit
end

local function children(f)
  local ok, list = pcall(function() return { f:GetChildren() } end)
  return ok and list or {}
end

local function within(v, range) return v ~= nil and v >= range[1] and v <= range[2] end

-- Another addon's tab: a button at the quest log's right edge, tab-sized.
local function atEdge(f, right)
  local kind = method(f, "GetObjectType")
  if kind ~= "Button" and kind ~= "CheckButton" then return false end
  local left = num(f, "GetLeft")
  return left ~= nil and math.abs(left - right) <= QuestLogTab.EDGE
    and within(num(f, "GetWidth"), QuestLogTab.TAB_W) and within(num(f, "GetHeight"), QuestLogTab.TAB_H)
end

local function label(f, key)
  if key then return key end
  local name = method(f, "GetName")
  if type(name) == "string" and name ~= "" then return name end
  return "unnamed " .. r(num(f, "GetWidth")) .. "x" .. r(num(f, "GetHeight"))
end

-- The visible side tabs, as { frame, label }: the native tabs, then other
-- children of QuestMapFrame built from the template, then other addons'
-- buttons at its right edge (children of QuestMapFrame or WorldMapFrame).
-- Protected frames never count: a tab anchored to one could not move in combat.
local function sideTabs(host, own)
  local list, seen = {}, {}
  if own then seen[own] = true end
  local function add(f, key)
    if seen[f] then return end
    seen[f] = true
    if method(f, "IsShown") and not method(f, "IsProtected") then
      list[#list + 1] = { frame = f, label = label(f, key) }
    end
  end
  for _, key in ipairs(QuestLogTab.NATIVE_TABS) do
    local t = nativeTab(host, key)
    if t then add(t, key) end
  end
  if host ~= _G.QuestMapFrame then return list end
  for _, f in ipairs(children(host)) do
    if fromTemplate(f) then add(f) end
  end
  local right = num(host, "GetRight")
  if not right then return list end
  for _, parent in ipairs({ host, _G.WorldMapFrame }) do
    if type(parent) == "table" then
      for _, f in ipairs(children(parent)) do
        if not seen[f] and atEdge(f, right) then add(f) end
      end
    end
  end
  return list
end

-- The lowest tab on screen; without positions, the last one in column order.
local function lowest(list)
  local best, low
  for _, c in ipairs(list) do
    local b = num(c.frame, "GetBottom")
    if b and (not low or b < low) then best, low = c, b end
  end
  return best or list[#list]
end

-- The gap between native tabs, read from their own anchors (TOP to BOTTOM).
local function nativeGap(host)
  for i = 2, #QuestLogTab.NATIVE_TABS do
    local t = nativeTab(host, QuestLogTab.NATIVE_TABS[i])
    if t then
      local ok, p, _, rp, _, y = pcall(t.GetPoint, t, 1)
      if ok and p == "TOP" and rp == "BOTTOM" and type(y) == "number" then return y end
    end
  end
  return QuestLogTab.OFFSET.gap
end

-- The first native tab's own anchor (readable while the tab is hidden).
local function nativeSlot(host)
  for _, key in ipairs(QuestLogTab.NATIVE_TABS) do
    local t = nativeTab(host, key)
    if t then
      local ok, p, rel, rp, x, y = pcall(t.GetPoint, t, 1)
      if not (ok and type(p) == "string") then return nil end
      rel = rel or method(t, "GetParent") or host
      if method(rel, "IsProtected") then return nil end
      return { p, rel, rp or p, tonumber(x) or 0, tonumber(y) or 0 }
    end
  end
end

---------------------------------------------------------------------------
-- Anchoring.
---------------------------------------------------------------------------
-- Hooks a side tab's OnShow/OnHide once: the column changed, so re-anchor.
local function watch(f)
  if watched[f] then return end
  watched[f] = true
  for _, ev in ipairs({ "OnShow", "OnHide" }) do
    pcall(function() f:HookScript(ev, function() QuestLogTab.reanchor() end) end)
  end
end

-- Decides the anchor every time it runs and applies the calibration offset on
-- every path. Sets tab.laAnchorKind.
local function applyAnchor(tab, host)
  local dx, dy = QuestLogTab.getOffset()
  local side = sideTabs(host, tab)
  for _, key in ipairs(QuestLogTab.NATIVE_TABS) do
    local t = nativeTab(host, key)
    if t then watch(t) end -- hidden ones too: they may show later
  end
  for _, c in ipairs(side) do watch(c.frame) end
  tab:ClearAllPoints()
  if #side > 0 then
    local c = lowest(side)
    tab:SetFrameLevel(host:GetFrameLevel() + 10)
    tab:SetPoint("TOP", c.frame, "BOTTOM", dx, nativeGap(host) + dy)
    tab.laAnchorKind = "below side tab " .. c.label
    return
  end
  local slot = nativeSlot(host)
  if slot then
    tab:SetFrameLevel(host:GetFrameLevel() + 10)
    tab:SetPoint(slot[1], slot[2], slot[3], slot[4] + dx, slot[5] + dy)
    tab.laAnchorKind = "native slot"
    return
  end
  local anchor = borderFrame(host)
  -- Below the border frame, so its border overlaps the tab's left edge.
  tab:SetFrameLevel(math.max(0, anchor:GetFrameLevel() - 1))
  local btn = closeButton(host)
  if btn then
    -- Left edge on the close button's right, tucked 6 px under the border. The
    -- vertical position is measured from the outer frame's top.
    local ct, ft = num(btn, "GetTop"), num(anchor, "GetTop")
    local fix = (ct and ft) and (ft - ct) or 0
    tab:SetPoint("TOPLEFT", btn, "TOPRIGHT", QuestLogTab.CLOSE_X + dx, QuestLogTab.OFFSET.y + fix + dy)
    tab.laAnchorKind = "close button"
  else
    tab:SetPoint("TOPLEFT", anchor, "TOPRIGHT", QuestLogTab.OFFSET.x + dx, QuestLogTab.OFFSET.y + dy)
    tab.laAnchorKind = "border"
  end
end

local function anchor(tab, host)
  local ok, err = pcall(applyAnchor, tab, host)
  if not ok then geterrorhandler()(err) end
end

function QuestLogTab.reanchor()
  for host, tab in pairs(tabs) do anchor(tab, host) end
end

-- Once more on the next frame, after other addons have placed their tabs.
local function reanchorNextFrame()
  if deferred or type(C_Timer) ~= "table" then return end
  deferred = true
  local ok = pcall(C_Timer.After, 0, function()
    deferred = false
    QuestLogTab.reanchor()
  end)
  if not ok then deferred = false end
end

---------------------------------------------------------------------------
-- Look.
---------------------------------------------------------------------------
local function hasAtlas(name)
  return type(C_Texture) == "table" and ns.Util.call(C_Texture.GetAtlasInfo, name) ~= nil
end

local function firstAtlas(list)
  for _, name in ipairs(list) do
    if hasAtlas(name) then return name end
  end
end

-- The native tabs' icon size, read from the first one that has an icon.
local function nativeIconSize(host)
  for _, key in ipairs(QuestLogTab.NATIVE_TABS) do
    local icon = field(nativeTab(host, key) or {}, "Icon")
    local w, h = num(icon, "GetWidth"), num(icon, "GetHeight")
    if w and h and w > 0 and h > 0 then return w, h end
  end
end

-- What a texture region shows: "atlas", name or "file", path or file ID.
local function source(region)
  if type(region) ~= "table" then return nil end
  local atlas = method(region, "GetAtlas")
  if type(atlas) == "string" and atlas ~= "" then return "atlas", atlas end
  local file = method(region, "GetTexture")
  if file == nil or file == "" then file = method(region, "GetTextureFileID") end
  if (type(file) == "string" and file ~= "") or (type(file) == "number" and file > 0) then
    return "file", file
  end
end

local function regions(f)
  local ok, list = pcall(function() return { f:GetRegions() } end)
  return ok and list or {}
end

-- The native tab's texture that shows something: native[key] when set, else
-- the first texture region on `layer`. Never its icon.
local function regionOf(native, key, layer)
  local icon = field(native, "Icon")
  local r = key and field(native, key)
  if type(r) == "table" and r ~= icon and source(r) then return r end
  for _, reg in ipairs(regions(native)) do
    if reg ~= icon and method(reg, "GetObjectType") == "Texture"
        and method(reg, "GetDrawLayer") == layer and source(reg) then
      return reg
    end
  end
end

-- dst takes src's anchors, with the native tab replaced by ours. An anchor to
-- any other frame, or none at all, centres dst instead. Returns the count.
local function anchorLike(dst, tab, src, native)
  local pts = {}
  for i = 1, num(src, "GetNumPoints") or 0 do
    local ok, p, rel, rp, x, y = pcall(src.GetPoint, src, i)
    if not (ok and type(p) == "string") or (rel ~= nil and rel ~= native) then
      pts = {}
      break
    end
    pts[#pts + 1] = { p, rp or p, tonumber(x) or 0, tonumber(y) or 0 }
  end
  dst:ClearAllPoints()
  if #pts == 0 then
    dst:SetPoint("CENTER", tab, "CENTER", 0, 0)
    return 0
  end
  for _, pt in ipairs(pts) do dst:SetPoint(pt[1], tab, pt[2], pt[3], pt[4]) end
  return #pts
end

-- Our texture on `layer` showing what the native region src shows (atlas, else
-- file with its tex coords), at its place, size and blend mode.
local function copyRegion(tab, native, src, layer)
  local kind, value = source(src)
  local t = tab:CreateTexture(nil, layer)
  local n = anchorLike(t, tab, src, native)
  local w, h = num(src, "GetWidth"), num(src, "GetHeight")
  local sized = w and h and w > 0 and h > 0
  if kind == "atlas" then
    t:SetAtlas(value, not sized)
  else
    t:SetTexture(value)
    local ok, c = pcall(function() return { src:GetTexCoord() } end)
    if ok and #c == 8 then t:SetTexCoord(unpack(c)) end
    if not sized and n < 2 then
      t:ClearAllPoints()
      t:SetAllPoints(tab)
    end
  end
  if sized then t:SetSize(w, h) end
  local blend = method(src, "GetBlendMode")
  if type(blend) == "string" then t:SetBlendMode(blend) end
  return t
end

-- The copied background again, brightened in gold: a hover or select glow
-- when the native tab has none to copy.
local function tintCopy(tab, native, bgSrc, layer, alpha)
  local t = copyRegion(tab, native, bgSrc, layer)
  t:SetBlendMode("ADD")
  t:SetVertexColor(1, 0.82, 0.2)
  t:SetAlpha(alpha)
  return t
end

-- Our logo where the native tab has its icon, sized like the native icons.
local function logoIcon(tab, host, native)
  local icon = tab:CreateTexture(nil, "ARTWORK")
  local nativeIcon = field(native, "Icon")
  if type(nativeIcon) == "table" then
    anchorLike(icon, tab, nativeIcon, native)
  else
    icon:SetPoint("CENTER", tab, "CENTER", 0, 0)
  end
  local w, h = nativeIconSize(host)
  icon:SetSize(w or QuestLogTab.SIDE_ICON_SIZE, h or QuestLogTab.SIDE_ICON_SIZE)
  icon:SetTexture(QuestLogTab.ICON)
  return icon
end

-- Copies the first native side tab's frame textures (background, hover,
-- select glow) and size onto our plain button; no template code runs. Returns
-- that tab's key, or nil when no native tab has a background to copy.
local function copiedLook(tab, host)
  for _, key in ipairs(QuestLogTab.NATIVE_TABS) do
    local native = nativeTab(host, key)
    local bgSrc = native and regionOf(native, "Background", "BACKGROUND")
    if bgSrc then
      local w, h = num(native, "GetWidth"), num(native, "GetHeight")
      if not (w and h and w > 0 and h > 0) then w, h = QuestLogTab.SIDE_SIZE.w, QuestLogTab.SIDE_SIZE.h end
      tab:SetSize(w, h)
      copyRegion(tab, native, bgSrc, "BACKGROUND")
      tab.laIcon = logoIcon(tab, host, native)
      local hl = method(native, "GetHighlightTexture")
      if not (type(hl) == "table" and hl ~= field(native, "Icon") and source(hl)) then
        hl = regionOf(native, nil, "HIGHLIGHT")
      end
      if hl then copyRegion(tab, native, hl, "HIGHLIGHT") else tintCopy(tab, native, bgSrc, "HIGHLIGHT", 0.35) end
      local selSrc = regionOf(native, "SelectedTexture", "OVERLAY")
      local sel = selSrc and copyRegion(tab, native, selSrc, "OVERLAY") or tintCopy(tab, native, bgSrc, "OVERLAY", 0.7)
      sel:Hide()
      tab.laSelected = sel
      return key
    end
  end
end

-- A glow over the whole tab: the glow atlas at its own size, or the background
-- atlas brightened in gold.
local function glow(tab, layer, atlas, bg, alpha)
  local t = tab:CreateTexture(nil, layer)
  t:SetPoint("CENTER", tab, "CENTER", 0, 0)
  if atlas then
    t:SetAtlas(atlas, true)
  else
    t:SetAtlas(bg, true)
    t:SetBlendMode("ADD")
    t:SetVertexColor(1, 0.82, 0.2)
    t:SetAlpha(alpha)
  end
  return t
end

local function atlasLook(tab, bg)
  tab:SetSize(QuestLogTab.SIDE_SIZE.w, QuestLogTab.SIDE_SIZE.h)
  local back = tab:CreateTexture(nil, "BACKGROUND")
  back:SetPoint("CENTER", tab, "CENTER", 0, 0)
  back:SetAtlas(bg, true)
  local icon = tab:CreateTexture(nil, "ARTWORK")
  icon:SetSize(QuestLogTab.SIDE_ICON_SIZE, QuestLogTab.SIDE_ICON_SIZE)
  icon:SetPoint("CENTER", tab, "CENTER", 0, 0)
  icon:SetTexture(QuestLogTab.ICON)
  tab.laIcon = icon
  glow(tab, "HIGHLIGHT", firstAtlas(QuestLogTab.ATLASES.hover), bg, 0.35)
  local sel = glow(tab, "OVERLAY", firstAtlas(QuestLogTab.ATLASES.select), bg, 0.7)
  sel:Hide()
  tab.laSelected = sel
end

local function bookmarkLook(tab)
  tab:SetSize(QuestLogTab.SIZE.w, QuestLogTab.SIZE.h)
  local bg = tab:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetTexture(BOOKMARK)
  -- Centred in the part that sticks out (the left 7 px are under the frame).
  local icon = tab:CreateTexture(nil, "ARTWORK")
  icon:SetSize(QuestLogTab.ICON_SIZE, QuestLogTab.ICON_SIZE)
  icon:SetPoint("CENTER", tab, "CENTER", 3, 0)
  icon:SetTexture(QuestLogTab.ICON)
  tab.laIcon = icon
  -- Hover: a soft gold highlight.
  local hl = tab:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture(BOOKMARK)
  hl:SetBlendMode("ADD")
  hl:SetVertexColor(1, 0.82, 0.2)
  hl:SetAlpha(0.35)
  -- Book open: a brighter gold glow on the border.
  local sel = tab:CreateTexture(nil, "OVERLAY")
  sel:SetAllPoints()
  sel:SetTexture(BOOKMARK)
  sel:SetBlendMode("ADD")
  sel:SetVertexColor(1, 0.85, 0.3)
  sel:SetAlpha(0.7)
  sel:Hide()
  tab.laSelected = sel
end

-- Selected (the gold glow) while the book is open.
local function setSelected(tab, on)
  if tab.laSelected then tab.laSelected:SetShown(on) end
end

local function showTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText("Leveling Advisor")
  GameTooltip:AddLine("Open the leveling book", 1, 1, 1)
  GameTooltip:Show()
end

local function nudge(tab, x, y)
  local icon = tab.laIcon
  if icon then pcall(function() icon:AdjustPointsOffset(x, y) end) end
end

-- A click toggles the book; it never switches the quest log's display mode.
local function setScripts(tab)
  tab:SetScript("OnMouseDown", function(self) nudge(self, 1, -1) end)
  tab:SetScript("OnMouseUp", function(self) nudge(self, -1, 1) end)
  tab:SetScript("OnEnter", showTooltip)
  tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
  tab:SetScript("OnClick", function()
    ns.UI.toggle()
    QuestLogTab.update()
  end)
end

-- Re-anchor (and re-sync the select glow) after the quest log switches
-- between its quests, events and map legend pages.
local function hookDisplayMode(host)
  if displayHooked or host ~= _G.QuestMapFrame or type(hooksecurefunc) ~= "function" then return end
  if type(field(host, "SetDisplayMode")) ~= "function" then return end
  displayHooked = pcall(hooksecurefunc, host, "SetDisplayMode", function()
    pcall(QuestLogTab.reanchor)
    pcall(QuestLogTab.update)
  end)
end

local function build(host, index)
  -- A plain button: the side-tab template's OnLoad would run inside
  -- CreateFrame, where an error reaches the error handler, not a pcall.
  local tab = CreateFrame("Button", "LevelingAdvisorQuestLogTab" .. index, host)
  local copied = copiedLook(tab, host)
  local look
  if copied then
    look = "copied-from " .. copied
  else
    local bg = firstAtlas(QuestLogTab.ATLASES.bg)
    if bg then
      atlasLook(tab, bg)
      look = "atlases"
    else
      bookmarkLook(tab)
      look = "fallback"
    end
  end
  tab.laLook = look
  setScripts(tab)
  applyAnchor(tab, host)
  -- Re-apply when the map frame resizes or reappears (maximise / minimise),
  -- and once more a frame after it shows.
  for _, f in ipairs({ borderFrame(host), host }) do
    pcall(function()
      f:HookScript("OnShow", function()
        anchor(tab, host)
        reanchorNextFrame()
      end)
      f:HookScript("OnSizeChanged", function() anchor(tab, host) end)
    end)
  end
  hookDisplayMode(host)
  setSelected(tab, ns.Util.call(ns.UI.isShown) and true or false)
  return tab
end

-- One tab on the first present host; idempotent. Returns the tab count.
function QuestLogTab.attach()
  local host = findHost()
  if not host then return 0 end
  if not tabs[host] then
    local ok, tab = pcall(build, host, 1)
    if not ok then
      geterrorhandler()(tab)
      return 0
    end
    tabs[host] = tab
  end
  return 1
end

local LIMIT = 200
local function clamp(v) return math.max(-LIMIT, math.min(LIMIT, v)) end

-- Stores the total offset, limited to +-LIMIT per axis. Returns ok, clamped.
function QuestLogTab.setOffset(x, y)
  if type(ns.db) ~= "table" then return false end
  QuestLogTab.clampedLast = false
  if x ~= nil then
    local cx, cy = clamp(x), clamp(y)
    QuestLogTab.clampedLast = (cx ~= x or cy ~= y)
    x, y = cx, cy
  end
  if type(ns.db.window) ~= "table" then ns.db.window = {} end
  if x == nil then ns.db.window.tabOffset = nil else ns.db.window.tabOffset = { x = x, y = y } end
  QuestLogTab.reanchor()
  return true, QuestLogTab.clampedLast
end

-- One line for /advisor tab: the anchor, the look, the side tabs found now,
-- the offset and the frames' positions.
function QuestLogTab.describe()
  local host = findHost()
  local wm = _G.WorldMapFrame
  local function pos(f)
    if type(f) ~= "table" then return "none" end
    return "R " .. r(num(f, "GetRight")) .. " T " .. r(num(f, "GetTop"))
  end
  local ox, oy = QuestLogTab.getOffset()
  local border = host and borderFrame(host)
  local tab = host and tabs[host]
  local names = {}
  for i, c in ipairs(host and sideTabs(host, tab) or {}) do names[i] = c.label end
  return string.format("anchor %s; look %s; side tabs %s; tab offset %s,%s; tab %s; close button %s;"
    .. " border %s; WorldMapFrame %s; QuestMapFrame %s",
    tab and tab.laAnchorKind or "none", tab and tab.laLook or "none",
    #names > 0 and table.concat(names, ", ") or "none", r(ox), r(oy), pos(tab),
    pos(host and closeButton(host)), pos(border ~= wm and border or nil), pos(wm), pos(_G.QuestMapFrame))
end

function QuestLogTab.update()
  local open = ns.UI.isShown()
  for _, tab in pairs(tabs) do setSelected(tab, open) end
end

function QuestLogTab.registerCompartment()
  local c = _G.AddonCompartmentFrame
  if type(c) ~= "table" or type(c.RegisterAddon) ~= "function" then return false end
  local ok = pcall(c.RegisterAddon, c, {
    text = "Leveling Advisor",
    icon = QuestLogTab.ICON,
    notCheckable = true,
    func = function()
      ns.UI.toggle()
      QuestLogTab.update()
    end,
  })
  return ok
end

---------------------------------------------------------------------------
-- Minimap button (ns.UI.MinimapButton): a LibDBIcon-style round button on the
-- minimap edge, written by us (no library). Left-click toggles the book,
-- right-click opens the guide menu (Guide on/off, Continue, Settings), drag moves it around the edge.
-- State: the angle (degrees) lives in LevelingAdvisorDB.window.minimap.angle;
-- visibility has ONE source of truth, the "minimap" setting (Settings.get).
---------------------------------------------------------------------------
ns.UI.MinimapButton = ns.UI.MinimapButton or {}
local MB = ns.UI.MinimapButton
MB.DEFAULT_ANGLE = 200
MB.MARGIN = 10 -- button centre sits this far outside the minimap's edge
local MM = "Interface\\Minimap\\"
MB.MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local mmButton

local function minimap()
  local m = _G.Minimap
  if type(m) == "table" then return m end
end

function MB.getAngle()
  local w = type(ns.db) == "table" and ns.db.window
  local m = type(w) == "table" and w.minimap
  local a = type(m) == "table" and tonumber(m.angle)
  return a or MB.DEFAULT_ANGLE
end

local function setAngle(a)
  if type(ns.db) ~= "table" then return end
  if type(ns.db.window) ~= "table" then ns.db.window = {} end
  if type(ns.db.window.minimap) ~= "table" then ns.db.window.minimap = {} end
  ns.db.window.minimap.angle = a
end

local function isSquare()
  local ok, shape = pcall(function() return _G.GetMinimapShape and _G.GetMinimapShape() end)
  return ok and shape == "SQUARE"
end

-- Offset from the minimap centre for an angle: on a circle of radius
-- width/2 + MARGIN, or clamped to the square edge for square minimaps.
function MB.position(angle)
  local mm = minimap()
  local w = (mm and num(mm, "GetWidth")) or 140
  local r = w / 2 + MB.MARGIN
  local c, s = math.cos(math.rad(angle)), math.sin(math.rad(angle))
  if isSquare() then
    local d = r * math.sqrt(2)
    return math.max(-r, math.min(r, c * d)), math.max(-r, math.min(r, s * d))
  end
  return c * r, s * r
end

function MB.reposition()
  local mm = minimap()
  if not (mmButton and mm) then return end
  local x, y = MB.position(MB.getAngle())
  mmButton:ClearAllPoints()
  mmButton:SetPoint("CENTER", mm, "CENTER", x, y)
end

function MB.refresh()
  if not mmButton then return end
  local on = true
  if ns.Settings and ns.Settings.get then on = ns.Settings.get("minimap") ~= false end
  mmButton:SetShown(on)
end

local function dragUpdate()
  local mm = minimap()
  if not mm then return end
  local ok, a = pcall(function()
    local cx, cy = _G.GetCursorPosition()
    local scale = mm:GetEffectiveScale()
    local mx, my = mm:GetCenter()
    return math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
  end)
  if not (ok and type(a) == "number") then return end
  setAngle(a)
  MB.reposition()
end

local function mmTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText("Leveling Advisor")
  GameTooltip:AddLine("Click: open the book", 0.7, 0.7, 0.7)
  GameTooltip:AddLine("Right-click: guide and settings", 0.7, 0.7, 0.7)
  GameTooltip:AddLine("Drag: move", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end

-- Always builds a new button; attach() is the idempotent entry point.
function MB.build()
  local mm = minimap()
  if not mm then return nil end
  local btn = CreateFrame("Button", "LevelingAdvisorMinimapButton", mm)
  btn:SetSize(31, 31)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel((num(mm, "GetFrameLevel") or 0) + 8)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton")

  local bg = btn:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetPoint("CENTER", btn, "CENTER", 0, 0)
  bg:SetTexture(MM .. "UI-Minimap-Background")
  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetSize(18, 18)
  icon:SetPoint("CENTER", btn, "CENTER", 1, -1)
  icon:SetTexture(QuestLogTab.ICON)
  -- Circular mask when the client supports it; otherwise the plain square icon.
  pcall(icon.SetMask, icon, MB.MASK)
  btn.laIcon = icon
  local border = btn:CreateTexture(nil, "OVERLAY")
  border:SetSize(50, 50)
  border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
  border:SetTexture(MM .. "MiniMap-TrackingBorder")
  local hl = btn:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture(MM .. "UI-Minimap-ZoomButton-Highlight")
  hl:SetBlendMode("ADD")

  btn:SetScript("OnMouseDown", function() icon:SetPoint("CENTER", btn, "CENTER", 2, -2) end)
  btn:SetScript("OnMouseUp", function() icon:SetPoint("CENTER", btn, "CENTER", 1, -1) end)
  btn:SetScript("OnEnter", mmTooltip)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  btn:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      ns.UI.Menu.openGuide(btn)
    else
      ns.UI.toggle()
      QuestLogTab.update()
    end
  end)
  btn:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", dragUpdate) end)
  btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

  mmButton = btn
  MB.reposition()
  MB.refresh()
  return btn
end

-- Idempotent; nil without a Minimap. A build error goes to the error handler.
function MB.attach()
  if mmButton then return mmButton end
  if not minimap() then return nil end
  local ok, btn = pcall(MB.build)
  if not ok then geterrorhandler()(btn); return nil end
  return btn
end

---------------------------------------------------------------------------
-- Quest giver ribbon (ns.UI.GiverRibbon): "Recommended — take it" under
-- the quest giver's quest page (QuestFrame) when the quest is in the last
-- recommendation: an eligible section row (not soon, not a turn-in), a pickup
-- of the current zone's frozen route plan, or a pickup for the recommended
-- dungeon. Reads the last
-- result only and never computes in the event: with no usable result it asks
-- the scheduler for one and shows the ribbon when it arrives. Says nothing for
-- other quests. Setting: "giverRibbon". Fail-soft without QuestFrame or
-- GetQuestID.
---------------------------------------------------------------------------
ns.UI.GiverRibbon = ns.UI.GiverRibbon or {}
local Ribbon = ns.UI.GiverRibbon
Ribbon.W, Ribbon.H = 260, 36
Ribbon.TITLE = "Recommended — take it"
Ribbon.GREEN = { 0.25, 0.75, 0.25 }
local PARCHMENT_ATLAS, PARCHMENT_FILE = "QuestBG-Parchment", "Interface\\QuestFrame\\QuestBG"
local ribbonFrame
local waitingFor -- questID whose dialog waits for a result

local function ribbonOn()
  return not (ns.Settings and ns.Settings.get and ns.Settings.get("giverRibbon") == false)
end

local function questFrame()
  local f = _G.QuestFrame
  if type(f) == "table" then return f end
end

local function shownQuestID()
  local id = ns.Util.call(_G.GetQuestID)
  if type(id) == "number" and id > 0 then return id end
end

local function withXP(text, xp)
  if type(xp) == "number" and xp > 0 then
    return text .. " · ~" .. ns.UI.Style.number(xp) .. " XP"
  end
  return text
end

local function estimate(db, questID, state)
  local q = ns.Util.method(db, "quest", questID)
  if type(q) ~= "table" or not (ns.XP and ns.XP.estimate) then return nil end
  local ok, xp = pcall(ns.XP.estimate, q, state.level, state.recordedXP)
  return ok and xp or nil
end

-- The last result, or nil when it is missing or stale for questID: the quest is
-- in its log or done there, or the player's level is not its level.
local function usableLast(questID)
  local A = ns.Advisor
  local last = A and A.last
  local state = last and last.state
  if not (last and last.rec and type(state) == "table") then return nil end
  if type(state.log) == "table" and state.log[questID] then return nil end
  if type(state.completed) == "table" and state.completed[questID] then return nil end
  local level = ns.Util.call(_G.UnitLevel, "player")
  if type(level) == "number" and level ~= state.level then return nil end
  return last
end

-- A row the player can pick up now: the engine's "eligible" status, which a
-- Contract C row carries as state "available" without `soon` (turn-ins are
-- "complete"). A Later row (too high for now) is never one.
local function eligibleRow(row)
  return row.state == "available" and not row.soon and not row.later
end

-- The Later section lists quests too high for now: not recommendations.
local LATER_SECTION = "later"

-- The ribbon's second line for questID in `last`, or nil when not recommended:
-- an eligible row of a recommended section, a pickup of the zone's frozen
-- route, or a pickup for the recommended dungeon.
function Ribbon.reason(last, questID)
  local rec, state = last.rec, last.state
  for _, section in ipairs(rec.sections or {}) do
    if section.key ~= LATER_SECTION then
      for _, row in ipairs(section.rows or {}) do
        if row.questID == questID and eligibleRow(row) then return withXP(tostring(section.title), row.xp) end
      end
    end
  end
  local A, db = ns.Advisor, ns.Advisor.db
  local plan = type(A.cachedPlan) == "function" and A.cachedPlan(state.mapID) or nil
  for i, step in ipairs(plan and plan.steps or {}) do
    for _, a in ipairs(step.actions or {}) do
      if a[1] == questID and a[2] == "pickup" then
        return withXP("Zone route step " .. i, estimate(db, questID, state))
      end
    end
  end
  local d = rec.dungeon
  for _, p in ipairs(type(d) == "table" and d.pickups or {}) do
    if p.questID == questID then
      return withXP(tostring(d.name) .. ": pick up before you go", estimate(db, questID, state))
    end
  end
  return nil
end

local function buildRibbon(host)
  local f = CreateFrame("Frame", "LevelingAdvisorGiverRibbon", host)
  f:SetSize(Ribbon.W, Ribbon.H)
  f:SetPoint("TOP", host, "BOTTOM", 0, -2)
  local Style = ns.UI.Style
  local border = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  border:SetAllPoints(f)
  border:SetColorTexture(Style.LEATHER[1], Style.LEATHER[2], Style.LEATHER[3], 1)
  local page = Style.texture(f, "BACKGROUND", PARCHMENT_ATLAS, PARCHMENT_FILE)
  page:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
  page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
  local logo = f:CreateTexture(nil, "ARTWORK")
  logo:SetSize(20, 20)
  logo:SetPoint("LEFT", f, "LEFT", 8, 0)
  logo:SetTexture(QuestLogTab.ICON)
  local title = Style.text(f, "GameFontNormal")
  Style.setTextColor(title, Ribbon.GREEN[1], Ribbon.GREEN[2], Ribbon.GREEN[3])
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 34, -4)
  title:SetText(Ribbon.TITLE)
  local reason = Style.text(f, "GameFontNormalSmall", Style.INK_SOFT)
  reason:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
  reason:SetWidth(Ribbon.W - 34 - 8)
  reason:SetWordWrap(false)
  f.laLogo, f.laTitle, f.laReason = logo, title, reason
  f:Hide()
  host:HookScript("OnHide", function() Ribbon.hide() end)
  return f
end

-- The ribbon frame on QuestFrame, built once; nil without QuestFrame.
local function ensureRibbon()
  if ribbonFrame then return ribbonFrame end
  local host = questFrame()
  if not host then return nil end
  local ok, f = pcall(buildRibbon, host)
  if not ok then geterrorhandler()(f); return nil end
  ribbonFrame = f
  return f
end

function Ribbon.hide()
  waitingFor = nil
  if ribbonFrame then ribbonFrame:Hide() end
end

-- Shows the ribbon for the quest on the dialog's page, or hides it.
function Ribbon.update()
  waitingFor = nil
  local id = shownQuestID()
  if not (id and ribbonOn() and questFrame()) then Ribbon.hide(); return end
  local last = usableLast(id)
  if not last then
    Ribbon.hide()
    waitingFor = id
    local s = ns.Advisor and ns.Advisor.scheduler
    if s then pcall(s.request, s, "open") end -- a compute later, never here
    return
  end
  local text = Ribbon.reason(last, id)
  if not text then Ribbon.hide(); return end
  local f = ensureRibbon()
  if not f then return end
  f.laReason:SetText(text)
  f:Show()
end

-- A new result while a dialog waits: show the ribbon if that quest is still up.
local function onResult()
  local id = waitingFor
  if not id then return end
  local host = questFrame()
  if not (host and ns.Util.method(host, "IsShown") and shownQuestID() == id) then
    waitingFor = nil
    return
  end
  if usableLast(id) then Ribbon.update() else waitingFor = nil end
end

ns.Events.on("QUEST_DETAIL", Ribbon.update)
for _, e in ipairs({ "QUEST_FINISHED", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_GREETING" }) do
  ns.Events.on(e, Ribbon.hide)
end
if ns.Advisor and type(ns.Advisor.onUpdate) == "function" then ns.Advisor.onUpdate(onResult) end

ns.Init.onReady(function()
  QuestLogTab.attach()
  MB.attach()
  ns.Settings.onChange(function(key)
    if key == "minimap" then MB.refresh() end
    if key == "giverRibbon" and not ribbonOn() then Ribbon.hide() end
  end)
  QuestLogTab.registerCompartment()
end)

ns.Events.on("ADDON_LOADED", function(name)
  if name == "Blizzard_WorldMap" then QuestLogTab.attach() end
end)
