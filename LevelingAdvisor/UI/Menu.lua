local _, ns = ...; ns.UI = ns.UI or {}; ns.UI.Menu = ns.UI.Menu or {}
local Menu = ns.UI.Menu
local method = ns.Util.method
local say = ns.Util.say

-- The quest right-click menu, Link to Chat and Ignore (spec 5.6).
local function quest(db, questID)
  return db and method(db, "quest", questID)
end

local function questName(questID)
  local A = ns.Advisor
  local q = A and quest(A.db, questID)
  return q and q.name or ("quest " .. tostring(questID))
end

function Menu.entries(questID)
  local ignored = ns.chardb and ns.chardb.ignored and ns.chardb.ignored[questID]
  return {
    { label = "Show on Map", action = "show" },
    { label = "Link to Chat", action = "link" },
    ignored and { label = "Stop Ignoring This Quest", action = "unignore" }
      or { label = "Ignore This Quest", action = "ignore" },
    { label = "Cancel", action = "cancel" },
  }
end

function Menu.questLink(db, questID)
  local ok, link = pcall(function() return GetQuestLink and GetQuestLink(questID) end)
  if ok and type(link) == "string" and link ~= "" then return link end
  local q = quest(db, questID)
  if not q then return nil end
  return string.format("|cffffff00|Hquest:%d:%s|h[%s]|h|r", questID, tostring(q.level or 0), tostring(q.name))
end

-- Tries each way to put the link in chat until one works and records the
-- attempts in Menu.lastLink (/advisor debug). On this client ChatEdit_InsertLink
-- returned false without inserting (diagnostic-results.md), so it comes last of
-- the insert methods and a false return counts as a failure.
function Menu.linkQuest(questID)
  local A = ns.Advisor
  local link = Menu.questLink(A and A.db, questID)
  Menu.lastLink = {}
  if not link then return false end
  local function record(name, result)
    Menu.lastLink[#Menu.lastLink + 1] = { name, result }
  end
  -- A step that returns true on success.
  local function insert(name, fn)
    if type(fn) ~= "function" then return false end
    local ok, r = pcall(fn, link)
    record(name, ok and r or false)
    return ok and r == true
  end
  -- A step that counts as success when it runs without error.
  local function ran(name, fn)
    local ok = pcall(fn)
    record(name, ok and "ran" or false)
    return ok
  end

  if insert("ChatFrameUtil.InsertLink", type(ChatFrameUtil) == "table" and ChatFrameUtil.InsertLink) then return true end

  if type(ChatEdit_GetActiveWindow) == "function" then
    local ok, box = pcall(ChatEdit_GetActiveWindow)
    if ok and type(box) == "table" and type(box.Insert) == "function" then
      if ran("ChatEdit_GetActiveWindow", function() box:Insert(link) end) then return true end
    else
      record("ChatEdit_GetActiveWindow", false)
    end
  end
  if type(ChatEdit_ActivateChat) == "function" and type(ChatEdit_ChooseBoxForSend) == "function" then
    if ran("ChatEdit_ActivateChat", function()
      local box = ChatEdit_ChooseBoxForSend()
      ChatEdit_ActivateChat(box)
      box:Insert(link)
    end) then return true end
  end
  if insert("ChatEdit_InsertLink", ChatEdit_InsertLink) then return true end

  if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.OpenChat) == "function" then
    if ran("ChatFrameUtil.OpenChat", function() ChatFrameUtil.OpenChat(link) end) then return true end
  elseif type(ChatFrame_OpenChat) == "function" then
    if ran("ChatFrame_OpenChat", function() ChatFrame_OpenChat(link) end) then return true end
  end
  say("Quest link: " .. link)
  return false
end

function Menu.ignore(questID)
  ns.Slash.setIgnored(questID, true)
  say("Ignoring " .. questName(questID) .. ". Type /advisor unignore " .. questID .. " to undo.")
end

function Menu.unignore(questID)
  ns.Slash.setIgnored(questID, false)
  say("No longer ignoring " .. questName(questID) .. ".")
end

local ACTIONS = {
  show = function(id) ns.UI.Nav.showQuest(id) end,
  link = function(id) Menu.linkQuest(id) end,
  ignore = function(id) Menu.ignore(id) end,
  unignore = function(id) Menu.unignore(id) end,
  cancel = function() end,
}

function Menu.open(owner, questID)
  if type(MenuUtil) ~= "table" or type(MenuUtil.CreateContextMenu) ~= "function" then return end
  local entries = Menu.entries(questID)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    method(root, "CreateTitle", questName(questID))
    for _, e in ipairs(entries) do
      if e.action == "cancel" then method(root, "CreateDivider") end
      method(root, "CreateButton", e.label, function() ACTIONS[e.action](questID) end)
    end
  end)
end

-- The shared click handling of quest rows, route lines and the detail title.
-- Returns true when the click was a menu or link click (the caller stops).
function Menu.handleClick(owner, questID, button)
  if not questID then return false end
  if button == "RightButton" then
    Menu.open(owner, questID)
    return true
  end
  if (button == nil or button == "LeftButton") and type(IsModifiedClick) == "function"
    and select(2, pcall(IsModifiedClick, "CHATLINK")) == true then
    Menu.linkQuest(questID)
    return true
  end
  return false
end

-- The minimap button's right-click menu (0.3.0): the guide switch ("Guide: On",
-- "Guide: Paused" or "Guide: Off"; on or paused, it turns the guide off),
-- Continue with waypoint (greyed out while the guide is off) and Settings.
-- Fail-soft: no MenuUtil means no menu; no guide module means Settings only.
function Menu.openGuide(owner)
  if type(MenuUtil) ~= "table" or type(MenuUtil.CreateContextMenu) ~= "function" then return end
  local Guide = ns.UI.Guide
  MenuUtil.CreateContextMenu(owner, function(_, root)
    method(root, "CreateTitle", "Leveling Advisor")
    if Guide then
      local on = Guide.enabled()
      local label = not on and "Guide: Off" or (Guide.paused() and "Guide: Paused" or "Guide: On")
      method(root, "CreateButton", label, function() Guide.setEnabled(not on) end)
      local item = method(root, "CreateButton", "Continue with waypoint", function()
        if Guide.enabled() then Guide.continue() end
      end)
      if not on then method(item, "SetEnabled", false) end
    end
    method(root, "CreateButton", "Settings", function() ns.Settings.open() end)
  end)
end
