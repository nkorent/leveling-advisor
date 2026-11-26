-- A side tab on the quest log's right edge that opens the book, plus the
-- addon compartment entry. Fail-soft: a missing host or compartment is
-- skipped silently.
local addonName, ns = ...; ns.UI = ns.UI or {}; ns.UI.QuestLogTab = ns.UI.QuestLogTab or {}
local QuestLogTab = ns.UI.QuestLogTab

-- QuestMapFrame is the quest log on this client; QuestLogFrame is only a
-- fallback for a client without it (never both).
QuestLogTab.HOSTS = { "QuestMapFrame", "QuestLogFrame" }
QuestLogTab.NATIVE_TABS = { "QuestsTab", "MapLegendTab", "EventsTab" }
-- x: the tab's left edge tucks 7 px under the frame's right border (the border
--    frame is drawn over it, so it looks like a bookmark sticking out of a book).
-- y: 60 px below the frame's top, level with the top of the quest list area
--    (just under the title bar).
-- gap: spacing below the last native side tab, when the client has them.
QuestLogTab.OFFSET = { x = -7, y = -60, gap = -3 }
QuestLogTab.CLOSE_X = -6 -- overlap under the border when anchored to the close button
QuestLogTab.SIZE = { w = 36, h = 40 }
QuestLogTab.ICON_SIZE = 26
local MEDIA = "Interface\\AddOns\\" .. tostring(addonName) .. "\\Media\\"
QuestLogTab.ICON = MEDIA .. "Logo"

local BOOKMARK = MEDIA .. "BookmarkTab"
local tabs = {} -- host frame -> tab

local function findHost()
  for _, name in ipairs(QuestLogTab.HOSTS) do
    local host = _G[name]
    if type(host) == "table" then return host end
  end
end

-- The last native side tab that is actually shown. On some clients the tab
-- tables exist but are hidden (no side tabs are visible), so they don't count.
local function lastNativeTab(host)
  local last, lastKey
  for _, key in ipairs(QuestLogTab.NATIVE_TABS) do
    local ok, t = pcall(function()
      local t = host[key]
      return type(t) == "table" and t:IsShown() and t or nil
    end)
    if ok and t then last, lastKey = t, key end
  end
  return last, lastKey
end

-- The frame that draws the visible outer border of the Map & Quest Log; only
-- meaningful when QuestMapFrame is the host (it lives inside WorldMapFrame).
local function borderFrame(host)
  if host ~= _G.QuestMapFrame then return host end
  local wm = _G.WorldMapFrame
  if type(wm) ~= "table" then return host end
  local ok, border = pcall(function() return wm.BorderFrame end)
  if ok and type(border) == "table" then return border end
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

local function num(frame, method)
  local ok, v = pcall(function() return frame[method](frame) end)
  if ok and type(v) == "number" then return v end
end

-- Decides the anchor every time it runs (native tabs can appear later) and
-- applies the calibration offset on every path. Sets tab.laAnchorKind.
local function applyAnchor(tab, host)
  local dx, dy = QuestLogTab.getOffset()
  local anchor = borderFrame(host)
  local native, key = lastNativeTab(host)
  tab:ClearAllPoints()
  if native then
    tab:SetFrameLevel(host:GetFrameLevel() + 10)
    tab:SetPoint("TOP", native, "BOTTOM", dx, QuestLogTab.OFFSET.gap + dy)
    tab.laAnchorKind = "native tab " .. key
    return
  end
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

local function showTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText("Leveling Advisor")
  GameTooltip:AddLine("Click to open the advisor.", 1, 1, 1)
  GameTooltip:Show()
end

local function build(host, index)
  local tab = CreateFrame("Button", "LevelingAdvisorQuestLogTab" .. index, host)
  tab:SetSize(QuestLogTab.SIZE.w, QuestLogTab.SIZE.h)
  applyAnchor(tab, host)
  tab.laHost = host
  -- Re-apply when the map frame resizes or reappears (maximise / minimise).
  for _, f in ipairs({ borderFrame(host), host }) do
    for _, ev in ipairs({ "OnShow", "OnSizeChanged" }) do
      pcall(function() f:HookScript(ev, function() applyAnchor(tab, host) end) end)
    end
  end

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

  tab:SetScript("OnEnter", showTooltip)
  tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
  tab:SetScript("OnClick", function()
    ns.UI.toggle()
    QuestLogTab.update()
  end)
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

function QuestLogTab.reanchor()
  for host, tab in pairs(tabs) do
    applyAnchor(tab, host)
  end
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

local function r(v) return v and math.floor(v + 0.5) or "n/a" end

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
  return string.format("anchor %s; tab offset %s,%s; close button %s; border %s; WorldMapFrame %s; QuestMapFrame %s",
    tab and tab.laAnchorKind or "none", r(ox), r(oy), pos(host and closeButton(host)), pos(border ~= wm and border or nil), pos(wm), pos(_G.QuestMapFrame))
end

function QuestLogTab.update()
  local open = ns.UI.isShown()
  for _, tab in pairs(tabs) do tab.laSelected:SetShown(open) end
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
-- right-click opens settings, drag moves it around the edge.
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
  GameTooltip:AddLine("Right-click: settings", 0.7, 0.7, 0.7)
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
      ns.Settings.open()
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

ns.Init.onReady(function()
  QuestLogTab.attach()
  MB.attach()
  ns.Settings.onChange(function(key) if key == "minimap" then MB.refresh() end end)
  QuestLogTab.registerCompartment()
end)

ns.Events.on("ADDON_LOADED", function(name)
  if name == "Blizzard_WorldMap" then QuestLogTab.attach() end
end)
