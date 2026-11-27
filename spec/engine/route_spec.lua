local H = require("spec.helpers.engine")
local ns = H.load()
local db = ns.DB.new(H.data())
local S18, S20, with, stepOf = H.states.S18, H.states.S20, H.with, H.stepOf
local Candidates, Route = ns.Candidates, ns.Route

-- Compact view of a route: per step, "questID:kind" action labels plus counts and xp.
local function summary(steps)
  local out = {}
  for i, st in ipairs(steps) do
    local labels = {}
    for j, a in ipairs(st.actions) do labels[j] = a[1] .. ":" .. a[2] end
    out[i] = { actions = labels, counts = st.counts, xp = st.xp }
  end
  return out
end

-- The distinct map IDs of the steps, sorted.
local function mapsOf(steps)
  local seen, out = {}, {}
  for _, st in ipairs(steps) do
    if not seen[st.mapID] then seen[st.mapID] = true; out[#out + 1] = st.mapID end
  end
  table.sort(out)
  return out
end

local function allNumeric(steps)
  for _, st in ipairs(steps) do
    if type(st.x) ~= "number" or type(st.y) ~= "number" then return false end
  end
  return true
end

describe("Route.forZone", function()
  it("picks up before objectives before turn-in", function()
    local steps = Route.forZone(db, S18, 1439, Candidates.build(db, S18), {})
    assert.is_true(stepOf(steps, 4763, "pickup") < stepOf(steps, 4763, "objective"))
    assert.is_true(stepOf(steps, 4763, "objective") <= stepOf(steps, 4763, "turnin"))
    assert.is_true(stepOf(steps, 966, "objective") <= stepOf(steps, 966, "turnin"))
  end)
  it("first step is the hub at the player's feet", function()
    local steps = Route.forZone(db, S18, 1439, Candidates.build(db, S18), { improve = false })
    assert.is_not_nil(stepOf(steps, 4763, "pickup"))
    assert.equals(1, stepOf(steps, 4763, "pickup"))
  end)
  it("extends a chain inside the route", function()
    local s = with(S18, { completed = { [965] = true } })
    local steps = Route.forZone(db, s, 1439, Candidates.build(db, s), {})
    assert.is_true(stepOf(steps, 4762, "turnin") <= stepOf(steps, 4763, "pickup"))
  end)
  it("ignored prerequisite blocks its follow-up", function()
    local s = with(S18, { completed = { [965] = true }, ignored = { [4762] = true } })
    local steps = Route.forZone(db, s, 1439, Candidates.build(db, s), {})
    assert.is_nil(stepOf(steps, 4763, "pickup"))
  end)
  it("includes recommended dungeon pickups only", function()
    -- level 22: 1275 (level 24) is yellow; at 20 it is orange and never routed
    local S22 = H.states.S22
    local c = Candidates.build(db, S22)
    assert.is_nil(stepOf(Route.forZone(db, S22, 1439, c, {}), 1275, "pickup"))
    assert.is_not_nil(stepOf(Route.forZone(db, S22, 1439, c, { dungeonKey = "BFD" }), 1275, "pickup"))
  end)
  it("leaves out another dungeon's quest when BFD is recommended", function()
    -- 1486 (Wailing Caverns) is eligible at S20 and its giver stands in Darkshore
    local c = Candidates.build(db, S20)
    assert.equals("eligible", H.candidateFor(c, 1486).status)
    assert.is_nil(stepOf(Route.forZone(db, S20, 1439, c, { dungeonKey = "BFD" }), 1486, "pickup"))
    assert.is_not_nil(stepOf(Route.forZone(db, S20, 1439, c, { dungeonKey = "WC" }), 1486, "pickup"))
  end)
  it("lists each step's actions, counts and turn-in XP (greedy order)", function()
    local steps = Route.forZone(db, S18, 1439, Candidates.build(db, S18), { improve = false })
    assert.same({
      { actions = { "4763:pickup" }, counts = { pickup = 1, objective = 0, turnin = 0 }, xp = 0 },
      { actions = { "7003:pickup", "7003:turnin" }, counts = { pickup = 1, objective = 0, turnin = 1 }, xp = 500 },
      { actions = { "4730:turnin", "5061:pickup", "5061:turnin" }, counts = { pickup = 1, objective = 0, turnin = 2 }, xp = 2180 },
      { actions = { "4763:objective" }, counts = { pickup = 0, objective = 1, turnin = 0 }, xp = 0 },
      { actions = { "966:objective", "966:turnin", "967:pickup", "967:objective", "967:turnin" },
        counts = { pickup = 1, objective = 2, turnin = 2 }, xp = 2350 },
      { actions = { "1000:pickup", "1000:objective", "1000:turnin" }, counts = { pickup = 1, objective = 1, turnin = 1 }, xp = 1500 },
      { actions = { "4763:turnin" }, counts = { pickup = 0, objective = 0, turnin = 1 }, xp = 1700 },
    }, summary(steps))
  end)
  it("puts every step on the zone map with numeric coordinates", function()
    local steps = Route.forZone(db, S18, 1439, Candidates.build(db, S18), {})
    assert.same({ 1439 }, mapsOf(steps))
    assert.is_true(allNumeric(steps))
  end)
  it("returns an empty route for a map with no quests", function()
    assert.same({}, Route.forZone(db, S18, 9999, Candidates.build(db, S18), {}))
  end)

  local function dbWith(edit)
    local data = H.data()
    edit(data.quests)
    return ns.DB.new(data)
  end
  local function copyRec(r)
    local out = {}
    for k, v in pairs(r) do out[k] = v end
    return out
  end

  it("gives no turn-in when an objective is off this map", function()
    local d = dbWith(function(q) q[4762][13] = { { 1440, 50.0, 35.0 } } end)
    local s = with(S18, { completed = { [965] = true } })
    local steps = Route.forZone(d, s, 1439, Candidates.build(d, s), {})
    assert.is_not_nil(stepOf(steps, 4762, "pickup"))
    assert.is_nil(stepOf(steps, 4762, "objective"))
    assert.is_nil(stepOf(steps, 4762, "turnin"))
    assert.is_nil(stepOf(steps, 4763, "pickup"))
  end)
  it("gives no turn-in for a progress quest without points", function()
    local d = dbWith(function(q) q[966][13] = nil end)
    local steps = Route.forZone(d, S18, 1439, Candidates.build(d, S18), {})
    assert.is_nil(stepOf(steps, 966, "turnin"))
    assert.is_nil(stepOf(steps, 967, "pickup"))
  end)
  it("treats an eligible quest without points as a delivery", function()
    local greedy = Route.forZone(db, S18, 1439, Candidates.build(db, S18), { improve = false })
    assert.same({ "4730:turnin", "5061:pickup", "5061:turnin" }, summary(greedy)[3].actions)
    local better = Route.forZone(db, S18, 1439, Candidates.build(db, S18), {})
    assert.equals(stepOf(better, 5061, "pickup"), stepOf(better, 5061, "turnin"))
  end)
  it("drops a breadcrumb whose target is in the route", function()
    local s = with(S18, { log = {}, completed = { [965] = true, [4762] = true } })
    local c = Candidates.build(db, s)
    assert.is_not_nil(H.candidateFor(c, 7006)) -- the breadcrumb is a candidate
    local steps = Route.forZone(db, s, 1439, c, {})
    assert.is_not_nil(stepOf(steps, 966, "pickup"))
    assert.is_nil(stepOf(steps, 7006, "pickup"))
  end)

  it("keeps a breadcrumb that its target requires (363 -> 364 shape)", function()
    -- 966 requires 7006 (all), while 7006 is flagged breadcrumbOf 966
    local d = dbWith(function(q) q[966][19] = { all = { 965, 7006 } } end)
    local s = with(S18, { log = {}, completed = { [965] = true } })
    local steps = Route.forZone(d, s, 1439, Candidates.build(d, s), {})
    assert.is_not_nil(stepOf(steps, 7006, "pickup"))
    assert.is_not_nil(stepOf(steps, 966, "pickup"))
    assert.is_true(stepOf(steps, 7006, "turnin") <= stepOf(steps, 966, "pickup"))
  end)
  it("keeps a breadcrumb that its target lists in prereq.any", function()
    local d = dbWith(function(q) q[966][19] = { any = { 7006, 4762 } } end)
    local s = with(S18, { log = {}, completed = { [965] = true } })
    local steps = Route.forZone(d, s, 1439, Candidates.build(d, s), {})
    assert.is_not_nil(stepOf(steps, 7006, "pickup"))
    assert.is_not_nil(stepOf(steps, 966, "pickup"))
  end)

  describe("exclusive quests (7005 is exclusive with 965)", function()
    local none = with(S18, { log = {}, completed = {} })
    local function routeWith(xp7005)
      local d = dbWith(function(q) q[7005][17] = xp7005 end)
      return Route.forZone(d, none, 1439, Candidates.build(d, none), {})
    end

    it("keeps 965 (675 XP) over 7005 (500 XP)", function()
      local steps = routeWith(500)
      assert.is_not_nil(stepOf(steps, 965, "pickup"))
      assert.is_nil(stepOf(steps, 7005, "pickup"))
    end)
    it("keeps 7005 when it is worth more, and drops 965's chain with it", function()
      local steps = routeWith(900)
      assert.is_not_nil(stepOf(steps, 7005, "pickup"))
      assert.is_nil(stepOf(steps, 965, "pickup"))
      assert.is_nil(stepOf(steps, 966, "pickup"))
      assert.is_nil(stepOf(steps, 967, "pickup"))
    end)
    it("keeps the lower quest ID on a tie", function()
      local steps = routeWith(675)
      assert.is_not_nil(stepOf(steps, 965, "pickup"))
      assert.is_nil(stepOf(steps, 7005, "pickup"))
    end)
  end)
  it("drops quests with cyclic prerequisites without hanging", function()
    local d = dbWith(function(q)
      local x, y = copyRec(q[7003]), copyRec(q[7003])
      x[19] = { all = { 8002 } }; y[19] = { all = { 8001 } }
      q[8001], q[8002] = x, y
    end)
    local steps = Route.forZone(d, S18, 1439, Candidates.build(d, S18), {})
    assert.is_nil(stepOf(steps, 8001, "pickup"))
    assert.is_nil(stepOf(steps, 8002, "pickup"))
  end)
  it("starts at the hub with the most pickups when the player is off-map", function()
    -- 4730 and 5061 share a hub (2 pickups); every other hub has at most 1
    local s = with(S18, { mapID = 1440, x = 50, y = 50, log = {}, ignored = { [966] = true, [7006] = true } })
    local steps = Route.forZone(db, s, 1439, Candidates.build(db, s), { improve = false })
    assert.same({ "4730:pickup", "4730:turnin", "5061:pickup", "5061:turnin" }, summary(steps)[1].actions)
    assert.equals(2, steps[1].counts.pickup)
  end)
end)

-- Level fit (0.3.0): the zone route visits yellow and green quests only (complete quests are
-- turned in at any level).
describe("Route.forZone level fit", function()
  local function copyRec(r)
    local out = {}
    for k, v in pairs(r) do out[k] = v end
    return out
  end
  local function dbWith(edit)
    local data = H.data()
    edit(data.quests)
    return ns.DB.new(data)
  end
  local function route(d, s)
    return Route.forZone(d, s, 1439, Candidates.build(d, s), {})
  end
  local function routedIDs(steps)
    local seen = {}
    for _, st in ipairs(steps) do
      for _, a in ipairs(st.actions) do seen[a[1]] = true end
    end
    return seen
  end

  it("leaves out an orange quest at the player's feet", function()
    local d = dbWith(function(q) q[8501] = copyRec(q[4763]); q[8501][19] = nil; q[8501][6] = 21 end)
    local steps = route(d, S18)
    assert.is_nil(routedIDs(steps)[8501])
    assert.is_not_nil(stepOf(steps, 4763, "pickup"))
  end)

  it("leaves out an orange chain follow-up (the chain extension)", function()
    -- 965 done, 4762 open: 4763 (now level 21) would follow 4762's turn-in
    local d = dbWith(function(q) q[4763][6] = 21 end)
    local steps = route(d, with(S18, { completed = { [965] = true } }))
    assert.is_not_nil(stepOf(steps, 4762, "turnin"))
    assert.is_nil(stepOf(steps, 4763, "pickup"))
  end)

  it("leaves out an orange in-progress quest; a yellow one stays", function()
    local steps = route(db, S18)
    assert.is_not_nil(stepOf(steps, 966, "objective")) -- 966 is level 18, in the log
    local d = dbWith(function(q) q[966][6] = 21 end)
    local ids = routedIDs(route(d, S18))
    assert.is_nil(ids[966])
    assert.is_nil(ids[967]) -- its follow-up waits too
  end)

  it("still turns in a complete orange quest", function()
    local d = dbWith(function(q) q[4730][6] = 22 end) -- 4730 is complete in S18's log
    assert.is_not_nil(stepOf(route(d, S18), 4730, "turnin"))
  end)

  it("no step has a quest that is not yellow or green, apart from turn-ins", function()
    local d = dbWith(function(q)
      q[8501] = copyRec(q[4763]); q[8501][19] = nil; q[8501][6] = 21
      q[5061][5] = 19
    end)
    for id in pairs(routedIDs(route(d, S18))) do
      local q = d:quest(id)
      local fit = ns.Difficulty.color(q.level, S18.level, S18.greyAtOrBelow)
      assert.is_true(fit == "yellow" or fit == "green" or id == 4730, id .. " is " .. fit)
    end
  end)
end)
