-- A leather bookmark on the quest log's right edge that opens the book, plus
-- the addon compartment entry. Fail-soft: a missing host or compartment is
-- skipped silently.
local addonName, ns = ...; ns.UI = ns.UI or {}; ns.UI.QuestLogTab = ns.UI.QuestLogTab or {}
local QuestLogTab = ns.UI.QuestLogTab

-- QuestMapFrame is the quest log on this client; QuestLogFrame is only a
-- fallback for a client without it (never both).
QuestLogTab.HOSTS = { "QuestMapFrame", "QuestLogFrame" }
QuestLogTab.NATIVE_TABS = { "QuestsTab", "MapLegendTab", "EventsTab" }
QuestLogTab.OFFSET = { x = -2, y = -40, gap = -3 }
QuestLogTab.ICON = "Interface\\Icons\\INV_Misc_Book_09"

local BOOKMARK = "Interface\\AddOns\\" .. tostring(addonName) .. "\\Media\\BookmarkTab"
local tabs = {} -- host frame -> tab

local function findHost()
  for _, name in ipairs(QuestLogTab.HOSTS) do
    local host = _G[name]
    if type(host) == "table" then return host end
  end
end

local function lastNativeTab(host)
  local last
  for _, key in ipairs(QuestLogTab.NATIVE_TABS) do
    local ok, t = pcall(function() return host[key] end)
    if ok and type(t) == "table" then last = t end
  end
  return last
end

local function showTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText("Leveling Advisor")
  GameTooltip:AddLine("Click to open the advisor.", 1, 1, 1)
  GameTooltip:Show()
end

local function build(host, index)
  local tab = CreateFrame("Button", "LevelingAdvisorQuestLogTab" .. index, host)
  tab:SetSize(40, 40)
  tab:SetFrameLevel(host:GetFrameLevel() + 10)
  local native = lastNativeTab(host)
  if native then
    tab:SetPoint("TOP", native, "BOTTOM", 0, QuestLogTab.OFFSET.gap)
  else
    tab:SetPoint("TOPLEFT", host, "TOPRIGHT", QuestLogTab.OFFSET.x, QuestLogTab.OFFSET.y)
  end

  local bg = tab:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetTexture(BOOKMARK)
  local icon = tab:CreateTexture(nil, "ARTWORK")
  icon:SetSize(24, 24)
  icon:SetPoint("CENTER", tab, "CENTER", -2, 0)
  icon:SetTexture(QuestLogTab.ICON)
  tab.laIcon = icon
  local hl = tab:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture(BOOKMARK)
  hl:SetBlendMode("ADD")
  hl:SetAlpha(0.35)
  local sel = tab:CreateTexture(nil, "OVERLAY")
  sel:SetAllPoints(icon)
  sel:SetTexture("Interface\\Buttons\\CheckButtonHilight")
  sel:SetBlendMode("ADD")
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

ns.Init.onReady(function()
  QuestLogTab.attach()
  QuestLogTab.registerCompartment()
end)

ns.Events.on("ADDON_LOADED", function(name)
  if name == "Blizzard_WorldMap" then QuestLogTab.attach() end
end)
