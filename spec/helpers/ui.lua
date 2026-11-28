-- UI spec helper: a fake WoW widget toolkit and a loader for the whole addon.
--
--   ui.FILES                 the addon's .lua files in TOC order, Data/ excluded
--   ui.load(opts) -> ns, env, fake, out
--   ui.with(name, overrides)  a copy of a named state with fields overridden
--   ui.spy(tbl, name[, fn])  wraps tbl[name] (or replaces it with fn); the spy
--                            counts calls in .n and keeps each call's args in
--                            .calls (a list of {n = select("#"), ...})
--
-- ui.load opts:
--   state    "S18" | "S20" | "H20" | a Contract B table: fake.setState(state)
--            runs after login
--   noData   do not load spec/fixtures/data_small.lua
--   patch    fn(ns.Data), runs before login
--   noAtlas  C_Texture.GetAtlasInfo returns nil for every atlas
--   atlases  extra atlas names GetAtlasInfo knows (default: ui.ATLASES, the ones
--            confirmed on the 1.60.1 client)
--   db, chardb  the saved variables found at ADDON_LOADED
--   globals  extra env globals (set before the addon files load)
--   without  list of global names removed from the fake env
--   questMap "tabs" (QuestMapFrame with QuestsTab and MapLegendTab), "plain"
--            (QuestMapFrame without native tabs) or nil (no QuestMapFrame)
--   sideTabTemplate  true: the client has the retail quest log side tab template
--            (QuestLogTabButtonTemplate, QuestLogTabButtonMixin; see sideTab below),
--            for native tabs and other addons' tabs built from it; otherwise
--            CreateFrame ignores that template name
--   questLog true adds a QuestLogFrame
--   questFrame true adds QuestFrame (the quest giver dialog, hidden) and GetQuestID, which
--            returns fake.questID (the quest on the dialog's page)
--   worldMap true adds WorldMapFrame, a map canvas (spec/helpers/mapcanvas.lua: SetMapID,
--            AddDataProvider, AcquirePin with the UI/MapPins.xml template; its
--            acquired pins are WorldMapFrame.pins). CreateFromMixins, Mixin,
--            MapCanvasPinMixin and MapCanvasDataProviderMixin always exist.
--   art      "tiles": C_Map.GetMapArtLayers / GetMapArtLayerTextures give a 1002 x 668
--            layer of 256 px tiles (12 file IDs) for every map; nil: no art API
--   minimap  true adds a 140 x 140 Minimap centred at (500, 500) with effective scale 1,
--            and GetCursorPosition (set fake.cursor = { x, y })
--   compartment true adds AddonCompartmentFrame (RegisterAddon is recorded in
--            fake.compartment)
--   waypointPin  with worldMap: Blizzard's user-waypoint pin, as Blizzard_SharedMapDataProviders
--            has it: WaypointLocationPinMixin (on MapCanvasPinMixin), the
--            WaypointLocationPinTemplate and a data provider on the world map that shows one
--            such pin at the user waypoint when it is on the shown map. Like the client's
--            provider (USER_WAYPOINT_UPDATED), it refreshes whenever the user waypoint changes.
--
-- fake (see the Plan 4b Task 1 brief for the full list):
--   newFrame(kind, name, parent, template)  the fake CreateFrame
--   widgets, named(name), find(pred), findAll(pred)
--   text(s)       the first visible widget whose text is s, else the first one
--   visible(w)    w and every parent are shown
--   click(w, button), enter(w), leave(w), type(editBox, s)
--   flush()       runs queued C_Timer callbacks
--   combat(bool)  the InCombatLockdown result
--   tooltip       GameTooltip: { owner, anchor, lines = {{text, r, g, b}}, itemID, shown }
--   setState(state)
--   waypoints, superTracked, superTrackedQuest, openedMaps   map API results
--                 (UiMapPoint, C_Map.SetUserWaypoint, C_SuperTrack, OpenWorldMap)
--   userWaypoint  what C_Map.GetUserWaypoint returns: { uiMapID, position = { x, y } } (0-1,
--                 a Vector2D with GetXY), set by C_Map.SetUserWaypoint or
--   setUserWaypoint(mapID, x, y)  a waypoint the player places by hand (nil clears it)
--   cleared       how many times C_Map.ClearUserWaypoint ran (it clears userWaypoint)
--   waypointProvider  the waypointPin data provider
--   scrollBoxes   every WowScrollBoxList created (box.rows = {{frame, element, extent}};
--                 box.retained = the last SetDataProvider's retain-scroll argument)
--   row(questID)  the Contract C row of that quest in the current rec
--   rowFrame(questID)  the list row frame now showing that quest
--   out           the printed lines (also the 4th value of ui.load)
-- env.errors collects errors sent to geterrorhandler() (assert it is empty in
-- "no error" tests: the addon pcalls listeners, events and refreshes).
--
-- Widget fake: strict, like the client. Each widget kind has the method set of
-- its real widget type (ui.API[kind], built from the retail hierarchy:
-- ScriptRegion < Region < Texture / FontString, ScriptRegion < Frame < Button
-- < CheckButton ...). A method of that set is the implementation below, or a
-- stub that records the call in w.calls as {name, ...} and returns nil. Any
-- other key reads as nil, so calling a misspelt or missing method raises
-- "attempt to call method 'X' (a nil value)", as on the client. CreateFrame
-- rejects unknown frame types.
-- GetChildren / GetRegions return a frame's child frames / textures and font
-- strings in creation order (SetParent moves a frame). GetLeft/GetRight/GetTop/GetBottom are stubs (nil): a spec that needs
-- a position sets them on the widget.
-- EditBox:SetText fires OnTextChanged(self, false) like the client;
-- fake.type sets the text the way typing does and fires OnTextChanged(self, true).
-- ScrollBox lists hand their row frames back in reversed order on every
-- SetDataProvider (a pool gives no order guarantee), so stale per-frame state
-- shows up.
local addon = require("spec.helpers.addon")
local load_addon = require("spec.helpers.load_addon")
local mapcanvas = require("spec.helpers.mapcanvas")

local ADDON_DIR = "LevelingAdvisor"
local FIXTURE = "spec/fixtures/data_small.lua"

local ui = {}

---------------------------------------------------------------------------
-- File list, read from the TOC so it follows the client's load order.
---------------------------------------------------------------------------
local function tocFiles()
  local files = {}
  for line in io.lines(ADDON_DIR .. "/LevelingAdvisor.toc") do
    line = line:gsub("%s+$", "")
    if line:match("%.lua$") and not line:match("^Data\\") then
      files[#files + 1] = (line:gsub("\\", "/"))
    end
  end
  return files
end

ui.FILES = tocFiles()

-- The map pin template from UI/MapPins.xml (parsed once).
local pinTemplate
function ui.pinTemplate()
  pinTemplate = pinTemplate
    or assert(mapcanvas.template(ADDON_DIR .. "/UI/MapPins.xml", "LevelingAdvisorMapPinTemplate"))
  return pinTemplate
end

---------------------------------------------------------------------------
-- Small utilities.
---------------------------------------------------------------------------
local function deepcopy(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local out = {}
  seen[v] = out
  for k, x in pairs(v) do out[deepcopy(k, seen)] = deepcopy(x, seen) end
  return out
end

local function packArgs(...)
  return { n = select("#", ...), ... }
end

-- A copy of a named state with fields overridden.
function ui.with(name, overrides)
  local s = deepcopy((assert(require("spec.helpers.states")[name], "unknown state " .. name)))
  for k, v in pairs(overrides or {}) do s[k] = v end
  return s
end

function ui.spy(tbl, name, fn)
  local original = tbl[name]
  local impl = fn or original
  local spy = { n = 0, calls = {}, original = original }
  tbl[name] = function(...)
    spy.n = spy.n + 1
    spy.calls[spy.n] = packArgs(...)
    if type(impl) == "function" then return impl(...) end
  end
  return spy
end

---------------------------------------------------------------------------
-- Widget fake.
---------------------------------------------------------------------------
local W = {} -- implemented widget methods

local function normPoint(self, point, a, b, c, d)
  if type(a) == "number" then return { point, self.parent, point, a, b or 0 } end
  if a == nil then return { point, self.parent, point, 0, 0 } end
  if type(b) == "number" then return { point, a, point, b, c or 0 } end
  return { point, a, b or point, c or 0, d or 0 }
end

function W:SetPoint(point, ...)
  local p = normPoint(self, point, ...)
  for i, old in ipairs(self.points) do
    if old[1] == point then self.points[i] = p; return end
  end
  self.points[#self.points + 1] = p
end
function W:GetPoint(i)
  local p = self.points[i or 1]
  if not p then return nil end
  return p[1], p[2], p[3], p[4], p[5]
end
function W:GetNumPoints() return #self.points end
function W:ClearAllPoints() self.points = {}; self.allPoints = nil end
function W:SetAllPoints(rel)
  rel = rel or self.parent
  self.points = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 } }
  self.allPoints = rel
end

function W:SetSize(w, h) self.width, self.height = w, h end
function W:SetWidth(w) self.width = w end
function W:SetHeight(h) self.height = h end
function W:GetWidth() return self.width or 0 end
function W:GetHeight() return self.height or 0 end
function W:GetSize() return self:GetWidth(), self:GetHeight() end

local function run(self, script, ...)
  local fn = self.scripts[script]
  if fn then return fn(self, ...) end
end

function W:Show()
  if self.shown then return end
  self.shown = true
  run(self, "OnShow")
end
function W:Hide()
  if not self.shown then return end
  self.shown = false
  run(self, "OnHide")
end
function W:SetShown(v) if v then self:Show() else self:Hide() end end
function W:IsShown() return self.shown end
function W:IsVisible()
  local w = self
  while w do
    if not w.shown then return false end
    w = w.parent
  end
  return true
end

-- EditBox:SetText fires OnTextChanged(self, false), as on the client. A
-- button's SetText sets its font string's text too (GetFontString).
function W:SetText(t)
  self.text = t
  local fs = rawget(self, "fontString")
  if fs then fs.text = t end
  if self.kind == "EditBox" then run(self, "OnTextChanged", false) end
end
function W:SetFontString(fs) self.fontString = fs end
function W:GetFontString() return rawget(self, "fontString") end
function W:GetText() return self.text end
function W:SetFormattedText(fmt, ...) self.text = string.format(fmt, ...) end
function W:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a } end
function W:GetTextColor()
  local c = self.textColor or {}
  return c[1], c[2], c[3], c[4]
end
function W:SetFontObject(f) self.font = f end
function W:SetShadowOffset(x, y)
  self.shadowOffset = { x, y }
  self.calls[#self.calls + 1] = { "SetShadowOffset", x, y }
end
function W:GetShadowOffset()
  local o = self.shadowOffset or { 0, 0 }
  return o[1], o[2]
end
function W:SetShadowColor(r, g, b, a)
  self.shadowColor = { r, g, b, a }
  self.calls[#self.calls + 1] = { "SetShadowColor", r, g, b, a }
end
function W:GetShadowColor()
  local c = self.shadowColor or { 0, 0, 0, 0 }
  return c[1], c[2], c[3], c[4]
end
function W:GetFontObject() return self.font end
function W:SetWordWrap(v) self.wordWrap = v end
function W:SetJustifyH(v) self.justifyH = v end
function W:SetJustifyV(v) self.justifyV = v end
function W:GetStringWidth() return #(self.text or "") * 6 end
function W:GetStringHeight()
  local n = #(self.text or "")
  if n == 0 then return 0 end
  local width = self.width or 0
  if width <= 0 then return 14 end
  return 14 * math.ceil(n * 6 / width)
end

function W:SetScript(name, fn) self.scripts[name] = fn end
function W:GetScript(name) return self.scripts[name] end
function W:HasScript() return true end
function W:HookScript(name, fn)
  local old = self.scripts[name]
  if old then
    self.scripts[name] = function(...) old(...); return fn(...) end
  else
    self.scripts[name] = fn
  end
end

-- Children go to the client that made their parent (rawget: _new is a field).
function W:CreateTexture(name, layer, template, sub)
  local t = rawget(self, "_new")("Texture", name, self)
  t.layer, t.textureTemplate, t.sublevel = layer, template, sub
  return t
end
function W:CreateFontString(name, layer, font)
  local fs = rawget(self, "_new")("FontString", name, self)
  fs.layer, fs.font = layer, font
  return fs
end

function W:GetParent() return self.parent end
-- Each frame keeps its child frames in creation order (GetChildren).
local function adopt(parent, child)
  if not parent then return end
  local list = rawget(parent, "_children")
  if not list then list = {}; rawset(parent, "_children", list) end
  list[#list + 1] = child
end
function W:SetParent(p)
  local old = self.parent and rawget(self.parent, "_children")
  for i, c in ipairs(old or {}) do
    if c == self then table.remove(old, i); break end
  end
  self.parent = p
  adopt(p, self)
end
local function isRegion(w) return w.kind == "Texture" or w.kind == "FontString" end
-- The child frames (not textures or font strings), like the client.
function W:GetChildren()
  local out = {}
  for _, c in ipairs(rawget(self, "_children") or {}) do
    if not isRegion(c) then out[#out + 1] = c end
  end
  return unpack(out)
end
-- The frame's textures and font strings, in creation order.
function W:GetRegions()
  local out = {}
  for _, c in ipairs(rawget(self, "_children") or {}) do
    if isRegion(c) then out[#out + 1] = c end
  end
  return unpack(out)
end
function W:GetName() return self.name end
function W:GetObjectType() return self.kind end
function W:RegisterEvent(e) self.events[e] = true end
function W:UnregisterEvent(e) self.events[e] = nil end

-- Textures.
function W:SetAtlas(a) self.atlas = a; self.texture = nil end
function W:GetAtlas() return self.atlas end
function W:SetTexture(t) self.texture = t; self.atlas = nil end
function W:GetTexture() return self.texture end
function W:SetTexCoord(...) self.texCoord = { ... } end
-- Always the 8 corner values (ULx, ULy, LLx, LLy, URx, URy, LRx, LRy), like the client.
function W:GetTexCoord()
  local c = self.texCoord
  if not c then return 0, 0, 0, 1, 1, 0, 1, 1 end
  if #c == 4 then return c[1], c[3], c[1], c[4], c[2], c[3], c[2], c[4] end
  return unpack(c, 1, 8)
end
function W:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
function W:SetDesaturated(v) self.desaturated = v end
function W:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function W:SetGradient(orientation, minColor, maxColor)
  self.gradient = { orientation, minColor, maxColor }
end
function W:SetBlendMode(m) self.blend = m end
function W:GetBlendMode() return self.blend end
function W:SetDrawLayer(layer, sub) self.layer, self.sublevel = layer, sub end
function W:GetDrawLayer() return self.layer, self.sublevel end

-- Frame state.
function W:SetAlpha(a) self.alpha = a end
function W:GetAlpha() return self.alpha or 1 end
function W:SetScale(s) self.scale = s end
function W:GetScale() return self.scale or 1 end
function W:SetChecked(v) self.checked = v and true or false end
function W:GetChecked() return self.checked or false end
function W:Enable() self.enabled = true end
function W:Disable() self.enabled = false end
function W:SetEnabled(v) self.enabled = v and true or false end
function W:IsEnabled() return self.enabled ~= false end
function W:SetFrameStrata(s) self.strata = s end
function W:GetFrameStrata() return self.strata or (self.parent and self.parent:GetFrameStrata()) or "MEDIUM" end
function W:SetFrameLevel(l) self.level = l end
function W:GetFrameLevel()
  if self.level then return self.level end
  return self.parent and self.parent:GetFrameLevel() + 1 or 0
end
function W:SetToplevel(v) self.toplevel = v end
function W:Raise() self.raised = (self.raised or 0) + 1 end

-- Mouse and moving.
function W:SetMovable(v) self.movable = v end
function W:EnableMouse(v) self.mouse = v end
function W:SetPropagateMouseClicks(v) self.propagateClicks = v end
function W:RegisterForDrag(...) self.drag = { ... } end
function W:RegisterForClicks(...) self.clicks = { ... } end
function W:StartMoving() self.moving = true end
function W:StopMovingOrSizing() self.moving = false end
function W:SetClampedToScreen(v) self.clamped = v end
function W:SetClipsChildren(v) self.clips = v end

-- Button and bar parts.
function W:SetHighlightTexture(t, blend) self.highlight = t; self.highlightBlend = blend end
-- The highlight texture object when one was set as a texture (a file path set
-- reads as nil here).
function W:GetHighlightTexture()
  if type(self.highlight) == "table" then return self.highlight end
end
function W:SetNormalTexture(t) self.normal = t end
function W:SetPushedTexture(t) self.pushed = t end
function W:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
function W:SetValue(v) self.value = v end
function W:GetValue() return self.value end
function W:SetStatusBarTexture(t) self.barTexture = t end
function W:SetStatusBarColor(r, g, b, a) self.barColor = { r, g, b, a } end

-- Scroll and edit.
function W:SetScrollChild(c) self.scrollChild = c end
function W:SetVerticalScroll(v) self.verticalScroll = v end
function W:SetFocus() self.focused = true end
function W:ClearFocus() self.focused = false end
function W:HighlightText() self.highlighted = true end

---------------------------------------------------------------------------
-- The method sets of the client's widget types (retail engine, 1.60.1). Only
-- these names resolve on a widget of that kind; see the note at the top.
---------------------------------------------------------------------------
local function list(...)
  local out = {}
  for i = 1, select("#", ...) do
    for _, k in ipairs((select(i, ...))) do out[#out + 1] = k end
  end
  return out
end

local SCRIPT_REGION = {
  "GetName", "GetObjectType", "IsObjectType", "GetParent", "SetParent", "IsForbidden",
  "SetScript", "GetScript", "HookScript", "HasScript",
  "Show", "Hide", "SetShown", "IsShown", "IsVisible",
  "SetPoint", "GetPoint", "GetNumPoints", "ClearAllPoints", "ClearPoint", "SetAllPoints",
  "AdjustPointsOffset", "GetPointByName",
  "SetSize", "SetWidth", "SetHeight", "GetSize", "GetWidth", "GetHeight",
  "GetLeft", "GetRight", "GetTop", "GetBottom", "GetCenter", "GetRect", "GetScaledRect",
  "GetBoundsRect", "IsRectValid", "IsAnchoringRestricted",
  "EnableMouse", "IsMouseEnabled", "IsMouseOver", "EnableMouseMotion", "EnableMouseClicks",
  "SetMouseClickEnabled", "SetMouseMotionEnabled", "IsMouseClickEnabled", "IsMouseMotionEnabled",
  "IsMouseMotionFocus", "SetPassThroughButtons",
  "SetAlpha", "GetAlpha", "GetEffectiveAlpha", "SetIgnoreParentAlpha", "IsIgnoringParentAlpha",
  "GetEffectiveScale", "CreateAnimationGroup", "GetAnimationGroups", "StopAnimating",
  "IsDragging", "CanChangeProtectedState", "IsProtected",
}
local REGION = { "SetDrawLayer", "GetDrawLayer", "SetVertexColor", "GetVertexColor" }
local TEXTURE = {
  "SetTexture", "GetTexture", "GetTextureFileID", "GetTextureFilePath", "SetAtlas", "GetAtlas",
  "SetTexCoord", "GetTexCoord", "SetColorTexture", "SetGradient", "SetBlendMode", "GetBlendMode",
  "SetDesaturated", "IsDesaturated", "SetDesaturation", "GetDesaturation", "SetRotation",
  "GetRotation", "SetMask", "AddMaskTexture", "RemoveMaskTexture", "GetNumMaskTextures",
  "SetHorizTile", "SetVertTile", "SetTexelSnappingBias", "SetSnapToPixelGrid", "SetNonBlocking",
}
local FONT_INSTANCE = {
  "SetFont", "GetFont", "SetFontObject", "GetFontObject", "SetTextColor", "GetTextColor",
  "SetJustifyH", "GetJustifyH", "SetJustifyV", "GetJustifyV", "SetShadowColor", "GetShadowColor",
  "SetShadowOffset", "GetShadowOffset", "SetSpacing", "GetSpacing", "SetIndentedWordWrap",
}
local FONT_STRING = {
  "SetText", "GetText", "SetFormattedText", "SetWordWrap", "CanWordWrap", "SetNonSpaceWrap",
  "CanNonSpaceWrap", "SetMaxLines", "GetMaxLines", "GetNumLines", "GetStringWidth",
  "GetStringHeight", "GetUnboundedStringWidth", "GetWrappedWidth", "IsTruncated", "SetTextHeight",
  "SetTextScale", "GetTextScale", "GetLineHeight", "SetTextToFit",
}
local FRAME = {
  "CreateTexture", "CreateFontString", "CreateMaskTexture", "CreateLine",
  "RegisterEvent", "UnregisterEvent", "UnregisterAllEvents", "IsEventRegistered", "RegisterUnitEvent",
  "SetFrameStrata", "GetFrameStrata", "SetFrameLevel", "GetFrameLevel", "SetFixedFrameStrata",
  "SetFixedFrameLevel", "SetToplevel", "IsToplevel", "Raise", "Lower",
  "SetMovable", "IsMovable", "SetResizable", "IsResizable", "StartMoving", "StartSizing",
  "StopMovingOrSizing", "SetUserPlaced", "IsUserPlaced", "SetDontSavePosition", "GetDontSavePosition",
  "SetClampedToScreen", "IsClampedToScreen", "SetClampRectInsets", "SetResizeBounds",
  "RegisterForDrag", "EnableMouseWheel", "IsMouseWheelEnabled", "EnableKeyboard",
  "IsKeyboardEnabled", "SetPropagateKeyboardInput", "SetPropagateMouseClicks", "SetHitRectInsets", "GetHitRectInsets",
  "SetScale", "GetScale", "SetClipsChildren", "DoesClipChildren",
  "GetChildren", "GetNumChildren", "GetRegions", "GetNumRegions", "SetID", "GetID",
  "SetAttribute", "GetAttribute", "SetHyperlinksEnabled", "SetFlattensRenderLayers",
  "SetUsingParentLevel", "SetIgnoreParentScale", "IsIgnoringParentScale",
  "SetIgnoreParentAlpha", "SetFrameBuffer", "SetDrawLayerEnabled",
}
local BUTTON = {
  "RegisterForClicks", "Click", "Enable", "Disable", "SetEnabled", "IsEnabled",
  "SetText", "GetText", "SetFormattedText", "GetTextWidth", "GetTextHeight", "SetFontString",
  "GetFontString", "SetNormalFontObject", "GetNormalFontObject", "SetHighlightFontObject",
  "GetHighlightFontObject", "SetDisabledFontObject", "GetDisabledFontObject",
  "SetNormalTexture", "GetNormalTexture", "SetPushedTexture", "GetPushedTexture",
  "SetHighlightTexture", "GetHighlightTexture", "SetDisabledTexture", "GetDisabledTexture",
  "SetNormalAtlas", "SetPushedAtlas", "SetHighlightAtlas", "SetDisabledAtlas",
  "SetButtonState", "GetButtonState", "LockHighlight", "UnlockHighlight", "IsHighlightLocked",
  "SetMotionScriptsWhileDisabled", "SetPushedTextOffset", "GetPushedTextOffset",
}
local CHECK_BUTTON = {
  "SetChecked", "GetChecked", "SetCheckedTexture", "GetCheckedTexture",
  "SetDisabledCheckedTexture", "GetDisabledCheckedTexture",
}
local EDIT_BOX = {
  "SetText", "GetText", "Insert", "SetFocus", "ClearFocus", "HasFocus", "HighlightText",
  "SetAutoFocus", "IsAutoFocus", "SetMaxLetters", "GetMaxLetters", "SetMultiLine", "IsMultiLine",
  "SetNumeric", "IsNumeric", "GetNumber", "SetNumber", "SetCursorPosition", "GetCursorPosition",
  "SetTextInsets", "GetTextInsets", "SetCountInvisibleLetters", "SetHistoryLines",
  "AddHistoryLine", "ClearHistory", "SetBlinkSpeed", "Enable", "Disable", "SetEnabled",
  "IsEnabled", "SetSecurityDisablePaste", "SetHighlightColor",
}
local SCROLL_FRAME = {
  "SetScrollChild", "GetScrollChild", "SetVerticalScroll", "GetVerticalScroll",
  "SetHorizontalScroll", "GetHorizontalScroll", "GetVerticalScrollRange",
  "GetHorizontalScrollRange", "UpdateScrollChildRect",
}
local VALUE_BAR = { "SetMinMaxValues", "GetMinMaxValues", "SetValue", "GetValue", "SetOrientation",
  "GetOrientation" }
local SLIDER = {
  "SetValueStep", "GetValueStep", "SetObeyStepOnDrag", "SetStepsPerPage", "SetThumbTexture",
  "GetThumbTexture", "Enable", "Disable", "SetEnabled", "IsEnabled",
}
local STATUS_BAR = {
  "SetStatusBarTexture", "GetStatusBarTexture", "SetStatusBarColor", "GetStatusBarColor",
  "SetStatusBarAtlas", "SetReverseFill", "GetReverseFill", "SetFillStyle", "GetFillStyle",
  "SetRotatesTexture",
}
local GAME_TOOLTIP = {
  "SetOwner", "GetOwner", "IsOwned", "ClearLines", "SetText", "AddLine", "AddDoubleLine",
  "AddTexture", "NumLines", "SetItemByID", "SetHyperlink", "SetMinimumWidth", "SetPadding",
  "FadeOut",
}

local function apiSet(...)
  local t = {}
  for _, k in ipairs(list(...)) do t[k] = true end
  return t
end

-- kind -> { [methodName] = true }
ui.API = {
  Texture = apiSet(SCRIPT_REGION, REGION, TEXTURE),
  FontString = apiSet(SCRIPT_REGION, REGION, FONT_INSTANCE, FONT_STRING),
  Frame = apiSet(SCRIPT_REGION, FRAME),
  EventFrame = apiSet(SCRIPT_REGION, FRAME),
  Button = apiSet(SCRIPT_REGION, FRAME, BUTTON),
  ItemButton = apiSet(SCRIPT_REGION, FRAME, BUTTON),
  CheckButton = apiSet(SCRIPT_REGION, FRAME, BUTTON, CHECK_BUTTON),
  EditBox = apiSet(SCRIPT_REGION, FRAME, FONT_INSTANCE, EDIT_BOX),
  ScrollFrame = apiSet(SCRIPT_REGION, FRAME, SCROLL_FRAME),
  Slider = apiSet(SCRIPT_REGION, FRAME, VALUE_BAR, SLIDER),
  StatusBar = apiSet(SCRIPT_REGION, FRAME, VALUE_BAR, STATUS_BAR),
  GameTooltip = apiSet(SCRIPT_REGION, FRAME, GAME_TOOLTIP),
}
-- CreateFrame accepts these (not Texture or FontString).
local FRAME_TYPES = {
  Frame = true, EventFrame = true, Button = true, ItemButton = true, CheckButton = true,
  EditBox = true, ScrollFrame = true, Slider = true, StatusBar = true, GameTooltip = true,
}

-- A method of the kind's set that the fake does not implement: records the call.
local stubs = {}
local function stub(k)
  local fn = stubs[k]
  if not fn then
    fn = function(self, ...)
      self.calls[#self.calls + 1] = { k, ... }
      return nil
    end
    stubs[k] = fn
  end
  return fn
end

-- One metatable per kind; its __index is a plain method table, as on the client
-- (MapPins reads getmetatable(pin).__index for the frame's own methods).
local KIND_MT = {}
for kind, api in pairs(ui.API) do
  local methods = {}
  for k in pairs(api) do methods[k] = W[k] or stub(k) end
  KIND_MT[kind] = { __index = methods }
end

-- Atlases confirmed on the 1.60.1 client (design spec, platform facts; the
-- diagnostic census): GetAtlasInfo knows only these unless opts.atlases adds more.
ui.ATLASES = {
  "QuestNormal", "QuestTurnin", "QuestDaily", "Waypoint-MapPin-Tracked",
  "Waypoint-MapPin-Untracked", "QuestBG-Parchment", "Campaign-QuestLog-LoreBook",
}

---------------------------------------------------------------------------
-- The fake client.
---------------------------------------------------------------------------
local function newClient(opts)
  local fake = { widgets = {}, scrollBoxes = {} }
  local env -- set by ui.load
  local combat = false

  local applyTemplates -- forward

  -- opts.sideTabTemplate: the retail quest log side tab (QuestMapFrame.xml,
  -- QuestLogTabButtonTemplate with QuestLogTabButtonMixin): a 43 x 55 tab with
  -- the questlog-tab-side background, an Icon, a hidden SelectedTexture (the gold
  -- select glow) and a hover glow on the HIGHLIGHT layer. The mixin's mouse-up
  -- switches the quest log's display mode; its SetChecked shows the glow and
  -- swaps the icon atlas.
  local SIDE_TAB = "QuestLogTabButtonTemplate"
  local sideTabMixin = {}
  function sideTabMixin:OnMouseDown() self.Icon:AdjustPointsOffset(1, -1) end
  function sideTabMixin:OnMouseUp(button, upInside)
    self.Icon:AdjustPointsOffset(-1, 1)
    if button == "LeftButton" and upInside then self:GetParent():SetDisplayMode(self.displayMode) end
  end
  function sideTabMixin:OnEnter()
    fake.tooltip:SetOwner(self, "ANCHOR_RIGHT", -4, -4)
    fake.tooltip:SetText(self.tooltipText)
    fake.tooltip:Show()
  end
  function sideTabMixin:OnLeave() fake.tooltip:Hide() end
  function sideTabMixin:SetChecked(checked)
    self.Icon:SetAtlas(checked and self.activeAtlas or self.inactiveAtlas)
    self.SelectedTexture:SetShown(checked)
  end
  local function sideTab(w)
    for k, v in pairs(sideTabMixin) do w[k] = v end
    w.width, w.height = 43, 55
    w.Background = w:CreateTexture(nil, "BACKGROUND")
    w.Background:SetAtlas("questlog-tab-side")
    w.Background:SetPoint("CENTER")
    w.Icon = w:CreateTexture(nil, "ARTWORK")
    w.Icon:SetPoint("CENTER", w, "CENTER", -2, 0)
    w.SelectedTexture = w:CreateTexture(nil, "OVERLAY")
    w.SelectedTexture:SetAtlas("questlog-tab-side-glow-select")
    w.SelectedTexture:SetPoint("CENTER")
    w.SelectedTexture.shown = false
    local hover = w:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAtlas("questlog-tab-side-glow-hover")
    hover:SetPoint("CENTER")
    for _, s in ipairs({ "OnMouseDown", "OnMouseUp", "OnEnter", "OnLeave" }) do w.scripts[s] = w[s] end
  end

  local function newWidget(kind, name, parent, template)
    local mt = assert(KIND_MT[kind], "the fake client has no widget type " .. tostring(kind))
    local w = setmetatable({
      kind = kind, name = name, parent = parent, template = template,
      shown = true, points = {}, scripts = {}, events = {}, calls = {},
      _new = newWidget,
    }, mt)
    fake.widgets[#fake.widgets + 1] = w
    adopt(parent, w)
    if name and env then env[name] = w end
    if template then applyTemplates(w, template) end
    return w
  end

  -- Scroll box list (WowScrollBoxList): SetDataProvider lays out one row
  -- frame per element, reusing the previous call's frames by position.
  local function boxSetDataProvider(box, dp, retain)
    box.dataProvider = dp
    box.retained = retain -- ScrollBoxConstants.RetainScrollPosition (true) or not
    local view = box.view or {}
    local old = box.rows or {}
    -- the frame pool hands the previous frames back in reversed order
    local pool = {}
    for i = #old, 1, -1 do pool[#pool + 1] = old[i].frame end
    local rows = {}
    for i, element in ipairs(dp and dp.collection or {}) do
      local frame = pool[i]
      local function acquire(tpl)
        if not frame then
          frame = newWidget("Button", nil, box, tpl or "LevelingAdvisorListRowTemplate")
        end
        frame:Show()
        return frame
      end
      if view.factory then
        view.factory(function(tpl, init)
          acquire(tpl)
          if init then init(frame, element) end
        end, element)
      else
        acquire(view.template)
        if view.initializer then view.initializer(frame, element) end
      end
      local extent = view.extent
      if view.extentCalc then extent = view.extentCalc(i, element) end
      rows[i] = { frame = acquire(), element = element, extent = extent }
    end
    for i = #rows + 1, #pool do pool[i]:Hide() end
    box.rows = rows
  end

  function applyTemplates(w, template)
    for t in tostring(template):gmatch("[^,%s]+") do
      if t == "ButtonFrameTemplate" then
        w.CloseButton = newWidget("Button", nil, w, "UIPanelCloseButton")
        w.Inset = newWidget("Frame", nil, w)
        w.PortraitContainer = newWidget("Frame", nil, w)
        w.PortraitContainer.portrait = w.PortraitContainer:CreateTexture(nil, "OVERLAY")
        w.SetTitle = function(self, title) self.title = title end
        w.SetPortraitToUnit = function(self, unit) self.portraitUnit = unit end
      elseif t == "UIPanelButtonTemplate" then
        -- the template's ButtonText (GameFontNormal) is the button's font string
        w:SetFontString(w:CreateFontString(nil, "ARTWORK", "GameFontNormal"))
      elseif t == "UIPanelCloseButton" then
        w.scripts.OnClick = function(self) self:GetParent():Hide() end
      elseif t == "UICheckButtonTemplate" then
        w.Text = w:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
      elseif t == "SearchBoxTemplate" then
        w.Instructions = w:CreateFontString(nil, "ARTWORK", "GameFontDisable")
        -- the template's own handler (hides the placeholder, shows the clear button)
        w.scripts.OnTextChanged = function(self) self.templateRan = (self.templateRan or 0) + 1 end
      elseif t == "UIPanelScrollFrameTemplate" then
        w.ScrollBar = newWidget("Slider", nil, w)
      elseif t == "WowScrollBoxList" then
        w.SetDataProvider = boxSetDataProvider
        fake.scrollBoxes[#fake.scrollBoxes + 1] = w
        w.GetDataProvider = function(self) return self.dataProvider end
      elseif t == SIDE_TAB and opts.sideTabTemplate then
        sideTab(w)
      end
    end
  end

  fake.newFrame = function(kind, name, parent, template)
    return newWidget(kind or "Frame", name, parent, template)
  end
  local function createFrame(kind, name, parent, template)
    kind = kind or "Frame"
    if not FRAME_TYPES[kind] then error("CreateFrame: Unknown frame type '" .. tostring(kind) .. "'", 2) end
    return newWidget(kind, name, parent, template)
  end

  function fake.named(name)
    for _, w in ipairs(fake.widgets) do
      if w.name == name then return w end
    end
    return nil
  end
  function fake.find(pred)
    for _, w in ipairs(fake.widgets) do
      if pred(w) then return w end
    end
    return nil
  end
  function fake.findAll(pred)
    local out = {}
    for _, w in ipairs(fake.widgets) do
      if pred(w) then out[#out + 1] = w end
    end
    return out
  end
  function fake.visible(w)
    return w ~= nil and w:IsVisible()
  end
  function fake.text(s)
    local first
    for _, w in ipairs(fake.widgets) do
      if w.text == s then
        if w:IsVisible() then return w end
        first = first or w
      end
    end
    return first
  end
  function fake.click(w, button)
    if w.enabled == false then return end
    if w.kind == "CheckButton" then w.checked = not w.checked end
    run(w, "OnClick", button or "LeftButton", false)
  end
  function fake.enter(w) run(w, "OnEnter", false) end
  function fake.leave(w) run(w, "OnLeave", false) end
  -- Typing changes the text without SetText and reports user input.
  function fake.type(box, s)
    box.text = s
    run(box, "OnTextChanged", true)
  end
  function fake.combat(v) combat = v and true or false end

  -- Globals.
  local g = {}
  g.UIParent = newWidget("Frame", "UIParent")
  g.UISpecialFrames = {}
  g.CreateFrame = createFrame
  g.InCombatLockdown = function() return combat end
  local atlases = {}
  for _, a in ipairs(ui.ATLASES) do atlases[a] = true end
  for _, a in ipairs(opts.atlases or {}) do atlases[a] = true end
  g.C_Texture = {
    GetAtlasInfo = function(atlas)
      if opts.noAtlas or not atlases[atlas] then return nil end
      return { atlas = atlas, width = 64, height = 64 }
    end,
  }
  if opts.sideTabTemplate then g.QuestLogTabButtonMixin = sideTabMixin end
  g.CreateColor = function(r, g_, b, a)
    local c = { r = r, g = g_, b = b, a = a }
    function c:GetRGBA() return self.r, self.g, self.b, self.a end
    function c:GetRGB() return self.r, self.g, self.b end
    return c
  end
  g.CreateScrollBoxListLinearView = function(...)
    local view = { padding = { ... } }
    function view:SetElementInitializer(tpl, fn) self.template, self.initializer = tpl, fn end
    function view:SetElementFactory(fn) self.factory = fn end
    function view:SetElementExtent(n) self.extent = n end
    function view:SetElementExtentCalculator(fn) self.extentCalc = fn end
    function view:SetPadding(...) self.padding = { ... } end
    return view
  end
  -- Only what the addon calls: like the widget fake, anything else is nil.
  g.ScrollUtil = {
    InitScrollBoxListWithScrollBar = function(box, bar, view)
      box.view, box.scrollBar = view, bar
    end,
  }
  g.ScrollBoxConstants = { RetainScrollPosition = true, DiscardScrollPosition = false }
  g.CreateDataProvider = function(list)
    local dp = { collection = {} }
    for i, v in ipairs(list or {}) do dp.collection[i] = v end
    function dp:Insert(...)
      for i = 1, select("#", ...) do self.collection[#self.collection + 1] = (select(i, ...)) end
    end
    function dp:InsertTable(t) for _, v in ipairs(t) do self:Insert(v) end end
    function dp:Flush() self.collection = {} end
    function dp:GetSize() return #self.collection end
    function dp:Find(i) return self.collection[i] end
    function dp:Enumerate() return ipairs(self.collection) end
    function dp:ForEach(fn) for _, v in ipairs(self.collection) do fn(v) end end
    return dp
  end

  -- Map API: records what the addon asked for.
  fake.waypoints, fake.openedMaps = {}, {}
  g.UiMapPoint = {
    CreateFromCoordinates = function(m, x, y) return { uiMapID = m, x = x, y = y } end,
  }
  local function vector(x, y)
    local v = { x = x, y = y }
    function v:GetXY() return self.x, self.y end
    return v
  end
  -- The user waypoint changed: Blizzard's pin provider (opts.waypointPin) redraws its pin.
  local function waypointChanged()
    local p = fake.waypointProvider
    if p and p:GetMap() then p:RefreshAllData() end
  end
  function fake.setUserWaypoint(mapID, x, y)
    fake.userWaypoint = mapID and { uiMapID = mapID, position = vector(x, y) } or nil
    waypointChanged()
  end
  g.C_Map = {
    SetUserWaypoint = function(p)
      fake.waypoints[#fake.waypoints + 1] = p
      fake.userWaypoint = { uiMapID = p.uiMapID, position = vector(p.x, p.y) }
      waypointChanged()
    end,
    GetUserWaypoint = function() return fake.userWaypoint end,
    ClearUserWaypoint = function()
      fake.cleared = (fake.cleared or 0) + 1
      fake.userWaypoint = nil
      waypointChanged()
    end,
  }
  if opts.art == "tiles" then
    g.C_Map.GetMapArtLayers = function()
      return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } }
    end
    g.C_Map.GetMapArtLayerTextures = function(mapID)
      local ids = {}
      for i = 1, 12 do ids[i] = mapID * 100 + i end
      return ids
    end
    g.C_Map.GetMapArtBackgroundAtlas = function() return nil end
  end
  g.C_SuperTrack = {
    SetSuperTrackedUserWaypoint = function(v) fake.superTracked = v end,
    SetSuperTrackedQuestID = function(id) fake.superTrackedQuest = id end,
    GetSuperTrackedQuestID = function() return fake.superTrackedQuest or 0 end,
  }
  g.OpenWorldMap = function(mapID) fake.openedMaps[#fake.openedMaps + 1] = mapID end
  -- hooksecurefunc([table,] name, hook): the original runs first, then the hook with the same
  -- arguments; the original's results are returned. A missing function is an error.
  g.hooksecurefunc = function(a, b, c)
    local tbl, name, hook = a, b, c
    if type(a) == "string" then tbl, name, hook = env, a, b end
    local orig = tbl[name]
    if type(orig) ~= "function" or type(hook) ~= "function" then
      error('Usage: hooksecurefunc([table,] "functionName", hookfunc)', 2)
    end
    tbl[name] = function(...)
      local r = packArgs(orig(...))
      hook(...)
      return unpack(r, 1, r.n)
    end
  end
  if opts.minimap then
    local mm = newWidget("Frame", "Minimap", g.UIParent)
    mm:SetSize(140, 140)
    function mm:GetCenter() return 500, 500 end
    function mm:GetEffectiveScale() return 1 end
    g.Minimap = mm
    fake.cursor = { 500, 500 }
    g.GetCursorPosition = function() return fake.cursor[1], fake.cursor[2] end
  end
  -- The pin and data provider mixins exist on every client; the world map is a
  -- map canvas (spec/helpers/mapcanvas.lua, attached in ui.load once env exists).
  for k, v in pairs(mapcanvas.mixins()) do g[k] = v end
  if opts.worldMap then
    local wm = newWidget("Frame", "WorldMapFrame", g.UIParent)
    wm.shown = false
    g.WorldMapFrame = wm
    fake.worldMap = wm
  end

  local tip = newWidget("GameTooltip", "GameTooltip", g.UIParent)
  tip.shown = false
  tip.lines = {}
  function tip:SetOwner(owner, anchor)
    self.owner, self.anchor = owner, anchor
    self.lines, self.itemID, self.link = {}, nil, nil
  end
  function tip:GetOwner() return self.owner end
  function tip:IsOwned(o) return self.owner == o end
  function tip:ClearLines() self.lines = {} end
  function tip:SetText(t, r, g_, b) self.lines = { { t, r, g_, b } } end
  function tip:AddLine(t, r, g_, b) self.lines[#self.lines + 1] = { t, r, g_, b } end
  function tip:AddDoubleLine(l, rt, lr, lg, lb) self.lines[#self.lines + 1] = { l, lr, lg, lb, right = rt } end
  function tip:SetItemByID(id) self.itemID = id end
  function tip:SetHyperlink(link) self.link = link end
  g.GameTooltip = tip
  fake.tooltip = tip

  -- Item API (Plan 4b Task 9). GetItemInfo returns nil until fake.loadItems.
  local ITEMS = {
    [15204] = { "Moonstone Wand", 2, 135473, 2, 19, "INVTYPE_RANGEDRIGHT" },
    [15202] = { "Wildkeeper Leggings", 2, 135001, 4, 2, "INVTYPE_LEGS" },
    [15203] = { "Guststorm Legguards", 2, 135002, 4, 1, "INVTYPE_LEGS" },
    [12346] = { "Empty Cleansing Bowl", 1, 135003, 12, 0, "" },
    [12355] = { "Talisman of Corruption", 1, 135004, 12, 0, "" },
  }
  local loaded, waiting = {}, {}
  fake.itemCounts, fake.itemButtonTexture, fake.itemButtonCount = {}, {}, {}
  fake.itemButtonVertex, fake.itemClicks = {}, {}
  g.C_Item = {
    GetItemInfoInstant = function(id)
      local it = ITEMS[id]
      if not it then return nil end
      return id, "type", "subtype", it[6], it[3], it[4], it[5]
    end,
    GetItemInfo = function(id)
      local it = ITEMS[id]
      if not (it and loaded[id]) then return nil end
      return it[1], "|cff0070dd|Hitem:" .. id .. "|h[" .. it[1] .. "]|h|r", it[2]
    end,
    GetItemCount = function(id) return fake.itemCounts[id] or 0 end,
    GetItemQualityColor = function(q)
      local c = ({ [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 } })[q] or { 0.6, 0.6, 0.6 }
      return c[1], c[2], c[3], "ff"
    end,
  }
  g.Item = {}
  function g.Item:CreateFromItemID(id)
    return { ContinueOnItemLoad = function(_, fn)
      if loaded[id] then fn() else waiting[#waiting + 1] = { id = id, fn = fn } end
    end }
  end
  function fake.loadItems(id)
    local queue = waiting
    waiting = {}
    for _, w in ipairs(queue) do
      if id == nil or w.id == id then
        loaded[w.id] = true
        w.fn()
      else
        waiting[#waiting + 1] = w
      end
    end
    if id ~= nil then loaded[id] = true else for k in pairs(ITEMS) do loaded[k] = true end end
  end
  g.SetItemButtonTexture = function(b, icon) fake.itemButtonTexture[b] = icon end
  g.SetItemButtonQuality = function(b, q, id) fake.lastQuality = { b, q, id } end
  g.SetItemButtonCount = function(b, n) fake.itemButtonCount[b] = n end
  g.SetItemButtonTextureVertexColor = function(b, r, gg, bb) fake.itemButtonVertex[b] = { r, gg, bb } end
  g.HandleModifiedItemClick = function(link) fake.itemClicks[#fake.itemClicks + 1] = link; return true end
  g.C_Spell = { GetSpellInfo = function(id)
    if id == 5061 then return { name = "Aquatic Form" } end
    return nil
  end }
  -- The quest log by questID: fake.setLog(questID, { choices = {{name, texture,
  -- count, quality, isUsable, itemID}}, rewards = {...}, money = n, xp = n,
  -- objectives = {{text, type, finished, numFulfilled, numRequired}} (what
  -- C_QuestLog.GetQuestObjectives returns; nil when absent) }).
  -- Installed on demand: a bare C_QuestLog would change the Adapter's reads.
  function fake.setLog(questID, rec)
    local log = fake.log or {}
    fake.log = log
    log[questID] = rec
    env.C_QuestLog = env.C_QuestLog or {}
    env.C_QuestLog.GetLogIndexForQuestID = function(id) return log[id] and 1 or nil end
    env.C_QuestLog.GetQuestObjectives = function(id) return log[id] and log[id].objectives end
    env.GetNumQuestLogChoices = function(id, isChoice)
      assert(id, "the selected-quest form errors in this build")
      return #(log[id] and log[id].choices or {})
    end
    env.GetQuestLogChoiceInfo = function(i, id)
      local c = log[id] and log[id].choices[i]
      if c then return unpack(c, 1, 6) end
    end
    env.GetNumQuestLogRewards = function(id) return #(log[id] and log[id].rewards or {}) end
    env.GetQuestLogRewardInfo = function(i, id)
      local c = log[id] and log[id].rewards[i]
      if c then return unpack(c, 1, 6) end
    end
    env.GetQuestLogRewardMoney = function(id) return log[id] and log[id].money or 0 end
    env.GetQuestLogRewardXP = function(id) return log[id] and log[id].xp end
  end

  -- Menu and chat (Plan 4b Task 10). fake.menu records the last context menu;
  -- fake.chat configures the link-insertion returns and records the calls.
  fake.chat = { insertLink = false, edit = false, openChat = true, frameOpen = true, calls = {} }
  fake.modifier = nil
  g.IsModifiedClick = function(kind) return fake.modifier ~= nil and fake.modifier == kind end
  g.GetQuestLink = function() return fake.questLink end
  g.MenuUtil = { CreateContextMenu = function(owner, gen)
    local m = { owner = owner, buttons = {} }
    fake.menu = m
    local root = {}
    function root:CreateTitle(t) m.title = t end
    function root:CreateButton(label, fn)
      local entry = { label = label, fn = fn, enabled = true } -- a client button starts enabled
      m.buttons[#m.buttons + 1] = entry
      return { SetEnabled = function(_, v) entry.enabled = v and true or false end }
    end
    function root:CreateDivider() end
    gen(owner, root)
  end }
  g.ChatFrameUtil = {
    InsertLink = function(l) fake.chat.calls[#fake.chat.calls + 1] = { "InsertLink", l }; return fake.chat.insertLink end,
    OpenChat = function(l) fake.chat.calls[#fake.chat.calls + 1] = { "OpenChat", l }; return fake.chat.openChat end,
  }
  g.ChatEdit_InsertLink = function(l) fake.chat.calls[#fake.chat.calls + 1] = { "ChatEdit_InsertLink", l }; return fake.chat.edit end
  g.ChatFrame_OpenChat = function(l) fake.chat.calls[#fake.chat.calls + 1] = { "ChatFrame_OpenChat", l }; return fake.chat.frameOpen end

  fake.globals = g
  fake.bind = function(e) env = e end
  return fake
end

---------------------------------------------------------------------------
-- Loader.
---------------------------------------------------------------------------
function ui.load(opts)
  opts = opts or {}
  local fake = newClient(opts)
  local extra = {}
  for k, v in pairs(fake.globals) do extra[k] = v end
  for k, v in pairs(opts.globals or {}) do extra[k] = v end
  local env, out = addon.env(extra)
  for _, k in ipairs(opts.without or {}) do env[k] = nil end
  fake.bind(env)
  env._G = env
  local WAYPOINT_TEMPLATE = "WaypointLocationPinTemplate"
  if fake.worldMap then
    local templates = { ui.pinTemplate() }
    if opts.waypointPin then
      templates[2] = { name = WAYPOINT_TEMPLATE, frameType = "Frame", mixin = "WaypointLocationPinMixin",
        scripts = {}, enableMouse = false }
    end
    mapcanvas.attach(fake.worldMap, {
      env = env,
      templates = templates,
      newFrame = function(frameType, parent, name, t)
        local f = fake.newFrame(frameType, nil, parent, name)
        if t.size then f.width, f.height = t.size[1], t.size[2] end
        return f
      end,
    })
    if opts.waypointPin then
      env.WaypointLocationPinMixin = env.CreateFromMixins(env.MapCanvasPinMixin)
      local provider = env.CreateFromMixins(env.MapCanvasDataProviderMixin)
      function provider:RemoveAllData() self:GetMap():RemoveAllPinsByTemplate(WAYPOINT_TEMPLATE) end
      function provider:RefreshAllData()
        self:RemoveAllData()
        local map, wp = self:GetMap(), fake.userWaypoint
        if wp and wp.uiMapID == map:GetMapID() then
          map:AcquirePin(WAYPOINT_TEMPLATE):SetPosition(wp.position.x, wp.position.y)
        end
      end
      fake.worldMap:AddDataProvider(provider)
      fake.waypointProvider = provider
    end
  end
  env.UIParent = fake.globals.UIParent
  env.GameTooltip = fake.tooltip
  if opts.questMap then
    env.QuestMapFrame = fake.newFrame("Frame", "QuestMapFrame", env.UIParent)
    if opts.questMap == "tabs" then
      env.QuestMapFrame.QuestsTab = fake.newFrame("Button", nil, env.QuestMapFrame)
      env.QuestMapFrame.MapLegendTab = fake.newFrame("Button", nil, env.QuestMapFrame)
    end
  end
  if opts.questLog then
    env.QuestLogFrame = fake.newFrame("Frame", "QuestLogFrame", env.UIParent)
  end
  if opts.questFrame then
    env.QuestFrame = fake.newFrame("Frame", "QuestFrame", env.UIParent)
    env.QuestFrame.shown = false
    env.GetQuestID = function() return fake.questID end
  end
  if opts.compartment then
    fake.compartment = {}
    env.AddonCompartmentFrame = {
      RegisterAddon = function(_, info) fake.compartment[#fake.compartment + 1] = info end,
    }
  end
  if opts.db then env.LevelingAdvisorDB = deepcopy(opts.db) end
  if opts.chardb then env.LevelingAdvisorCharDB = deepcopy(opts.chardb) end

  local ns = load_addon(ADDON_DIR, ui.FILES, env)
  if not opts.noData then
    local chunk = assert(loadfile(FIXTURE))
    setfenv(chunk, env)
    chunk("LevelingAdvisor", ns)
  end
  if opts.patch then opts.patch(ns.Data) end

  ns.Events.dispatch("ADDON_LOADED", "LevelingAdvisor")
  ns.Events.dispatch("PLAYER_LOGIN")

  fake.out = out
  -- The Contract C row of a quest in the advisor's current rec.
  function fake.row(questID)
    for _, sec in ipairs(ns.Advisor.last.rec.sections or {}) do
      for _, row in ipairs(sec.rows) do
        if row.questID == questID then return row end
      end
    end
  end
  -- The list row frame now showing that quest.
  function fake.rowFrame(questID)
    for _, box in ipairs(fake.scrollBoxes) do
      for _, r in ipairs(box.rows or {}) do
        if r.element.kind == "quest" and r.element.row.questID == questID and r.frame:IsShown() then
          return r.frame
        end
      end
    end
  end
  fake.flush = env.flush
  function fake.setState(state)
    if type(state) == "string" then
      state = assert(require("spec.helpers.states")[state], "unknown state " .. state)
    end
    local src = deepcopy(state)
    ns.Adapter.snapshot = function() return deepcopy(src) end
    return ns.Advisor.compute()
  end
  if opts.state then fake.setState(opts.state) end
  return ns, env, fake, out
end

return ui
