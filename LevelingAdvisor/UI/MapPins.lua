local addonName, ns = ...

-- World-map pins for the recommended quests (spec 5.6). Two parts:
--   * MapPins.build: a pure model, rec -> pins for one zone map;
--   * the rendering glue: a MapCanvasDataProviderMixin provider and a pin
--     template (MapPins.xml), modelled on dev/LevelingAdvisorDiag/Pins.lua
--     variants A and B, which were visible on WoW: Forever 1.60.1.
-- Every WoW global is fail-soft: a missing API skips the feature, never errors.
local MapPins = {}
ns.MapPins = MapPins

local call, method = ns.Util.call, ns.Util.method

local TEMPLATE = "LevelingAdvisorMapPinTemplate"
local LEVEL_TYPE = "PIN_FRAME_LEVEL_AREA_POI"
local MERGE_DISTANCE = 0.5 -- map units (0-100)

-- never "later": its quests are too high for now
local PICKUP_SECTIONS = { here = true, class = true, chains = true, next = true }
local TURNIN_SECTION = "turnin"

-- The pin is a small gold-rimmed shield (own texture, Media/PinShield.tga,
-- made by tools/make-pin-textures.py) with the quest glyph (! pick up, ? turn
-- in) on top. If the client cannot load the texture, a medallion of stacked
-- discs (shadow, gold rim, dark inner) is drawn instead.
local PIN_W, PIN_H = 16, 18
local MEDIA = "Interface\\AddOns\\" .. tostring(addonName) .. "\\Media\\"
local SHIELD_TEX, GLOW_TEX = MEDIA .. "PinShield", MEDIA .. "PinShieldGlow"
local GLOW_W, GLOW_H = 26, 29
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local HOVER_SCALE = 1.35
local REST_ALPHA, HOVER_ALPHA = 0.86, 1.0
local GLOW = { size = 22, color = { 1.0, 0.82, 0.0, 0.25 } }
local LAYERS = {
  { size = 16, color = { 0, 0, 0, 0.55 } }, -- shadow
  { size = 14, color = { 1.0, 0.82, 0.0, 1 } }, -- rim
  { size = 11, color = { 0.10, 0.07, 0.03, 0.95 } }, -- inner
}
local GLYPH_SIZE = 9
local GLYPH_DY = 1 -- the shield's point is at the bottom: glyph sits a bit high
local ATLAS = { pickup = "QuestNormal", turnin = "QuestTurnin" }
local FALLBACK = {
  pickup = "Interface\\GossipFrame\\AvailableQuestIcon",
  turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
}

-- Difficulty colour names (Engine/Difficulty.lua) -> RGB, like the quest log.
local COLORS = {
  grey = { 0.5, 0.5, 0.5 },
  green = { 0.25, 0.75, 0.25 },
  yellow = { 1.0, 0.82, 0.0 },
  orange = { 1.0, 0.5, 0.25 },
  red = { 1.0, 0.1, 0.1 },
}
MapPins.COLORS = COLORS -- shared with the book (UI/Style.lua DIFFICULTY)
local GREY_TEXT = { 0.62, 0.62, 0.62 }
local LIGHT_TEXT = { 0.8, 0.8, 0.8 }

---------------------------------------------------------------------------
-- Pure model.
---------------------------------------------------------------------------
local function giverName(db, place)
  if not (place and place.kind == 1 and place.id) then return nil end
  local npc = method(db, "npc", place.id)
  return type(npc) == "table" and npc[1] or nil
end

local function questEntry(db, row, section, place)
  return {
    id = row.questID, name = row.name, level = row.level, color = row.color,
    section = section.title, sectionKey = section.key, xp = row.xp,
    giverName = giverName(db, place),
  }
end

local function findPin(pins, place)
  for _, p in ipairs(pins) do
    if p.mapID == place.mapID and math.abs(p.x - place.x) <= MERGE_DISTANCE
        and math.abs(p.y - place.y) <= MERGE_DISTANCE then
      return p
    end
  end
  return nil
end

local function addQuest(pins, kind, place, quest)
  local pin = findPin(pins, place)
  if not pin then
    pin = { mapID = place.mapID, x = place.x, y = place.y, kind = kind, quests = {} }
    pins[#pins + 1] = pin
  end
  if kind == "turnin" then pin.kind = "turnin" end
  pin.quests[#pin.quests + 1] = quest
end

local function hasPoint(place, mapID)
  return type(place) == "table" and place.mapID == mapID
    and type(place.x) == "number" and type(place.y) == "number"
end

-- A quest from a route step (no section row): the section column shows the
-- zone name, or "This zone".
local function routeEntry(db, q, mapID, place, state)
  local z = method(db, "zone", mapID)
  local color
  if ns.Difficulty and state then
    color = ns.Difficulty.color(q.level, state.level, state.greyAtOrBelow)
  end
  return {
    id = q.id, name = q.name, level = q.level, color = color,
    section = type(z) == "table" and z.name or "This zone", sectionKey = "route",
    xp = q.xp, giverName = giverName(db, place),
  }
end

-- The first anti-goal: a "!" only for a quest the player can pick up
-- right now (Advisor.canPickUp: Eligibility "eligible"). With a player state
-- and nothing to check it with, nothing is a pickup; without a state (the pure
-- model on its own) the rows' own state decides.
local function pickable(db, id, state)
  if state == nil then return true end
  local A = ns.Advisor
  return type(A) == "table" and type(A.canPickUp) == "function" and A.canPickUp(db, id, state) == true
end

-- A "?" only once the quest is complete in the log.
local function turnInReady(id, state)
  if state == nil then return true end
  local entry = type(state.log) == "table" and state.log[id] or nil
  return type(entry) == "table" and entry.complete and true or false
end

-- Section rows that may become pins: turn-in rows (complete) at the turn-in;
-- available rows (not "soon", not in the log) at the giver. In-progress rows
-- get no pin: Blizzard's quest POI shows their objectives. A Later row (too
-- high for now; its section is not in PICKUP_SECTIONS either) is never a pin.
local function rowPinnable(db, row, kind, state)
  if row.later then return false end
  if kind == "turnin" then return row.state == "complete" and turnInReady(row.questID, state) end
  return row.state == "available" and not row.soon and pickable(db, row.questID, state)
end

-- rec: Recommendation (sections); steps: the zone route of mapID (optional,
-- Engine.route steps); state: player state (the pickup and turn-in checks and
-- the route quest colours; optional for the pure model).
function MapPins.build(rec, db, mapID, steps, state)
  local pins = {}
  if mapID == nil then return pins end
  local seen = {} -- "kind:questID" already on a pin
  for _, section in ipairs(type(rec) == "table" and rec.sections or {}) do
    local kind
    if section.key == TURNIN_SECTION then
      kind = "turnin"
    elseif PICKUP_SECTIONS[section.key] then
      kind = "pickup"
    end
    if kind then
      for _, row in ipairs(section.rows or {}) do
        local place
        if kind == "turnin" then
          local q = method(db, "quest", row.questID)
          place = type(q) == "table" and q.turnIn or nil
        else
          place = row.giver
        end
        if hasPoint(place, mapID) and rowPinnable(db, row, kind, state) then
          seen[kind .. ":" .. tostring(row.questID)] = true
          addQuest(pins, kind, place, questEntry(db, row, section, place))
        end
      end
    end
  end
  for _, step in ipairs(steps or {}) do
    for _, action in ipairs(step.actions or {}) do
      local id, akind = action[1], action[2]
      local kind = (akind == "pickup" or akind == "turnin") and akind or nil
      -- A planned turn-in of a quest the player has not accepted yet, or has
      -- not finished, is not actionable (and would turn its giver's "!" into a
      -- "?"): skip it.
      local planned = kind == "turnin" and not turnInReady(id, state)
      -- done actions (already picked up / turned in) get no pin
      local done = state and ns.Advisor and ns.Advisor.actionDone
        and ns.Advisor.actionDone(id, akind, state)
      -- a later chain step (prerequisite not done yet) is no pickup yet; its
      -- pin appears on the compute after the prerequisite's turn-in
      local latent = kind == "pickup" and not done and not pickable(db, id, state)
      if kind and not planned and not done and not latent and not seen[kind .. ":" .. tostring(id)] then
        local q = method(db, "quest", id)
        if type(q) == "table" then
          local place = (kind == "turnin") and q.turnIn or q.giver
          if hasPoint(place, mapID) then
            seen[kind .. ":" .. tostring(id)] = true
            addQuest(pins, kind, place, routeEntry(db, q, mapID, place, state))
          end
        end
      end
    end
  end
  return pins
end

---------------------------------------------------------------------------
-- Model for what the map shows right now.
---------------------------------------------------------------------------
-- The zone route of the displayed map: the advisor's frozen per-zone plan
-- (shared with the book's zone page), so refreshes never recompute it. nil in
-- combat without a plan; a throwing plan goes to the error handler.
local function zoneRoute(A, mapID)
  if type(A) ~= "table" or type(A.plan) ~= "function" then return nil end
  local ok, plan = pcall(A.plan, mapID)
  if not ok then
    geterrorhandler()(plan)
    return nil
  end
  return type(plan) == "table" and plan.steps or nil
end

-- The "Show on map" pin (Nav): one entry { mapID, x, y, kind, quests }, shown
-- on its own map even when pinsAll is off, and only when the client
-- could not set a waypoint (the game's super-track pinpoint marks it otherwise).
local focus
local FOCUS_SECTION = "Shown on map"

-- The focus goes once its quest is done, or (for a pickup) accepted.
local function focusStale(state)
  local q = focus.quests[1]
  local id = q and q.id
  if not (id and type(state) == "table") then return false end
  if type(state.completed) == "table" and state.completed[id] then return true end
  return focus.kind == "pickup" and type(state.log) == "table" and state.log[id] ~= nil
end

local function addFocus(pins, mapID, state)
  if not focus then return end
  if focusStale(state) then focus = nil; return end
  if focus.mapID ~= mapID then return end
  local place = { mapID = focus.mapID, x = focus.x, y = focus.y }
  for _, q in ipairs(focus.quests) do
    local dup = false
    local pin = findPin(pins, place)
    for _, have in ipairs(pin and pin.quests or {}) do
      if q.id ~= nil and have.id == q.id then dup = true end
    end
    if pin and dup then
      if focus.kind == "turnin" then pin.kind = "turnin" end
    else
      addQuest(pins, focus.kind, place, q)
    end
  end
end

-- The pins the map shows for mapID: the recommended quests (pinsAll) plus the
-- focus pin. No map (the world map before it is first opened) shows nothing.
function MapPins.model(mapID)
  local A = ns.Advisor
  local last = A and A.last
  local pins = {}
  if mapID == nil then return pins end
  if ns.Settings.get("pinsAll") and last and last.rec then
    pins = MapPins.build(last.rec, A.db, mapID, zoneRoute(A, mapID), last.state)
  end
  addFocus(pins, mapID, last and last.state)
  return pins
end

local function currentMapID()
  if method(WorldMapFrame, "IsShown") then return method(WorldMapFrame, "GetMapID") end
  local best = type(C_Map) == "table" and call(C_Map.GetBestMapForUnit, "player")
  return best or method(WorldMapFrame, "GetMapID")
end

-- Pins the map would show for the current map (for /advisor pins).
function MapPins.count()
  local id = currentMapID()
  return id and #MapPins.model(id) or 0
end

local function mapName(mapID)
  local z = method(ns.Advisor and ns.Advisor.db, "zone", mapID)
  if type(z) == "table" and z.name then return z.name end
  local info = type(C_Map) == "table" and call(C_Map.GetMapInfo, mapID)
  if type(info) == "table" and info.name then return info.name end
  return "map " .. tostring(mapID)
end

-- The /advisor pins line.
function MapPins.describe()
  local last = ns.Advisor and ns.Advisor.last
  if not (last and last.rec) then return "No recommendation yet: type /advisor first" end
  local id = currentMapID()
  if not id then return "No map to count pins on." end
  return string.format("Pins on map %s (%s): %d", mapName(id), tostring(id), #MapPins.model(id))
end

---------------------------------------------------------------------------
-- Pin frame.
---------------------------------------------------------------------------
-- A centred disc of the given size and colour. Uses the alpha-masked disc
-- texture; when the client rejects it (SetTexture false, or no texture
-- afterwards) the layer becomes a plain colour square, never invisible.
local function paintDisc(tex, size, color)
  method(tex, "SetSize", size, size)
  method(tex, "ClearAllPoints")
  method(tex, "SetPoint", "CENTER", 0, 0)
  local ok = method(tex, "SetTexture", DISC)
  local missing = false
  if ok ~= false and type(tex) == "table" and type(tex.GetTexture) == "function" then
    local good, got = pcall(tex.GetTexture, tex)
    missing = good and got == nil
  end
  if ok == false or missing then
    method(tex, "SetColorTexture", color[1], color[2], color[3], color[4])
  else
    method(tex, "SetVertexColor", color[1], color[2], color[3], color[4])
  end
end

-- True when tex shows a texture: SetTexture did not report failure and the
-- texture reads back non-nil.
local function loaded(tex, path)
  local ok = method(tex, "SetTexture", path)
  if ok == false then return false end
  if type(tex) == "table" and type(tex.GetTexture) == "function" then
    local good, got = pcall(tex.GetTexture, tex)
    if good and got == nil then return false end
  end
  return true
end

local function place(tex, w, h)
  method(tex, "SetSize", w, h)
  method(tex, "ClearAllPoints")
  method(tex, "SetPoint", "CENTER", 0, 0)
end

-- Medallion fallback: the shield texture did not load.
local function buildMedallion(pin, glow, layer)
  pin.laGlow = glow
  paintDisc(glow, GLOW.size, GLOW.color)
  method(glow, "Hide")
  for i, l in ipairs(LAYERS) do paintDisc(layer(-2 + i), l.size, l.color) end
end

-- Visual holder (a child frame, so scaling it leaves the pin's map position
-- alone) with the glow, the shield and the glyph. Built once per pin frame
-- (frames are pooled); falls back to the pin itself without CreateFrame.
local function ensureHolder(pin)
  if pin.laHolder then return pin.laHolder end
  local holder = call(CreateFrame, "Frame", nil, pin) or pin
  method(holder, "SetAllPoints", pin)
  -- The holder only draws; the pin keeps the mouse (tooltip, click).
  if holder ~= pin then method(holder, "EnableMouse", false) end
  local function layer(sublevel)
    return method(holder, "CreateTexture", nil, "ARTWORK", nil, sublevel)
  end
  local glow, shield = layer(-2), layer(-1)
  if glow and shield and loaded(shield, SHIELD_TEX) then
    place(shield, PIN_W, PIN_H)
    pin.laShield = shield
    if loaded(glow, GLOW_TEX) then
      place(glow, GLOW_W, GLOW_H)
      method(glow, "Hide")
      pin.laGlow = glow
    else
      method(glow, "Hide") -- a missing glow just means no glow
      pin.laGlow = nil
    end
  else
    method(shield, "Hide") -- unused layer (no texture)
    pin.laShield = nil
    buildMedallion(pin, glow, layer)
  end
  pin.laGlyph = layer(2)
  pin.laHolder = holder
  return holder
end

-- The kind's atlas when the client has it, else the GossipFrame file.
local function setGlyph(tex, kind)
  kind = ATLAS[kind] and kind or "pickup"
  method(tex, "SetSize", GLYPH_SIZE, GLYPH_SIZE)
  method(tex, "ClearAllPoints")
  method(tex, "SetPoint", "CENTER", 0, GLYPH_DY)
  local found = type(C_Texture) == "table" and call(C_Texture.GetAtlasInfo, ATLAS[kind]) ~= nil
  if found then
    method(tex, "SetAtlas", ATLAS[kind])
  else
    method(tex, "SetTexture", FALLBACK[kind])
  end
end

local function applyKind(pin, kind)
  ensureHolder(pin)
  method(pin, "SetSize", PIN_W, PIN_H)
  setGlyph(pin.laGlyph, kind)
  method(pin.laHolder, "SetScale", 1)
  method(pin.laHolder, "SetAlpha", REST_ALPHA)
  method(pin.laGlow, "Hide")
end

LevelingAdvisorMapPinMixin = (CreateFromMixins and MapCanvasPinMixin)
  and CreateFromMixins(MapCanvasPinMixin) or {}
local Pin = LevelingAdvisorMapPinMixin

local inCombat = ns.Util.inCombat

-- SetPassThroughButtons is restricted for addon code in combat on modern
-- engines: a blocked action ("Interface action failed because of an AddOn"),
-- not a Lua error, so pcall does not help. Our OnLoad and MapCanvas's own
-- AcquirePin both call it on our pins (HereBeDragons-Pins stubs it for the
-- same reason). The mixin method below shadows the frame's own: out of
-- combat it calls the frame method at once (right-click through a pin still
-- zooms the map out); in combat it waits for PLAYER_REGEN_ENABLED.
local pendingPass = setmetatable({}, { __mode = "k" }) -- pin -> { n, ... }

local function framePassThrough(pin, ...)
  local mt = getmetatable(pin)
  local index = type(mt) == "table" and mt.__index or nil
  local fn = type(index) == "table" and index.SetPassThroughButtons or nil
  if type(fn) == "function" then pcall(fn, pin, ...) end
end

function Pin:SetPassThroughButtons(...)
  if inCombat() then
    pendingPass[self] = { n = select("#", ...), ... }
    return
  end
  pendingPass[self] = nil
  framePassThrough(self, ...)
end

local function flushPassThrough()
  if inCombat() then return end
  local pins = {}
  for pin, args in pairs(pendingPass) do pins[pin] = args end
  for pin, args in pairs(pins) do
    pendingPass[pin] = nil
    framePassThrough(pin, unpack(args, 1, args.n))
  end
end

if ns.Events and type(ns.Events.on) == "function" then
  ns.Events.on("PLAYER_REGEN_ENABLED", flushPassThrough)
end

function Pin:OnLoad()
  method(self, "UseFrameLevelType", LEVEL_TYPE)
  method(self, "SetScalingLimits", 1, 1.0, 1.2)
  self:SetPassThroughButtons("RightButton")
end

function Pin:OnAcquired(entry)
  self.entry = entry
  applyKind(self, entry.kind)
  method(self, "SetPosition", entry.x / 100, entry.y / 100)
end

-- The pin whose tooltip is up: a pin released by a map refresh takes it along.
local hoverPin

function Pin:LAOnEnter()
  hoverPin = self
  if self.laHolder then
    method(self.laHolder, "SetScale", HOVER_SCALE)
    method(self.laHolder, "SetAlpha", HOVER_ALPHA)
    method(self.laGlow, "Show")
  end
  local tip, entry = GameTooltip, self.entry
  if not (tip and entry) then return end
  tip:SetOwner(self, "ANCHOR_RIGHT")
  tip:AddLine("Leveling Advisor")
  for _, q in ipairs(entry.quests) do
    local c = COLORS[q.color] or COLORS.yellow
    tip:AddDoubleLine("[" .. tostring(q.level or "?") .. "] " .. tostring(q.name), q.section or "",
      c[1], c[2], c[3], GREY_TEXT[1], GREY_TEXT[2], GREY_TEXT[3])
    local detail = "~" .. tostring(math.floor((q.xp or 0) + 0.5)) .. " XP"
    if q.giverName then detail = detail .. " \194\183 " .. q.giverName end
    tip:AddLine(detail, LIGHT_TEXT[1], LIGHT_TEXT[2], LIGHT_TEXT[3])
  end
  tip:AddLine("Click: set waypoint", GREY_TEXT[1], GREY_TEXT[2], GREY_TEXT[3])
  tip:Show()
end

local function rest(pin)
  if pin.laHolder then
    method(pin.laHolder, "SetScale", 1)
    method(pin.laHolder, "SetAlpha", REST_ALPHA)
    method(pin.laGlow, "Hide")
  end
end

function Pin:LAOnLeave()
  if hoverPin == self then hoverPin = nil end
  rest(self)
  if GameTooltip then GameTooltip:Hide() end
end

-- Hides the tooltip of a pin that goes away under the mouse (map refresh),
-- only when that pin still owns it.
local function releaseHover(pin)
  if not hoverPin or (pin and pin ~= hoverPin) then return end
  local owner = hoverPin
  hoverPin = nil
  rest(owner)
  if GameTooltip and method(GameTooltip, "GetOwner") == owner then method(GameTooltip, "Hide") end
end

local baseOnReleased = type(MapCanvasPinMixin) == "table" and MapCanvasPinMixin.OnReleased or nil

function Pin:OnReleased()
  releaseHover(self)
  if type(baseOnReleased) == "function" then pcall(baseOnReleased, self) end
end

-- pcall that also requires fn to be a function; true when it ran cleanly.
local function ran(fn, ...)
  return type(fn) == "function" and pcall(fn, ...) or false
end

---------------------------------------------------------------------------
-- Our waypoint and the game's square waypoint pin. The game marks a
-- super-tracked user waypoint twice: its super-track pinpoint and, on the
-- world map, the square user-waypoint pin (Blizzard's WaypointLocationPinTemplate,
-- WaypointLocationDataProviderMixin). While the user waypoint is the one we set,
-- that pin is hidden; a waypoint the player places by hand keeps it. Every API
-- here is optional: a missing one is a silent no-op.
---------------------------------------------------------------------------
local SHARING_TEMPLATE = "WaypointLocationPinTemplate"
local SAME_SPOT = 0.002 -- map units (0-1)
local ours -- { mapID, x, y } (0-100): the waypoint setWaypoint set last
local hiddenByUs = setmetatable({}, { __mode = "k" }) -- sharing pins we hid

local function waypointXY(wp)
  local pos = wp.position
  if type(pos) == "table" then
    if type(pos.x) == "number" and type(pos.y) == "number" then return pos.x, pos.y end
    return method(pos, "GetXY")
  end
  return wp.x, wp.y
end

-- The client's current user waypoint, or nil.
local function userWaypoint()
  local wp = type(C_Map) == "table" and call(C_Map.GetUserWaypoint) or nil
  return type(wp) == "table" and wp or nil
end

-- True when the current user waypoint is at spot ({ mapID, x, y }, 0-100): the
-- same uiMapID and a position within SAME_SPOT.
function MapPins.isWaypointAt(spot)
  if type(spot) ~= "table" or type(spot.x) ~= "number" or type(spot.y) ~= "number" then return false end
  local wp = userWaypoint()
  if not wp or wp.uiMapID ~= spot.mapID then return false end
  local x, y = waypointXY(wp)
  if type(x) ~= "number" or type(y) ~= "number" then return false end
  return math.abs(x - spot.x / 100) <= SAME_SPOT and math.abs(y - spot.y / 100) <= SAME_SPOT
end

-- True when the current user waypoint is ours (the one setWaypoint set last).
function MapPins.isOurWaypoint()
  return ours ~= nil and MapPins.isWaypointAt(ours)
end

-- Whether the client has a user waypoint now; nil when it cannot tell (no
-- C_Map.GetUserWaypoint).
function MapPins.hasUserWaypoint()
  if type(C_Map) ~= "table" or type(C_Map.GetUserWaypoint) ~= "function" then return nil end
  return userWaypoint() ~= nil
end

-- The world map's active pins of a template: the client's pools enumerate
-- pin -> true; a plain list (index -> pin) is read too.
local function activePins(template)
  local pins = {}
  local map = WorldMapFrame
  if type(map) ~= "table" then return pins end
  pcall(function()
    local iter, st, ctl = map:EnumeratePinsByTemplate(template)
    if type(iter) ~= "function" then return end
    for a, b in iter, st, ctl do
      local pin = type(a) == "table" and a or b
      if type(pin) == "table" then pins[#pins + 1] = pin end
    end
  end)
  return pins
end

-- Hides a sharing pin while the waypoint is ours; shows again one we hid
-- once it is not.
local function judge(pin, isOurs)
  if isOurs then
    if method(pin, "IsShown") ~= false then method(pin, "Hide") end
    hiddenByUs[pin] = true
  elseif hiddenByUs[pin] then
    hiddenByUs[pin] = nil
    method(pin, "Show")
  end
end

local function sweep()
  local isOurs = MapPins.isOurWaypoint()
  for _, pin in ipairs(activePins(SHARING_TEMPLATE)) do judge(pin, isOurs) end
end

-- Now and once more on the next frame: the game's provider may redraw its pin
-- after our handler ran.
local function sweepSoon()
  sweep()
  if type(C_Timer) == "table" then call(C_Timer.After, 0, function() pcall(sweep) end) end
end

local function onEvent(event, fn)
  if ns.Events and type(ns.Events.on) == "function" then ns.Events.on(event, fn) end
end

onEvent("USER_WAYPOINT_UPDATED", sweepSoon)

-- A pin acquired while the waypoint is ours is hidden at once. The hook only
-- reaches pins created after it (Mixin copies the method); the sweeps cover
-- older ones. Under pcall: an error must not break the map's AcquirePin.
local hooked = false
function MapPins.hookSharingPin()
  if hooked then return true end
  local mixin = _G.WaypointLocationPinMixin
  if type(hooksecurefunc) ~= "function" or type(mixin) ~= "table"
      or type(mixin.OnAcquired) ~= "function" then
    return false
  end
  hooked = pcall(hooksecurefunc, mixin, "OnAcquired", function(pin)
    pcall(function() judge(pin, MapPins.isOurWaypoint()) end)
  end) and true or false
  return hooked
end

onEvent("ADDON_LOADED", function(name)
  if name == "Blizzard_WorldMap" or name == "Blizzard_SharedMapDataProviders" then MapPins.hookSharingPin() end
end)

-- Sets the user waypoint at entry (0-100) and super-tracks it. Returns true
-- when the client took it, false otherwise (Nav then adds its focus pin).
-- opts.quiet: no chat line either way (the guide sets waypoints on its own).
function MapPins.setWaypoint(entry, opts)
  local quiet = type(opts) == "table" and opts.quiet
  local ok = false
  local point
  if type(UiMapPoint) == "table" and type(C_Map) == "table" and type(C_SuperTrack) == "table" then
    local made, p = pcall(UiMapPoint.CreateFromCoordinates, entry.mapID, entry.x / 100, entry.y / 100)
    if made and p then point = p end
  end
  -- ours before the call: the game may draw its pin from inside SetUserWaypoint
  local previous = ours
  if point then
    ours = { mapID = entry.mapID, x = entry.x, y = entry.y }
    ok = ran(C_Map.SetUserWaypoint, point) and ran(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
  end
  if not ok then
    ours = previous
    if not quiet then ns.Util.say("Waypoints are not available on this client.") end
    return false
  end
  sweepSoon()
  if quiet then return true end
  local first = entry.quests[1]
  ns.Util.say(string.format("Waypoint set: %s (%s %.1f, %.1f)",
    tostring(first and first.name), mapName(entry.mapID), entry.x, entry.y))
  return true
end

-- Forgets our waypoint (the guide was turned off): any current user waypoint
-- is then not ours, so the sweep shows a sharing pin we hid again and the
-- player can click that waypoint away on the map.
function MapPins.releaseOurs()
  ours = nil
  sweep()
end

-- The /advisor debug line: the world map's active pins by template, how many
-- of them are hidden, and whose the user waypoint is. pinPools keys first,
-- EnumerateAllPins otherwise.
function MapPins.describeMapPins()
  local map = WorldMapFrame
  if type(map) ~= "table" then return "map pins: no world map" end
  local counts, names = {}, {}
  local function add(template, pin)
    template = tostring(template or "?")
    local c = counts[template]
    if not c then
      c = { n = 0, hidden = 0 }
      counts[template] = c
      names[#names + 1] = template
    end
    c.n = c.n + 1
    if method(pin, "IsShown") == false then c.hidden = c.hidden + 1 end
  end
  local pools = rawget(map, "pinPools")
  local read = false
  if type(pools) == "table" then
    read = pcall(function()
      for template, pool in pairs(pools) do
        local iter, st, ctl = pool:EnumerateActive()
        for a, b in iter, st, ctl do
          local pin = type(a) == "table" and a or b
          if type(pin) == "table" then add(template, pin) end
        end
      end
    end)
  end
  if not read and type(map.EnumerateAllPins) == "function" then
    counts, names = {}, {}
    read = pcall(function()
      for pin in map:EnumerateAllPins() do add(pin.pinTemplate, pin) end
    end)
  end
  if not read then return "map pins: n/a" end
  table.sort(names)
  local parts = {}
  for _, name in ipairs(names) do
    local c = counts[name]
    parts[#parts + 1] = name .. " " .. c.n .. (c.hidden > 0 and (" (hidden " .. c.hidden .. ")") or "")
  end
  local whose = MapPins.isOurWaypoint() and "ours" or (userWaypoint() and "not ours" or "none")
  return "map pins: " .. (#parts > 0 and table.concat(parts, ", ") or "none") .. "; waypoint: " .. whose
end

function Pin:LAOnClick(button)
  if button ~= nil and button ~= "LeftButton" then return end
  if self.entry then MapPins.setWaypoint(self.entry) end
end

-- MapCanvasMixin:AcquirePin replaces the pin's OnMouseUp script with a handler
-- that calls pin:OnClick(button) (and may route motion through OnMouseEnter /
-- OnMouseLeave), so the XML scripts above never run on such clients. These
-- methods cover that path; a client keeps only one OnMouseUp script, so a
-- click never fires twice.
function Pin:OnClick(button) self:LAOnClick(button) end
function Pin:OnMouseEnter() self:LAOnEnter() end
function Pin:OnMouseLeave() self:LAOnLeave() end

---------------------------------------------------------------------------
-- Data provider.
---------------------------------------------------------------------------
local provider

local function newProvider()
  local p = CreateFromMixins(MapCanvasDataProviderMixin)
  function p:RemoveAllData()
    releaseHover(nil)
    local map = self:GetMap()
    if map then map:RemoveAllPinsByTemplate(TEMPLATE) end
  end
  function p:RefreshAllData()
    self:RemoveAllData()
    local map = self:GetMap()
    if not map then return end
    for _, entry in ipairs(MapPins.model(map:GetMapID())) do
      -- Under pcall: a failure must not break the map's refresh of all providers.
      local ok, err = pcall(map.AcquirePin, map, TEMPLATE, entry)
      if not ok then geterrorhandler()(err) end
    end
    -- The map refreshes every provider on show and on a map change: a sharing
    -- pin re-acquired there (or made before our OnAcquired hook) is hidden
    -- again, now and a frame later in case the game's provider runs after ours.
    pcall(sweepSoon)
  end
  return p
end

local function draw()
  if provider then provider:RefreshAllData() end
end

-- Redraws only while the world map is shown: pins for a closed map are wasted
-- work (a plan scan or route per advisor result). The map redraws on show
-- (MapCanvas refreshes its providers, and our OnShow hook calls draw).
-- `~= false`: a client or fake without IsShown still redraws.
local function refresh()
  if method(WorldMapFrame, "IsShown") ~= false then draw() end
end

-- entry: { mapID, x, y, kind = "pickup"|"turnin", quests = { { id, name, ... } } }
-- or nil to clear. The pin is drawn with section "Shown on map".
function MapPins.setFocus(entry)
  focus = nil
  if type(entry) == "table" and type(entry.quests) == "table" then
    focus = { mapID = entry.mapID, x = entry.x, y = entry.y,
      kind = entry.kind == "turnin" and "turnin" or "pickup", quests = {} }
    for i, q in ipairs(entry.quests) do
      local copy = {}
      for k, v in pairs(q) do copy[k] = v end
      copy.section, copy.sectionKey = FOCUS_SECTION, "focus"
      focus.quests[i] = copy
    end
  end
  refresh()
end

local function safe(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then geterrorhandler()(err) end
  end
end

-- Adds the provider to the world map, once. Skips silently when the client
-- has no world map or data provider API.
function MapPins.install()
  if provider then return end
  if not (type(WorldMapFrame) == "table" and type(WorldMapFrame.AddDataProvider) == "function"
      and CreateFromMixins and MapCanvasDataProviderMixin) then
    return
  end
  provider = newProvider()
  WorldMapFrame:AddDataProvider(provider)

  if ns.Advisor and ns.Advisor.onUpdate then ns.Advisor.onUpdate(safe(refresh)) end
  ns.Settings.onChange(function(key)
    if key == "pinsAll" then refresh() end
  end)
  -- An open world map counts as a shown window, so the scheduler may compute
  -- (Advisor.setMapShown); a stale or missing result is requested on show.
  if type(WorldMapFrame.HookScript) == "function" then
    WorldMapFrame:HookScript("OnShow", safe(function()
      call(ns.Advisor and ns.Advisor.setMapShown, true)
      draw()
    end))
    WorldMapFrame:HookScript("OnHide", safe(function()
      call(ns.Advisor and ns.Advisor.setMapShown, false)
    end))
  end
end

ns.Init.onReady(MapPins.install)
ns.Init.onReady(MapPins.hookSharingPin)
