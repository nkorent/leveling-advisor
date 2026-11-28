local _, ns = ...

local Settings_ = {}
ns.Settings = Settings_

local PANEL_NAME = "Leveling Advisor"

Settings_.DEFAULTS = { elite = true, dungeons = true, pinsAll = true, recorder = true, minimap = true,
  giverRibbon = true, guide = true }

-- Kept per character (LevelingAdvisorCharDB.settings, made on the first write);
-- every other key is per account (LevelingAdvisorDB.settings).
Settings_.PER_CHARACTER = { guide = true }

local OPTIONS = {
  { key = "elite", label = "Include elite and group quests" },
  { key = "dungeons", label = "Recommend dungeons and their quests" },
  { key = "pinsAll", label = "Show pins for all recommended quest givers" },
  { key = "recorder", label = "Record quest data (local only)" },
  { key = "minimap", label = "Show minimap button" },
  { key = "giverRibbon", label = "Mark recommended quests at quest givers" },
  { key = "guide", label = "Guide: set a waypoint to the next step automatically" },
}

local listeners = {}
local panelFrame, panelCategory

-- The table that holds key: the character's or the account's settings, or nil
-- before the saved variables are set up. create: make the character's table.
local function store(key, create)
  if not Settings_.PER_CHARACTER[key] then return ns.db and ns.db.settings end
  local c = ns.chardb
  if type(c) ~= "table" then return nil end
  if type(c.settings) ~= "table" then
    if not create then return nil end
    c.settings = {}
  end
  return c.settings
end

function Settings_.get(key)
  local t = store(key, false)
  local v = t and t[key]
  if v == nil then return Settings_.DEFAULTS[key] end
  return v
end

function Settings_.set(key, value)
  local t = store(key, true)
  if not t then return end
  t[key] = value
  for i = 1, #listeners do
    local ok, err = pcall(listeners[i], key, value)
    if not ok then geterrorhandler()(err) end
  end
end

function Settings_.onChange(fn)
  listeners[#listeners + 1] = fn
end

function Settings_.forEngine()
  return { elite = Settings_.get("elite"), dungeons = Settings_.get("dungeons") }
end

function Settings_.aboutLine()
  local meta = ns.Data and ns.Data.meta
  local game = (meta and meta.gameData) or "not built"
  return "Leveling Advisor " .. tostring(ns.VERSION)
    .. " — GPL-3.0 — data: QuestieDB Forever (GPL-3.0), outof.games, OpenMap (MIT), an in-game census"
    .. " of map sizes and your own recorder. Game data "
    .. game .. "."
end

local function addCheckbox(frame, index, opt)
  local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16 - (index - 1) * 30)
  local label = cb.Text or cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  if not cb.Text then label:SetPoint("LEFT", cb, "RIGHT", 4, 0) end
  label:SetText(opt.label)
  cb:SetScript("OnClick", function(self)
    local on = self:GetChecked() and true or false
    Settings_.set(opt.key, on)
  end)
  return cb
end

local function buildPanel()
  local frame = CreateFrame("Frame", nil, nil)
  frame.name = PANEL_NAME
  local boxes = {}
  for i, opt in ipairs(OPTIONS) do boxes[i] = addCheckbox(frame, i, opt) end
  local about = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  about:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16 - #OPTIONS * 30 - 12)
  about:SetText(Settings_.aboutLine())
  frame:SetScript("OnShow", function()
    for i, opt in ipairs(OPTIONS) do boxes[i]:SetChecked(Settings_.get(opt.key)) end
    about:SetText(Settings_.aboutLine())
  end)
  return frame
end

-- Returns the registered category (or legacy frame), or nil when no API exists.
function Settings_.registerPanel()
  local ok, frame = pcall(buildPanel)
  if not ok then return nil end
  if type(Settings) == "table" and Settings.RegisterCanvasLayoutCategory
      and Settings.RegisterAddOnCategory then
    local ok2, category = pcall(function()
      local c = Settings.RegisterCanvasLayoutCategory(frame, PANEL_NAME)
      Settings.RegisterAddOnCategory(c)
      return c
    end)
    if ok2 and category then
      panelFrame, panelCategory = frame, category
      return category
    end
  end
  if type(InterfaceOptions_AddCategory) == "function" then
    if pcall(InterfaceOptions_AddCategory, frame) then
      panelFrame, panelCategory = frame, frame
      return frame
    end
  end
  return nil
end

function Settings_.open()
  if ns.Util.inCombat() then
    ns.Util.say(ns.Util.COMBAT_MSG)
    return
  end
  if not panelCategory then Settings_.registerPanel() end
  if not panelCategory then return end
  if type(panelCategory.GetID) == "function" and type(Settings) == "table"
      and Settings.OpenToCategory then
    pcall(Settings.OpenToCategory, panelCategory:GetID())
  elseif InterfaceOptionsFrame_OpenToCategory then
    pcall(InterfaceOptionsFrame_OpenToCategory, panelFrame)
  end
end
