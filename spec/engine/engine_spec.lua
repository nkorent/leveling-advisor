local H = require("spec.helpers.engine")
local ns = H.load()
local db = ns.DB.new(H.data())
local S18, S20, H20, with = H.states.S18, H.states.S20, H.states.H20, H.with
local Engine = ns.Engine

local function sortedKeys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out)
  return out
end

describe("Engine.compute", function()
  it("returns exactly zones, dungeon and sections", function()
    assert.same({ "sections", "zones" }, sortedKeys(Engine.compute(db, S18))) -- dungeon is nil at 18
    -- BFD at 22 (its level-23 and -24 quests are orange, so not recommended, at 20)
    assert.same({ "dungeon", "sections", "zones" }, sortedKeys(Engine.compute(db, H.states.S22)))
  end)

  it("Horde state sees only Horde content", function()
    -- level 22: the Horde quest 6382 (level 24) in Ashenvale is orange at 20
    local r = Engine.compute(db, with(H20, { level = 22 }))
    -- Darkshore (1439) and Loch Modan (1432) are Alliance-only
    assert.same({ 1440 }, { r.zones[1].mapID })
    assert.equals(1, #r.zones)
    assert.is_nil(r.dungeon)
  end)

  it("level extremes do not error", function()
    assert.has_no.errors(function() Engine.compute(db, with(S18, { level = 1, completed = {}, log = {} })) end)
    assert.has_no.errors(function() Engine.compute(db, with(S18, { level = 60 })) end)
  end)

  it("level 60 with an empty log yields no quest sections", function()
    local r = Engine.compute(db, with(S18, { level = 60, log = {} }))
    assert.same({}, r.sections)
    assert.is_nil(r.dungeon)
  end)
end)

describe("Engine.route candidate reuse", function()
  local builds, realBuild
  before_each(function()
    builds, realBuild = 0, ns.Candidates.build
    ns.Candidates.build = function(...)
      builds = builds + 1
      return realBuild(...)
    end
  end)
  after_each(function() ns.Candidates.build = realBuild end)

  it("reuses the candidates compute built for the same db and state", function()
    local rec = Engine.compute(db, S18)
    Engine.route(db, S18, 1439, rec)
    Engine.route(db, S18, 1440, rec)
    assert.equals(1, builds)
  end)

  it("rebuilds when the state is a different snapshot", function()
    local rec = Engine.compute(db, S18)
    local later = with(S18, { completed = { [4762] = true, [965] = true, [4763] = true } })
    local steps = Engine.route(db, later, 1439, rec)
    assert.equals(2, builds)
    assert.is_nil(H.stepOf(steps, 4763, "pickup")) -- done in the newer state
  end)

  it("rebuilds when the state is mutated in place", function()
    local s = with(S18, { completed = { [4762] = true, [965] = true } })
    local rec = Engine.compute(db, s)
    s.completed[4763] = true
    local steps = Engine.route(db, s, 1439, rec)
    assert.equals(2, builds)
    assert.is_nil(H.stepOf(steps, 4763, "pickup"))
  end)

  it("still reuses when the state is unchanged", function()
    local s = with(S18, { completed = { [4762] = true, [965] = true } })
    local rec = Engine.compute(db, s)
    Engine.route(db, s, 1439, rec)
    assert.equals(1, builds)
  end)

  it("rebuilds when a log entry completes in place", function()
    local s = with(S18, { log = { [966] = { complete = false } } })
    local rec = Engine.compute(db, s)
    s.log[966].complete = true
    Engine.route(db, s, 1439, rec)
    assert.equals(2, builds)
  end)

  it("rebuilds when the db is a different one", function()
    local rec = Engine.compute(db, S18)
    Engine.route(ns.DB.new(H.data()), S18, 1439, rec)
    assert.equals(2, builds)
  end)

  it("rebuilds without a recommendation", function()
    Engine.compute(db, S18)
    Engine.route(db, S18, 1439, nil)
    assert.equals(2, builds)
  end)

  it("gives the same route whether or not the candidates were reused", function()
    local rec = Engine.compute(db, S20)
    local reused = Engine.route(db, S20, 1439, rec)
    local fresh = Engine.route(db, S20, 1439, { dungeon = rec.dungeon })
    assert.same(fresh, reused)
  end)
end)

describe("Engine performance", function()
  local synthetic = require("spec.helpers.synthetic")
  local big = ns.DB.new(synthetic(7000, 50))

  -- Counts quests and how many share a giver position with an earlier quest.
  local function giverStats(data)
    local n, dup, seen = 0, 0, {}
    for _, r in pairs(data.quests) do
      n = n + 1
      local g = r[11]
      local k = g[3] .. ":" .. g[4] .. ":" .. g[5]
      if seen[k] then dup = dup + 1 end
      seen[k] = true
    end
    return n, dup
  end

  it("synthetic data is deterministic and varied", function()
    assert.same(synthetic(7000, 50), synthetic(7000, 50))
    local n, dup = giverStats(synthetic(7000, 50))
    assert.equals(7000, n)
    assert.is_true(dup <= 5)
  end)

  it("synthetic data gives S18 real work", function()
    local r = Engine.compute(big, S18)
    assert.is_true(#r.zones > 0)
    assert.is_true(#r.sections > 0)
  end)

  -- Warm-up and best-of-batches below exclude only LuaJIT trace compilation
  -- and GC pauses. WoW has no JIT so never pays that cost; with -joff, cold
  -- and warm runs take the same time. One call does not finish compiling the
  -- traces, so this test must not rely on an earlier test having run: it warms
  -- up on its own (20 untimed calls) and takes the best of 5 timed batches of
  -- 5 calls, each after a collection. The 10 ms bound is unchanged.
  it("computes 7,000 quests under 10 ms", function()
    for _ = 1, 20 do Engine.compute(big, S18) end -- warm up
    local best = math.huge
    for _ = 1, 5 do
      collectgarbage()
      local t = os.clock()
      for _ = 1, 5 do Engine.compute(big, S18) end
      best = math.min(best, (os.clock() - t) / 5)
    end
    assert.is_true(best < 0.010)
  end)

  it("routes the busiest synthetic zone under 15 ms", function()
    local busiest, most = nil, -1
    for _, id in ipairs(big:zoneIDs()) do
      local n = #big:questsInZone(id)
      if n > most then busiest, most = id, n end
    end
    local rec = Engine.compute(big, S18)
    local clock = function() return os.clock() * 1000 end
    -- One untimed run warms LuaJIT's trace compiler. The timed figure is the
    -- best of three runs after a collection, so a GC pause or a busy machine
    -- does not decide the result.
    local steps = Engine.route(big, S18, busiest, rec, clock)
    local ms = math.huge
    for _ = 1, 3 do
      collectgarbage()
      local t = os.clock()
      steps = Engine.route(big, S18, busiest, rec, clock)
      ms = math.min(ms, (os.clock() - t) * 1000)
    end
    assert.is_true(ms < 15)
    assert.is_true(#steps > 0)
  end)
end)
