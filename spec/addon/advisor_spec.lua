local addon = require("spec.helpers.addon")
local H = require("spec.helpers.engine")

local FILES = {
  "Core/DB.lua", "Engine/Tuning.lua", "Engine/Difficulty.lua", "Engine/XP.lua",
  "Engine/Geo.lua", "Engine/Eligibility.lua", "Engine/Hubs.lua",
  "Engine/Travel.lua", "Engine/Candidates.lua", "Engine/ZoneScore.lua",
  "Engine/Sections.lua", "Engine/Dungeons.lua", "Engine/Route.lua",
  "Engine/RouteImprove.lua", "Engine/Engine.lua",
  "Core/Util.lua", "Core/Init.lua", "Core/Settings.lua", "Core/Adapter.lua",
  "Core/Recorder.lua", "Core/Scheduler.lua", "Core/Advisor.lua", "Core/Slash.lua",
}

local PREFIX = "|cffffd100Leveling Advisor:|r "

local function fakeApi()
  return {
    faction = function() return "Alliance" end,
    race = function() return 4 end,
    class = function() return "DRUID", 11 end,
    level = function() return 18 end,
    xp = function() return 4500 end,
    xpMax = function() return 7300 end,
    mapID = function() return 1439 end,
    position = function() return 0.38, 0.41 end,
    completed = function() return { 4762, 965 } end,
    logEntries = function() return { [966] = { complete = false }, [4730] = { complete = true } } end,
    greyAtOrBelow = function() return nil end,
  }
end

-- opts: data (default fixture), extra (env globals)
local function setup(opts)
  opts = opts or {}
  local ns, env, out = addon.load(FILES, opts.extra)
  ns.Data = opts.data or H.data()
  ns.db = { settings = {}, recorder = { xp = {}, levels = {}, details = {}, accepted = {} } }
  ns.chardb = { ignored = {}, collapsed = {} }
  ns.Advisor.init({ api = fakeApi() })
  return ns, env, out
end

local function run(env, msg) env.SlashCmdList.LEVELINGADVISOR(msg) end

describe("Advisor", function()
  it("wires quest events to the recorder alongside the scheduler", function()
    local ns = setup()
    ns.Events.dispatch("QUEST_ACCEPTED", 7)
    ns.Events.dispatch("QUEST_TURNED_IN", 7, 0)
    assert.equals(7, ns.db.recorder.accepted[1][1])
    assert.is_table(ns.Advisor.recorder)
  end)

  it("registers /advisor", function()
    local _, env = setup()
    assert.equals("/advisor", env.SLASH_LEVELINGADVISOR1)
  end)

  it("says so with empty data and raises no error", function()
    local _, env, out = setup({ data = {} })
    run(env, "")
    assert.same({ PREFIX .. "No quest data loaded. Run the data pipeline and /reload." }, out)
    assert.same({}, env.errors)
  end)

  it("does not crash when ns.Data is nil", function()
    local ns, env, out = addon.load(FILES)
    ns.db, ns.chardb = { settings = {} }, { ignored = {} }
    ns.Advisor.init()
    assert.is_nil(ns.Advisor.db)
    run(env, "")
    assert.equals(PREFIX .. "No quest data loaded. Run the data pipeline and /reload.", out[1])
  end)

  describe("data load error", function()
    local function broken()
      local ns, env, out = addon.load(FILES)
      ns.Data = H.data()
      ns.db = { settings = {}, recorder = { xp = {}, levels = {}, details = {}, accepted = {} } }
      ns.chardb = { ignored = {}, collapsed = {} }
      ns.DB.new = function() error("boom", 0) end
      ns.Advisor.init({ api = fakeApi() })
      return ns, env, out
    end

    it("reports the error instead of the no-data text", function()
      local ns, env, out = broken()
      assert.is_nil(ns.Advisor.db)
      run(env, "")
      assert.same({ PREFIX .. "Quest data failed to load: boom" }, out)
      assert.same({}, env.errors)
    end)

    it("still wires the scheduler and the recorder", function()
      local ns = broken()
      assert.is_table(ns.Advisor.scheduler)
      ns.Events.dispatch("QUEST_ACCEPTED", 7)
      assert.equals(7, ns.db.recorder.accepted[1][1])
    end)

    it("registers the settings panel even when init fails", function()
      local ns, env = addon.load(FILES)
      local registered = 0
      ns.Settings.registerPanel = function() registered = registered + 1 end
      ns.Advisor.init = function() error("init boom", 0) end
      ns.Events.dispatch("PLAYER_LOGIN")
      assert.equals(1, registered)
      assert.equals(1, #env.errors)
    end)
  end)

  it("says so when there is nothing to recommend", function()
    local ns, env, out = setup()
    ns.Advisor.summaryLines = function() return {} end
    run(env, "")
    assert.same({ PREFIX .. "No recommendations for this character right now." }, out)
  end)

  it("wires init and the panel through Init.onReady", function()
    local ns, env = addon.load(FILES)
    ns.Events.dispatch("PLAYER_LOGIN")
    assert.is_table(ns.Advisor.scheduler)
    assert.same({}, env.errors)
  end)

  describe("S18 summary", function()
    local ns, env, out
    before_each(function() ns, env, out = setup(); run(env, "") end)

    it("prints exactly the expected S18 summary", function()
      assert.same({
        "Zones:",
        "  1. Darkshore (10–20) — 6 quests, ~7030 XP — You are here — finish before you leave",
        "  2. Ashenvale (18–30) — 3 quests, ~4000 XP — Next zone — walk south",
        "  3. Loch Modan (10–20) — 1 quest, ~900 XP — Catch up — 1 quest you skipped at your level",
        "Ready to Turn In (1):",
        "  [17] Beached Sea Creature — 134 yd (ready)",
        "Right Here (2):",
        "  [18] The Blackwood Corrupted — 51 yd",
        "  [18] Either Way — 126 yd",
        "Class Quests (1):",
        "  [16] Aquatic Form — 219 yd",
        "For Your Next Zone (3):",
        "  [19] Bathran's Hair — 5366 yd",
        "  [20] The Ancient Statuette — 5344 yd",
        "  [20] Riverglades Survey — 5395 yd",
        "Later — too high for now (1):", -- level fit: 991 is orange at 18
        "  [21] Raene's Cleansing — 5366 yd",
      }, out)
    end)

    it("has no dungeon line at level 18", function()
      for _, l in ipairs(out) do assert.is_nil(l:match("^Dungeon:")) end
    end)

    it("computes once and stores last", function()
      assert.is_table(ns.Advisor.last.rec)
      assert.is_table(ns.Advisor.last.state)
    end)
  end)

  describe("summaryLines formatting", function()
    it("handles yards, soon, ready and dungeon", function()
      local ns = setup()
      local rec = {
        zones = {},
        dungeon = { name = "Blackfathom Deeps", minLevel = 22, maxLevel = 28,
          reason = "Best at 22 — three of its quests start on your way" },
        sections = { { key = "x", title = "Right Here", rows = {
          { questID = 1, name = "A", level = 18, state = "available", yards = nil },
          { questID = 2, name = "B", level = 19, state = "progress", soon = true, yards = 51.4 },
          { questID = 3, name = "C", level = 20, state = "complete", yards = 3.6 },
        } } },
      }
      assert.same({
        "Dungeon: Blackfathom Deeps (22–28) — Best at 22 — three of its quests start on your way",
        "Right Here (3):",
        "  [18] A",
        "  [19] B — 51 yd (soon)",
        "  [20] C — 4 yd (ready)",
      }, ns.Advisor.summaryLines(rec, nil))
    end)
  end)

  describe("map shown", function()
    it("lets the scheduler compute while only the world map is shown", function()
      local ns, env = setup()
      assert.is_false(ns.Advisor.isShown())
      ns.Advisor.setMapShown(true)
      env.flush()
      assert.equals(1, ns.Advisor.scheduler.runs)
      assert.is_table(ns.Advisor.last)
      -- a state change while the map is open is recomputed
      ns.Events.dispatch("QUEST_LOG_UPDATE")
      env.flush()
      assert.equals(2, ns.Advisor.scheduler.runs)
    end)

    it("stops allowing computes once the map and window are hidden", function()
      local ns, env = setup()
      ns.Advisor.setMapShown(true)
      env.flush()
      ns.Advisor.setMapShown(false)
      ns.Events.dispatch("QUEST_LOG_UPDATE")
      env.flush()
      assert.equals(1, ns.Advisor.scheduler.runs)
    end)

    it("keeps computing while the window is shown even if the map hides", function()
      local ns, env = setup()
      ns.Advisor.setWindowShown(true)
      ns.Advisor.setMapShown(true)
      ns.Advisor.setMapShown(false)
      env.flush()
      ns.Events.dispatch("QUEST_LOG_UPDATE")
      env.flush()
      assert.equals(2, ns.Advisor.scheduler.runs)
    end)
  end)

  describe("ignore", function()
    it("ignore 4763 sets the entry and requests a recompute", function()
      local ns, env, out = setup()
      ns.Advisor.setWindowShown(true)
      env.flush()
      assert.equals(1, ns.Advisor.scheduler.runs)
      run(env, "ignore 4763")
      assert.is_true(ns.chardb.ignored[4763])
      assert.equals(PREFIX .. "Ignoring quest 4763.", out[#out])
      env.flush()
      assert.equals(2, ns.Advisor.scheduler.runs)
    end)

    it("rejects an invalid id with usage", function()
      local ns, env, out = setup()
      run(env, "ignore abc")
      run(env, "unignore")
      assert.same({}, ns.chardb.ignored)
      assert.equals(PREFIX .. "Usage: /advisor ignore <questID>", out[1])
      assert.equals(PREFIX .. "Usage: /advisor unignore <questID>", out[2])
    end)

    it("unignore clears one entry and unignore all clears every entry", function()
      local ns, env, out = setup()
      ns.chardb.ignored = { [1] = true, [2] = true, [3] = true }
      run(env, "unignore 2")
      assert.same({ [1] = true, [3] = true }, ns.chardb.ignored)
      assert.equals(PREFIX .. "No longer ignoring quest 2.", out[#out])
      local n = 0
      local orig = ns.Advisor.scheduler.request
      ns.Advisor.scheduler.request = function(...) n = n + 1; return orig(...) end
      run(env, "unignore all")
      assert.equals(1, n)
      assert.same({}, ns.chardb.ignored)
      assert.equals(PREFIX .. "Cleared all ignored quests.", out[#out])
    end)
  end)

  describe("event wiring", function()
    it("maps each event to its scheduler reason", function()
      local ns = setup()
      local sched, reasons, combatEnds = ns.Advisor.scheduler, {}, 0
      sched.request = function(_, reason) reasons[#reasons + 1] = reason end
      sched.onCombatEnd = function() combatEnds = combatEnds + 1 end
      local expected = {
        QUEST_LOG_UPDATE = "quest", QUEST_ACCEPTED = "quest", QUEST_TURNED_IN = "quest",
        QUEST_REMOVED = "quest", PLAYER_LEVEL_UP = "level", ZONE_CHANGED_NEW_AREA = "zone",
      }
      for event, reason in pairs(expected) do
        reasons = {}
        ns.Events.dispatch(event)
        assert.same({ reason }, reasons, event)
      end
      reasons = {}
      ns.Settings.set("elite", false)
      assert.same({ "settings" }, reasons)
      ns.Events.dispatch("PLAYER_REGEN_ENABLED")
      assert.equals(1, combatEnds)
    end)
  end)

  describe("combat", function()
    it("prints the no-data message in combat", function()
      local _, env, out = setup({ data = {}, extra = { InCombatLockdown = function() return true end } })
      run(env, "")
      assert.same({ PREFIX .. "No quest data loaded. Run the data pipeline and /reload." }, out)
    end)

    it("prints the combat message and does not compute", function()
      local ns, env, out = setup({ extra = { InCombatLockdown = function() return true end } })
      run(env, "")
      assert.same({ PREFIX .. "Not in combat: try again after the fight." }, out)
      assert.is_nil(ns.Advisor.last)
    end)

    it("route returns nil in combat", function()
      local combat = false
      local ns = setup({ extra = { InCombatLockdown = function() return combat end } })
      ns.Advisor.compute()
      assert.is_table(ns.Advisor.route(1439))
      combat = true
      assert.is_nil(ns.Advisor.route(1439))
    end)

    it("route returns nil before any compute", function()
      local ns = setup()
      assert.is_nil(ns.Advisor.route(1439))
    end)

    it("route passes a clock when debugprofilestop exists", function()
      local seen
      local ns = setup({ extra = { debugprofilestop = function() return 1 end } })
      ns.Advisor.compute()
      local real = ns.Engine.route
      ns.Engine.route = function(_, _, _, _, clock) seen = clock; return {} end
      ns.Advisor.route(1439)
      ns.Engine.route = real
      assert.equals("function", type(seen))
    end)

    it("route passes no clock without debugprofilestop", function()
      local seen = "unset"
      local ns = setup()
      ns.Advisor.compute()
      ns.Engine.route = function(_, _, _, _, clock) seen = clock; return {} end
      ns.Advisor.route(1439)
      assert.is_nil(seen)
    end)
  end)

  describe("other subcommands", function()
    it("export says unavailable without ns.Export", function()
      local _, env, out = setup()
      run(env, "export")
      assert.equals(PREFIX .. "Export is not available yet.", out[1])
    end)

    it("export calls ns.Export.run when present", function()
      local ns, env = setup()
      local called
      ns.Export = { run = function() called = true end }
      run(env, "export")
      assert.is_true(called)
    end)

    it("about prints the about line", function()
      local ns, env, out = setup()
      run(env, "about")
      assert.equals(PREFIX .. ns.Settings.aboutLine(), out[1])
    end)

    it("debug prints counters and help lists commands", function()
      local _, env, out = setup()
      run(env, "")
      local n = #out
      run(env, "debug")
      assert.is_truthy(out[n + 1]:match("level=18, mapID=1439, log=2"))
      assert.is_truthy(out[n + 1]:match("log=2, grey=%S+$"))
      run(env, "help")
      assert.is_truthy(#out > n + 2)
    end)

    it("pins prints the pin count on the current map and help lists it", function()
      local ns, env, out = setup()
      ns.MapPins = { describe = function() return "Pins on map X (1): 3" end }
      run(env, "pins")
      assert.equals(PREFIX .. "Pins on map X (1): 3", out[#out])
      ns.MapPins = nil
      run(env, "pins")
      assert.equals(PREFIX .. "Map pins are not available.", out[#out])
      local n = #out
      run(env, "help")
      local found
      for i = n + 1, #out do if out[i]:find("/advisor pins", 1, true) then found = true end end
      assert.is_true(found)
    end)

    it("debug labels computes and scheduler runs separately", function()
      local _, env, out = setup()
      run(env, "")
      run(env, "debug")
      assert.is_truthy(out[#out]:match("computes=1 %(all calls%), scheduler runs=0 %(timer%-driven%)"))
    end)

    it("help lists /advisor help", function()
      local _, env, out = setup()
      run(env, "help")
      local found = false
      for _, l in ipairs(out) do if l:find("/advisor help", 1, true) then found = true end end
      assert.is_true(found)
    end)

    it("an unknown subcommand says so, then prints the help", function()
      local _, env, out = setup()
      run(env, "frobnicate now")
      assert.equals(PREFIX .. 'Unknown command "frobnicate".', out[1])
      assert.equals(PREFIX .. "Commands:", out[2])
      assert.is_true(#out > 3)
    end)

    it("routes a thrown error to the error handler", function()
      local ns, env = setup()
      ns.Settings.open = function() error("boom") end
      run(env, "settings")
      assert.equals(1, #env.errors)
    end)
  end)
end)
