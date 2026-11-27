-- tools/engine-smoke.lua as assertions: it runs on the shipped data (Data/*.lua), the way the
-- client loads the TOC, and prints zones, the dungeon and the sections. Here its output is
-- parsed and checked, so a broken data build or engine fails the suite (and the release build).
-- Skipped when the generated data or luajit is absent.
local DATA = { "Meta", "Zones", "NPCs", "Dungeons", "Quests" }
local SECTION_KEYS = { turnin = true, here = true, class = true, chains = true, next = true, later = true }

local function exists(p)
  local f = io.open(p, "r")
  if f then f:close() end
  return f ~= nil
end

local function haveData()
  for _, f in ipairs(DATA) do
    if not exists("LevelingAdvisor/Data/" .. f .. ".lua") then return false end
  end
  return true
end

local function haveLuajit()
  local status = os.execute("command -v luajit >/dev/null 2>&1")
  return status == 0 or status == true
end

-- Runs the tool; returns its output (stdout and stderr) and exit code.
local function smoke(args)
  local p = assert(io.popen("luajit tools/engine-smoke.lua " .. (args or "") .. " 2>&1; echo \"EXIT:$?\""))
  local out = p:read("*a")
  p:close()
  local code = tonumber(out:match("EXIT:(%d+)%s*$"))
  return (out:gsub("EXIT:%d+%s*$", "")), code
end

local function lines(s)
  local out = {}
  for l in s:gmatch("[^\n]+") do out[#out + 1] = l end
  return out
end

-- Parses the report into { files, data, state, zones = {...}, dungeon, sections = {...} }.
local function parse(out)
  local r = { zones = {}, sections = {} }
  local section
  for _, l in ipairs(lines(out)) do
    local nData, nEngine = l:match("^files %(from LevelingAdvisor%.toc%): (%d+) Data, (%d+) engine")
    if nData then r.files = { data = tonumber(nData), engine = tonumber(nEngine) } end
    local q, n, z, c, d = l:match("; (%d+) quests, (%d+) NPCs, (%d+) zones, (%d+) continents, (%d+) dungeons$")
    if q then
      r.data = { quests = tonumber(q), npcs = tonumber(n), zones = tonumber(z), continents = tonumber(c),
        dungeons = tonumber(d) }
    end
    local fac, race, class, lvl, map = l:match("^state: (%a+) race (%d+) class (%u+) level (%d+) at map (%d+)")
    if fac then
      r.state = { faction = fac, race = tonumber(race), class = class, level = tonumber(lvl), mapID = tonumber(map) }
    end
    r.zoneCount = r.zoneCount or tonumber(l:match("^zones %((%d+)%):$"))
    local zi, zmap, zq, here = l:match("^  (%d+)%. .- %[(%d+)%] levels .-, (%d+) quests, .- here (%a+): ")
    if zi then
      r.zones[#r.zones + 1] = { index = tonumber(zi), mapID = tonumber(zmap), quests = tonumber(zq), here = here == "true" }
    end
    if l == "dungeon: none" then r.dungeon = false end
    local dkey, dmin, dmax, dq = l:match("^dungeon: .- %[(%w+)%] levels (%d+)%-(%d+), (%d+) quests")
    if dkey then r.dungeon = { key = dkey, minLevel = tonumber(dmin), maxLevel = tonumber(dmax), quests = tonumber(dq) } end
    r.sectionCount = r.sectionCount or tonumber(l:match("^sections %((%d+)%):$"))
    local skey, srows = l:match("^  .- %[(%a+)%]: (%d+) rows$")
    if skey then
      section = { key = skey, rows = tonumber(srows), shown = {} }
      r.sections[#r.sections + 1] = section
    end
    local ri, rid = l:match("^    (%d+)%. (%d+) ")
    if ri and section then section.shown[#section.shown + 1] = tonumber(rid) end
  end
  return r
end

;((haveData() and haveLuajit()) and describe or pending)("tools/engine-smoke.lua on the shipped data", function()
  local ns
  setup(function()
    ns = {}
    for _, f in ipairs(DATA) do
      assert(loadfile("LevelingAdvisor/Data/" .. f .. ".lua"))("LevelingAdvisor", ns)
    end
  end)

  local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
  end

  local FACTION = { Alliance = 1, Horde = 2 }

  -- The checks every report must pass, for the player in r.state.
  local function checkReport(out, code)
    assert.equals(0, code, out)
    assert.is_nil(out:find("engine-smoke:", 1, true), out)
    local r = parse(out)
    -- the TOC lists the five Data files and Core/DB.lua plus the Engine files
    assert.same({ data = 5, engine = 16 }, r.files)
    -- the report counts what the Data files hold
    local D = ns.Data
    assert.same({ quests = count(D.quests), npcs = count(D.npcs), zones = count(D.zones),
      continents = count(D.continents), dungeons = count(D.dungeons) }, r.data)
    assert.is_true(r.data.quests > 1000 and r.data.dungeons > 10, out)
    -- zones: 1 to 3, numbered in order, distinct, live and usable by the player's faction
    assert.is_true(r.zoneCount >= 1 and r.zoneCount <= 3, out)
    assert.equals(r.zoneCount, #r.zones, out)
    local seen = {}
    for i, z in ipairs(r.zones) do
      assert.equals(i, z.index)
      assert.is_nil(seen[z.mapID], out); seen[z.mapID] = true
      local zone = D.zones[z.mapID]
      assert.is_truthy(zone and zone.live, out)
      assert.is_nil(zone.kind, out)
      assert.is_true(zone.faction ~= 1 and zone.faction ~= 2 or zone.faction == FACTION[r.state.faction], out)
      assert.is_true(z.quests >= 1, out)
      assert.equals(z.mapID == r.state.mapID, z.here, out)
    end
    -- the dungeon line: none, or one in its level window
    assert.is_not_nil(r.dungeon, out)
    if r.dungeon then
      local d = D.dungeons[r.dungeon.key]
      assert.is_truthy(d, out)
      assert.same({ d.minLevel, d.maxLevel }, { r.dungeon.minLevel, r.dungeon.maxLevel })
      assert.is_true(r.state.level >= d.minLevel - 2 and r.state.level <= d.maxLevel, out)
      assert.is_true(r.dungeon.quests >= 2, out)
    end
    -- sections: known keys, each listed once, its first rows printed, every row a real quest
    assert.is_true(r.sectionCount >= 1, out)
    assert.equals(r.sectionCount, #r.sections, out)
    local keys = {}
    for _, s in ipairs(r.sections) do
      assert.is_true(SECTION_KEYS[s.key] == true, out)
      assert.is_nil(keys[s.key], out); keys[s.key] = true
      assert.is_true(s.rows >= 1, out)
      assert.equals(math.min(3, s.rows), #s.shown, out)
      for _, id in ipairs(s.shown) do assert.is_truthy(D.quests[id], out) end
    end
    return r
  end

  it("reports the default player (level 18 Night Elf druid in Darkshore)", function()
    local out, code = smoke()
    local r = checkReport(out, code)
    assert.same({ faction = "Alliance", race = 8, class = "DRUID", level = 18, mapID = 1439 }, r.state)
  end)

  it("reports a player given on the command line (level 1 Undead rogue in Brill)", function()
    local out, code = smoke("Horde 16 ROGUE 8 1 1420 61 52")
    local r = checkReport(out, code)
    assert.same({ faction = "Horde", race = 16, class = "ROGUE", level = 1, mapID = 1420 }, r.state)
    assert.is_false(r.dungeon)
  end)

  it("reports a level 40 Skyborne in Stranglethorn", function()
    local out, code = smoke("Alliance 4294967296 MAGE 128 40 1434 40 40")
    local r = checkReport(out, code)
    assert.equals(40, r.state.level)
  end)

  it("rejects bad arguments with usage and exit code 2", function()
    for _, args in ipairs({
      "Horde 16 ROGUE 8 1 1420 61",          -- seven arguments
      "Pirates 16 ROGUE 8 1 1420 61 52",     -- unknown faction
      "Horde 16 ROGUE 8 61 1420 61 52",      -- level above 60
      "Horde 16 rogue 8 1 1420 61 52",       -- class not upper case
      "Horde 16 ROGUE 8 1 1420 161 52",      -- x outside 0-100
    }) do
      local out, code = smoke(args)
      assert.equals(2, code, args .. "\n" .. out)
      assert.is_truthy(out:find("usage: luajit tools/engine-smoke.lua", 1, true), out)
    end
  end)
end)
