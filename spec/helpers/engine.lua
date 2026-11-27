-- Engine spec helper.
--   load()   -> fresh ns with every existing engine file loaded in TOC order
--               (files not written yet are skipped).
--   data()   -> Data table from spec/fixtures/data_small.lua. The fixture is
--               run like a generated addon file, as chunk("LevelingAdvisor", ns)
--               into a fresh ns (so it starts with `local _, ns = ...` and sets
--               ns.Data); data() returns ns.Data. Loaded lazily on call.
--   states   -> S18/S20/H20 from spec.helpers.states, loaded lazily on access.
-- Record shapes: steps have `actions` = list of {questID, kind}; sections have
-- `key` and `rows` (each with `questID`); dungeons have `pickups` (questID).
local ADDON = "LevelingAdvisor"
local DIR = ADDON

local FILES = {
  "Core/DB.lua", "Engine/Tuning.lua", "Engine/Difficulty.lua", "Engine/XP.lua",
  "Engine/Geo.lua", "Engine/Eligibility.lua", "Engine/Unlock.lua", "Engine/Hubs.lua",
  "Engine/Travel.lua", "Engine/Candidates.lua", "Engine/ZoneScore.lua",
  "Engine/Sections.lua", "Engine/Dungeons.lua", "Engine/Route.lua",
  "Engine/RouteImprove.lua", "Engine/Engine.lua",
}

local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() end
  return f ~= nil
end

local M = {}

function M.load()
  local ns = {}
  for _, f in ipairs(FILES) do
    local path = DIR .. "/" .. f
    if exists(path) then assert(loadfile(path))(ADDON, ns) end
  end
  return ns
end

function M.data()
  local ns = {}
  assert(loadfile("spec/fixtures/data_small.lua"))(ADDON, ns)
  return ns.Data
end

M.states = setmetatable({}, { __index = function(t, k)
  local s = require("spec.helpers.states")
  for key, v in pairs(s) do rawset(t, key, v) end
  return rawget(t, k)
end })

function M.with(base, overrides)
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  for k, v in pairs(overrides or {}) do out[k] = v end
  return out
end

function M.ids(section)
  local out = {}
  for i, row in ipairs(section.rows) do out[i] = row.questID end
  return out
end

function M.keys(sections)
  local out = {}
  for i, s in ipairs(sections) do out[i] = s.key end
  return out
end

function M.find(sections, key)
  for _, s in ipairs(sections) do
    if s.key == key then return s end
  end
  return nil
end

function M.stepOf(steps, questID, kind)
  for i, step in ipairs(steps) do
    for _, a in ipairs(step.actions) do
      if a[1] == questID and a[2] == kind then return i end
    end
  end
  return nil
end

function M.candidateFor(candidates, questID)
  for _, c in ipairs(candidates) do
    if c.quest.id == questID then return c end
  end
  return nil
end

function M.pickupFor(dungeon, questID)
  for _, p in ipairs(dungeon.pickups) do
    if p.questID == questID then return p end
  end
  return nil
end

-- Every row's questID across all sections, in display order.
function M.rowIDs(sections)
  local out = {}
  for _, section in ipairs(sections) do
    for _, row in ipairs(section.rows) do out[#out + 1] = row.questID end
  end
  return out
end

function M.pickupIDs(dungeon)
  local out = {}
  for i, p in ipairs(dungeon.pickups) do out[i] = p.questID end
  return out
end

return M
