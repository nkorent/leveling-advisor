local _, ns = ...; ns.UI = ns.UI or {}; ns.UI.MainView = ns.UI.MainView or {}
local UI = ns.UI
local MainView = UI.MainView
local Style, Model, ZoneArt, List, QuestRow = UI.Style, UI.Model, UI.ZoneArt, UI.List, UI.QuestRow
local call, method = ns.Util.call, ns.Util.method

-- The main page (spec 5.5). Left: character line, XP bar, three recommended
-- zone cards and the dungeon card. Right: the recommended quests in sections.
local W, CARD_H, GAP = Style.CONTENT_W, 88, 8
local BORDER, BORDER_HERE, BORDER_HOVER = { 0.16, 0.11, 0.05 }, Style.GOLD, { 0.66, 0.57, 0.36 }
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local XP_COLOR, RESTED_COLOR = { 0.58, 0.0, 0.55 }, { 0.0, 0.39, 0.88, 0.55 }
local ZONE_CARDS = 3

local function setBorder(card, c)
  for _, t in ipairs(card.border) do t:SetColorTexture(c[1], c[2], c[3], 1) end
end

local function newBorder(over)
  local edges = {}
  for i = 1, 4 do edges[i] = over:CreateTexture(nil, "OVERLAY") end
  edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(2)
  edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(2)
  edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(2)
  edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(2)
  return edges
end

-- Darkens the art from the left (text side) to the right.
local function shade(over)
  local tex = over:CreateTexture(nil, "BACKGROUND")
  tex:SetAllPoints(over)
  tex:SetColorTexture(1, 1, 1, 1)
  local a, b = call(CreateColor, 0, 0, 0, 0.82), call(CreateColor, 0, 0, 0, 0.08)
  if not (a and b and pcall(tex.SetGradient, tex, "HORIZONTAL", a, b)) then
    tex:SetColorTexture(0, 0, 0, 0.5)
  end
  return tex
end

-- A 382 x 88 card button; card:set(m, kind) fills it from a zone or dungeon model.
function MainView.card(parent)
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(W, CARD_H)
  local card = { frame = btn, art = ZoneArt.newBox(btn, W, CARD_H) }
  card.art:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
  local base = method(btn, "GetFrameLevel") or 1
  method(card.art, "SetFrameLevel", base + 1)
  method(card.art.canvas, "SetFrameLevel", base + 2)

  local over = CreateFrame("Frame", nil, btn)
  over:SetAllPoints(btn)
  method(over, "SetFrameLevel", base + 5)
  card.shade = shade(over)
  card.border = newBorder(over)
  card.nameText = Style.text(over, "GameFontNormalLarge", Style.GOLD)
  card.nameText:SetPoint("TOPLEFT", over, "TOPLEFT", 10, -8)
  card.levelsText = Style.text(over, "GameFontHighlightSmall")
  card.levelsText:SetPoint("LEFT", card.nameText, "RIGHT", 8, 0)
  card.statsText = Style.text(over, "GameFontHighlightSmall")
  card.statsText:SetPoint("TOPLEFT", over, "TOPLEFT", 10, -34)
  card.reasonText = Style.text(over, "GameFontHighlightSmall", Style.REASON)
  card.reasonText:SetPoint("BOTTOMLEFT", over, "BOTTOMLEFT", 10, 9)
  card.reasonText:SetWidth(W - 20)
  card.reasonText:SetWordWrap(false)
  card.nameText:SetWordWrap(false)
  -- text over bright art stays legible with a shadow
  for _, fs in ipairs({ card.nameText, card.levelsText, card.statsText, card.reasonText }) do
    method(fs, "SetShadowColor", 0, 0, 0, 1)
    method(fs, "SetShadowOffset", 1, -1)
  end
  btn.laCard = card

  function card:set(m, kind)
    self.model, self.kind = m, kind
    self.nameText:SetText(m.name or "")
    self.levelsText:SetText(m.group and (m.levels .. " · " .. m.group) or m.levels or "")
    -- a long name is cut with an ellipsis before it reaches the levels text
    local room = W - 20 - 8 - (self.levelsText:GetStringWidth() or 0)
    self.nameText:SetWidth(math.max(40, math.min(self.nameText:GetStringWidth() or 0, room)))
    self.statsText:SetText(m.stats or "")
    self.reasonText:SetText(m.reason or "")
    self.here = m.isHere and true or false
    setBorder(self, self.here and BORDER_HERE or BORDER)
    ZoneArt.draw(self.art, kind == "dungeon" and m.artMapID or m.mapID, "crop")
  end

  btn:SetScript("OnEnter", function() setBorder(card, BORDER_HOVER) end)
  btn:SetScript("OnLeave", function() setBorder(card, card.here and BORDER_HERE or BORDER) end)
  btn:SetScript("OnClick", function()
    local m = card.model
    if not m then return end
    if card.kind == "dungeon" then
      UI.show({ kind = "dungeon", key = m.key })
    else
      UI.show({ kind = "zone", mapID = m.mapID })
    end
  end)
  return card
end

local function newBar(parent, color, level)
  local bar = CreateFrame("StatusBar", nil, parent)
  bar:SetSize(W, 12)
  bar:SetStatusBarTexture(BAR_TEXTURE)
  bar:SetStatusBarColor(color[1], color[2], color[3], color[4])
  method(bar, "SetFrameLevel", level)
  return bar
end

local view = {}

local function setQuestList()
  if not view.list then return end
  local ctx = UI.context()
  local collapsed = ns.chardb and ns.chardb.collapsed or {}
  local ui = ns.chardb and ns.chardb.ui
  view.list:set(Model.questList(ctx.rec, collapsed, ui and ui.laterOpen))
end

local function buildHeader(frame)
  local root = CreateFrame("Frame", nil, frame)
  root:SetAllPoints(frame)
  local p = { root = root }
  p.sign = root:CreateTexture(nil, "ARTWORK")
  p.sign:SetSize(16, 16)
  p.sign:SetPoint("LEFT", root, "LEFT", 2, 0)
  p.title = Style.text(root, "QuestFont", Style.INK)
  p.title:SetPoint("LEFT", root, "LEFT", 22, 0)
  p.count = Style.text(root, "QuestFont", Style.INK_SOFT)
  p.count:SetJustifyH("RIGHT")
  p.count:SetPoint("RIGHT", root, "RIGHT", -4, 0)
  return p
end

local function buildText(frame)
  local root = CreateFrame("Frame", nil, frame)
  root:SetAllPoints(frame)
  local p = { root = root }
  p.text = Style.text(root, "QuestFont", Style.INK_SOFT)
  p.text:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -6)
  p.text:SetWidth(W)
  return p
end

local function toggle(key)
  local c = ns.chardb
  if not c then return end
  if key == "later" then -- collapsed by default: the saved flag is "open"
    c.ui = c.ui or {}
    c.ui.laterOpen = not c.ui.laterOpen
    setQuestList()
    return
  end
  c.collapsed = c.collapsed or {}
  if c.collapsed[key] then c.collapsed[key] = nil else c.collapsed[key] = true end
  setQuestList()
end

-- Fills a pooled row frame for one list element (header, quest or text).
function MainView.initRow(frame, e)
  if e.kind == "header" then
    local p = List.part(frame, "header", buildHeader)
    Style.setTexture(p.sign, nil, e.collapsed and "Interface\\Buttons\\UI-PlusButton-Up"
      or "Interface\\Buttons\\UI-MinusButton-Up")
    p.title:SetText(e.title or "")
    p.count:SetText(tostring(e.count or 0))
    frame:SetScript("OnClick", function() toggle(e.key) end)
  elseif e.kind == "quest" then
    local cur = UI.current()
    QuestRow.render(frame, e.row, { sectionKey = e.sectionKey,
      selected = cur and cur.questID == e.row.questID })
  else
    local p = List.part(frame, "text", buildText)
    p.text:SetText(e.text or "")
    frame:SetScript("OnClick", nil)
  end
end

-- "Guide: On/Paused/Off" and "Resume guide", on their own row right
-- under the recommendations heading's rule. Labels follow Guide.onChange; hidden
-- without the guide module. Paused, the toggle still turns the guide off and
-- Resume guide resumes it.
local function refreshGuide()
  local G = ns.UI.Guide
  local on = G and G.enabled()
  if view.guideToggle then
    view.guideToggle:SetShown(G ~= nil)
    view.guideToggle:SetText(G and G.label() or "Guide: Off")
  end
  if view.guideContinue then
    view.guideContinue:SetShown(G ~= nil)
    view.guideContinue:SetEnabled(on and true or false)
  end
end

local LIST_TOP = 28 -- the list's offset below the heading
local GUIDE_GAP = 4
local GUIDE_ROW = 22 + GUIDE_GAP -- button height + the gap below it

-- Sizes a button to its widest label: the text width + 24 (the template's
-- ends), at least min; fallback when the client cannot measure the text.
local function fitWidth(b, labels, min, fallback)
  local fs = method(b, "GetFontString")
  local widest
  for _, label in ipairs(labels) do
    b:SetText(label)
    local w = method(fs, "GetStringWidth")
    if type(w) == "number" and w > 0 then widest = math.max(widest or 0, w) end
  end
  b:SetWidth(widest and math.max(min, widest + 24) or fallback)
end

function MainView.buildGuideControls(right)
  view.guideContinue = Style.button(right, "Resume guide", 110)
  fitWidth(view.guideContinue, { "Resume guide" }, 100, 110)
  view.guideContinue:SetPoint("TOPRIGHT", view.questsHeading.rule, "BOTTOMRIGHT", 0, -GUIDE_GAP)
  view.guideContinue:SetScript("OnClick", function()
    if ns.UI.Guide then ns.UI.Guide.continue() end
  end)
  view.guideToggle = Style.button(right, "Guide: On", 100)
  fitWidth(view.guideToggle, { "Guide: On", "Guide: Paused", "Guide: Off" }, 80, 100)
  view.guideToggle:SetPoint("RIGHT", view.guideContinue, "LEFT", -4, 0)
  view.guideToggle:SetScript("OnClick", function()
    local G = ns.UI.Guide
    if G then G.setEnabled(not G.enabled()) end
  end)
  if ns.UI.Guide then ns.UI.Guide.onChange(refreshGuide) end
  refreshGuide()
end

local function build(leftParent, rightParent)
  local left = CreateFrame("Frame", nil, leftParent)
  left:SetAllPoints(leftParent)
  local right = CreateFrame("Frame", nil, rightParent)
  right:SetAllPoints(rightParent)
  view.questsHeading = Style.heading(right, "Recommended Quests")
  view.questsHeading:SetPoint("TOPLEFT", right, "TOPLEFT", 0, 0)
  MainView.buildGuideControls(right)
  view.list = List.new(right, function(frame, e) MainView.initRow(frame, e) end)
  if view.list then
    local top = LIST_TOP + (ns.UI.Guide and GUIDE_ROW or 0)
    view.list.box:SetPoint("TOPLEFT", right, "TOPLEFT", 0, -top)
    view.list.box:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 0)
    view.list.bar:SetPoint("TOPLEFT", view.list.box, "TOPRIGHT", 4, 0)
    view.list.bar:SetPoint("BOTTOMLEFT", view.list.box, "BOTTOMRIGHT", 4, 0)
  else
    view.noList = Style.text(right, "QuestFont", Style.INK_SOFT)
    view.noList:SetPoint("TOPLEFT", right, "TOPLEFT", 0, -34)
    view.noList:SetText("The quest list is not available on this client.")
  end

  view.charLeft = Style.text(left, "QuestFont", Style.INK)
  view.charLeft:SetPoint("TOPLEFT", left, "TOPLEFT", 0, 0)
  view.charRight = Style.text(left, "QuestFont", Style.INK)
  view.charRight:SetJustifyH("RIGHT")
  view.charRight:SetPoint("TOPRIGHT", left, "TOPRIGHT", 0, 0)
  view.charLeft:SetPoint("RIGHT", view.charRight, "LEFT", -8, 0)
  view.charLeft:SetWordWrap(false)

  local base = method(left, "GetFrameLevel") or 1
  view.rested = newBar(left, RESTED_COLOR, base + 1)
  view.rested:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -22)
  local back = view.rested:CreateTexture(nil, "BACKGROUND")
  back:SetAllPoints(view.rested)
  back:SetColorTexture(0, 0, 0, 0.45)
  view.xp = newBar(left, XP_COLOR, base + 2)
  view.xp:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -22)

  view.zonesHeading = Style.heading(left, "Recommended Zones")
  view.zonesHeading:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -46)
  view.cards = {}
  for i = 1, ZONE_CARDS do
    local c = MainView.card(left)
    c.frame:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -(72 + (i - 1) * (CARD_H + GAP)))
    view.cards[i] = c
  end
  view.empty = Style.text(left, "QuestFont", Style.INK_SOFT)
  view.empty:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -82)
  view.empty:SetText("No zones to recommend right now.")

  view.dungeonHeading = Style.heading(left, "Recommended Dungeon")
  view.dungeonHeading:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -366)
  view.dungeon = MainView.card(left)
  view.dungeon.frame:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -392)
  return left, right
end

local function setHeading(h, shown)
  h:SetShown(shown)
  h.rule:SetShown(shown)
end

local function update(_, ctx)
  setQuestList()
  refreshGuide()
  local m = Model.left(ctx.rec, ctx.state, ctx.db, UI.playerInfo())
  view.charLeft:SetText(m.char.left)
  view.charRight:SetText(m.char.right)
  local max = m.char.xpMax > 0 and m.char.xpMax or 1
  view.xp:SetMinMaxValues(0, max)
  view.xp:SetValue(m.char.xp)
  view.rested:SetMinMaxValues(0, max)
  view.rested:SetValue(math.min(m.char.xp + m.char.rested, max))

  setHeading(view.zonesHeading, true)
  for i, c in ipairs(view.cards) do
    local z = m.zones[i]
    if z then c:set(z, "zone") end
    c.frame:SetShown(z ~= nil)
  end
  view.empty:SetShown(#m.zones == 0)
  setHeading(view.dungeonHeading, m.dungeon ~= nil)
  if m.dungeon then view.dungeon:set(m.dungeon, "dungeon") end
  view.dungeon.frame:SetShown(m.dungeon ~= nil)
end

UI.registerView("main", { build = build, update = update })
