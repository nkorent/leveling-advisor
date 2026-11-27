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
local CHAIN_ICON = "Interface\\AddOns\\LevelingAdvisor\\Media\\ChainLink"
local CHAIN_SIZE = 17
local CHAIN_PENDING = { 0.48, 0.31, 0.07 } -- earlier quests left: brown-gold
local CHAIN_READY = { 0.18, 0.42, 0.12 }   -- chain ready: green
local CHAIN_COUNT = { 0.62, 0.12, 0.09 }
local CHAIN_BLOCKED = { 1, 0.2, 0.2 }

-- The chain badge: a link icon (a Frame, so it can show a tooltip) and, while earlier
-- quests are left, their count.
function QuestRow.buildBadge(root)
  local b = { frame = CreateFrame("Frame", nil, root) }
  b.frame:SetSize(CHAIN_SIZE, CHAIN_SIZE)
  b.frame:EnableMouse(true)
  -- The badge takes the mouse for its tooltip; clicks must still reach the row (left click,
  -- right-click menu). Either the client passes them on, or we forward them: never both.
  if type(b.frame.SetPropagateMouseClicks) == "function" then
    b.frame:SetPropagateMouseClicks(true)
  else
    b.frame:SetScript("OnMouseUp", function(_, button)
      local row = root:GetParent()
      local onClick = row and row:GetScript("OnClick")
      if onClick then onClick(row, button) end
    end)
  end
  b.icon = b.frame:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(CHAIN_SIZE, CHAIN_SIZE)
  b.icon:SetPoint("LEFT", b.frame, "LEFT", 0, 0)
  b.icon:SetTexture(CHAIN_ICON)
  b.count = Style.text(b.frame, "GameFontNormalSmall", CHAIN_COUNT)
  b.count:SetTextColor(CHAIN_COUNT[1], CHAIN_COUNT[2], CHAIN_COUNT[3])
  b.count:SetPoint("LEFT", b.icon, "RIGHT", 1, 0)
  b.frame:SetScript("OnEnter", function(self)
    local path = b.path
    if not path or type(GameTooltip) ~= "table" then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Chain quest", 1, 1, 1)
    if path.blocked then
      GameTooltip:AddLine("Not available to your character", CHAIN_BLOCKED[1], CHAIN_BLOCKED[2], CHAIN_BLOCKED[3])
    elseif path.remaining > 0 then
      GameTooltip:AddLine(path.remaining .. (path.remaining == 1 and " earlier quest" or " earlier quests")
        .. " to do first", 1, 1, 1)
    else
      GameTooltip:AddLine("Earlier quests done", 1, 1, 1)
    end
    GameTooltip:Show()
  end)
  b.frame:SetScript("OnLeave", function()
    if type(GameTooltip) == "table" then GameTooltip:Hide() end
  end)
  b.frame:Hide()
  return b
end

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
  p.chain = QuestRow.buildBadge(root)
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

-- Shows or hides the chain badge for `path` (nil hides it); returns the width it takes.
local function layoutBadge(p, path)
  local b = p.chain
  b.path = path
  if not path then
    b.frame:Hide()
    return 0
  end
  local c = path.remaining > 0 and CHAIN_PENDING or CHAIN_READY
  b.icon:SetVertexColor(c[1], c[2], c[3])
  local w = CHAIN_SIZE
  b.count:SetShown(path.remaining > 0)
  if path.remaining > 0 then
    b.count:SetText(tostring(path.remaining))
    w = w + 1 + (b.count:GetStringWidth() or 0)
  end
  b.frame:SetWidth(w)
  b.frame:Show()
  return w
end

-- "Start: <name> · <zone>" for a chain with earlier quests left, "First: <name> · not in the
-- advisor's data" when its first open step is not a shipped quest (nothing says it can be
-- started), else nil.
local function chainSub(db, path)
  if path.remaining <= 0 then return nil end
  -- a chain that cannot be finished never says where to start
  if path.blocked then return "Not available to your character" end
  if path.first then
    local step = path.steps[path.first]
    local zone = step and step.giver and QuestInfo.zoneName(db, step.giver.mapID)
    return "Start: " .. ((step and step.name) or "Unknown quest") .. (zone and (" · " .. zone) or "")
  end
  for _, s in ipairs(path.steps) do
    if s.status ~= "done" then
      if s.status == "unknown" and (s.reason == "stub" or s.reason == "missing") then
        return "First: " .. (s.name or "Unknown quest") .. " · not in the advisor's data"
      end
      break
    end
  end
  return nil
end

local function layoutTitle(p, tags, badgeW)
  local avail = W - TITLE_X - PIN - 8 - QuestRow.ICONS_W - (badgeW > 0 and badgeW + 6 or 0)
  local tagsW = 0
  for i, t in ipairs(tags) do
    p.tags[i]:SetText(t.text)
    tagsW = tagsW + 6 + (p.tags[i]:GetStringWidth() or 0)
  end
  local titleW = math.max(40, math.min(p.title:GetStringWidth() or 0, avail - tagsW))
  p.title:SetWidth(titleW)
  local prev = p.title
  if badgeW > 0 then
    p.chain.frame:ClearAllPoints()
    p.chain.frame:SetPoint("LEFT", p.title, "RIGHT", 6, 0)
    prev = p.chain.frame
  end
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
      -- offsets of a scaled button are in its own units (I6)
      b:SetPoint("RIGHT", p.root, "RIGHT", -(PIN + 8 + (#ids - i) * MINI_STEP) / (b.laScale or 1), 0)
      UI.Items.setItem(b, { itemID = id })
      b:Show()
    else
      b.laItemID = nil
      b:Hide()
    end
  end
end

-- opts = { onClick = fn(row) | nil, sectionKey, selected, sub, chain }
-- A row on a chain shows its "Chain n/m" tag (the chain position). opts.chain: a row with an
-- unlock path shows the chain badge (and its Start sub line) instead of the tag; a row
-- without one keeps the tag.
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
  local path = opts.chain and A and A.db and A.last
    and QuestInfo.unlockPath(A.db, row.questID, A.last.state) or nil
  local tags
  if path then
    tags = QuestInfo.tags(row, q) -- the badge replaces the "Chain n/m" tag (R4)
  else
    tags = QuestInfo.tags(row, q, A and A.db, A and A.last and A.last.state)
  end
  layoutTitle(p, tags, layoutBadge(p, path))
  layoutIcons(p, q)
  p.sub:SetWidth(W - TITLE_X - PIN - 8 - QuestRow.ICONS_W)
  local sub = opts.sub
  if sub == nil and A and A.db then
    sub = QuestInfo.subLine(A.db, row, A.last and A.last.state)
  end
  local chain = path and chainSub(A.db, path)
  p.sub:SetText(chain or sub or "")
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
