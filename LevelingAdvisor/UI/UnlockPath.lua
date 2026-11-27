local _, ns = ...; ns.UI = ns.UI or {}; ns.UI.UnlockPath = ns.UI.UnlockPath or {}
local UnlockPath = ns.UI.UnlockPath
local UI = ns.UI
local Style, QuestInfo = UI.Style, UI.QuestInfo
local method = ns.Util.method

-- The Unlock Path section of the quest detail page: the quests to do before this one
-- (Engine/Unlock.lua), earliest first, then the quest itself. A row is a status dot on a
-- connector line, the level box, the name over a sub line, and a map pin on a step to go to.
-- Rows, group labels and connector lines are pooled; render hides what a path does not use.

local W = 360 -- the detail page's width (UI/QuestDetail.lua)
local ROW_H, LABEL_H, FOLD_H = 36, 16, 26
local DOT, INDENT = 22, 18
local LEVEL_X, NAME_X = 31, 70 -- from the row's left edge
local LINE_X = 10 -- the connector runs under the centre of an unindented dot
local PIN = 26
local FOLD_AFTER = 3 -- more done steps than this fold into one row

local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local CHECK = "Interface\\Buttons\\UI-CheckBox-Check"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local RED = { 0.62, 0.12, 0.09 }
local GREEN = { 0.24, 0.48, 0.12 }
local DONE_INK = { 0.36, 0.28, 0.17 }
local LINK = { 0.48, 0.31, 0.07 }
local PARCHMENT = { 0.92, 0.84, 0.65 }
local NOT_IN_DATA = "Not in the advisor's data"

-- Dot looks: ring and fill colours, the glyph's ink; the start step has a gold halo.
local LOOKS = {
  done = { ring = { 0.13, 0.22, 0.06 }, fill = { 0.24, 0.35, 0.12 } },
  start = { ring = { 0.29, 0.05, 0.03 }, fill = RED, ink = Style.GOLD, halo = true },
  progress = { ring = Style.GOLD, fill = { 0.23, 0.15, 0.07 }, ink = Style.GOLD },
  locked = { ring = { 0.54, 0.42, 0.23 }, fill = PARCHMENT, ink = Style.INK_SOFT },
  unknown = { ring = { 0.66, 0.54, 0.35 }, fill = PARCHMENT, ink = { 0.48, 0.33, 0.15 } },
  blocked = { ring = { 0.29, 0.05, 0.03 }, fill = RED, ink = { 0.98, 0.90, 0.78 } },
  this = { ring = { 0.08, 0.06, 0.05 }, fill = { 0.08, 0.06, 0.05 }, ink = Style.GOLD },
}

local FACTION_ONLY = { [1] = "Alliance only", [2] = "Horde only" }
local BLOCKED = {
  race = "other race", class = "other class",
  exclusive = "ruled out by another quest", unavailable = "ruled out by another quest",
  breadcrumb = "ruled out by another quest",
}

---------------------------------------------------------------------------
-- Texts (pure).
---------------------------------------------------------------------------
-- "<NPC>, <Zone>" of a place; either part alone when the other is unknown.
local function where(db, place)
  if type(place) ~= "table" then return nil end
  local who = QuestInfo.npcName(db, place)
  local zone = QuestInfo.zoneName(db, place.mapID)
  if who and zone then return who .. ", " .. zone end
  return who or zone
end

-- How a quest stub starts (its start = { kind, name, mapID }): an NPC reads "<NPC>, <Zone>"
-- when its map is a known zone.
local function startText(db, start)
  if type(start) ~= "table" then return NOT_IN_DATA end
  local name = start.name
  if start.kind == 3 then return name and ("Starts from an item: " .. name) or "Starts from an item" end
  if start.kind == 2 then return name and ("Starts at an object: " .. name) or "Starts at an object" end
  if start.kind == 1 and name then
    local zone = QuestInfo.zoneName(db, start.mapID)
    return zone and (name .. ", " .. zone) or (name .. " (location unknown)")
  end
  return NOT_IN_DATA
end

-- `rec` is the step's quest or stub (its faction).
local function blockedText(step, rec)
  local why = BLOCKED[step.reason]
  if step.reason == "faction" then why = FACTION_ONLY[rec and rec.faction] end
  return why and ("Not available: " .. why) or "Not available to your character"
end

-- The sub line of a step row. `q` is the step's DB quest (nil for stubs and missing quests);
-- `first`: the step to start with, which adds its XP.
local function subText(s, step, q, first)
  local status, reason = step.status, step.reason
  if status == "blocked" then return blockedText(step, q or step.stub) end
  if status == "unknown" then
    if reason == "conflict" then return "Unclear in the advisor's data" end
    if reason == "stub" then return startText(s.db, step.stub and step.stub.start) end
    return NOT_IN_DATA
  end
  if status == "locked" and reason == "level" and q and q.requiredLevel then
    return "Unlocks at level " .. q.requiredLevel
  end
  local parts = {}
  local place = where(s.db, step.giver)
  if place then
    parts[1] = place
  elseif step.stub then
    parts[1] = startText(s.db, step.stub.start) -- a stub implied done by a later step
  end
  if first and q then
    local xp = ns.XP.estimate(q, s.state.level, s.state.recordedXP)
    if xp > 0 then parts[#parts + 1] = "~" .. Style.number(xp) .. " XP" end
  end
  return table.concat(parts, " · ")
end

local function groupLabel(g)
  if g.kind == "any" then return "ONE OF" end
  if (g.size or 0) <= 2 then return "NEEDS BOTH" end
  return "NEEDS ALL " .. g.size
end

---------------------------------------------------------------------------
-- Widgets.
---------------------------------------------------------------------------
local function pooled(list, i, make)
  local w = list[i]
  if not w then w = make(); list[i] = w end
  return w
end

local function disc(parent, size, layer)
  local t = Style.texture(parent, layer, nil, DISC)
  t:SetSize(size, size)
  t:SetPoint("CENTER", parent, "CENTER", 0, 0)
  return t
end

-- A 22 px status dot: halo, ring, fill, and the done check or a glyph (number, "?", "X").
local function newDot(parent)
  local d = CreateFrame("Frame", nil, parent)
  d:SetSize(DOT, DOT)
  d.halo = disc(d, DOT + 4, "BACKGROUND")
  d.halo:SetVertexColor(Style.GOLD[1], Style.GOLD[2], Style.GOLD[3], 0.55)
  d.ring = disc(d, DOT, "BORDER")
  d.fill = disc(d, DOT - 4, "ARTWORK")
  d.check = Style.texture(d, "OVERLAY", nil, CHECK)
  d.check:SetSize(16, 16)
  d.check:SetPoint("CENTER", d, "CENTER", 0, 0)
  d.glyph = Style.text(d, "GameFontNormalSmall")
  d.glyph:SetJustifyH("CENTER")
  d.glyph:SetPoint("CENTER", d, "CENTER", 0, 0)
  return d
end

-- look: a LOOKS key; glyph: the dot's text, nil for the done check.
local function setDot(d, look, glyph)
  local l = LOOKS[look]
  d.ring:SetVertexColor(l.ring[1], l.ring[2], l.ring[3])
  d.fill:SetVertexColor(l.fill[1], l.fill[2], l.fill[3])
  d.halo:SetShown(l.halo == true)
  d.check:SetShown(glyph == nil)
  d.glyph:SetShown(glyph ~= nil)
  d.glyph:SetText(glyph or "")
  if l.ink then d.glyph:SetTextColor(l.ink[1], l.ink[2], l.ink[3]) end
end

local function newRow(s)
  local r = CreateFrame("Button", nil, s.frame)
  r:SetHeight(ROW_H)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetHighlightTexture(WHITE, "ADD")
  local hl = method(r, "GetHighlightTexture")
  if type(hl) == "table" then method(hl, "SetVertexColor", 1, 1, 1, 0.08) end
  r.bg = r:CreateTexture(nil, "BACKGROUND") -- a step that can be started now
  r.bg:SetAllPoints(r)
  r.bg:SetColorTexture(1.0, 0.96, 0.84, 0.35)
  r.dot = newDot(r)
  r.dot:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -(ROW_H - DOT) / 2)
  -- the level box of QuestRow
  r.levelBox = r:CreateTexture(nil, "ARTWORK")
  r.levelBox:SetSize(30, 18)
  r.levelBox:SetPoint("TOPLEFT", r, "TOPLEFT", LEVEL_X, -(ROW_H - 18) / 2)
  r.levelBox:SetColorTexture(0.08, 0.06, 0.05, 1)
  r.level = Style.text(r, "GameFontNormalSmall")
  r.level:SetSize(30, 18)
  r.level:SetJustifyH("CENTER")
  r.level:SetPoint("TOPLEFT", r, "TOPLEFT", LEVEL_X, -(ROW_H - 18) / 2)
  r.name = Style.text(r, "QuestFont", Style.INK)
  r.name:SetPoint("TOPLEFT", r, "TOPLEFT", NAME_X, -3)
  r.name:SetWordWrap(false)
  r.tag = Style.text(r, "GameFontNormalSmall", RED)
  r.tag:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
  r.tag:SetText("START HERE")
  r.sub = Style.text(r, "GameFontNormalSmall", Style.INK_SOFT)
  r.sub:SetPoint("TOPLEFT", r, "TOPLEFT", NAME_X, -20)
  r.sub:SetWordWrap(false)
  r.pin = Style.pinButton(r, nil)
  r.pin:SetPoint("RIGHT", r, "RIGHT", -2, 0)
  return r
end

local function setLevel(r, level, color)
  local c = Style.DIFFICULTY[color] or Style.DIFFICULTY.yellow
  r.level:SetText(level and tostring(level) or "?")
  r.level:SetTextColor(c[1], c[2], c[3])
end

-- A row that opens questID's page; nil: a row that does not react.
local function setClick(r, questID)
  r:EnableMouse(questID ~= nil)
  if not questID then
    r:SetScript("OnClick", nil)
    return
  end
  r:SetScript("OnClick", function(self, button)
    if UI.Menu.handleClick(self, questID, button) then return end
    if button and button ~= "LeftButton" then return end
    UI.openQuest(questID)
  end)
end

-- Name and sub widths: the name shrinks to leave room for the START HERE tag.
local function fit(r, ix, tag, pin)
  local avail = W - ix - NAME_X - (pin and (PIN + 6) or 4)
  local tagW = tag and (6 + (r.tag:GetStringWidth() or 0)) or 0
  r.name:SetWidth(math.max(40, math.min(r.name:GetStringWidth() or 0, avail - tagW)))
  r.sub:SetWidth(avail)
end

local function stepRow(s, r, ix, step, index, path)
  local q = method(s.db, "quest", step.questID)
  local status = step.status
  local glyph = tostring(step.number or index)
  if status == "done" then glyph = nil end
  if status == "unknown" then glyph = "?" end
  if status == "blocked" then glyph = "X" end
  setDot(r.dot, LOOKS[status] and status or "unknown", glyph)
  local state = s.state
  setLevel(r, step.level, ns.Difficulty.color(step.level, state.level, state.greyAtOrBelow))
  r.name:SetText((step.reason ~= "missing" and step.name) or "Unknown quest")
  local ink = status == "done" and DONE_INK or Style.INK
  r.name:SetTextColor(ink[1], ink[2], ink[3])
  -- the anti-goal: only the path's first startable step says where to start
  local first = index == path.first and status == "start"
  local pin = (status == "start" or status == "progress") and step.giver ~= nil
  r.sub:SetText(subText(s, step, q, first))
  r.bg:SetShown(status == "start")
  r.tag:SetShown(first)
  r.pin:SetShown(pin)
  if pin then
    local id = step.questID
    r.pin:SetScript("OnClick", function() UI.Nav.showQuest(id) end)
  end
  fit(r, ix, first, pin)
  setClick(r, q and step.questID or nil)
  r.step = step
end

-- The last row: the quest itself, numbered after its steps.
local function thisRow(s, r, path, quest)
  quest = quest or {}
  local q = method(s.db, "quest", path.questID)
  setDot(r.dot, "this", tostring((path.total or #path.steps) + 1))
  local level = quest.level or (q and q.level)
  local state = s.state
  setLevel(r, level, quest.color or ns.Difficulty.color(level, state.level, state.greyAtOrBelow))
  r.name:SetText(quest.title or (q and q.name) or "Unknown quest")
  r.name:SetTextColor(Style.INK[1], Style.INK[2], Style.INK[3])
  local place = where(s.db, q and q.giver)
  r.sub:SetText("This quest" .. (place and (" · " .. place) or ""))
  r.bg:Hide()
  r.tag:Hide()
  r.pin:Hide()
  fit(r, 0, false, false)
  setClick(r, nil)
  r.step = nil
end

---------------------------------------------------------------------------
-- Layout.
---------------------------------------------------------------------------
local function placeRow(s, y, ix)
  s.nRows = s.nRows + 1
  local r = pooled(s.rows, s.nRows, function() return newRow(s) end)
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", s.frame, "TOPLEFT", ix, -y)
  r:SetSize(W - ix, ROW_H)
  r:Show()
  return r
end

-- Joins the previous dot to the dot centred at y `center`: green above a done dot.
local function connect(s, center, green)
  if s.prevCenter then
    s.nLines = s.nLines + 1
    local t = pooled(s.lines, s.nLines, function() return s.frame:CreateTexture(nil, "BACKGROUND") end)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", s.frame, "TOPLEFT", LINE_X, -s.prevCenter)
    t:SetSize(2, center - s.prevCenter)
    if green then
      t:SetColorTexture(GREEN[1], GREEN[2], GREEN[3], 1)
    else
      t:SetColorTexture(Style.INK_SOFT[1], Style.INK_SOFT[2], Style.INK_SOFT[3], 0.6)
    end
    t:Show()
  end
  s.prevCenter = center
end

local function label(s, y, group)
  s.nLabels = s.nLabels + 1
  local l = pooled(s.labels, s.nLabels, function()
    local fs = Style.text(s.frame, "GameFontNormalSmall", Style.INK_SOFT)
    fs.mark = disc(s.frame, 8, "ARTWORK") -- a knot on the connector
    fs.mark:SetVertexColor(Style.INK_SOFT[1], Style.INK_SOFT[2], Style.INK_SOFT[3])
    return fs
  end)
  l:SetText(groupLabel(group))
  l:ClearAllPoints()
  l:SetPoint("TOPLEFT", s.frame, "TOPLEFT", LEVEL_X, -(y + 3))
  l.mark:ClearAllPoints()
  l.mark:SetPoint("CENTER", s.frame, "TOPLEFT", LINE_X + 1, -(y + LABEL_H / 2))
  l:Show()
  l.mark:Show()
  return y + LABEL_H
end

local function hideAll(s)
  for _, r in ipairs(s.rows) do r:Hide() end
  for _, l in ipairs(s.labels) do l:Hide(); l.mark:Hide() end
  for _, t in ipairs(s.lines) do t:Hide() end
  s.fold:Hide()
  s.nRows, s.nLabels, s.nLines, s.prevCenter = 0, 0, 0, nil
end

-- The summary right of the heading; returns the y below the header.
local function header(s, path)
  local total, done = path.total or #path.steps, path.done or 0
  local line1 = Style.plural(total, "quest") .. " before this one"
  if done > 0 then line1 = line1 .. " · " .. Style.number(done) .. " done" end
  s.summary:SetText(line1)
  local two = (path.xp or 0) > 0 and (path.remaining or 0) > 0
  s.summary2:SetText(two and ("~" .. Style.number(path.xp) .. " XP on the way") or "")
  s.summary2:SetShown(two)
  -- a second summary line pushes the heading's rule down
  local rule = s.heading.rule
  if two then
    rule:SetPoint("TOPLEFT", s.frame, "TOPLEFT", 0, -31)
  else
    rule:SetPoint("TOPLEFT", s.heading, "BOTTOMLEFT", 0, -3)
  end
  local y = two and 38 or 28
  s.blockedLine:SetShown(path.blocked == true)
  if path.blocked then
    s.blockedLine:ClearAllPoints()
    s.blockedLine:SetPoint("TOPLEFT", s.frame, "TOPLEFT", 0, -y)
    y = y + math.max(s.blockedLine:GetStringHeight() or 0, 12) + 6
  end
  return y
end

local function newFold(s)
  local f = CreateFrame("Frame", nil, s.frame)
  f:SetSize(W, FOLD_H)
  f.dot = newDot(f)
  f.dot:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(FOLD_H - DOT) / 2)
  setDot(f.dot, "done", nil)
  f.text = Style.text(f, "GameFontNormalSmall", Style.INK_SOFT)
  f.text:SetPoint("LEFT", f, "LEFT", LEVEL_X, 0)
  local b = CreateFrame("Button", nil, f)
  local fs = Style.text(b, "GameFontNormalSmall", LINK)
  fs:SetPoint("LEFT", b, "LEFT", 0, 0)
  b:SetFontString(fs)
  b:SetText("Show all")
  b:SetSize(math.max(fs:GetStringWidth() or 0, 40), 16)
  b:SetPoint("LEFT", f.text, "RIGHT", 6, 0)
  b:SetScript("OnEnter", function() fs:SetTextColor(Style.INK[1], Style.INK[2], Style.INK[3]) end)
  b:SetScript("OnLeave", function() fs:SetTextColor(LINK[1], LINK[2], LINK[3]) end)
  s.fold, s.showAll = f, b
end

---------------------------------------------------------------------------
-- The section.
---------------------------------------------------------------------------
function UnlockPath.new(parent)
  local s = { frame = parent, rows = {}, labels = {}, lines = {}, expanded = false,
    nRows = 0, nLabels = 0, nLines = 0 }
  s.heading = Style.heading(parent, "Unlock Path")
  s.heading:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  s.summary = Style.text(parent, "GameFontNormalSmall", Style.INK_SOFT)
  s.summary:SetJustifyH("RIGHT")
  s.summary:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -3)
  s.summary2 = Style.text(parent, "GameFontNormalSmall", Style.INK_SOFT)
  s.summary2:SetJustifyH("RIGHT")
  s.summary2:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -17)
  s.blockedLine = Style.text(parent, "GameFontNormalSmall", RED)
  s.blockedLine:SetWidth(W)
  s.blockedLine:SetWordWrap(true)
  s.blockedLine:SetText("This chain is not available to your character.")
  newFold(s)
  s.showAll:SetScript("OnClick", function() s:expand() end)

  -- Draws `path` (Unlock.path, or nil) for the quest of detail model `quest`; db and state
  -- default to the advisor's. Returns the section's height, 0 without a path.
  function s:render(path, quest, db, state)
    local A = ns.Advisor
    self.path, self.quest = path, quest
    self.db = db or (A and A.db)
    self.state = state or (A and A.last and A.last.state) or {}
    hideAll(self)
    if type(path) ~= "table" or type(path.steps) ~= "table" or #path.steps == 0 then return 0 end
    local y = header(self, path)
    local fold = (path.done or 0) > FOLD_AFTER and not self.expanded
    local folded, group = 0, nil
    if fold then
      for _, step in ipairs(path.steps) do
        if step.status == "done" then folded = folded + 1 end
      end
    end
    for i, step in ipairs(path.steps) do
      if fold and step.status == "done" then
        if not self.fold:IsShown() then -- the first done step's place holds them all
          self.fold:ClearAllPoints()
          self.fold:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -y)
          self.fold.text:SetText(Style.number(folded) .. " earlier steps done")
          self.fold:Show()
          connect(self, y + FOLD_H / 2, true)
          y = y + FOLD_H
        end
      else
        local g = step.group
        local key = g and (tostring(g.kind) .. ":" .. tostring(g.id)) or nil
        if key and key ~= group then y = label(self, y, g) end
        group = key
        local ix = g and INDENT or 0
        stepRow(self, placeRow(self, y, ix), ix, step, i, path)
        connect(self, y + ROW_H / 2, step.status == "done")
        y = y + ROW_H
      end
    end
    thisRow(self, placeRow(self, y, 0), path, quest)
    connect(self, y + ROW_H / 2, false)
    return y + ROW_H
  end

  -- Show all: the done steps unfold; the page learns the new height through onResize.
  function s:expand()
    self.expanded = true
    local h = self:render(self.path, self.quest, self.db, self.state)
    if self.onResize then self.onResize(h) end
  end

  -- Another quest: its done steps start folded again.
  function s:reset()
    self.expanded = false
  end

  hideAll(s)
  return s
end
