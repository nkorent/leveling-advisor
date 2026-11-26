local H = require("spec.helpers.engine")

-- Anti-goal: never recommend a quest the player cannot get. Each case here
-- makes one quest unobtainable (level, missing prerequisite, elite setting)
-- and checks that it stays out of the route, the zone counts and the sections.
describe("Quests the player cannot get", function()
  local ns, db
  local S18, with, stepOf, find, ids = H.states.S18, H.with, H.stepOf, H.find, H.ids

  before_each(function()
    ns = H.load()
    db = ns.DB.new(H.data())
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
  local function route(d, state)
    return ns.Route.forZone(d, state, 1439, ns.Candidates.build(d, state), {})
  end

  describe("maximum level", function()
    it("a quest above its maximum level is never offered or routed", function()
      local c = ns.Candidates.build(db, S18)
      assert.is_nil(H.candidateFor(c, 7008))
      local secs = ns.Sections.build(db, S18, c, ns.ZoneScore.rank(db, S18, c))
      for _, sec in ipairs(secs) do
        for _, id in ipairs(ids(sec)) do assert.not_equals(7008, id) end
      end
      local steps = route(db, S18)
      assert.is_nil(stepOf(steps, 7008, "pickup"))
      assert.is_nil(stepOf(steps, 7008, "turnin"))
    end)
  end)

  describe("prerequisites", function()
    it("an any-prerequisite quest with none of its prerequisites done is not eligible", function()
      -- 7003 needs 7004 or 965
      local s = with(S18, { completed = { [4762] = true } })
      local status, reason = ns.Eligibility.check(db, db:quest(7003), s)
      assert.is_nil(status)
      assert.equals("prereq", reason)
    end)
    it("and it stays out of the candidates and the route while 965 is not turned in", function()
      -- 965 is ignored, so neither prerequisite of 7003 can ever be done
      local s = with(S18, { completed = { [4762] = true }, ignored = { [965] = true } })
      assert.is_nil(H.candidateFor(ns.Candidates.build(db, s), 7003))
      assert.is_nil(stepOf(route(db, s), 7003, "pickup"))
    end)
    it("is routed after the prerequisite's turn-in when that quest is in the route", function()
      local s = with(S18, { completed = { [4762] = true } })
      local steps = route(db, s)
      assert.is_true(stepOf(steps, 965, "turnin") <= stepOf(steps, 7003, "pickup"))
    end)
  end)

  describe("chain extension", function()
    -- 965 done, 4762 open: 4763 follows 4762 and could be added to the route
    local s = with(S18, { completed = { [965] = true } })

    it("adds the follow-up when nothing else gates it", function()
      local steps = route(db, s)
      assert.is_not_nil(stepOf(steps, 4762, "turnin"))
      assert.is_not_nil(stepOf(steps, 4763, "pickup"))
    end)

    it("leaves out a follow-up that is one level too high ('soon')", function()
      local d = dbWith(function(q) q[4763][5] = 19 end) -- requiredLevel 19 at level 18
      local steps = route(d, s)
      assert.is_not_nil(stepOf(steps, 4762, "pickup"))
      assert.is_nil(stepOf(steps, 4763, "pickup"))
    end)

    it("leaves out a follow-up that is more than two levels too high", function()
      local d = dbWith(function(q) q[4763][5] = 21 end)
      assert.is_nil(stepOf(route(d, s), 4763, "pickup"))
    end)

    it("leaves out an elite follow-up when elite quests are off", function()
      local d = dbWith(function(q) q[4763][9] = 1 end) -- elite flag
      local off = with(s, { settings = { elite = false, dungeons = true } })
      assert.is_nil(stepOf(route(d, off), 4763, "pickup"))
    end)

    it("keeps the same elite follow-up when elite quests are on", function()
      local d = dbWith(function(q) q[4763][9] = 1 end)
      assert.is_not_nil(stepOf(route(d, s), 4763, "pickup"))
    end)
  end)

  describe("a quest that is 'soon' (level 19 requirement at level 18)", function()
    -- 8100: plain quest next to the player; 8101: druid class quest
    local function soonDb()
      return dbWith(function(q)
        -- 8100 has an objective on the zone map; 8102 is a rich quest in the next zone
        q[8100] = copyRec(q[7001]); q[8100][3] = nil; q[8100][5] = 19; q[8100][13] = { { 1439, 41.0, 41.0 } }
        q[8101] = copyRec(q[5061]); q[8101][5] = 19
        q[8102] = copyRec(q[1010]); q[8102][5] = 19; q[8102][17] = 9999
      end)
    end

    it("is a 'soon' candidate", function()
      local c = ns.Candidates.build(soonDb(), S18)
      assert.equals("soon", H.candidateFor(c, 8100).status)
      assert.equals("soon", H.candidateFor(c, 8101).status)
      assert.equals("soon", H.candidateFor(c, 8102).status)
    end)

    it("is not routed", function()
      local steps = route(soonDb(), S18)
      assert.is_nil(stepOf(steps, 8100, "pickup"))
      assert.is_nil(stepOf(steps, 8100, "objective"))
      assert.is_nil(stepOf(steps, 8100, "turnin"))
      assert.is_nil(stepOf(steps, 8101, "pickup"))
    end)

    it("is not counted in the zone's quests or XP", function()
      local d = soonDb()
      local z = ns.ZoneScore.rank(d, S18, ns.Candidates.build(d, S18))
      assert.equals(6, z[1].questCount)
      assert.equals(7030, z[1].xp)
    end)

    it("does not appear in Right Here, chains or the next-zone section", function()
      local d = soonDb()
      local c = ns.Candidates.build(d, S18)
      local secs = ns.Sections.build(d, S18, c, ns.ZoneScore.rank(d, S18, c))
      assert.same({ 4763, 7003 }, ids(find(secs, "here")))
      assert.is_nil(find(secs, "chains"))
      assert.same({ 1010, 1007, 1100 }, ids(find(secs, "next")))
    end)

    it("shows a soon class quest only as a marked row in Class Quests", function()
      local d = soonDb()
      local c = ns.Candidates.build(d, S18)
      local class = find(ns.Sections.build(d, S18, c, ns.ZoneScore.rank(d, S18, c)), "class")
      assert.same({ 5061, 8101 }, ids(class))
      assert.is_false(class.rows[1].soon)
      assert.is_true(class.rows[2].soon)
    end)
  end)
end)
