local addonName, ns = ...

ns.VERSION = "0.2.0"

---------------------------------------------------------------------------
-- Events: one shared frame, several pcall-protected handlers per event.
---------------------------------------------------------------------------
local Events = {}
ns.Events = Events

local handlers = {}
local frame = CreateFrame("Frame")

function Events.dispatch(event, ...)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok then geterrorhandler()(err) end
  end
end

function Events.on(event, fn)
  local list = handlers[event]
  if not list then
    list = {}
    handlers[event] = list
    -- An unknown event is skipped, not fatal.
    pcall(function() frame:RegisterEvent(event) end)
  end
  list[#list + 1] = fn
end

frame:SetScript("OnEvent", function(_, event, ...) Events.dispatch(event, ...) end)

---------------------------------------------------------------------------
-- Saved variables.
---------------------------------------------------------------------------
local Init = {}
ns.Init = Init

local function fill(t, key, default)
  if t[key] == nil then t[key] = default end
end

-- Like fill, but also replaces a non-table value with a fresh table.
local function fillTable(t, key)
  if type(t[key]) ~= "table" then t[key] = {} end
  return t[key]
end

-- Pure: fills missing tables, never overwrites existing values.
function Init.migrate(db, chardb)
  if type(db) ~= "table" then db = {} end
  if type(chardb) ~= "table" then chardb = {} end
  fill(db, "version", 1)
  fillTable(db, "settings")
  fillTable(db, "window")
  local rec = fillTable(db, "recorder")
  fillTable(rec, "xp")
  fillTable(rec, "levels")
  fillTable(rec, "details")
  fillTable(rec, "accepted")
  fillTable(chardb, "ignored")
  fillTable(chardb, "collapsed")
  return db, chardb
end

local readyFns, ready = {}, false

local function runSafe(fn)
  local ok, err = pcall(fn)
  if not ok then geterrorhandler()(err) end
end

-- Runs fn once at PLAYER_LOGIN, after ns.db / ns.chardb are set up.
-- Registered after login has already happened: runs immediately.
function Init.onReady(fn)
  if ready then
    runSafe(fn)
  else
    readyFns[#readyFns + 1] = fn
  end
end

local function setup()
  if ns.db then return end
  LevelingAdvisorDB, LevelingAdvisorCharDB =
    Init.migrate(LevelingAdvisorDB, LevelingAdvisorCharDB)
  ns.db, ns.chardb = LevelingAdvisorDB, LevelingAdvisorCharDB
end

local function becomeReady()
  setup()
  if ready then return end
  ready = true
  local fns = readyFns
  readyFns = {}
  for _, fn in ipairs(fns) do runSafe(fn) end
end

Events.on("ADDON_LOADED", function(name)
  if name ~= addonName then return end
  setup()
  if type(IsLoggedIn) == "function" and IsLoggedIn() then becomeReady() end
end)

Events.on("PLAYER_LOGIN", becomeReady)
