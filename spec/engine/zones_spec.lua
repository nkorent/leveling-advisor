local H = require("spec.helpers.engine")

describe("Candidates and ZoneScore", function()
  local ns, db, Candidates, ZoneScore
  local S18, with = H.states.S18, H.with

  before_each(function()
    ns = H.load()
    db = ns.DB.new(H.data())
    Candidates, ZoneScore = ns.Candidates, ns.ZoneScore
  end)

  local function mapIDs(zones)
    local out = {}
    for i, z in ipairs(zones) do out[i] = z.mapID end
    return out
  end

  it("S18 ranks Darkshore, Ashenvale, Loch Modan with reasons", function()
    local z = ZoneScore.rank(db, S18, Candidates.build(db, S18))
    assert.same({ 1439, 1440, 1432 }, { z[1].mapID, z[2].mapID, z[3].mapID })
    assert.equals("You are here — finish before you leave", z[1].reason)
    assert.is_true(z[1].isHere)
    assert.equals("Next zone — walk south", z[2].reason)
    -- Loch Modan's only quest (1081, level 15) is green at 18; the boat reason is in "ZoneScore
    -- level fit" below
    assert.equals("Catch up — 1 quest you skipped at your level", z[3].reason)
    assert.equals(6, z[1].questCount)
    assert.equals(7030, z[1].xp)
    assert.equals(1, z[1].chains)
    assert.equals(3, z[2].questCount) -- 991 (level 21) is orange at 18: Later, not counted
  end)

  it("never names the other faction's transport as the reason", function()
    local s = with(S18, { mapID = 1440, x = 40, y = 10 })
    -- 1081 made yellow (level 17), so Loch Modan's reason comes from the links, not "Catch up"
    local data = H.data()
    data.quests[1081][6] = 17
    local db = ns.DB.new(data)
    local z = ZoneScore.rank(db, s, Candidates.build(db, s))
    local found
    for _, r in ipairs(z) do
      if r.mapID == 1432 then found = r end
      assert.is_nil((r.reason or ""):find("zeppelin", 1, true))
    end
    assert.is_truthy(found)
    assert.equals("Most XP for your level", found.reason)
  end)

  it("S18 scores: 6825.0, 3932.3 and 144.1 (hub bonus, fit weight, no travel at home, travel elsewhere)", function()
    local z = ZoneScore.rank(db, S18, Candidates.build(db, S18))
    assert.near(6825.0, z[1].score, 0.05)
    -- Ashenvale: 991 (orange) is not counted, so 1010 and 1007 share a hub of two:
    -- (1450 + 1350) x 1.25 + 1200 - 767.7 travel
    assert.near(3932.3, z[2].score, 0.05)
    -- Loch Modan: 1081 is green, weighted 0.8: 900 x 0.8 - 575.9 travel
    assert.near(144.1, z[3].score, 0.05)
  end)

  it("never lists the other faction's zone", function()
    local z = ZoneScore.rank(db, S18, Candidates.build(db, S18))
    assert.same({ 1439, 1440, 1432 }, mapIDs(z)) -- Durotar (1411) is Horde-only
  end)

  it("never lists the other faction's zone, even with quests the player can take there", function()
    -- A neutral (faction 3) quest in Horde Durotar, worth more than Loch Modan's whole score.
    local function patched(zoneFaction)
      local data = H.data()
      local r = {}
      for k, v in pairs(data.quests[840]) do r[k] = v end
      r[1], r[2], r[5], r[6], r[17] = "Neutral Errand", 3, 16, 18, 4000
      data.quests[8000] = r
      data.zones[1411].faction = zoneFaction
      return ns.DB.new(data)
    end
    local hordeDb = patched(2)
    local c = Candidates.build(hordeDb, S18)
    assert.equals("eligible", H.candidateFor(c, 8000).status)
    assert.same({ 1439, 1440, 1432 }, mapIDs(ZoneScore.rank(hordeDb, S18, c)))
    -- control: the same quest in a contested Durotar does rank, so only the faction rule hides it
    local openDb = patched(3)
    local ranked = mapIDs(ZoneScore.rank(openDb, S18, Candidates.build(openDb, S18)))
    assert.is_truthy(table.concat(ranked, ","):find("1411", 1, true), table.concat(ranked, ","))
  end)

  it("elite setting off drops elite quests from candidates", function()
    local s = with(S18, { settings = { elite = false, dungeons = true } })
    assert.is_nil(H.candidateFor(Candidates.build(db, s), 1000))
  end)

  it("elite setting off keeps an elite quest that is in the log", function()
    local s = with(S18, {
      settings = { elite = false, dungeons = true },
      log = { [966] = { complete = false }, [4730] = { complete = true }, [1000] = { complete = false } },
    })
    local found = H.candidateFor(Candidates.build(db, s), 1000)
    assert.is_not_nil(found)
    assert.equals("progress", found.status)
  end)

  it("player's zone is not pinned when it has fewer than 2 quests", function()
    local s = with(S18, {
      completed = { [4762] = true, [965] = true, [4763] = true, [5061] = true, [1000] = true,
                    [7003] = true, [966] = true, [4730] = true },
      log = {},
    })
    local z = ZoneScore.rank(db, s, Candidates.build(db, s))
    -- Darkshore keeps one quest (1200 XP) and falls to second place
    assert.same({ 1440, 1439, 1432 }, mapIDs(z))
    assert.is_true(z[2].isHere)
  end)

  -- Hand-built candidates: one quest per entry, XP given directly, yellow (full weight).
  local function cand(id, mapID, x, y, xp, extra)
    local q = { id = id, zone = mapID, giver = { mapID = mapID, x = x, y = y } }
    for k, v in pairs(extra or {}) do q[k] = v end
    return { quest = q, status = "eligible", fit = "yellow", xp = xp }
  end
  -- The player stands in Darkshore (1439), so that zone has no travel cost.
  local function homeScore(list)
    local z = ZoneScore.rank(db, S18, list)
    assert.equals(1439, z[1].mapID)
    return z[1].score
  end

  describe("score formula", function()
    it("adds 25% per extra giver at the same hub", function()
      -- three givers at one spot: factor 1.5 each
      assert.near(4500, homeScore({
        cand(1, 1439, 40, 40, 1000), cand(2, 1439, 40, 40, 1000), cand(3, 1439, 40, 40, 1000),
      }), 1e-6)
    end)

    it("does not give a hub bonus to givers that are far apart", function()
      assert.near(3000, homeScore({
        cand(1, 1439, 10, 10, 1000), cand(2, 1439, 50, 50, 1000), cand(3, 1439, 90, 90, 1000),
      }), 1e-6)
    end)

    it("caps the hub bonus at +100%", function()
      -- six givers at one spot: 1 + min(0.25 * 5, 1.0) = 2.0 each, not 2.25
      local list = {}
      for i = 1, 6 do list[i] = cand(i, 1439, 40, 40, 1000) end
      assert.near(12000, homeScore(list), 1e-6)
    end)

    it("halves elite and group quests", function()
      assert.near(2000, homeScore({
        cand(1, 1439, 10, 10, 1000),
        cand(2, 1439, 50, 50, 1000, { elite = true }),
        cand(3, 1439, 90, 90, 1000, { groupSize = 2 }),
      }), 1e-6) -- 1000 + 500 + 500
    end)

    it("subtracts travel for a zone the player is not in", function()
      local z = ZoneScore.rank(db, S18, { cand(1, 1440, 50, 50, 1000), cand(2, 1439, 10, 10, 100), cand(3, 1439, 90, 90, 100) })
      -- Ashenvale: 1000 minus the walk there (767.7 to its centre)
      assert.same({ 1439, 1440 }, mapIDs(z))
      assert.near(232.3, z[2].score, 0.1)
    end)
  end)

  describe("ordering and limits", function()
    local function zoneDb(extra)
      local data = H.data()
      for _, id in ipairs(extra) do
        local z = {}
        for k, v in pairs(data.zones[1440]) do z[k] = v end
        z.name = "Zone " .. id
        z.links = {}
        data.zones[id] = z
      end
      return ns.DB.new(data)
    end

    it("pins the player's zone first when it has 2 quests, despite a lower score", function()
      local z = ZoneScore.rank(db, S18, {
        cand(1, 1439, 10, 10, 100), cand(2, 1439, 90, 90, 100), cand(3, 1440, 50, 50, 5000),
      })
      assert.same({ 1439, 1440 }, mapIDs(z))
      assert.is_true(z[1].score < z[2].score)
    end)

    it("does not pin the player's zone with one quest", function()
      local z = ZoneScore.rank(db, S18, { cand(1, 1439, 10, 10, 100), cand(3, 1440, 50, 50, 5000) })
      assert.same({ 1440, 1439 }, mapIDs(z))
    end)

    it("keeps only the best 3 zones", function()
      local d = zoneDb({ 1500, 1501, 1502, 1503 })
      local z = ZoneScore.rank(d, S18, {
        cand(1, 1500, 50, 50, 40000), cand(2, 1501, 50, 50, 30000),
        cand(3, 1502, 50, 50, 20000), cand(4, 1503, 50, 50, 10000),
      })
      assert.same({ 1500, 1501, 1502 }, mapIDs(z))
    end)

    it("sorts equal scores by ascending map ID", function()
      local d = zoneDb({ 1500, 1501 })
      -- the 1501 quest has the lower ID, so it is seen first; the sort must still put 1500 first
      local z = ZoneScore.rank(d, S18, { cand(1, 1501, 50, 50, 9000), cand(2, 1500, 50, 50, 9000) })
      assert.equals(z[1].score, z[2].score)
      assert.same({ 1500, 1501 }, mapIDs(z))
    end)
  end)
end)

describe("ZoneScore zone kind", function()
  local ns, Candidates, ZoneScore
  before_each(function()
    ns = H.load()
    Candidates, ZoneScore = ns.Candidates, ns.ZoneScore
  end)

  local function rank(kindZone, kind, state)
    local data = H.data()
    data.zones[kindZone].kind = kind
    local db = ns.DB.new(data)
    return ZoneScore.rank(db, state, Candidates.build(db, state))
  end

  it("never recommends a city, even when the player stands in it", function()
    local zones = rank(1439, "city", H.states.S18)
    assert.is_true(#zones > 0) -- the other zones still rank
    for _, z in ipairs(zones) do assert.not_equals(1439, z.mapID) end
  end)
  it("never recommends a battleground", function()
    local zones = rank(1439, "battleground", H.states.S18)
    assert.is_true(#zones > 0)
    for _, z in ipairs(zones) do assert.not_equals(1439, z.mapID) end
  end)
  it("skips a city with the most XP", function()
    local s = H.with(H.states.S18, { mapID = 1440, x = 40, y = 10 })
    for _, z in ipairs(rank(1439, "city", s)) do assert.not_equals(1439, z.mapID) end
    assert.is_truthy(rank(1439, nil, s)[1])
  end)
  it("an unknown kind is a leveling zone", function()
    assert.equals(1439, rank(1439, "dungeon", H.states.S18)[1].mapID)
  end)
  it("its quests still appear in Right Here", function()
    local data = H.data()
    data.zones[1439].kind = "city"
    local db = ns.DB.new(data)
    local c = Candidates.build(db, H.states.S18)
    local sections = ns.Sections.build(db, H.states.S18, c, ZoneScore.rank(db, H.states.S18, c))
    local here = {}
    for _, row in ipairs(H.find(sections, "here").rows) do here[#here + 1] = row.questID end
    assert.same({ 4763, 7003 }, here) -- Darkshore's, as when it is a leveling zone
  end)
end)

-- Level fit (0.3.0): a zone counts only its yellow and green quests (yellow at full weight,
-- green at Tuning.FIT_WEIGHT.green), the player's zone is pinned only with 2 of them, and a
-- zone of mostly green quests says the player skipped them.
describe("ZoneScore level fit", function()
  local ns, Candidates, ZoneScore
  local S18, with = H.states.S18, H.with

  before_each(function()
    ns = H.load()
    Candidates, ZoneScore = ns.Candidates, ns.ZoneScore
  end)

  local function copyRec(r)
    local out = {}
    for k, v in pairs(r) do out[k] = v end
    return out
  end

  local function dbWith(edit)
    local data = H.data()
    edit(data.quests, data)
    return ns.DB.new(data)
  end

  local function rank(d, s)
    return ZoneScore.rank(d, s, Candidates.build(d, s))
  end

  local function zoneOf(zones, mapID)
    for _, z in ipairs(zones) do
      if z.mapID == mapID then return z end
    end
    return nil
  end

  it("does not score a zone whose 3 quests are all orange", function()
    -- Loch Modan: 1081 and two copies, all level 21 (orange at 18)
    local d = dbWith(function(q)
      q[1081][6] = 21
      q[8201] = copyRec(q[1081]); q[8202] = copyRec(q[1081])
    end)
    local c = Candidates.build(d, S18)
    for _, id in ipairs({ 1081, 8201, 8202 }) do assert.equals("later", H.candidateFor(c, id).status) end
    local z = ZoneScore.rank(d, S18, c)
    assert.is_nil(zoneOf(z, 1432))
    assert.same({ 1439, 1440 }, { z[1].mapID, z[2].mapID })
    assert.equals(2, #z)
  end)

  it("does not pin the player's zone with 1 recommendable quest among orange ones", function()
    -- Darkshore keeps one fitting quest (967, 1200 XP); two orange copies stand beside it
    local s = with(S18, {
      completed = { [4762] = true, [965] = true, [4763] = true, [5061] = true, [1000] = true,
                    [7003] = true, [966] = true, [4730] = true },
      log = {},
    })
    local d = dbWith(function(q)
      for i, id in ipairs({ 8301, 8302 }) do
        q[id] = copyRec(q[967]); q[id][19] = nil; q[id][6] = 21; q[id][17] = 5000 + i
      end
    end)
    local c = Candidates.build(d, s)
    assert.equals("later", H.candidateFor(c, 8301).status)
    local z = ZoneScore.rank(d, s, c)
    local here = zoneOf(z, 1439)
    assert.equals(1, here.questCount)
    assert.equals(1200, here.xp)
    assert.equals(1440, z[1].mapID) -- Ashenvale fits better
  end)

  it("the player's zone with only orange quests is not listed; the top zone fits", function()
    -- the player stands in Loch Modan, whose three quests are all level 21 (orange at 18)
    local s = with(S18, { mapID = 1432, x = 35, y = 47 })
    local d = dbWith(function(q)
      q[1081][6] = 21
      q[8201] = copyRec(q[1081]); q[8202] = copyRec(q[1081])
    end)
    local z = rank(d, s)
    assert.is_nil(zoneOf(z, 1432))
    assert.is_false(z[1].isHere)
    assert.equals(1439, z[1].mapID) -- Darkshore, all yellow
  end)

  -- Darkshore keeps `n` fitting quests (the rest completed) beside two orange copies.
  local function darkshoreWith(n)
    local done = { 4762, 965, 4763, 5061, 1000, 7003, 966, 4730 }
    local s = with(S18, { completed = {}, log = {} })
    for i = 1, #done - (n - 1) do s.completed[done[i]] = true end
    local d = dbWith(function(q)
      for i, id in ipairs({ 8301, 8302 }) do
        q[id] = copyRec(q[967]); q[id][19] = nil; q[id][6] = 21; q[id][17] = 5000 + i
      end
    end)
    return d, s
  end

  it("pins the player's zone at exactly 2 recommendable quests, not at 1", function()
    local d, s = darkshoreWith(2)
    local c = Candidates.build(d, s)
    local fitting = 0
    for _, cand in ipairs(c) do
      if cand.quest.zone == 1439 and not cand.quest.dungeonQuest and Candidates.recommendable(cand) then
        fitting = fitting + 1
      end
    end
    assert.equals(2, fitting)
    local z = ZoneScore.rank(d, s, c)
    assert.same({ 1439, true }, { z[1].mapID, z[1].isHere })
    local d1, s1 = darkshoreWith(1)
    local z1 = rank(d1, s1)
    assert.equals(1, zoneOf(z1, 1439).questCount)
    assert.is_false(z1[1].isHere)
  end)

  it("a logged green quest does not count towards 'Catch up'", function()
    local db = ns.DB.new(H.data())
    local function cand(id, status)
      return { quest = { id = id, zone = 1432, giver = { mapID = 1432, x = id, y = id } },
        status = status, xp = 100, fit = "green" }
    end
    local z = ZoneScore.rank(db, S18, { cand(1, "eligible"), cand(2, "progress"), cand(3, "progress") })
    assert.is_nil(z[1].reason:match("^Catch up"))
    local z2 = ZoneScore.rank(db, S18, { cand(1, "eligible"), cand(2, "eligible"), cand(3, "progress") })
    assert.equals("Catch up — 2 quests you skipped at your level", z2[1].reason)
  end)

  it("weights a turn-in at the yellow weight whatever its colour", function()
    local db = ns.DB.new(H.data())
    local function cand(id, x, status, fit)
      return { quest = { id = id, zone = 1439, giver = { mapID = 1439, x = x, y = x } },
        status = status, xp = 1000, fit = fit }
    end
    local z = ZoneScore.rank(db, S18, { cand(1, 10, "eligible", "yellow"), cand(2, 90, "complete", "green") })
    assert.near(2000, z[1].score, 1e-6)
  end)

  it("weights a green quest at Tuning.FIT_WEIGHT.green", function()
    assert.same({ yellow = 1.0, green = 0.8 }, ns.Tuning.FIT_WEIGHT)
    local db = ns.DB.new(H.data())
    local function cand(id, x, xp, fit)
      return { quest = { id = id, zone = 1439, giver = { mapID = 1439, x = x, y = x } },
        status = "eligible", xp = xp, fit = fit }
    end
    local z = ZoneScore.rank(db, S18, { cand(1, 10, 1000, "yellow"), cand(2, 90, 1000, "green") })
    assert.near(1800, z[1].score, 1e-6)
    assert.equals(2000, z[1].xp) -- the XP shown is not weighted
  end)

  it("says 'Catch up' for a zone whose quests are mostly green", function()
    -- Loch Modan: 1081 (15) and a level-14 copy are green at 18, a level-17 copy is yellow
    local d = dbWith(function(q)
      q[8401] = copyRec(q[1081]); q[8401][6] = 14
      q[8402] = copyRec(q[1081]); q[8402][6] = 17
    end)
    local lm = zoneOf(rank(d, S18), 1432)
    assert.equals(3, lm.questCount)
    assert.equals("Catch up — 2 quests you skipped at your level", lm.reason)
  end)

  it("says 'Catch up' in the singular for one skipped quest", function()
    -- Loch Modan has only 1081 (level 15, green at 18)
    local lm = zoneOf(rank(dbWith(function() end), S18), 1432)
    assert.equals("Catch up — 1 quest you skipped at your level", lm.reason)
  end)

  it("keeps the link reason when half or fewer of the quests are green", function()
    local d = dbWith(function(q)
      q[8402] = copyRec(q[1081]); q[8402][6] = 17 -- one green, one yellow: not more than half
    end)
    assert.equals("Alternative — boat from Auberdine", zoneOf(rank(d, S18), 1432).reason)
  end)

  it("never says 'Catch up' for the player's own zone", function()
    local s = with(S18, { mapID = 1432, x = 35, y = 47 })
    local d = dbWith(function(q)
      q[8401] = copyRec(q[1081]); q[8401][6] = 14
    end)
    local lm = zoneOf(rank(d, s), 1432)
    assert.is_true(lm.isHere)
    assert.equals("You are here — finish before you leave", lm.reason)
  end)
end)
