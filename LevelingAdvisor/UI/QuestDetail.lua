local _, ns = ...; ns.UI = ns.UI or {}; ns.UI.QuestDetail = ns.UI.QuestDetail or {}
local QuestDetail = ns.UI.QuestDetail
local UI = ns.UI
local Style, QuestInfo = UI.Style, UI.QuestInfo
local method = ns.Util.method

-- The quest detail page: a scrolling stack of named sections (spec 5.6).
local W = 360
local GAP = 10
local GIVER_H, BUTTON_H = 56, 26
local HEADING_H = 24
local ORDER = { "head", "giver", "unlock", "map", "why", "objective", "items", "actions" }

local function fill(frame, r, g, b, a)
  local tex = frame:CreateTexture(nil, "BACKGROUND")
  tex:SetAllPoints(frame)
  tex:SetColorTexture(r, g, b, a)
  return tex
end

local function wrapped(parent, font, color, x, y)
  local fs = Style.text(parent, font, color)
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
  fs:SetWidth(W - (x or 0))
  fs:SetWordWrap(true)
  return fs
end

local function height(fs)
  return fs:GetStringHeight() or 0
end

local function buildHead(frame)
  local h = {}
  h.title = wrapped(frame, "QuestTitleFont", Style.INK)
  -- The title is a click target for the quest menu and Shift-click linking.
  h.hit = CreateFrame("Button", nil, frame)
  h.hit:SetPoint("TOPLEFT", h.title, "TOPLEFT", 0, 0)
  h.hit:SetSize(W, 20)
  h.hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  h.level = Style.text(frame, "QuestFont")
  h.meta = Style.text(frame, "QuestFont", Style.INK_SOFT)
  h.meta:SetWordWrap(true)
  h.chainXp = Style.text(frame, "QuestFont", Style.INK_SOFT)
  h.chainXp:SetWidth(W)
  return h
end

local function buildGiver(frame)
  local g = {}
  fill(frame, 0.48, 0.33, 0.15, 0.12)
  g.marker = Style.texture(frame, "ARTWORK", "QuestNormal", QuestInfo.MARKER_FILES.QuestNormal)
  g.marker:SetSize(16, 16)
  g.marker:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
  g.title = Style.text(frame, "QuestFont", Style.INK)
  g.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -6)
  g.title:SetWidth(W - 30 - 44)
  g.title:SetWordWrap(false)
  g.coords = Style.text(frame, "GameFontNormalSmall", Style.INK_SOFT)
  g.coords:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -23)
  g.status = Style.text(frame, "GameFontNormalSmall", Style.INK_SOFT)
  g.status:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, -38)
  g.status:SetWidth(W - 30 - 44)
  g.status:SetWordWrap(true) -- "Needs 4 earlier quests first. Start with ..." takes two lines
  g.pin = Style.pinButton(frame, nil)
  g.pin:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
  return g
end

local function buildBlock(frame, label)
  local b = {}
  b.heading = Style.heading(frame, label)
  b.heading:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  b.body = wrapped(frame, "QuestFont", Style.INK, 0, -HEADING_H)
  return b
end

local function buildActions(frame)
  local a = {}
  a.button = Style.button(frame, "Show on Map", 160)
  a.button:SetSize(160, BUTTON_H)
  a.button:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  a.hint = Style.text(frame, "GameFontNormalSmall", Style.INK_SOFT)
  a.hint:SetPoint("LEFT", a.button, "RIGHT", 10, 0)
  a.hint:SetText("Right-click a quest for more")
  return a
end

-- Stacks the visible sections top-down and sizes the scroll child.
local function layout(d)
  local y = 0
  for _, s in ipairs(d.sections) do
    if s.height > 0 then
      s.frame:ClearAllPoints()
      s.frame:SetPoint("TOPLEFT", d.content, "TOPLEFT", 0, -y)
      s.frame:SetSize(W, s.height)
      s.frame:Show()
      y = y + s.height + GAP
    else
      s.frame:Hide()
    end
  end
  d.content:SetSize(W, math.max(y, 1))
end

local function setSection(d, name, h)
  d.byName[name].height = h
end

local function renderHead(d, m)
  local h = d.parts.head
  h.title:SetText(m.title or "")
  h.title:SetWidth(W)
  h.hit:SetHeight(math.max(height(h.title), 20))
  local y = height(h.title) + 4
  local c = Style.DIFFICULTY[m.color] or Style.DIFFICULTY.yellow
  h.level:SetText("[" .. tostring(m.level or "?") .. "]")
  Style.setTextColor(h.level, c[1], c[2], c[3])
  h.level:ClearAllPoints()
  h.level:SetPoint("TOPLEFT", h.title, "TOPLEFT", 0, -y)
  local levelW = (h.level:GetStringWidth() or 0) + 6
  local bits = {}
  if m.requiredText then bits[#bits + 1] = m.requiredText end
  if m.chainText then bits[#bits + 1] = m.chainText end
  for _, t in ipairs(m.tags or {}) do bits[#bits + 1] = t.text end
  if m.xpText then bits[#bits + 1] = m.xpText end
  h.meta:SetText(table.concat(bits, " · "))
  h.meta:SetWidth(W - levelW)
  h.meta:ClearAllPoints()
  h.meta:SetPoint("TOPLEFT", h.title, "TOPLEFT", levelW, -y)
  y = y + math.max(height(h.meta), 16)
  h.chainXp:SetText(m.chainXpText or "")
  h.chainXp:SetShown(m.chainXpText ~= nil)
  if m.chainXpText then
    h.chainXp:ClearAllPoints()
    h.chainXp:SetPoint("TOPLEFT", h.title, "TOPLEFT", 0, -(y + 2))
    y = y + 2 + math.max(height(h.chainXp), 16)
  end
  setSection(d, "head", y)
end

local function renderGiver(d, m)
  local g = d.parts.giver
  if not m.giver then setSection(d, "giver", 0); return end
  -- m.state is the availability status; a soon quest is not available yet
  local marker = QuestInfo.marker(m.state == "soon" and "unavailable" or m.state)
  Style.setTexture(g.marker, marker.atlas, marker.atlas and QuestInfo.MARKER_FILES[marker.atlas] or marker.file,
    marker.desaturated)
  g.title:SetText(m.giver.title or "")
  g.coords:SetText(m.giver.coords or "")
  g.status:SetText(m.giver.status or "")
  setSection(d, "giver", math.max(GIVER_H, 38 + height(g.status) + 6))
end

local function renderBlock(d, name, text)
  local b = d.parts[name]
  if not text then setSection(d, name, 0); return end
  b.body:SetText(text)
  b.body:SetWidth(W)
  setSection(d, name, HEADING_H + math.max(height(b.body), 14))
end

---------------------------------------------------------------------------
-- Items section: provided, required and reward item buttons.
---------------------------------------------------------------------------
local CELL_W, CELL_H = 180, 44

local function pooled(list, i, make)
  local w = list[i]
  if not w then w = make(); list[i] = w end
  return w
end

local function buildItems(frame)
  return { frame = frame, headings = {}, labels = {}, buttons = {}, nHeading = 0, nLabel = 0, nButton = 0 }
end

local function resetItems(p)
  for _, h in ipairs(p.headings) do h:SetText(""); h:Hide(); h.rule:Hide() end
  for _, l in ipairs(p.labels) do l:SetText(""); l:Hide() end
  for _, b in ipairs(p.buttons) do b:Hide() end
  p.nHeading, p.nLabel, p.nButton = 0, 0, 0
end

local function itemsHeading(p, y, label)
  p.nHeading = p.nHeading + 1
  local h = pooled(p.headings, p.nHeading, function() return Style.heading(p.frame, "") end)
  h:SetText(label)
  h:ClearAllPoints()
  h:SetPoint("TOPLEFT", p.frame, "TOPLEFT", 0, -y)
  h:Show(); h.rule:Show()
  return y + HEADING_H
end

local function itemsLabel(p, y, text)
  p.nLabel = p.nLabel + 1
  local l = pooled(p.labels, p.nLabel, function()
    local fs = Style.text(p.frame, "QuestFont", Style.INK)
    fs:SetWidth(W)
    fs:SetWordWrap(true)
    return fs
  end)
  l:SetText(text)
  l:ClearAllPoints()
  l:SetPoint("TOPLEFT", p.frame, "TOPLEFT", 0, -y)
  l:Show()
  return y + math.max(height(l), 14) + 4
end

local function itemsGrid(p, y, entries, questName)
  for i, e in ipairs(entries) do
    p.nButton = p.nButton + 1
    local b = pooled(p.buttons, p.nButton, function() return UI.Items.newButton(p.frame, 37) end)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", p.frame, "TOPLEFT", ((i - 1) % 2) * CELL_W, -(y + math.floor((i - 1) / 2) * CELL_H))
    UI.Items.setItem(b, e, questName)
    b:Show()
  end
  return y + math.ceil(#entries / 2) * CELL_H + 4
end

local function renderItems(d, m)
  local p = d.parts.items
  resetItems(p)
  local q = d.db:quest(m.questID)
  local model = q and UI.Items.model(d.db, q, d.state, UI.Items.realEnv(m.questID))
  if not model then setSection(d, "items", 0); return end
  local y = 0
  local function group(label, list)
    if #list == 0 then return end
    y = itemsGrid(p, itemsHeading(p, y, (Style.plural(#list, label):gsub("^[%d,]+ ", ""))), list, m.title)
  end
  group("Provided item", model.provided)
  group("Required item", model.required)
  if model.hasRewards then
    y = itemsHeading(p, y, "Rewards")
    if model.choiceLabel then y = itemsGrid(p, itemsLabel(p, y, model.choiceLabel), model.choice, m.title) end
    if model.fixedLabel then y = itemsGrid(p, itemsLabel(p, y, model.fixedLabel), model.fixed, m.title) end
    for _, line in ipairs(model.lines) do y = itemsLabel(p, y, line) end
  end
  setSection(d, "items", y > 0 and (y - 4) or 0)
end

local function renderMap(d, m)
  local mm = d.parts.map
  local q = d.db:quest(m.questID)
  local model = q and QuestInfo.miniMap(d.db, q, d.state)
  setSection(d, "map", model and mm:show(model, m) or 0)
  if not model then mm:hide() end
end

function QuestDetail.new(parent)
  local d = { sections = {}, byName = {}, parts = {} }
  d.scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  d.scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  d.scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  d.content = CreateFrame("Frame", nil, d.scroll)
  d.content:SetSize(W, 1)
  d.scroll:SetScrollChild(d.content)

  -- A file added in an update is not loaded until the client restarts (/reload is not
  -- enough): without UI/UnlockPath.lua the page goes without the section (height 0).
  local UnlockPath = UI.UnlockPath
  local builders = {
    head = buildHead, giver = buildGiver,
    unlock = type(UnlockPath) == "table" and type(UnlockPath.new) == "function"
      and function(f) return UnlockPath.new(f) end or nil,
    why = function(f) return buildBlock(f, "Why Now") end,
    objective = function(f) return buildBlock(f, "Objective") end,
    items = buildItems,
    map = function(f) return UI.MiniMap.new(f) end,
    actions = buildActions,
  }
  for _, name in ipairs(ORDER) do
    local frame = CreateFrame("Frame", nil, d.content)
    frame:SetSize(W, 1)
    local entry = { name = name, frame = frame, height = 0 }
    d.sections[#d.sections + 1] = entry
    d.byName[name] = entry
    if builders[name] then d.parts[name] = builders[name](frame) end
  end

  d.message = Style.text(d.content, "QuestFont", Style.INK_SOFT)
  d.message:SetPoint("TOPLEFT", d.content, "TOPLEFT", 0, -6)
  d.message:SetWidth(W)
  d.message:SetWordWrap(true)
  d.message:Hide()

  -- Show all in the Unlock Path changes its height
  if d.parts.unlock then
    d.parts.unlock.onResize = function(h)
      setSection(d, "unlock", h)
      layout(d)
    end
  end
  d.parts.head.hit:SetScript("OnClick", function(self, button)
    UI.Menu.handleClick(self, d.questID, button)
  end)
  d.parts.giver.pin:SetScript("OnClick", function()
    if d.questID then UI.Nav.showQuest(d.questID) end
  end)
  d.parts.actions.button:SetScript("OnClick", function()
    if d.questID then UI.Nav.showQuest(d.questID) end
  end)

  -- Shows a message instead of a quest.
  function d:clear(text)
    self.questID = nil
    for _, s in ipairs(self.sections) do s.height = 0 end
    layout(self)
    self.message:SetText(text or "")
    self.message:Show()
  end

  function d:show(questID, source)
    local ctx = UI.context()
    local m = ctx.db and ctx.state and QuestInfo.detail(ctx.db, questID, ctx.state, source)
    if not m then
      self:clear("This quest is not in the advisor's database.")
      return
    end
    -- an advisor refresh of the same quest keeps the reader's place
    local sameQuest = self.questID == questID
    self.questID, self.db, self.state, self.model = questID, ctx.db, ctx.state, m
    self.message:Hide()
    local unlock = self.parts.unlock
    if unlock and not sameQuest then unlock:reset() end
    renderHead(self, m)
    renderGiver(self, m)
    setSection(self, "unlock", unlock and unlock:render(m.unlock, m, ctx.db, ctx.state) or 0)
    renderMap(self, m)
    renderBlock(self, "why", m.why)
    renderBlock(self, "objective", m.objective)
    renderItems(self, m)
    setSection(self, "actions", BUTTON_H)
    layout(self)
    if not sameQuest then method(self.scroll, "SetVerticalScroll", 0) end
  end

  return d
end
