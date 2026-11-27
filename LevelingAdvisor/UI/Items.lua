local _, ns = ...; ns.UI = ns.UI or {}; ns.UI.Items = ns.UI.Items or {}
local Items = ns.UI.Items
local UI = ns.UI
local Style = UI.Style
local call, method = ns.Util.call, ns.Util.method

-- Item buttons, the quest items/rewards model and the proficiency check
-- (spec 5.6). Names and quality load asynchronously; the icon is instant.
local PLATE = "Interface\\QuestFrame\\UI-QuestItemNameFrame"
local NOTE_COLOR = { 1, 0.82, 0 }
local NOTES = {
  given = "Leveling Advisor: given to you when you accept the quest",
  needed = "Leveling Advisor: needed for %s",
}

-- C_Item functions, falling back to the older globals when C_Item is absent.
local function itemAPI()
  local c = type(C_Item) == "table" and C_Item or {}
  return {
    GetItemInfoInstant = c.GetItemInfoInstant or GetItemInfoInstant,
    GetItemInfo = c.GetItemInfo or GetItemInfo,
    GetItemCount = c.GetItemCount or GetItemCount,
    GetItemQualityColor = c.GetItemQualityColor or GetItemQualityColor,
  }
end

---------------------------------------------------------------------------
-- Proficiency (pure).
---------------------------------------------------------------------------
local PROFICIENCY = {
  WARRIOR = { armor = { 1, 2, 3, 4, 6 },   weapon = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 } },
  PALADIN = { armor = { 1, 2, 3, 4, 6, 7 }, weapon = { 0, 1, 4, 5, 6, 7, 8 } },
  HUNTER  = { armor = { 1, 2, 3 },         weapon = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 } },
  ROGUE   = { armor = { 1, 2 },            weapon = { 2, 3, 4, 7, 13, 15, 16, 18 } },
  PRIEST  = { armor = { 1 },               weapon = { 4, 10, 15, 19 } },
  SHAMAN  = { armor = { 1, 2, 3, 6, 9 },   weapon = { 0, 1, 4, 5, 10, 13, 15 } },
  MAGE    = { armor = { 1 },               weapon = { 7, 10, 15, 19 } },
  WARLOCK = { armor = { 1 },               weapon = { 7, 10, 15, 19 } },
  DRUID   = { armor = { 1, 2, 8 },         weapon = { 4, 5, 10, 13, 15 } },
}
for _, p in pairs(PROFICIENCY) do
  for _, key in ipairs({ "armor", "weapon" }) do
    local set = {}
    for _, v in ipairs(p[key]) do set[v] = true end
    p[key] = set
  end
end

-- Only weapons (2) and armor (4) can fail.
function Items.canUse(classFile, classID, subclassID, equipLoc)
  local p = PROFICIENCY[classFile]
  if not p then return true end
  if classID == 4 then
    -- cloaks, miscellaneous (0) and cosmetic (5) armor are never unusable
    if equipLoc == "INVTYPE_CLOAK" or subclassID == 0 or subclassID == 5 then return true end
    return p.armor[subclassID] == true
  elseif classID == 2 then
    if subclassID == 14 or subclassID == 20 then return true end
    return p.weapon[subclassID] == true
  end
  return true
end

---------------------------------------------------------------------------
-- Model (pure).
---------------------------------------------------------------------------
local function pair(e)
  if type(e) == "table" then return e[1], e[2] or 1 end
  return e, 1
end

local function fromDB(list)
  local out = {}
  for i, e in ipairs(list or {}) do
    local id, count = pair(e)
    out[i] = { itemID = id, count = count }
  end
  return out
end

local function copyEntries(list)
  local out = {}
  for i, e in ipairs(list or {}) do
    out[i] = { itemID = e.itemID, count = e.count, usable = e.usable }
  end
  return out
end

-- The name a required item has in the quest log: its item objective's (Contract A
-- field 26), else the item's own name (env.itemName, GetItemInfo).
local function requiredName(q, id, env)
  for _, o in ipairs(q.objectives or {}) do
    if o.kind == 3 and o.id == id and o.name then return o.name end
  end
  return env.itemName and env.itemName(id) or nil
end

-- env: count(itemID) -> bags count; live = Items.liveRewards; objectives =
-- QuestInfo.liveObjectives (the quest log's live objectives); itemName(itemID).
-- A required item's count is the data's (nil when unknown: never a made-up 1); the
-- log's numRequired / numFulfilled for that item win.
function Items.model(db, q, state, env)
  env = env or {}
  local live = env.live
  local m = { provided = {}, required = {}, lines = {} }
  local items = q.items or {}
  for _, id in ipairs(items.provided or {}) do
    m.provided[#m.provided + 1] = { itemID = id, note = "given" }
  end
  for _, e in ipairs(items.required or {}) do
    local id, count = e, nil
    if type(e) == "table" then id, count = e[1], e[2] end
    local have = env.count and env.count(id) or 0
    local progress = env.objectives
      and UI.QuestInfo.liveProgress(env.objectives, requiredName(q, id, env), "item") or nil
    if progress then count, have = progress.need, progress.have end
    m.required[#m.required + 1] = { itemID = id, count = count, have = have, note = "needed" }
  end
  local r = q.rewards or {}
  local xpLine, money
  if live then
    m.choice, m.fixed = copyEntries(live.choice), copyEntries(live.fixed)
    money = live.money
    if live.xp then xpLine = "Experience: " .. Style.number(live.xp) end
  else
    m.choice, m.fixed = fromDB(r.choice), fromDB(r.fixed)
    money = r.money
  end
  if not xpLine then
    local xp = ns.XP.estimate(q, state and state.level, state and state.recordedXP) or 0
    if xp > 0 then xpLine = "Experience: ~" .. Style.number(xp) end
  end
  if xpLine and not xpLine:find("^Experience: 0$") then m.lines[#m.lines + 1] = xpLine end
  if (money or 0) > 0 then m.lines[#m.lines + 1] = "Money: " .. Style.money(money) end
  for _, rep in ipairs(r.rep or {}) do
    local name, amount = rep[1], rep[2] or 0
    m.lines[#m.lines + 1] = tostring(name) .. " reputation " .. (amount >= 0 and "+" or "") .. amount
  end
  if r.spellID then
    local name = env.spellName and env.spellName(r.spellID)
    m.lines[#m.lines + 1] = name and ("You will learn: " .. name) or "You will learn a spell."
  end
  if #m.choice > 0 then m.choiceLabel = "You will be able to choose one of these rewards:" end
  if #m.fixed > 0 then m.fixedLabel = #m.choice > 0 and "You will also receive:" or "You will receive:" end
  m.hasRewards = (#m.choice + #m.fixed + #m.lines) > 0
  return m
end

---------------------------------------------------------------------------
-- Live data (the by-questID calls; the selected-quest form errors here).
---------------------------------------------------------------------------
local function readItems(countFn, infoFn, questID)
  local out = {}
  local n = tonumber(call(countFn, questID, true)) or 0
  for i = 1, n do
    local _, _, count, _, usable, itemID = call(infoFn, i, questID)
    if itemID then out[#out + 1] = { itemID = itemID, count = count or 1, usable = usable } end
  end
  return out, n
end

function Items.liveRewards(questID)
  if type(C_QuestLog) ~= "table" or not call(C_QuestLog.GetLogIndexForQuestID, questID) then return nil end
  local choice, nc = readItems(GetNumQuestLogChoices, GetQuestLogChoiceInfo, questID)
  local fixed, nr = readItems(GetNumQuestLogRewards, GetQuestLogRewardInfo, questID)
  local xp = call(GetQuestLogRewardXP, questID)
  if nc == 0 and nr == 0 and xp == nil then return nil end
  return { choice = choice, fixed = fixed, money = tonumber(call(GetQuestLogRewardMoney, questID)) or 0, xp = xp }
end

function Items.realEnv(questID)
  return {
    live = Items.liveRewards(questID),
    objectives = UI.QuestInfo.liveObjectives(questID),
    itemName = function(id)
      local name = call(itemAPI().GetItemInfo, id)
      return name
    end,
    count = function(id)
      return tonumber(call(itemAPI().GetItemCount, id)) or 0
    end,
    spellName = function(id)
      local info = type(C_Spell) == "table" and call(C_Spell.GetSpellInfo, id)
      return type(info) == "table" and info.name or nil
    end,
  }
end

---------------------------------------------------------------------------
-- Buttons.
---------------------------------------------------------------------------
local function modifier()
  return call(IsShiftKeyDown) or call(IsControlKeyDown)
end

local function itemLink(id)
  local _, link = call(itemAPI().GetItemInfo, id)
  return link
end

-- The ItemButton intrinsic draws its slot frame and quality border for a
-- 37 px button; they do not follow SetSize.
Items.SLOT = 37

-- size: the on-screen size. A mini button (I6) is a full 37 px button scaled
-- down (Blizzard's own way for small item buttons), so its slot frame and
-- quality border shrink with it; b.laScale is that scale (anchor offsets of
-- the button are in its own, scaled, units).
function Items.newButton(parent, size, mini)
  size = size or (mini and 22 or Items.SLOT)
  local ok, b = pcall(CreateFrame, "ItemButton", nil, parent)
  if not ok or type(b) ~= "table" then
    b = CreateFrame("Button", nil, parent)
    b.laFallback = true
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
  end
  if mini then
    b:SetSize(Items.SLOT, Items.SLOT)
    b.laScale = size / Items.SLOT
    method(b, "SetScale", b.laScale)
  else
    b:SetSize(size, size)
  end
  b.laMini = mini and true or false
  if type(b.Count) ~= "table" then
    b.Count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.Count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
  end
  if not mini then
    b.laPlate = b:CreateTexture(nil, "BACKGROUND")
    b.laPlate:SetTexture(PLATE)
    b.laPlate:SetSize(128, 62)
    b.laPlate:SetPoint("LEFT", b, "RIGHT", -6, 0)
    b.laName = Style.text(b, "GameFontNormalSmall", Style.INK)
    b.laName:SetWidth(110)
    b.laName:SetWordWrap(true)
    method(b.laName, "SetMaxLines", 2)
    b.laName:SetPoint("LEFT", b, "RIGHT", 8, 0)
  end
  if mini then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") else b:RegisterForClicks("LeftButtonUp") end
  b:SetScript("OnEnter", function(self)
    local id = self.laItemID
    if not id or type(GameTooltip) ~= "table" then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(id)
    local note = self.laNote and NOTES[self.laNote]
    if note then
      GameTooltip:AddLine(string.format(note, tostring(self.laQuestName or "")), NOTE_COLOR[1], NOTE_COLOR[2], NOTE_COLOR[3])
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
  b:SetScript("OnClick", function(self, button)
    local id = self.laItemID
    if not id then return end
    if not modifier() then
      -- a plain click on a row's icon is a click on the row; on the detail page it does nothing
      if self.laMini then
        local row = self:GetParent() and self:GetParent():GetParent()
        local fn = row and method(row, "GetScript", "OnClick")
        if fn then fn(row, button) end
      end
      return
    end
    local link = itemLink(id)
    if link then
      call(HandleModifiedItemClick, link)
    else
      ns.Util.say("No link for this item yet: try again in a moment.")
    end
  end)
  return b
end

local function showCount(b, entry)
  if entry.have ~= nil then
    -- a required item: "have/count", or just "have" when the count is unknown
    b.Count:SetText(entry.count and (entry.have .. "/" .. entry.count) or tostring(entry.have))
    b.Count:Show()
  else
    call(SetItemButtonCount, b, (entry.count or 1) > 1 and entry.count or 1)
  end
end

local function applyInfo(b, id, name, quality)
  if b.laName then
    b.laName:SetText(name or "")
    if quality then
      local r, g, bl = call(itemAPI().GetItemQualityColor, quality)
      if r then Style.setTextColor(b.laName, r, g, bl) end
    end
  end
  if quality then call(SetItemButtonQuality, b, quality, id) end
end

function Items.setItem(b, entry, questName)
  local id = entry.itemID
  local token = {}
  b.laToken, b.laItemID, b.laNote, b.laQuestName = token, id, entry.note, questName
  local api = itemAPI()
  local _, _, _, equipLoc, icon, classID, subclassID = call(api.GetItemInfoInstant, id)
  if b.laFallback then
    if icon then b.icon:SetTexture(icon) end
  else
    call(SetItemButtonTexture, b, icon)
  end
  showCount(b, entry)

  local usable = entry.usable
  if usable == nil then
    local ctx = UI.context()
    usable = Items.canUse(ctx.state and ctx.state.classFile, classID, subclassID, equipLoc)
  end
  if usable == false then
    call(SetItemButtonTextureVertexColor, b, 1, 0.1, 0.1)
    b.laTinted = true
  elseif b.laTinted then
    call(SetItemButtonTextureVertexColor, b, 1, 1, 1)
    b.laTinted = nil
  end

  if b.laName then b.laName:SetText("") end
  call(SetItemButtonQuality, b, nil, id) -- clear the border of the item this button showed before
  local name, _, quality = call(api.GetItemInfo, id)
  if name then
    applyInfo(b, id, name, quality)
  elseif type(Item) == "table" then
    pcall(function()
      Item:CreateFromItemID(id):ContinueOnItemLoad(function()
        if b.laToken ~= token then return end
        local n, _, q = call(api.GetItemInfo, id)
        applyInfo(b, id, n, q)
      end)
    end)
  end
end
