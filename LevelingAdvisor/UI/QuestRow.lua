local _, ns = ...; ns.UI = ns.UI or {}; ns.UI.QuestRow = ns.UI.QuestRow or {}
local QuestRow = ns.UI.QuestRow
local UI = ns.UI
local Style, List, QuestInfo = UI.Style, UI.List, UI.QuestInfo
local method = ns.Util.method

-- One quest row of the book's lists (44 px): marker, level, title, tags, sub line
-- and the Show on Map button.
QuestRow.HEIGHT = 44
QuestRow.ICONS_W = 78 -- the reward icons: up to three 22 px buttons

local W = Style.CONTENT_W
local PIN = 26
local MAX_TAGS = 6
local MAX_ICONS = 3
local MINI, MINI_STEP = 22, 26
local TITLE_X = 60
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function build(frame)
  local root = CreateFrame("Frame", nil, frame)
  root:SetAllPoints(frame)
  local p = { root = root }
  p.bg = root:CreateTexture(nil, "BACKGROUND")
  p.bg:SetAllPoints(root)
  p.bg:SetColorTexture(Style.GOLD[1], Style.GOLD[2], Style.GOLD[3], 0.18)
  p.marker = Style.texture(root, "ARTWORK", "QuestNormal", QuestInfo.MARKER_FILES.QuestNormal)
  p.marker:SetSize(16, 16)
  p.marker:SetPoint("TOPLEFT", root, "TOPLEFT", 4, -5)
  p.levelBox = root:CreateTexture(nil, "ARTWORK")
  p.levelBox:SetSize(30, 18)
  p.levelBox:SetPoint("TOPLEFT", root, "TOPLEFT", 24, -4)
  p.levelBox:SetColorTexture(0.08, 0.06, 0.05, 1)
  p.level = Style.text(root, "GameFontNormalSmall")
  p.level:SetSize(30, 18)
  p.level:SetJustifyH("CENTER")
  p.level:SetPoint("TOPLEFT", root, "TOPLEFT", 24, -4)
  p.title = Style.text(root, "QuestFont", Style.INK)
  p.title:SetPoint("TOPLEFT", root, "TOPLEFT", TITLE_X, -5)
  p.title:SetWordWrap(false)
  p.tags = {}
  for i = 1, MAX_TAGS do
    local t = Style.text(root, "GameFontNormalSmall", Style.INK_SOFT)
    t:SetWordWrap(false)
    p.tags[i] = t
  end
  p.sub = Style.text(root, "GameFontNormalSmall", Style.INK_SOFT)
  p.sub:SetPoint("TOPLEFT", root, "TOPLEFT", TITLE_X, -25)
  p.sub:SetWordWrap(false)
  p.pin = Style.pinButton(root, nil)
  p.pin:SetPoint("RIGHT", root, "RIGHT", -4, 0)
  p.minis = {}
  for i = 1, MAX_ICONS do
    p.minis[i] = UI.Items.newButton(root, MINI, true)
    p.minis[i]:Hide()
  end
  return p
end

local function layoutTitle(p, tags)
  local avail = W - TITLE_X - PIN - 8 - QuestRow.ICONS_W
  local tagsW = 0
  for i, t in ipairs(tags) do
    p.tags[i]:SetText(t.text)
    tagsW = tagsW + 6 + (p.tags[i]:GetStringWidth() or 0)
  end
  local titleW = math.max(40, math.min(p.title:GetStringWidth() or 0, avail - tagsW))
  p.title:SetWidth(titleW)
  local prev = p.title
  for i = 1, MAX_TAGS do
    local fs = p.tags[i]
    local t = tags[i]
    fs:SetShown(t ~= nil)
    if t then
      fs:SetTextColor(t.color[1], t.color[2], t.color[3])
      fs:ClearAllPoints()
      fs:SetPoint("LEFT", prev, "RIGHT", 6, 0)
      prev = fs
    end
  end
end

-- Up to three reward icons (database rewards: choices first, then fixed),
-- packed against the pin. Rows use the database, not the live log.
local function layoutIcons(p, q)
  local ids = {}
  local r = q and q.rewards or {}
  for _, list in ipairs({ r.choice or {}, r.fixed or {} }) do
    for _, e in ipairs(list) do
      if #ids < MAX_ICONS then ids[#ids + 1] = type(e) == "table" and e[1] or e end
    end
  end
  for i, b in ipairs(p.minis) do
    local id = ids[i]
    if id then
      b:ClearAllPoints()
      b:SetPoint("RIGHT", p.root, "RIGHT", -(PIN + 8 + (#ids - i) * MINI_STEP), 0)
      UI.Items.setItem(b, { itemID = id })
      b:Show()
    else
      b.laItemID = nil
      b:Hide()
    end
  end
end

-- opts = { onClick = fn(row) | nil, sectionKey, selected, sub }
function QuestRow.render(frame, row, opts)
  opts = opts or {}
  local p = List.part(frame, "quest", build)
  local m = QuestInfo.marker(row.soon and "unavailable" or row.state)
  Style.setTexture(p.marker, m.atlas, m.atlas and QuestInfo.MARKER_FILES[m.atlas] or m.file, m.desaturated)
  local c = Style.DIFFICULTY[row.color] or Style.DIFFICULTY.yellow
  p.level:SetText(tostring(row.level or ""))
  p.level:SetTextColor(c[1], c[2], c[3])
  p.title:SetText(row.name or "")
  local A = ns.Advisor
  local q = A and A.db and method(A.db, "quest", row.questID)
  layoutTitle(p, QuestInfo.tags(row, q))
  layoutIcons(p, q)
  p.sub:SetWidth(W - TITLE_X - PIN - 8 - QuestRow.ICONS_W)
  local sub = opts.sub
  if sub == nil and A and A.db then
    sub = QuestInfo.subLine(A.db, row, A.last and A.last.state)
  end
  p.sub:SetText(sub or "")
  p.bg:SetShown(opts.selected and true or false)

  frame:SetHighlightTexture(WHITE, "ADD")
  local hl = method(frame, "GetHighlightTexture")
  if type(hl) == "table" then method(hl, "SetVertexColor", 1, 1, 1, 0.08) end
  frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  frame:SetScript("OnClick", function(_, button)
    if UI.Menu.handleClick(frame, row.questID, button) then return end
    if button and button ~= "LeftButton" then return end
    if opts.onClick then
      opts.onClick(row)
    elseif UI.openQuest then
      UI.openQuest(row.questID, { section = opts.sectionKey, yards = row.yards })
    end
  end)
  p.pin:SetScript("OnClick", function() UI.Nav.showQuest(row.questID) end)
  return p
end
