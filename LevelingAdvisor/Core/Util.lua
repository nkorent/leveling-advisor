local _, ns = ...

local Util = {}
ns.Util = Util

local PREFIX = "|cffffd100Leveling Advisor:|r "

-- pcall wrapper: returns fn's results, or nil when fn is not a function or throws.
local function unwrap(ok, ...)
  if ok then return ... end
  return nil
end

function Util.call(fn, ...)
  if type(fn) ~= "function" then return nil end
  return unwrap(pcall(fn, ...))
end

-- Calls obj:name(...) fail-soft.
function Util.method(obj, name, ...)
  if type(obj) ~= "table" then return nil end
  local ok, fn = pcall(function() return obj[name] end)
  if not ok or type(fn) ~= "function" then return nil end
  return unwrap(pcall(fn, obj, ...))
end

-- NPC id is the 6th "-" separated field of Creature-/Vehicle- GUIDs.
function Util.npcIDFromGUID(guid)
  if type(guid) ~= "string" then return nil end
  local kind, id = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-")
  if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
  return tonumber(id)
end

function Util.say(msg)
  print(PREFIX .. tostring(msg))
end

function Util.round1(n)
  return math.floor(n * 10 + 0.5) / 10
end
