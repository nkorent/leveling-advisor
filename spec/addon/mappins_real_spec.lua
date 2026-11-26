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
  "Core/Util.lua", "Core/Init.lua", "Core/Settings.lua", "UI/MapPins.lua",
}

local have = exists("LevelingAdvisor/Data/Quests.lua") and exists("LevelingAdvisor/Data/NPCs.lua")
local maybe = have and describe or pending

maybe("MapPins with the real engine and data", function()
  -- tools/engine-smoke.lua Horde 16 ROGUE 8 1 1420 61 52 (level 1 Undead rogue in Brill)
  it("pins the displayed zone's pickups for a level 1 rogue in Brill", function()
    local ns = addon.load(FILES)
    local db = ns.DB.new(ns.Data)
    local state = {
      faction = "Horde", raceMask = 16, classFile = "ROGUE", classMask = 8,
      level = 1, xp = 0, xpMax = 400, mapID = 1420, x = 61, y = 52,
      completed = {}, log = {}, ignored = {}, recordedXP = {},
      settings = { elite = true, dungeons = true },
    }
    local rec = ns.Engine.compute(db, state)
    local steps = ns.Engine.route(db, state, 1420, rec)
    local pins = ns.MapPins.build(rec, db, 1420, steps, state)
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
end)
