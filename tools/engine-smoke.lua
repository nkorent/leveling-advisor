-- Engine smoke test on the generated data (run with luajit from the repo root):
--   luajit tools/engine-smoke.lua [faction raceMask classFile classMask level mapID x y]
-- With no arguments the player is the Night Elf Druid below; with arguments (all eight) it is
-- that player, e.g.  luajit tools/engine-smoke.lua Horde 16 ROGUE 8 1 1420 30.8 66.2
-- Loads the Data\, Core\DB.lua and Engine\ files listed in LevelingAdvisor.toc, in TOC
-- order, the way the client does, chunk("LevelingAdvisor", ns), builds
-- ns.DB.new(ns.Data), runs ns.Engine.compute for one fixed player and prints the zones,
-- each section's title and row count, and its first 3 rows.
-- Exits non-zero on any Lua error.
local ADDON = "LevelingAdvisor"
local ROOT = ((arg and arg[0]) or ""):match("^(.*)/tools/[^/]*$") or "."
local DIR = ROOT .. "/" .. ADDON

-- Data, then Core/DB.lua and the Engine files, as the TOC lists them (so the list cannot drift).
local function tocFiles()
  local f, err = io.open(DIR .. "/" .. ADDON .. ".toc", "r")
  if not f then error(err, 0) end
  local data, engine = {}, {}
  for line in f:lines() do
    local path = line:gsub("\r$", ""):match("^%s*(.-)%s*$"):gsub("\\", "/")
    if path ~= "" and not path:match("^#") then
      if path:match("^Data/") then
        data[#data + 1] = path
      elseif path == "Core/DB.lua" or path:match("^Engine/") then
        engine[#engine + 1] = path
      end
    end
  end
  f:close()
  if #data == 0 or engine[1] ~= "Core/DB.lua" or #engine < 2 then
    error("TOC does not list Data files, then Core\\DB.lua before the Engine files", 0)
  end
  return data, engine
end

local USAGE = "usage: luajit tools/engine-smoke.lua [faction raceMask classFile classMask level mapID x y]\n"
  .. "  faction Alliance|Horde; raceMask, classMask, level, mapID whole numbers (level 1-60); x, y 0-100"

local function usageError(msg)
  io.stderr:write("engine-smoke: " .. msg .. "\n" .. USAGE .. "\n")
  os.exit(2)
end

-- Contract B: Alliance Night Elf Druid, level 18, Darkshore (1439) at 45, 50, nothing done.
local STATE = {
  faction = "Alliance", raceMask = 8, classMask = 1024, classFile = "DRUID",
  level = 18, xp = 0, xpMax = 7300,
  mapID = 1439, x = 45, y = 50,
  greyAtOrBelow = nil,
  completed = {}, log = {}, ignored = {}, recordedXP = {},
  settings = { elite = true, dungeons = true },
}

-- Replaces the default player with the one named on the command line (all eight, or none).
local function applyArgs(args)
  if #args == 0 then return end
  if #args ~= 8 then usageError("expected 8 arguments, got " .. #args) end
  local faction, classFile = args[1], args[3]
  if faction ~= "Alliance" and faction ~= "Horde" then usageError("faction must be Alliance or Horde") end
  if not classFile:match("^%u+$") then usageError("classFile must be upper case, e.g. ROGUE") end
  local nums = {}
  local fields = { { "raceMask", 2 }, { "classMask", 4 }, { "level", 5 }, { "mapID", 6 }, { "x", 7 }, { "y", 8 } }
  for _, f in ipairs(fields) do
    local name = f[1]
    local n = tonumber(args[f[2]])
    if not n then usageError(name .. " is not a number") end
    nums[name] = n
  end
  for _, name in ipairs({ "raceMask", "classMask", "level", "mapID" }) do
    if nums[name] ~= math.floor(nums[name]) then usageError(name .. " must be a whole number") end
  end
  if nums.raceMask < 1 or nums.classMask < 1 then usageError("masks must be positive") end
  if nums.level < 1 or nums.level > 60 then usageError("level must be 1-60") end
  if nums.mapID < 1 then usageError("mapID must be positive") end
  if nums.x < 0 or nums.x > 100 or nums.y < 0 or nums.y > 100 then usageError("x and y must be 0-100") end
  STATE.faction, STATE.classFile = faction, classFile
  STATE.raceMask, STATE.classMask, STATE.level = nums.raceMask, nums.classMask, nums.level
  STATE.mapID, STATE.x, STATE.y = nums.mapID, nums.x, nums.y
end

local function count(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

local function str(v)
  if v == nil then return "-" end
  if type(v) == "number" and v ~= math.floor(v) then return string.format("%.1f", v) end
  return tostring(v)
end

local function main()
  local ns = {}
  local started = os.clock()
  local DATA, ENGINE = tocFiles()
  print(string.format("files (from %s.toc): %d Data, %d engine (%s .. %s)", ADDON, #DATA, #ENGINE, ENGINE[1],
    ENGINE[#ENGINE]))
  for _, list in ipairs({ DATA, ENGINE }) do
    for _, f in ipairs(list) do
      local chunk, err = loadfile(DIR .. "/" .. f)
      if not chunk then error(err, 0) end
      chunk(ADDON, ns)
    end
  end
  local loaded = os.clock()
  local data = ns.Data or {}
  local meta = data.meta or {}
  print(string.format("data: built %s, game data %s%s; %d quests, %d NPCs, %d zones, %d continents, %d dungeons",
    str(meta.built), str(meta.gameData), meta.provisional and " (PROVISIONAL)" or "",
    count(data.quests), count(data.npcs), count(data.zones), count(data.continents), count(data.dungeons)))

  local db = ns.DB.new(data)
  local built = os.clock()
  local rec = ns.Engine.compute(db, STATE)
  local done = os.clock()
  print(string.format("state: %s race %d class %s level %d at map %d (%s, %s)", STATE.faction, STATE.raceMask,
    STATE.classFile, STATE.level, STATE.mapID, str(STATE.x), str(STATE.y)))
  print(string.format("time: load %.2fs, DB.new %.2fs, compute %.2fs", loaded - started, built - loaded, done - built))

  print(string.format("zones (%d):", #(rec.zones or {})))
  for i, z in ipairs(rec.zones or {}) do
    print(string.format("  %d. %s [%s] levels %s-%s, %s quests, %s xp, chains %s, here %s: %s", i, str(z.name),
      str(z.mapID), str(z.minLevel), str(z.maxLevel), str(z.questCount), str(z.xp), str(z.chains),
      str(z.isHere), str(z.reason)))
  end

  local d = rec.dungeon
  if d then
    print(string.format("dungeon: %s [%s] levels %s-%s, %s quests, %s xp: %s", str(d.name), str(d.key),
      str(d.minLevel), str(d.maxLevel), str(d.questCount), str(d.xp), str(d.reason)))
  else
    print("dungeon: none")
  end

  print(string.format("sections (%d):", #(rec.sections or {})))
  for _, s in ipairs(rec.sections or {}) do
    print(string.format("  %s [%s]: %d rows", str(s.title), str(s.key), #(s.rows or {})))
    for i = 1, math.min(3, #(s.rows or {})) do
      local r = s.rows[i]
      local g = r.giver or {}
      print(string.format("    %d. %s %s (lvl %s, %s, %s) xp %s, giver %s at %s %s,%s, %s yd", i, str(r.questID),
        str(r.name), str(r.level), str(r.color), str(r.state), str(r.xp), str(g.id), str(g.mapID), str(g.x),
        str(g.y), r.yards and string.format("%.0f", r.yards) or "-"))
    end
  end
end

applyArgs(arg or {})
local ok, err = xpcall(main, debug.traceback)
if not ok then
  io.stderr:write("engine-smoke: " .. tostring(err) .. "\n")
  os.exit(1)
end
