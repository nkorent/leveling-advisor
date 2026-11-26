local _, ns = ...

local Slash = {}
ns.Slash = Slash

local say = ns.Util.say

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function printSummary()
  local A = ns.Advisor
  if not A.db then
    if A.loadError then
      say("Quest data failed to load: " .. tostring(A.loadError))
    else
      say("No quest data loaded. Run the data pipeline and /reload.")
    end
    return
  end
  if inCombat() then
    say("Not in combat: try again after the fight.")
    return
  end
  local rec, err = A.compute()
  if not rec then
    say("Could not compute recommendations: " .. tostring(err))
    return
  end
  local lines = A.summaryLines(rec, A.db)
  if #lines == 0 then
    say("No recommendations for this character right now.")
    return
  end
  for _, line in ipairs(lines) do print(line) end
end

local function questArg(arg)
  local id = tonumber(arg:match("^(%d+)$"))
  if id and id > 0 then return id end
  return nil
end

-- Shared by the slash commands and the quest menu.
function Slash.setIgnored(id, on)
  ns.chardb.ignored[id] = on and true or nil
  if ns.Advisor.scheduler then ns.Advisor.scheduler:request("settings") end
end

local function ignore(arg)
  local id = questArg(arg)
  if not id then say("Usage: /advisor ignore <questID>"); return end
  Slash.setIgnored(id, true)
  say("Ignoring quest " .. id .. ".")
end

local function unignore(arg)
  if arg:lower() == "all" then
    for k in pairs(ns.chardb.ignored) do ns.chardb.ignored[k] = nil end
    if ns.Advisor.scheduler then ns.Advisor.scheduler:request("settings") end
    say("Cleared all ignored quests.")
    return
  end
  local id = questArg(arg)
  if not id then say("Usage: /advisor unignore <questID>"); return end
  Slash.setIgnored(id, false)
  say("No longer ignoring quest " .. id .. ".")
end

local function showOnMap(arg)
  local id = questArg(arg)
  if not id then say("Usage: /advisor map <questID>"); return end
  if ns.UI and ns.UI.Nav and ns.UI.Nav.showQuest then
    ns.UI.Nav.showQuest(id)
  else
    say("The map view is not available.")
  end
end

local function debugInfo()
  local A = ns.Advisor
  local n = A.db and #A.db:questIDs() or 0
  local last = A.last
  local ms = last and last.ms and ns.Util.round1(last.ms) or "n/a"
  local s = last and last.state
  local logSize = 0
  if s then for _ in pairs(s.log) do logSize = logSize + 1 end end
  say(string.format("quests=%d, last compute=%s ms, computes=%d (all calls), scheduler runs=%d (timer-driven), level=%s, mapID=%s, log=%d, grey=%s",
    n, tostring(ms), A.computes or 0, A.scheduler and A.scheduler.runs or 0,
    tostring(s and s.level), tostring(s and s.mapID), logSize,
    tostring(s and s.greyAtOrBelow)))
  local last = ns.UI and ns.UI.Menu and ns.UI.Menu.lastLink
  if last then
    local bits = {}
    for i, a in ipairs(last) do bits[i] = a[1] .. "=" .. tostring(a[2]) end
    say("last link: " .. table.concat(bits, ", "))
  end
end

local function pins()
  if ns.MapPins and ns.MapPins.describe then
    say(ns.MapPins.describe())
  else
    say("Map pins are not available.")
  end
end

local function help()
  say("Commands:")
  print("  /advisor — open the advisor book")
  print("  /advisor summary — recommendations in chat")
  print("  /advisor ignore <questID> — hide a quest")
  print("  /advisor unignore <questID|all> — show it again")
  print("  /advisor settings — open settings")
  print("  /advisor export — export recorder data")
  print("  /advisor about — version and data sources")
  print("  /advisor map <questID> — show a quest on the map")
  print("  /advisor pins — count the map pins on the current map")
  print("  /advisor debug — diagnostics")
  print("  /advisor help — list the commands")
end

function Slash.handle(msg)
  local name, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  name = name:lower()
  if name == "" then
    if ns.UI and ns.UI.toggle then ns.UI.toggle() else printSummary() end
  elseif name == "summary" then printSummary()
  elseif name == "ignore" then ignore(arg)
  elseif name == "unignore" then unignore(arg)
  elseif name == "settings" then ns.Settings.open()
  elseif name == "export" then
    if ns.Export and ns.Export.run then ns.Export.run() else say("Export is not available yet.") end
  elseif name == "about" then say(ns.Settings.aboutLine())
  elseif name == "map" then showOnMap(arg)
  elseif name == "pins" then pins()
  elseif name == "debug" then debugInfo()
  elseif name == "help" then help()
  else
    say('Unknown command "' .. name .. '".')
    help()
  end
end

SLASH_LEVELINGADVISOR1 = "/advisor"
SlashCmdList["LEVELINGADVISOR"] = function(msg)
  local ok, err = pcall(Slash.handle, msg)
  if not ok then geterrorhandler()(err) end
end

ns.Init.onReady(function() ns.Advisor.init() end)
ns.Init.onReady(function() ns.Settings.registerPanel() end)
