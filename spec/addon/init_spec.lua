local addon = require("spec.helpers.addon")

local function readToc()
  local f = assert(io.open("LevelingAdvisor/LevelingAdvisor.toc", "r"))
  local text = f:read("*a")
  f:close()
  local files, meta = {}, {}
  for line in text:gmatch("[^\r\n]+") do
    local k, v = line:match("^##%s*([%w]+):%s*(.-)%s*$")
    if k then meta[k] = v elseif not line:match("^%s*#") and line:match("%S") then
      files[#files + 1] = line:match("^%s*(.-)%s*$")
    end
  end
  return files, meta
end

local function engineFiles()
  local f = assert(io.open("spec/helpers/engine.lua", "r"))
  local text = f:read("*a")
  f:close()
  local block = text:match("local FILES = (%b{})")
  local out = {}
  for p in block:gmatch('"([^"]+)"') do out[#out + 1] = p end
  return out
end

describe("TOC", function()
  it("lists the engine in loader order", function()
    local files = readToc()
    local got = {}
    for _, f in ipairs(files) do
      local p = f:gsub("\\", "/")
      if p:match("^Engine/") or p == "Core/DB.lua" then got[#got + 1] = p end
    end
    assert.same(engineFiles(), got)
  end)

  it("lists data files before the engine", function()
    local files = readToc()
    local pos = {}
    for i, f in ipairs(files) do pos[f] = i end
    assert.is_true(pos["Data\\Meta.lua"] < pos["Data\\Quests.lua"])
    assert.is_true(pos["Data\\Quests.lua"] < pos["Core\\DB.lua"])
  end)

  it("lists the Core files in load order", function()
    local got = {}
    for _, f in ipairs((readToc())) do
      local n = f:match("^Core\\(.+)%.lua$")
      if n and n ~= "DB" then got[#got + 1] = n end
    end
    assert.same({ "Util", "Init", "Settings", "Adapter", "Recorder", "Scheduler", "Export", "Advisor", "Slash" }, got)
  end)

  it("files exist", function()
    for _, f in ipairs((readToc())) do
      if not f:match("^Data\\") then
        local h = io.open("LevelingAdvisor/" .. f:gsub("\\", "/"), "r")
        assert.is_truthy(h, f)
        if h then h:close() end
      end
    end
  end)
end)

describe("Init", function()
  local FILES = { "Core/Util.lua", "Core/Init.lua" }

  it("version matches the TOC", function()
    local ns = addon.load(FILES)
    local _, meta = readToc()
    assert.equals(meta.Version, ns.VERSION)
    assert.equals("16001", meta.Interface)
  end)

  it("migrate fills an empty db", function()
    local ns = addon.load(FILES)
    local db, chardb = ns.Init.migrate({}, {})
    assert.same({
      version = 1, settings = {}, window = {},
      recorder = { xp = {}, levels = {}, details = {}, accepted = {} },
    }, db)
    assert.same({ ignored = {}, collapsed = {} }, chardb)
  end)

  it("migrate keeps existing values", function()
    local ns = addon.load(FILES)
    local db, chardb = ns.Init.migrate(
      { settings = { elite = false }, recorder = { xp = { [1] = { [10] = 5 } } } },
      { ignored = { [7] = true } })
    assert.is_false(db.settings.elite)
    assert.equals(5, db.recorder.xp[1][10])
    assert.is_true(chardb.ignored[7])
    assert.same({}, db.recorder.levels)
  end)

  it("ready runs once after both events", function()
    local ns, env = addon.load(FILES)
    local calls = 0
    ns.Init.onReady(function() calls = calls + 1 end)
    ns.Events.dispatch("ADDON_LOADED", "Other")
    assert.is_nil(ns.db)
    ns.Events.dispatch("ADDON_LOADED", "LevelingAdvisor")
    assert.equals(0, calls)
    ns.Events.dispatch("PLAYER_LOGIN")
    ns.Events.dispatch("PLAYER_LOGIN")
    assert.equals(1, calls)
    assert.equals(1, ns.db.version)
    assert.equals(ns.db, env.LevelingAdvisorDB)
    assert.equals(ns.chardb, env.LevelingAdvisorCharDB)
  end)

  it("late onReady reports errors", function()
    local ns, env = addon.load(FILES)
    ns.Events.dispatch("ADDON_LOADED", "LevelingAdvisor")
    ns.Events.dispatch("PLAYER_LOGIN")
    ns.Init.onReady(function() error("late boom") end)
    assert.equals(1, #env.errors)
    assert.matches("late boom", env.errors[1])
  end)

  it("PLAYER_LOGIN without ADDON_LOADED still sets up", function()
    local ns = addon.load(FILES)
    local calls = 0
    ns.Init.onReady(function() calls = calls + 1 end)
    ns.Events.dispatch("PLAYER_LOGIN")
    ns.Events.dispatch("PLAYER_LOGIN")
    assert.equals(1, calls)
    assert.equals(1, ns.db.version)
  end)

  it("ADDON_LOADED after login becomes ready without PLAYER_LOGIN", function()
    local ns = addon.load(FILES, { IsLoggedIn = function() return true end })
    local calls = 0
    ns.Init.onReady(function() calls = calls + 1 end)
    ns.Events.dispatch("ADDON_LOADED", "LevelingAdvisor")
    assert.equals(1, calls)
    assert.equals(1, ns.db.version)
  end)

  it("migrate replaces non-table fields", function()
    local ns = addon.load(FILES)
    local db = ns.Init.migrate({ recorder = 5, settings = "x" }, { ignored = true })
    assert.same({ xp = {}, levels = {}, details = {}, accepted = {} }, db.recorder)
    assert.same({}, db.settings)
  end)

  it("skips an event the client does not know instead of failing", function()
    local ns, env = addon.load(FILES, {
      CreateFrame = function()
        local f = { events = {} }
        function f:RegisterEvent(e)
          if e == "NOT_AN_EVENT" then error("unknown event") end
          self.events[e] = true
        end
        function f:SetScript() end
        return f
      end,
    })
    local seen = 0
    assert.has_no.errors(function()
      ns.Events.on("NOT_AN_EVENT", function() seen = seen + 1 end)
      ns.Events.on("FOO", function() end)
    end)
    ns.Events.dispatch("NOT_AN_EVENT")
    assert.equals(1, seen)
  end)

  it("keeps handlers isolated and routes the frame's OnEvent", function()
    local ns, env = addon.load(FILES)
    local seen = {}
    ns.Events.on("FOO", function() error("boom") end)
    ns.Events.on("FOO", function(...) seen[#seen + 1] = { ... } end)
    assert.is_true(env.frame.events.FOO)
    env.frame.onEvent(env.frame, "FOO", 1, 2)
    assert.same({ { 1, 2 } }, seen)
    assert.equals(1, #env.errors)
  end)
end)

describe("Util", function()
  local U = addon.load({ "Core/Util.lua" }).Util

  it("npcIDFromGUID", function()
    assert.equals(3649, U.npcIDFromGUID("Creature-0-3770-1-17-3649-0000ABCDEF"))
    assert.is_nil(U.npcIDFromGUID("Player-1-0ABC"))
    assert.is_nil(U.npcIDFromGUID(nil))
  end)

  it("call and method are fail-soft", function()
    assert.equals(3, U.call(function(a, b) return a + b end, 1, 2))
    assert.is_nil(U.call(nil))
    assert.is_nil(U.call(function() error("x") end))
    local obj = { get = function(self, n) return self.v + n end, v = 1 }
    assert.equals(3, U.method(obj, "get", 2))
    assert.is_nil(U.method(obj, "missing"))
    assert.is_nil(U.method(nil, "get"))
  end)

  it("round1 rounds to one decimal", function()
    assert.equals(1.3, U.round1(1.26))
    assert.equals(2, U.round1(2))
  end)

  it("say prefixes the message", function()
    local ns, _, out = addon.load({ "Core/Util.lua" })
    ns.Util.say("hi")
    assert.same({ "|cffffd100Leveling Advisor:|r hi" }, out)
  end)

  it("inCombat reads InCombatLockdown as a boolean, false without the API", function()
    local ns, env = addon.load({ "Core/Util.lua" })
    env.InCombatLockdown = function() return 1 end
    assert.is_true(ns.Util.inCombat())
    env.InCombatLockdown = function() return nil end
    assert.is_false(ns.Util.inCombat())
    env.InCombatLockdown = nil
    assert.is_false(ns.Util.inCombat())
  end)
end)
