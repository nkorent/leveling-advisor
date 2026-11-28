local _, ns = ...

local Slash = {}
ns.Slash = Slash

local say = ns.Util.say

local inCombat = ns.Util.inCombat

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
    say(ns.Util.COMBAT_MSG)
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

-- The ignore list changed: recompute.
local function replanIgnored()
  if ns.Advisor.scheduler then ns.Advisor.scheduler:request("settings") end
end

-- Shared by the slash commands and the quest menu.
function Slash.setIgnored(id, on)
  ns.chardb.ignored[id] = on and true or nil
  replanIgnored()
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
    replanIgnored()
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
  local link = ns.UI and ns.UI.Menu and ns.UI.Menu.lastLink
  if link then
    local bits = {}
    for i, a in ipairs(link) do bits[i] = a[1] .. "=" .. tostring(a[2]) end
    say("last link: " .. table.concat(bits, ", "))
  end
  -- the world map's pin templates: names the game's waypoint pin if our guess is wrong
  local pins = ns.MapPins and ns.MapPins.describeMapPins
  if type(pins) == "function" then
    local ok, line = pcall(pins)
    if ok and line then say(line) end
  end
  local guide = ns.UI and ns.UI.Guide and ns.UI.Guide.debugLine
  if type(guide) == "function" then
    local ok, line = pcall(guide)
    if ok and line then say(line) end
  end
end

local function pins()
  if ns.MapPins and ns.MapPins.describe then
    say(ns.MapPins.describe())
  else
    say("Map pins are not available.")
  end
end

local function tabCmd(arg)
  local QLT = ns.UI and ns.UI.QuestLogTab
  if not QLT then say("The bookmark tab is not available."); return end
  if arg == "" then say(QLT.describe()); return end
  if arg:lower() == "reset" then
    QLT.setOffset(nil); say("Bookmark tab offset cleared."); return
  end
  local dx, dy = arg:match("^(%-?[%d%.]+)%s+(%-?[%d%.]+)$")
  dx, dy = tonumber(dx), tonumber(dy)
  if not dx then say("Usage: /advisor tab <dx> <dy> | reset"); return end
  local ox, oy = QLT.getOffset()
  local _, clamped = QLT.setOffset(ox + dx, oy + dy)
  if clamped then say("Tab offset limited to \194\177200.") end
  say(QLT.describe())
end

local function minimapCmd()
  local on = not ns.Settings.get("minimap")
  ns.Settings.set("minimap", on)
  say(on and "Minimap button shown." or "Minimap button hidden.")
end

local CONTINUED = {
  combat = "Guide: the waypoint is set after the fight.",
  none = "Guide: no next step right now.",
  off = "The guide is off. Type /advisor guide on to turn it on.",
  failed = "Guide: waypoints are not available on this client.",
}

local function guideCmd(arg)
  local G = ns.UI and ns.UI.Guide
  if not G then say("The guide is not available."); return end
  arg = arg:lower()
  if arg == "" then
    say(G.describe())
  elseif arg == "on" then
    G.setEnabled(true)
    say("Guide on: a waypoint marks your next step.")
  elseif arg == "off" then
    G.setEnabled(false)
    say("Guide off.")
  elseif arg == "resume" or arg == "continue" then
    local status, t = G.continue()
    if status == "set" then
      say("Guide: waypoint set to " .. tostring(t and t.label) .. ".")
    else
      say(CONTINUED[status] or G.describe())
    end
  else
    say("Usage: /advisor guide on|off|resume")
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
  print("  /advisor tab [dx dy|reset] — nudge the quest-log bookmark tab")
  print("  /advisor minimap — show or hide the minimap button")
  print("  /advisor guide [on|off|resume] — a waypoint to your next step")
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
  elseif name == "tab" then tabCmd(arg)
  elseif name == "minimap" then minimapCmd()
  elseif name == "guide" then guideCmd(arg)
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
