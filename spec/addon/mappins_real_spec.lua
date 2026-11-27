local addon = require("spec.helpers.addon")

local function exists(p)
  local f = io.open(p, "r")
  if f then f:close() end
  return f ~= nil
end

local FILES = {
  "Data/Meta.lua", "Data/Zones.lua", "Data/NPCs.lua", "Data/Dungeons.lua", "Data/Quests.lua",
  "Core/DB.lua", "Engine/Tuning.lua", "Engine/Difficulty.lua", "Engine/XP.lua",
  "Engine/Geo.lua", "Engine/Eligibility.lua", "Engine/Hubs.lua",
  "Engine/Travel.lua", "Engine/Candidates.lua", "Engine/ZoneScore.lua",
  "Engine/Sections.lua", "Engine/Dungeons.lua", "Engine/Route.lua",
  "Engine/RouteImprove.lua", "Engine/Engine.lua",
  "Core/Util.lua", "Core/Init.lua", "Core/Settings.lua", "Core/Advisor.lua", "UI/MapPins.lua",
}

local have = exists("LevelingAdvisor/Data/Quests.lua") and exists("LevelingAdvisor/Data/NPCs.lua")
local maybe = have and describe or pending

local MERGE = 0.5 -- MapPins merges places this close (map units)

local function player(faction, raceMask, classFile, classMask, level, mapID, x, y)
  return {
    faction = faction, raceMask = raceMask, classFile = classFile, classMask = classMask,
    level = level, xp = 0, xpMax = 400, mapID = mapID, x = x, y = y,
    completed = {}, log = {}, ignored = {}, recordedXP = {},
    settings = { elite = true, dungeons = true },
  }
end

maybe("MapPins with the real engine and data", function()
  local ns, db
  setup(function()
    ns = addon.load(FILES)
    db = ns.DB.new(ns.Data)
  end)

  local function pinsFor(state)
    local rec = ns.Engine.compute(db, state)
    local steps = ns.Engine.route(db, state, state.mapID, rec)
    return ns.MapPins.build(rec, db, state.mapID, steps, state), rec
  end

  -- tools/engine-smoke.lua Horde 16 ROGUE 8 1 1420 61 52 (level 1 Undead rogue in Brill)
  it("pins the displayed zone's pickups for a level 1 rogue in Brill", function()
    local state = player("Horde", 16, "ROGUE", 8, 1, 1420, 61, 52)
    local pins, rec = pinsFor(state)
    local pickups = 0
    for _, p in ipairs(pins) do
      assert.equals(1420, p.mapID)
      if p.kind == "pickup" then pickups = pickups + 1 end
    end
    -- Rude Awakening (363) is dropped by Engine.route (data: breadcrumbOf 364, while
    -- 364 requires 363), so only A Rogue's Deal's giver is a route pickup here.
    assert.is_true(#pins >= 1 and pickups >= 1, "pickup pins: " .. pickups)
    -- sections alone miss them (the reported bug)
    assert.equals(0, #ns.MapPins.build(rec, db, 1420))
  end)

  -- Every pin must be one the player can act on, at the right place: a "!" only for a quest
  -- Advisor.canPickUp accepts, a "?" only with a quest complete in the log, and each quest on
  -- its pin sits at its giver (pickup) or turn-in NPC.
  local CHARACTERS = {
    { "level 1 Undead rogue in Brill", player("Horde", 16, "ROGUE", 8, 1, 1420, 61, 52) },
    { "level 5 Human warrior in Goldshire", player("Alliance", 1, "WARRIOR", 1, 5, 1429, 42, 65) },
    { "level 12 Night Elf druid in Auberdine", player("Alliance", 8, "DRUID", 1024, 12, 1439, 37, 44) },
    { "level 15 Orc warrior at the Crossroads", player("Horde", 2, "WARRIOR", 1, 15, 1413, 52, 30) },
    { "level 7 Skyborne mage on Zephras Isle", player("Alliance", 2 ^ 32, "MAGE", 128, 7, 2521, 45, 45) },
  }

  local function near(place, pin)
    return type(place) == "table" and place.mapID == pin.mapID
      and math.abs(place.x - pin.x) <= MERGE and math.abs(place.y - pin.y) <= MERGE
  end

  local function checkPins(label, state, pins)
    local turnins = 0
    for _, pin in ipairs(pins) do
      assert.equals(state.mapID, pin.mapID, label)
      local readyHere = false
      for _, entry in ipairs(pin.quests) do
        local q = db:quest(entry.id)
        assert.is_truthy(q, label .. ": unknown quest " .. tostring(entry.id))
        local logEntry = state.log[entry.id]
        local ready = logEntry ~= nil and logEntry.complete == true
        if ready and near(q.turnIn, pin) then
          readyHere = true
        else
          assert.is_true(ns.Advisor.canPickUp(db, entry.id, state),
            label .. ": pin for " .. entry.id .. " but the player cannot pick it up")
          assert.is_true(near(q.giver, pin), label .. ": pickup " .. entry.id .. " is not at its giver")
        end
      end
      if pin.kind == "turnin" then
        turnins = turnins + 1
        assert.is_true(readyHere, label .. ": '?' pin without a complete quest turned in there")
      end
    end
    return turnins
  end

  for _, c in ipairs(CHARACTERS) do
    local label, base = c[1], c[2]
    it("every pin is actionable and in place: " .. label, function()
      local pins, rec = pinsFor(base)
      local pickups = 0
      for _, p in ipairs(pins) do if p.kind == "pickup" then pickups = pickups + 1 end end
      assert.is_true(pickups >= 1, label .. ": no pickup pins")
      assert.equals(0, checkPins(label, base, pins))

      -- Accept the first three quests the player can pick up and finish them: their
      -- turn-ins (where on this map) become "?" pins, and their pickups go away.
      local state = {}
      for k, v in pairs(base) do state[k] = v end
      state.log = {}
      local taken = 0
      for _, sec in ipairs(rec.sections) do
        for _, row in ipairs(sec.rows) do
          if taken < 3 and row.state == "available" and not row.soon and not state.log[row.questID] then
            state.log[row.questID] = { complete = true }
            taken = taken + 1
          end
        end
      end
      assert.is_true(taken >= 1, label .. ": nothing to accept")
      local after = pinsFor(state)
      local turnins = checkPins(label .. " (quests done)", state, after)
      local onMap = 0
      for id in pairs(state.log) do
        local t = db:quest(id).turnIn
        if t and t.mapID == state.mapID then onMap = onMap + 1 end
      end
      if onMap > 0 then assert.is_true(turnins >= 1, label .. ": no '?' pin for a finished quest") end
    end)
  end
end)
