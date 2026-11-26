local H = require("spec.helpers.engine")
local ns = H.load()
local db = ns.DB.new(H.data())
local S18, with, stepOf = H.states.S18, H.with, H.stepOf
local RouteImprove, Route, Candidates = ns.RouteImprove, ns.Route, ns.Candidates

local function st(x, ...)        -- one step on Darkshore at (x, 50); 1 unit = 60 yd
  local a, args = {}, { ... }
  for i = 1, #args, 2 do a[#a + 1] = { args[i], args[i + 1] } end
  return { mapID = 1439, x = x, y = 50, actions = a, counts = {}, xp = 0 }
end
local START = { 1439, 50, 50 }

describe("RouteImprove", function()
  it("fixes the greedy zig-zag", function()
    local steps, stats = RouteImprove.improve(db, { st(51, 9001, "turnin"), st(53, 9002, "turnin"), st(48, 9003, "turnin") }, START, {})
    assert.same({ 48, 51, 53 }, { steps[1].x, steps[2].x, steps[3].x })
    assert.near(480, stats.before, 0.1); assert.near(420, stats.after, 0.1)
  end)
  -- Instances found by comparing the improver with one that has 2-opt (or
  -- longer Or-opt runs) switched off: each is solved better only with the
  -- feature, so these fail if it stops working.
  local function pt(x, y, id)
    local s = st(x, id, "turnin"); s.y = y
    return s
  end
  local function route(spec) -- { {x, y}, ... } -> steps with turn-ins 9001, 9002, ...
    local out = {}
    for i, p in ipairs(spec) do out[i] = pt(p[1], p[2], 9000 + i) end
    return out
  end
  local function order(steps)
    local ids = {}
    for i, s in ipairs(steps) do ids[i] = s.actions[1][1] - 9000 end
    return ids
  end

  describe("2-opt and Or-opt", function()
    it("reverses a segment (2-opt)", function()
      local input = route({ { 51, 57 }, { 77, 13 }, { 38, 90 }, { 75, 75 }, { 44, 55 } })
      local steps, stats = RouteImprove.improve(db, input, { 1439, 80, 97 }, {})
      assert.same({ 4, 3, 5, 1, 2 }, order(steps))
      assert.near(7454.3, stats.after, 0.5)
      assert.near(12908.1, stats.before, 0.5)
    end)

    it("moves a run of two steps (Or-opt)", function()
      local input = route({ { 12, 50 }, { 9, 71 }, { 78, 10 }, { 50, 60 }, { 3, 92 } })
      local steps, stats = RouteImprove.improve(db, input, { 1439, 30, 79 }, {})
      assert.near(8401.2, stats.after, 0.5)
      assert.same({ 5, 2, 1, 4, 3 }, order(steps))
    end)

    it("moves a run of three steps (Or-opt)", function()
      local input = route({ { 28, 87 }, { 14, 55 }, { 69, 76 }, { 99, 0 }, { 61, 19 }, { 60, 30 } })
      local steps, stats = RouteImprove.improve(db, input, { 1439, 49, 64 }, {})
      assert.near(10925.7, stats.after, 0.5)
      assert.same({ 2, 1, 3, 6, 5, 4 }, order(steps))
    end)

    it("never needs the length safety net", function()
      local input = route({ { 51, 57 }, { 77, 13 }, { 38, 90 }, { 75, 75 }, { 44, 55 } })
      local _, stats = RouteImprove.improve(db, input, { 1439, 80, 97 }, {})
      assert.is_nil(stats.reverted)
      assert.is_nil(stats.invalidInput)
    end)
  end)

  it("keeps a pickup before its turn-in", function()
    local steps = RouteImprove.improve(db, { st(60, 9001, "pickup"), st(52, 9001, "turnin") }, START, {})
    assert.equals("pickup", steps[1].actions[1][2])
  end)
  it("keeps a chain's turn-in before the follow-up pickup", function()   -- 4763 needs 4762
    local steps = RouteImprove.improve(db, { st(60, 4762, "turnin"), st(51, 4763, "pickup") }, START, {})
    assert.equals(4762, steps[1].actions[1][1])
  end)
  it("merges steps that end up at the same point", function()
    local steps = RouteImprove.improve(db, { st(50, 9001, "pickup"), st(60, 9002, "turnin"), st(50, 9003, "turnin") }, START, {})
    assert.equals(2, #steps); assert.equals(2, #steps[1].actions)
  end)
  it("stops at the time budget", function()
    local t = 0
    local _, stats = RouteImprove.improve(db, { st(51, 9001, "turnin"), st(53, 9002, "turnin"), st(48, 9003, "turnin") },
      START, { clock = function() t = t + 10; return t end })
    assert.is_true(stats.passes <= 1)
  end)
  describe("without a clock", function()
    -- 150 scattered turn-ins: far more candidate moves than the cap allows
    local function scattered()
      local seed, input = 777, {}
      local function rnd()
        seed = (seed * 1103515245 + 12345) % 2147483648
        return seed / 2147483648
      end
      for i = 1, 150 do
        local s = st(rnd() * 100, 9000 + i, "turnin"); s.y = rnd() * 100
        input[i] = s
      end
      return input
    end

    it("still stops after the candidate cap", function()
      local _, stats = RouteImprove.improve(db, scattered(), START, {})
      assert.is_true(stats.candidates <= ns.Tuning.ROUTE_IMPROVE_MAX_CANDIDATES)
      assert.is_true(stats.passes <= 1)
    end)

    it("still improves the route before the cap stops it", function()
      local _, stats = RouteImprove.improve(db, scattered(), START, {})
      assert.is_true(stats.moves > 0)
      assert.is_true(stats.after < stats.before)
    end)

    it("leaves a small route alone: the cap does not bite", function()
      local _, stats = RouteImprove.improve(db, { st(51, 9001, "turnin"), st(53, 9002, "turnin"), st(48, 9003, "turnin") }, START, {})
      assert.is_true(stats.candidates < ns.Tuning.ROUTE_IMPROVE_MAX_CANDIDATES)
    end)

    it("bounds the improver when Engine.route is called without a clock", function()
      local S18c = H.states.S18
      local synthetic = require("spec.helpers.synthetic")
      local big = ns.DB.new(synthetic(7000, 50))
      local busiest, most = nil, -1
      for _, id in ipairs(big:zoneIDs()) do
        local n = #big:questsInZone(id)
        if n > most then busiest, most = id, n end
      end
      local orig, seen = RouteImprove.improve, nil
      RouteImprove.improve = function(d, steps, start, opts)
        local r, stats = orig(d, steps, start, opts)
        seen = stats
        return r, stats
      end
      local ok, err = pcall(ns.Engine.route, big, S18c, busiest, ns.Engine.compute(big, S18c))
      RouteImprove.improve = orig
      assert.is_true(ok, err)
      assert.is_true(seen.candidates <= ns.Tuning.ROUTE_IMPROVE_MAX_CANDIDATES)
    end)
  end)
  it("never lengthens the fixture route or breaks its rules", function()
    local c = Candidates.build(db, S18); local start = { 1439, 38.0, 41.0 }
    local greedy = Route.forZone(db, S18, 1439, c, { improve = false })
    local better = Route.forZone(db, S18, 1439, c, {})
    assert.is_true(RouteImprove.length(db, better, start) <= RouteImprove.length(db, greedy, start))
    assert.is_true(stepOf(better, 4763, "pickup") <= stepOf(better, 4763, "objective"))
    assert.is_true(stepOf(better, 966, "objective") <= stepOf(better, 966, "turnin"))
  end)
  it("returns an empty list for an empty route", function()
    local steps, stats = RouteImprove.improve(db, {}, START, {})
    assert.same({}, steps); assert.equals(0, stats.before)
  end)
  it("does not mutate its input", function()
    local input = { st(51, 9001, "turnin"), st(53, 9002, "turnin"), st(48, 9003, "turnin") }
    RouteImprove.improve(db, input, START, {})
    assert.same({ 51, 53, 48 }, { input[1].x, input[2].x, input[3].x })
  end)
  for _, p in ipairs({ { 38, 41 }, { 60, 20 }, { 45, 80 }, { 70, 70 }, { 20, 30 } }) do
    it("never lengthens the route from player position " .. p[1] .. "," .. p[2], function()
      local s = with(S18, { mapID = 1439, x = p[1], y = p[2] })
      local c = Candidates.build(db, s)
      local start = { 1439, p[1], p[2] }
      local greedy = Route.forZone(db, s, 1439, c, { improve = false })
      local better = Route.forZone(db, s, 1439, c, {})
      assert.is_true(RouteImprove.length(db, better, start) <= RouteImprove.length(db, greedy, start) + 1e-6)
      assert.is_true(stepOf(better, 4763, "pickup") <= stepOf(better, 4763, "objective"))
      assert.is_true(stepOf(better, 966, "objective") <= stepOf(better, 966, "turnin"))
      assert.is_true(stepOf(better, 4763, "objective") <= stepOf(better, 4763, "turnin"))
      assert.is_true(stepOf(better, 966, "turnin") <= stepOf(better, 967, "pickup"))
    end)
  end
  it("with one pass allowed, stays valid and not longer", function()
    local old = ns.Tuning.ROUTE_IMPROVE_MAX_PASSES
    ns.Tuning.ROUTE_IMPROVE_MAX_PASSES = 1
    local ok, err = pcall(function()
      local c = Candidates.build(db, S18); local start = { 1439, 38.0, 41.0 }
      local greedy = Route.forZone(db, S18, 1439, c, { improve = false })
      local better, stats = RouteImprove.improve(db, greedy, start, {})
      assert.is_true(stats.passes <= 1)
      assert.is_true(RouteImprove.length(db, better, start) <= RouteImprove.length(db, greedy, start))
      assert.is_true(stepOf(better, 4763, "pickup") <= stepOf(better, 4763, "objective"))
      assert.is_true(stepOf(better, 966, "objective") <= stepOf(better, 966, "turnin"))
    end)
    ns.Tuning.ROUTE_IMPROVE_MAX_PASSES = old
    assert.is_true(ok, err)
  end)
  it("honours opts.deps with an already satisfied any", function()
    local input = { st(50, 7004, "turnin"), st(51, 7003, "pickup"), st(90, 965, "turnin"),
      st(91, 9001, "turnin"), st(95, 9002, "turnin"), st(92, 9003, "turnin") }
    local _, stats = RouteImprove.improve(db, input, START, { deps = { [7003] = { all = {}, any = {} } } })
    assert.is_true(stats.moves > 0)
    assert.is_true(stats.after < stats.before)
  end)
  it("requires at least one any turn-in before the pickup", function()
    local input = { st(60, 9001, "turnin"), st(70, 9002, "turnin"), st(51, 9003, "pickup") }
    local steps = RouteImprove.improve(db, input, START, { deps = { [9003] = { all = {}, any = { 9001, 9002 } } } })
    local pos = {}
    for i, s in ipairs(steps) do pos[s.actions[1][1]] = i end
    assert.is_true(pos[9003] > math.min(pos[9001], pos[9002]))
  end)
  it("returns an invalid input unchanged and flags it", function()
    local input = { st(60, 9001, "turnin"), st(51, 9001, "pickup"), st(40, 9002, "turnin") }
    local steps, stats = RouteImprove.improve(db, input, START, {})
    assert.is_true(stats.invalidInput)
    assert.same({ 60, 51, 40 }, { steps[1].x, steps[2].x, steps[3].x })
  end)
  it("does not mutate inputs when merging", function()
    local input = { st(50, 9001, "pickup"), st(60, 9002, "turnin"), st(50, 9003, "turnin") }
    input[1].counts = { pickup = 1 }
    RouteImprove.improve(db, input, START, {})
    assert.equals(1, #input[1].actions)
    assert.same({ pickup = 1 }, input[1].counts)
    assert.is_nil(input[1].merged)
    assert.equals(3, #input)
  end)
  it("Route.forZone passes the clock through", function()
    local calls = 0
    Route.forZone(db, S18, 1439, Candidates.build(db, S18), { clock = function() calls = calls + 1; return 0 end })
    assert.is_true(calls > 0)
  end)

  it("Route.forZone passes deps to the improver", function()
    local orig, seen = RouteImprove.improve, nil
    RouteImprove.improve = function(d, steps, start, opts)
      seen = opts
      return orig(d, steps, start, opts)
    end
    local ok, err = pcall(Route.forZone, db, S18, 1439, Candidates.build(db, S18), {})
    RouteImprove.improve = orig
    assert.is_true(ok, err)
    assert.is_table(seen.deps)
    for _, d in pairs(seen.deps) do assert.is_table(d.all); assert.is_table(d.any) end
  end)
  it("does not lengthen the stale-tail repro", function()
    local function pt(x, y) local s = st(x, 9001, "turnin"); s.y = y; return s end
    local input = { pt(21.0, 7.3), pt(22.3, 77.4), pt(4.6, 89.1), pt(5.8, 73.8) }
    input[2].actions = { { 9002, "turnin" } }; input[3].actions = { { 9003, "turnin" } }
    input[4].actions = { { 9004, "turnin" } }
    local _, stats = RouteImprove.improve(db, input, { 1439, 46, 89 }, {})
    assert.is_true(stats.after < stats.before)
    assert.near(6084.6, stats.after, 0.5)
    assert.is_true(stats.passes <= 2)
  end)
  -- Seeded random routes of 4-12 scattered turn-ins. Assertions are
  -- unconditional; `withStart` decides only whether the route has a start.
  local function randomRoutes(seed, count, withStart)
    local function rnd()
      seed = (seed * 1103515245 + 12345) % 2147483648
      return seed / 2147483648
    end
    local routes = {}
    for r = 1, count do
      local n = 4 + math.floor(rnd() * 9)
      local input = {}
      for i = 1, n do input[i] = pt(rnd() * 100, rnd() * 100, 9000 + i) end
      local start = nil
      if withStart then start = { 1439, rnd() * 100, rnd() * 100 } end
      routes[r] = { input = input, start = start, n = n }
    end
    return routes
  end
  local function tally(steps)
    local count = {}
    for _, s in ipairs(steps) do
      for _, a in ipairs(s.actions) do count[a[1]] = (count[a[1]] or 0) + 1 end
    end
    return count
  end
  local function onceEach(n)
    local want = {}
    for i = 1, n do want[9000 + i] = 1 end
    return want
  end

  for _, withStart in ipairs({ true, false }) do
    it("never lengthens random routes and keeps every action (fuzz, start " .. tostring(withStart) .. ")", function()
      local gained = 0
      for _, r in ipairs(randomRoutes(12345, 100, withStart)) do
        local out, stats = RouteImprove.improve(db, r.input, r.start, {})
        assert.is_true(stats.after <= stats.before + 1e-6)
        assert.is_nil(stats.reverted)
        assert.is_nil(stats.invalidInput)
        assert.is_true(stats.passes < ns.Tuning.ROUTE_IMPROVE_MAX_PASSES)
        assert.same(onceEach(r.n), tally(out))
        gained = gained + (stats.before - stats.after)
      end
      -- an improver that did nothing would pass the checks above
      assert.is_true(gained > 0)
    end)
  end
end)
