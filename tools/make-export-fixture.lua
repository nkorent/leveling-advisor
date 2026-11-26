-- Prints the LA1J export string for a fixed sample store (fixture for the
-- pipeline importer). Usage: luajit tools/make-export-fixture.lua
-- Standalone: does not need busted.
local ns = {
  VERSION = "0.1.0",
  Settings = { get = function() return true end },
}
-- The real Util, Recorder and Export, so the store has the shape the addon writes.
for _, f in ipairs({ "Util", "Recorder", "Export" }) do
  local chunk = assert(loadfile("LevelingAdvisor/Core/" .. f .. ".lua"))
  chunk("LevelingAdvisor", ns)
end

local api = {
  questID = function() return 4763 end,
  npcGUID = function() return "Creature-0-0-0-0-3649-0000000000" end,
  mapID = function() return 1439 end,
  position = function() return 0.374, 0.401 end,
  rewardXP = function() return 1700 end,
  numChoices = function() return 3 end,
  choiceLink = function(i) return "|cff0070dd|Hitem:" .. ({ 15204, 15202, 15203 })[i] .. "::::|h[Item]|h|r" end,
  numRewards = function() return 0 end,
  rewardLink = function() return nil end,
  level = function() return 18 end,
  now = function() return 1764000000 end,
  gossipAvailable = function() return { { questID = 4763, questLevel = 18 } } end,
  greetingAvailable = function() return {} end,
}

local store = { xp = {}, levels = {}, details = {}, accepted = {} }
local rec = ns.Recorder.new(store, api)
rec:onGossip()
rec:onDetail()
rec:onAccepted(4763)
rec:onComplete()
rec:onTurnedIn(4763, 1700)
local meta = { gameData = "1.60.1", built = "2026-11-25" }

local E = ns.Export
io.write(E.encode(E.payload(store, meta)), "\n")
